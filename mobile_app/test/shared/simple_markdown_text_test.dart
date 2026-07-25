import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealth_triangle/shared/simple_markdown_text.dart';

void main() {
  Future<RichText> pumpAndGetRichText(WidgetTester tester, String text) async {
    await tester.pumpWidget(MaterialApp(home: SimpleMarkdownText(text)));
    return tester.widget<RichText>(find.byType(RichText));
  }

  testWidgets('plain text with no bold markers renders unchanged',
      (tester) async {
    final richText = await pumpAndGetRichText(tester, 'Hello world');
    final span = richText.text as TextSpan;
    expect(span.toPlainText(), 'Hello world');
  });

  testWidgets('renders **bold** segments as bold TextSpans, asterisks stripped',
      (tester) async {
    final richText =
        await pumpAndGetRichText(tester, 'This is **important** text');
    final span = richText.text as TextSpan;
    expect(span.toPlainText(), 'This is important text');

    final children = span.children!;
    expect(children.length, 3);
    expect((children[0] as TextSpan).text, 'This is ');
    expect((children[1] as TextSpan).text, 'important');
    expect((children[1] as TextSpan).style?.fontWeight, FontWeight.bold);
    expect((children[2] as TextSpan).text, ' text');
  });

  testWidgets('handles multiple bold segments', (tester) async {
    final richText =
        await pumpAndGetRichText(tester, '**Safety:** high. **Return:** low.');
    final span = richText.text as TextSpan;
    expect(span.toPlainText(), 'Safety: high. Return: low.');

    final boldChildren = span.children!
        .whereType<TextSpan>()
        .where((s) => s.style?.fontWeight == FontWeight.bold)
        .map((s) => s.text)
        .toList();
    expect(boldChildren, ['Safety:', 'Return:']);
  });

  testWidgets('an unclosed ** does not throw and is left as literal text',
      (tester) async {
    final richText = await pumpAndGetRichText(tester, 'Unclosed **bold text');
    final span = richText.text as TextSpan;
    expect(span.toPlainText(), 'Unclosed **bold text');
  });
}
