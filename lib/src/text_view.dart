import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart';

import 'models.dart';

/// Represents a matched pattern in the text with its boundaries.
class _PatternMatch {
  final int start;
  final int end;
  final bool isUrl;
  final bool isFormatting;

  _PatternMatch({
    required this.start,
    required this.end,
    required this.isUrl,
    required this.isFormatting,
  });

  bool contains(int index) => index >= start && index < end;
}

/// Result of finding a safe truncation index.
class _TruncationResult {
  final int index;
  final String? closingTags;

  _TruncationResult({required this.index, this.closingTags});
}

/// Finds a safe truncation index that doesn't break markdown formatting, URLs, or words.
///
/// This function ensures that truncation doesn't happen:
/// 1. In the middle of a URL - includes the entire URL (UrlParser handles shortening)
/// 2. In the middle of markdown formatting tags - cuts before or after the formatted section
/// 3. In the middle of a word - cuts at the end of the word (if word is < 50 characters)
///
/// [text] - The original text to truncate
/// [desiredIndex] - The initial truncation index calculated by TextPainter
/// [supportedTypes] - The list of parser types (contains regex patterns)
/// [regexOptions] - Regex options for pattern matching
///
/// Returns an adjusted index that respects markdown, URL, and word boundaries.
/// Also returns optional closing tags if the truncation occurs inside formatted text.
_TruncationResult _findSafeTruncationIndex(
  String text,
  int desiredIndex,
  List<ParserType> supportedTypes,
  RegexOptions regexOptions,
) {
  // Early return if index is at the end or beyond
  if (desiredIndex >= text.length) {
    return _TruncationResult(index: text.length);
  }

  // Early return if index is at the start
  if (desiredIndex <= 0) {
    return _TruncationResult(index: 0);
  }

  // Build regex pattern from all parser types
  final patternStrings = <String>[];
  final urlPatterns = <String>[];
  final formattingPatterns = <String>[];

  for (var type in supportedTypes) {
    if (type.pattern != null && type.pattern!.isNotEmpty) {
      patternStrings.add(type.pattern!);

      // Identify URL patterns (typically contain http, www, or are very long)
      if (type.pattern!.contains(r'http') ||
          type.pattern!.contains(r'www') ||
          type.pattern!.length > 100) {
        urlPatterns.add(type.pattern!);
      } else if (type.pattern!.contains(r'*') ||
          type.pattern!.contains(r'_') ||
          type.pattern!.contains(r'~')) {
        // Formatting patterns contain *, _, or ~
        formattingPatterns.add(type.pattern!);
      }
    }
  }

  if (patternStrings.isEmpty) {
    return _TruncationResult(index: desiredIndex);
  }

  // Find all matches in the text
  final matches = <_PatternMatch>[];

  for (var pattern in patternStrings) {
    try {
      final regex = RegExp(
        pattern,
        multiLine: regexOptions.multiLine,
        caseSensitive: regexOptions.caseSensitive,
        dotAll: regexOptions.dotAll,
        unicode: regexOptions.unicode,
      );

      final isUrl = urlPatterns.contains(pattern);
      final isFormatting = formattingPatterns.contains(pattern);

      for (var match in regex.allMatches(text)) {
        matches.add(_PatternMatch(
          start: match.start,
          end: match.end,
          isUrl: isUrl,
          isFormatting: isFormatting,
        ));
      }
    } catch (e) {
      // Skip invalid regex patterns
      continue;
    }
  }

  // Sort matches by start position
  matches.sort((a, b) => a.start.compareTo(b.start));

  // Check if desiredIndex falls within any match
  for (var match in matches) {
    if (match.contains(desiredIndex)) {
      // For URLs, always cut before the URL to respect maxLines
      // The UrlParser will handle shortening it with its built-in truncation
      if (match.isUrl) {
        return _TruncationResult(index: match.start);
      }

      // For formatting (bold, italic, etc.), cut at desiredIndex and append closing tag
      if (match.isFormatting) {
        final matchedText = text.substring(match.start, match.end);
        final openingTag = _extractOpeningTag(matchedText);

        if (openingTag != null) {
          // Closing tag is the opening tag reversed
          final closingTag = openingTag.split('').reversed.join('');
          return _TruncationResult(
              index: desiredIndex, closingTags: closingTag);
        }

        // Fallback: cut at desiredIndex without closing tags
        return _TruncationResult(index: desiredIndex);
      }
    }
  }

  // If we're very close to the end of a match (within 3 characters),
  // include the entire match to avoid awkward cuts like "**bol"
  for (var match in matches) {
    if (desiredIndex > match.start &&
        desiredIndex < match.end &&
        match.end - desiredIndex <= 3) {
      // For URLs, cut before them to respect maxLines
      if (match.isUrl) {
        return _TruncationResult(index: match.start);
      }
      // For formatting, we already handled it above in the contains() check
      // but as a safety, cut at desiredIndex with closing tag
      if (match.isFormatting) {
        final matchedText = text.substring(match.start, match.end);
        final openingTag = _extractOpeningTag(matchedText);
        if (openingTag != null) {
          final closingTag = openingTag.split('').reversed.join('');
          return _TruncationResult(
              index: desiredIndex, closingTags: closingTag);
        }
      }
    }
  }

  // Find the start of the current word by going backwards
  var wordStart = desiredIndex;
  while (wordStart > 0 && !_isWordBoundary(text[wordStart - 1])) {
    wordStart--;
  }

  // Cut at word start
  return _TruncationResult(index: wordStart);

  // Check if we're cutting in the middle of a word
  // If so, cut at the end of the word (if it's not too long, i.e., < 50 chars)
  // var adjustedIndex = desiredIndex;
  //
  // // Find the end of the current word by going forwards
  // var wordEnd = desiredIndex;
  // while (wordEnd < text.length && !_isWordBoundary(text[wordEnd])) {
  //   wordEnd++;
  // }
  //
  // // Calculate word length
  // final wordLength = wordEnd - wordStart;
  //
  // // If we're in the middle of a word and the word is not too long (< 50 chars),
  // // cut at the end of the word instead
  // if (wordLength > 0 &&
  //     wordLength < 50 &&
  //     desiredIndex > wordStart &&
  //     desiredIndex < wordEnd) {
  //   adjustedIndex = wordEnd;
  // }
  //
  // return adjustedIndex;
}

/// Helper function to check if a character is a word boundary
bool _isWordBoundary(String char) {
  // Word boundaries: space, newline, tab, punctuation (except hyphen and apostrophe within words)
  return char == ' ' ||
      char == '\n' ||
      char == '\t' ||
      char == '.' ||
      char == ',' ||
      char == '!' ||
      char == '?' ||
      char == ';' ||
      char == ':' ||
      char == ')' ||
      char == ']' ||
      char == '}' ||
      char == '"' ||
      char == "'";
}

/// Extracts the opening formatting tag from a matched text.
/// For example, "**bold text**" returns "**", "__*text*__" returns "__*".
String? _extractOpeningTag(String matchedText) {
  const formatChars = {'*', '_', '~'};

  var i = 0;
  while (i < matchedText.length && formatChars.contains(matchedText[i])) {
    i++;
  }

  if (i == 0 || i == matchedText.length) return null;
  return matchedText.substring(0, i);
}

/// Creates a [RichText] widget that supports emails, mentions, hashtags and more.
///
/// When [viewLessText] is specified, toggling between view more and view less will be supported.
///
/// For displaying a rich text editor, see the [RichTextEditor] class
///
class RichTextView extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextStyle linkStyle;
  final TextDirection? textDirection;
  final bool softWrap;
  final double textScaleFactor;
  final int? maxLines;
  final StrutStyle? strutStyle;
  final TextWidthBasis textWidthBasis;
  final bool selectable;
  final GestureTapCallback? onTap;
  final Function()? onMore;
  final bool truncate;
  final double? prefixIconWidth;

  /// Uniform dimensions assumed for every inline placeholder (e.g. WidgetSpan)
  /// produced by [supportedTypes] parsers when measuring content for
  /// truncation. Without this, truncation measurement cannot lay out
  /// placeholder spans. Does not apply to [prefixWidgetSpan], which is
  /// estimated separately via [prefixIconWidth].
  final PlaceholderDimensions? placeholderDimensions;

  /// the view more text if `truncate` is true
  final String viewMoreText;

  /// the view more and view less text's style
  final TextStyle? viewMoreLessStyle;

  /// if included, will show a view less text
  final String? viewLessText;
  final List<ParserType> supportedTypes;
  final RegexOptions regexOptions;
  final TextAlign textAlign;

  /// A prefix widget to display before the text.
  final WidgetSpan? prefixWidgetSpan;

  /// Whether to show "Show more" or "Show less" link at the end
  /// of the text. Tapping on the button will toggle the text
  /// between truncated and expanded text.
  final bool toggleTruncate;

  RichTextView({
    Key? key,
    required this.text,
    required this.supportedTypes,
    required this.truncate,
    required this.linkStyle,
    this.style,
    this.toggleTruncate = false,
    this.regexOptions = const RegexOptions(),
    this.textAlign = TextAlign.start,
    this.textDirection = TextDirection.ltr,
    this.softWrap = true,
    this.textScaleFactor = 1.0,
    this.strutStyle,
    this.textWidthBasis = TextWidthBasis.parent,
    this.maxLines,
    this.onTap,
    this.onMore,
    this.viewMoreText = 'more',
    this.viewLessText,
    this.viewMoreLessStyle,
    this.selectable = false,
    this.prefixWidgetSpan,
    this.prefixIconWidth,
    this.placeholderDimensions,
  }) : super(key: key);

  @override
  State<RichTextView> createState() => _RichTextViewState();
}

class _RichTextViewState extends State<RichTextView> {
  late bool _expanded;
  late int? _maxLines;
  late TextStyle linkStyle;

  // Map to keep track of visible to original index mapping
  Map<int, int> visibleToOriginalIndexMap = {};

  @override
  void initState() {
    super.initState();
    _expanded = !widget.truncate;
    _maxLines = widget.truncate ? (widget.maxLines ?? 2) : widget.maxLines;
    linkStyle = widget.linkStyle;
  }

  // The default mapper for text selection.
  //
  // It uses a basic logic for mapping, where originalIndex is incremented
  // at the same rate as visibleIndex.
  // This can be used for any mapping that doesn't modify the original text.
  void defaultVisibleToOriginalSelectionMapper({
    required String originalText,
    required Map<int, int> visibleToOriginalIndexMap,
    required int originalIndex,
    required Function(int) updateOriginalIndex,
    required int visibleIndex,
    required Function(int) updateVisibleIndex,
  }) {
    for (var i = 0; i < originalText.length; i++) {
      visibleToOriginalIndexMap[visibleIndex] = originalIndex;
      visibleIndex++;
      originalIndex++;
      updateVisibleIndex(visibleIndex);
      updateOriginalIndex(originalIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    visibleToOriginalIndexMap.clear();

    var _style = widget.style ?? Theme.of(context).textTheme.bodyMedium;
    var link = _expanded && widget.viewLessText == null
        ? TextSpan()
        : TextSpan(
            children: [
              TextSpan(
                  text: _expanded ? widget.viewLessText : widget.viewMoreText,
                  recognizer: TapGestureRecognizer()
                    ..onTap = () {
                      if (!_expanded && widget.onMore != null) {
                        widget.onMore!();
                      } else {
                        setState(() {
                          _expanded = !_expanded;
                        });
                      }
                    }),
            ],
            style: widget.viewMoreLessStyle ?? linkStyle,
          );

    List<InlineSpan> parseText(String txt) {
      var newString = txt;

      var _mapping = <String, ParserType>{};

      for (var type in widget.supportedTypes) {
        _mapping[type.pattern!] = type;
      }

      final pattern = '(${_mapping.keys.toList().join('|')})';

      var widgets = <InlineSpan>[];
      var originalIndex = 0;
      var visibleIndex = 0;

      newString.splitMapJoin(
        RegExp(
          pattern,
          multiLine: widget.regexOptions.multiLine,
          caseSensitive: widget.regexOptions.caseSensitive,
          dotAll: widget.regexOptions.dotAll,
          unicode: widget.regexOptions.unicode,
        ),
        onMatch: (Match match) {
          final matchText = match[0];

          final mapping = _mapping[matchText!] ??
              _mapping[_mapping.keys.firstWhere((element) {
                var ret = false;
                RegExp(
                  element,
                  multiLine: widget.regexOptions.multiLine,
                  caseSensitive: widget.regexOptions.caseSensitive,
                  dotAll: widget.regexOptions.dotAll,
                  unicode: widget.regexOptions.unicode,
                ).allMatches(matchText).forEach((element) {
                  if (element.group(0) == match[0]) {
                    ret = true;
                  }
                });

                return ret;
              }, orElse: () {
                return '';
              })];

          InlineSpan span;

          if (mapping != null) {
            if (mapping.renderSpan != null) {
              var matched = Matched(
                display: matchText,
                value: matchText,
                start: match.start,
                end: match.end,
              );
              span = mapping.renderSpan!(
                str: matchText,
                matched: matched,
                style: _style,
                linkStyle: linkStyle,
              );

              // Get the rendered text.
              final renderedText = span.toPlainText();

              if (mapping.visibleToOriginalSelectionMapper != null) {
                mapping.visibleToOriginalSelectionMapper!(
                  originalText: matchText,
                  visibleText: renderedText,
                  visibleToOriginalIndexMap: visibleToOriginalIndexMap,
                  originalIndex: originalIndex,
                  updateOriginalIndex: (int index) {
                    originalIndex = index;
                  },
                  visibleIndex: visibleIndex,
                  updateVisibleIndex: (int index) {
                    visibleIndex = index;
                  },
                );
              } else {
                defaultVisibleToOriginalSelectionMapper(
                  originalText: matchText,
                  visibleToOriginalIndexMap: visibleToOriginalIndexMap,
                  originalIndex: originalIndex,
                  updateOriginalIndex: (int index) {
                    originalIndex = index;
                  },
                  visibleIndex: visibleIndex,
                  updateVisibleIndex: (int index) {
                    visibleIndex = index;
                  },
                );
              }
            } else if (mapping.renderText != null) {
              var result = mapping.renderText!(str: matchText);

              result.start = match.start;
              result.end = match.end;

              span = TextSpan(
                text: '${result.display}',
                style: mapping.style ?? linkStyle,
                recognizer: mapping.onTap == null
                    ? null
                    : (TapGestureRecognizer()
                      ..onTap = () => mapping.onTap!(result)),
              );

              final renderedText = span.toPlainText();

              if (mapping.visibleToOriginalSelectionMapper != null) {
                mapping.visibleToOriginalSelectionMapper!(
                  originalText: matchText,
                  visibleText: renderedText,
                  visibleToOriginalIndexMap: visibleToOriginalIndexMap,
                  originalIndex: originalIndex,
                  updateOriginalIndex: (int index) {
                    originalIndex = index;
                  },
                  visibleIndex: visibleIndex,
                  updateVisibleIndex: (int index) {
                    visibleIndex = index;
                  },
                );
              } else {
                defaultVisibleToOriginalSelectionMapper(
                  originalText: matchText,
                  visibleToOriginalIndexMap: visibleToOriginalIndexMap,
                  originalIndex: originalIndex,
                  updateOriginalIndex: (int index) {
                    originalIndex = index;
                  },
                  visibleIndex: visibleIndex,
                  updateVisibleIndex: (int index) {
                    visibleIndex = index;
                  },
                );
              }
            } else {
              var matched = Matched(
                  display: matchText,
                  value: matchText,
                  start: match.start,
                  end: match.end);
              span = TextSpan(
                text: '$matchText',
                style: mapping.style ?? linkStyle,
                recognizer: mapping.onTap == null
                    ? null
                    : (TapGestureRecognizer()
                      ..onTap = () => mapping.onTap!(matched)),
              );

              defaultVisibleToOriginalSelectionMapper(
                originalText: matchText,
                visibleToOriginalIndexMap: visibleToOriginalIndexMap,
                originalIndex: originalIndex,
                updateOriginalIndex: (int index) {
                  originalIndex = index;
                },
                visibleIndex: visibleIndex,
                updateVisibleIndex: (int index) {
                  visibleIndex = index;
                },
              );
            }
          } else {
            span = TextSpan(
              text: '$matchText',
              style: _style,
            );
            defaultVisibleToOriginalSelectionMapper(
              originalText: matchText,
              visibleToOriginalIndexMap: visibleToOriginalIndexMap,
              originalIndex: originalIndex,
              updateOriginalIndex: (int index) {
                originalIndex = index;
              },
              visibleIndex: visibleIndex,
              updateVisibleIndex: (int index) {
                visibleIndex = index;
              },
            );
          }
          widgets.add(span);
          return '';
        },
        onNonMatch: (String text) {
          defaultVisibleToOriginalSelectionMapper(
            originalText: text,
            visibleToOriginalIndexMap: visibleToOriginalIndexMap,
            originalIndex: originalIndex,
            updateOriginalIndex: (int index) {
              originalIndex = index;
            },
            visibleIndex: visibleIndex,
            updateVisibleIndex: (int index) {
              visibleIndex = index;
            },
          );

          widgets.add(TextSpan(
            text: '$text',
            style: _style,
          ));

          return '';
        },
      );
      return widgets;
    }

    final content = TextSpan(children: parseText(widget.text), style: _style);

    Widget result = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        assert(constraints.hasBoundedWidth);
        final maxWidth = constraints.maxWidth;

        var textPainter = TextPainter(
          text: link,
          textDirection: widget.textDirection,
          textAlign: widget.textAlign,
          maxLines: _maxLines,
        );

        textPainter.layout(minWidth: constraints.minWidth, maxWidth: maxWidth);
        final linkSize = textPainter.size;

        final ellipsis = '…';
        textPainter.text = TextSpan(text: ellipsis, style: _style);
        textPainter.layout(minWidth: constraints.minWidth, maxWidth: maxWidth);
        final ellipsisSize = textPainter.size;

        // First measure content without the prefix to avoid WidgetSpan dimension issues
        textPainter.text = content;
        if (widget.placeholderDimensions != null) {
          var placeholderCount = 0;
          content.visitChildren((child) {
            if (child is PlaceholderSpan) placeholderCount++;
            return true;
          });
          if (placeholderCount > 0) {
            textPainter.setPlaceholderDimensions(
              List<PlaceholderDimensions>.filled(
                placeholderCount,
                widget.placeholderDimensions!,
              ),
            );
          }
        }
        textPainter.layout(minWidth: constraints.minWidth, maxWidth: maxWidth);
        final contentSize = textPainter.size;
        final contentExceedsMaxLines = textPainter.didExceedMaxLines;

        // Estimate prefix width instead of directly measuring the WidgetSpan
        final prefixWidth = widget.prefixIconWidth ?? 0;

        // Determine if text will exceed max lines with the prefix
        final exceedsMaxLines = contentExceedsMaxLines ||
            (widget.prefixWidgetSpan != null &&
                _maxLines != null &&
                contentSize.height + (prefixWidth > 0 ? 5.0 : 0) >
                    textPainter.preferredLineHeight * _maxLines!);

        var textSpan;
        if (exceedsMaxLines) {
          // Calculate position for truncation
          final availableWidth = maxWidth -
              // "Show more"/"Show less" will be appended to the end of the text
              // if `toggleTruncate` is true. Otherwise, ellipsis will be appended.
              // Therefore, we need to subtract the width of the appended text
              // from the total width of the text.
              (widget.toggleTruncate ? linkSize.width : ellipsisSize.width) -
              prefixWidth;

          // Adjust the calculation to account for prefix width
          final pos = textPainter.getPositionForOffset(Offset(
            min(contentSize.width, availableWidth),
            contentSize.height,
          ));
          final endIndex = textPainter.getOffsetBefore(pos.offset);

          // Adjust the endIndex to account for the prefix
          var adjustedEndIndex = max(0, endIndex ?? 0);

          // Check if we're cutting in the middle of an emoji/grapheme cluster.
          if (adjustedEndIndex > 0 && adjustedEndIndex < widget.text.length) {
            // Just check if substring ends with a surrogate.
            final testSub = widget.text.substring(0, adjustedEndIndex);

            if (testSub.isNotEmpty) {
              final lastCodeUnit = testSub.codeUnitAt(testSub.length - 1);

              // Check if it's a UTF-16 surrogate (high or low).
              // https://github.com/flutter/flutter/blob/248d746575b713da74144750527356a1c0095546/packages/flutter/lib/src/painting/text_painter.dart#L603
              final isUtf16Surrogate = (lastCodeUnit & 0xF800) == 0xD800;

              if (isUtf16Surrogate) {
                // We're in the middle of a character, take one more complete character.
                final charCount =
                    testSub.substring(0, testSub.length - 1).characters.length;

                adjustedEndIndex =
                    widget.text.characters.take(charCount + 1).string.length;
              }
            }
          }

          // Apply smart truncation to avoid cutting in the middle of URLs or markdown formatting
          final truncationResult = _findSafeTruncationIndex(
            widget.text,
            adjustedEndIndex,
            widget.supportedTypes,
            widget.regexOptions,
          );

          final textChildren = _expanded
              ? parseText(widget.text)
              : parseText(
                  widget.text.substring(0, truncationResult.index) +
                      // Append closing tags if we cut inside formatted text
                      (truncationResult.closingTags ?? '') +
                      // Append the ellipsis if `toggleTruncate` is false
                      // (i.e. "Show more"/"Show less" is not shown)
                      // and the text is truncated.
                      (!widget.toggleTruncate ? ellipsis : ''),
                );

          final lastTextSpan = textChildren
              .lastWhereOrNull((child) => child is TextSpan) as TextSpan?;

          final _text = TextSpan(
            children: textChildren,
            style: widget.style,
          );

          final textEndsWithNewLine =
              lastTextSpan?.text?.endsWith('\n') ?? false;

          textSpan = TextSpan(
            children: [
              if (widget.prefixWidgetSpan != null) widget.prefixWidgetSpan!,
              _text,
              if (widget.toggleTruncate) ...[
                if (!textEndsWithNewLine)
                  TextSpan(
                    text: ' ',
                    style: widget.style,
                  ),
                link,
              ],
            ],
          );
        } else {
          textSpan = TextSpan(
            children: [
              if (widget.prefixWidgetSpan != null) widget.prefixWidgetSpan!,
              ...content.children ?? [content],
            ],
            style: content.style,
          );
        }

        if (widget.selectable) {
          return SelectableText.rich(
            textSpan,
            strutStyle: widget.strutStyle,
            textWidthBasis: widget.textWidthBasis,
            textAlign: widget.textAlign,
            textDirection: widget.textDirection,
            onTap: widget.onTap,
            contextMenuBuilder: contextMenuBuilder,
          );
        }

        return RichText(
          textAlign: widget.textAlign,
          textDirection: widget.textDirection,
          text: textSpan,
          textWidthBasis: widget.textWidthBasis,
          textScaler: TextScaler.linear(widget.textScaleFactor),
        );
      },
    );

    return result;
  }

  Widget contextMenuBuilder(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final value = editableTextState.textEditingValue;
    final selection = value.selection;
    final copyItem = editableTextState.contextMenuButtonItems
        .firstWhereOrNull(
      (menuItem) => menuItem.type == ContextMenuButtonType.copy,
    )
        ?.copyWith(
      // Override copy action to properly select original text.
      onPressed: () {
        if (selection.isCollapsed) {
          return;
        }
        final startVisibleIndex = selection.start;
        final endVisibleIndex = selection.end;

        // Convert visible selection indices to original text indices
        final startOriginalIndex =
            visibleToOriginalIndexMap[startVisibleIndex] ?? 0;
        final endOriginalIndex = visibleToOriginalIndexMap[endVisibleIndex];

        final selectedText =
            widget.text.substring(startOriginalIndex, endOriginalIndex);

        if (selection.isCollapsed) {
          return;
        }
        final text = selectedText;
        Clipboard.setData(ClipboardData(text: text));

        // This part is copied from the default copy action in the editable text
        // to properly close the toolbar and handles after copying.
        editableTextState
            .bringIntoView(editableTextState.textEditingValue.selection.extent);
        editableTextState.hideToolbar(false);

        switch (defaultTargetPlatform) {
          case TargetPlatform.iOS:
          case TargetPlatform.macOS:
          case TargetPlatform.linux:
          case TargetPlatform.windows:
            break;
          case TargetPlatform.android:
          case TargetPlatform.fuchsia:
            // Collapse the selection and hide the toolbar and handles.
            editableTextState.userUpdateTextEditingValue(
              TextEditingValue(
                text: text,
                selection: TextSelection.collapsed(offset: selection.end),
              ),
              SelectionChangedCause.toolbar,
            );
        }
      },
    );
    final otherButtonItems = editableTextState.contextMenuButtonItems
        .where(
          (menuItem) => menuItem.type != ContextMenuButtonType.copy,
        )
        .toList();

    final buttonItems = [
      if (copyItem != null) copyItem,
      ...otherButtonItems,
    ];

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }
}
