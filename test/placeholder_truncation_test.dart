import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_text_view/rich_text_view.dart';

const _placeholderDimensions = PlaceholderDimensions(
  size: Size(20, 20),
  alignment: PlaceholderAlignment.baseline,
  baseline: TextBaseline.alphabetic,
  baselineOffset: 16,
);

class _TokenParser extends ParserType {
  _TokenParser()
      : super(
          pattern: r':[a-z_]+:',
          renderSpan: ({
            required Matched matched,
            String? str,
            TextStyle? style,
            TextStyle? linkStyle,
          }) {
            final token = str!;
            return TextSpan(
              children: [
                const WidgetSpan(child: SizedBox(width: 20, height: 20)),
                TextSpan(
                  text: token.substring(1),
                  style: (style ?? const TextStyle()).copyWith(fontSize: 0),
                ),
              ],
            );
          },
        );
}

Widget _view(
  String text, {
  List<ParserType> supportedTypes = const [],
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 140,
        child: RichTextView(
          text: text,
          truncate: true,
          maxLines: 2,
          toggleTruncate: true,
          viewMoreText: 'View more',
          linkStyle: const TextStyle(color: Colors.blue),
          placeholderDimensions: _placeholderDimensions,
          supportedTypes: supportedTypes,
        ),
      ),
    ),
  );
}

String _renderedText(WidgetTester tester) {
  final richText = tester.widget<RichText>(find.byType(RichText));
  return (richText.text as TextSpan).toPlainText();
}

void main() {
  testWidgets('measures placeholder spans while truncating',
      (WidgetTester tester) async {
    const text =
        'A long row of text :pink_blossom: continues with :blue_heart: and '
        ':yellow_star: until it must be truncated.';

    await tester.pumpWidget(_view(text, supportedTypes: [_TokenParser()]));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_renderedText(tester), contains('View more'));
  });

  testWidgets('keeps ordinary text truncation unchanged',
      (WidgetTester tester) async {
    const text = 'A simple sentence with enough words to require truncation.';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 140,
            child: RichTextView(
              text: text,
              truncate: true,
              maxLines: 2,
              toggleTruncate: true,
              viewMoreText: 'View more',
              linkStyle: const TextStyle(color: Colors.blue),
              supportedTypes: const [],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_renderedText(tester), contains('View more'));
  });

  testWidgets('does not render partial placeholder tokens',
      (WidgetTester tester) async {
    const text =
        'Words before the sticker :pink_blossom: continue after the token.';

    await tester.pumpWidget(_view(text, supportedTypes: [_TokenParser()]));
    await tester.pumpAndSettle();

    final displayedText = _renderedText(tester);
    expect(displayedText, contains('View more'));
    expect(RegExp(r':[a-z_]+').hasMatch(displayedText), isFalse);
  });
}
