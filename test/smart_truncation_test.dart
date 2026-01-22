import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_text_view/rich_text_view.dart';

void main() {
  group('Smart Truncation Tests', () {
    testWidgets('Truncates before URL when cut would be in the middle',
        (WidgetTester tester) async {
      const testText =
          'Check this link https://google.com/very/long/path for more info';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200, // Narrow width to force truncation
              child: RichTextView(
                text: testText,
                truncate: true,
                maxLines: 2,
                supportedTypes: [
                  UrlParser(onTap: (url) {}),
                ],
                linkStyle: const TextStyle(color: Colors.blue),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // The text should be truncated before the URL, not in the middle
      final richTextWidget = tester.widget<RichText>(find.byType(RichText));
      final textSpan = richTextWidget.text as TextSpan;
      final displayedText = textSpan.toPlainText();

      // Should not contain partial URL
      expect(displayedText.contains('https://google.com/very'), isFalse);
      // Should either contain full URL or no URL at all
      if (displayedText.contains('https://')) {
        expect(displayedText.contains('https://google.com/very/long/path'),
            isTrue);
      }
    });

    testWidgets('Truncates markdown formatting properly',
        (WidgetTester tester) async {
      const testText =
          'Some text **this is bold** and more text continues here for a while';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200, // Narrow width to force truncation
              child: RichTextView(
                text: testText,
                truncate: true,
                maxLines: 2,
                supportedTypes: [
                  BoldParser(),
                ],
                linkStyle: const TextStyle(color: Colors.blue),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final richTextWidget = tester.widget<RichText>(find.byType(RichText));
      final textSpan = richTextWidget.text as TextSpan;
      final displayedText = textSpan.toPlainText();

      // Should not have unclosed bold tags
      final boldOpenCount = '**'.allMatches(displayedText).length;
      // If there's a **, there should be an even number (opening and closing)
      // OR the markdown should be removed by the parser
      expect(boldOpenCount % 2, 0);
    });

    testWidgets('Does not break italic formatting',
        (WidgetTester tester) async {
      const testText =
          'Normal text _italic text here_ and more normal text after that';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: RichTextView(
                text: testText,
                truncate: true,
                maxLines: 2,
                supportedTypes: [
                  ItalicParser(),
                ],
                linkStyle: const TextStyle(color: Colors.blue),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final richTextWidget = tester.widget<RichText>(find.byType(RichText));
      final textSpan = richTextWidget.text as TextSpan;
      final displayedText = textSpan.toPlainText();

      // Should not have single underscores (either both or none)
      final underscoreCount = '_'.allMatches(displayedText).length;
      expect(underscoreCount % 2, 0);
    });

    testWidgets('Handles multiple URLs in text', (WidgetTester tester) async {
      const testText =
          'First link https://example.com and second https://google.com here';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: RichTextView(
                text: testText,
                truncate: true,
                maxLines: 1,
                supportedTypes: [
                  UrlParser(onTap: (url) {}),
                ],
                linkStyle: const TextStyle(color: Colors.blue),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final richTextWidget = tester.widget<RichText>(find.byType(RichText));
      final textSpan = richTextWidget.text as TextSpan;
      final displayedText = textSpan.toPlainText();

      // Should not have partial URLs like "https://exam"
      // Either full URL or cut before it
      if (displayedText.contains('example')) {
        expect(displayedText.contains('example.com'), isTrue);
      }
      if (displayedText.contains('google')) {
        expect(displayedText.contains('google.com'), isTrue);
      }
    });
  });
}

class BoldParser extends ParserType {
  BoldParser({
    Function(Matched)? onTap,
    TextStyle? style,
    String pattern = r'\*\*(?!\*)([^\*_]+?)\*\*(?!\*)',
  }) : super(onTap: onTap, style: style, pattern: pattern) {
    renderText = ({String? str}) {
      return Matched(
        display: str?.substring(2, str.length - 2),
        value: str?.substring(2, str.length - 2),
      );
    };
  }
}

class ItalicParser extends ParserType {
  ItalicParser({
    Function(Matched)? onTap,
    TextStyle? style,
    String pattern = r'(?<!\w)(?<!\*)_(?!_)([^_\*]+?)[.,]?\_(?!\w)(?!\*)',
  }) : super(onTap: onTap, style: style, pattern: pattern) {
    renderText = ({String? str}) {
      return Matched(
        display: str?.substring(1, str.length - 1),
        value: str?.substring(1, str.length - 1),
      );
    };
  }
}

class UrlParser extends ParserType {
  UrlParser({
    Function(Matched)? onTap,
    TextStyle? style,
    String pattern = r'https?:\/\/[^\s]+',
  }) : super(onTap: onTap, style: style, pattern: pattern);
}
