import 'package:flutter/material.dart';

/// Renders `**bold**` segments as actual bold text instead of showing the
/// literal asterisks. The AI assistant's replies use this markdown syntax,
/// but the chat bubble was a plain Text widget with no renderer for it.
/// Intentionally minimal — no external markdown package — since this is
/// the only markdown feature currently used, and the rest of the app's
/// dependency tree is already fairly old (avoids adding a heavier
/// integration surface for one syntax feature).
class SimpleMarkdownText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const SimpleMarkdownText(this.text, {super.key, this.style});

  static final RegExp _boldPattern = RegExp(r'\*\*(.+?)\*\*');

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    var lastEnd = 0;
    for (final match in _boldPattern.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    return RichText(text: TextSpan(style: style, children: spans));
  }
}
