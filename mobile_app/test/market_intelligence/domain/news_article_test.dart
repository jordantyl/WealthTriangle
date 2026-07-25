import 'package:flutter_test/flutter_test.dart';
import 'package:wealth_triangle/market_intelligence/domain/news_article.dart';

void main() {
  group('NewsArticle.fromJson', () {
    test('parses the "uuid"/"publisher"/"link" JSON shape', () {
      final article = NewsArticle.fromJson({
        'uuid': 'abc123',
        'title': 'Markets rally',
        'publisher': 'Reuters',
        'link': 'https://example.com/a',
        'thumbnail': {
          'resolutions': [
            {'url': 'https://example.com/img.png'}
          ]
        },
        'providerPublishTime': 1700000000,
        'summary': 'Full text here.',
      });

      expect(article.id, 'abc123');
      expect(article.source, 'Reuters');
      expect(article.url, 'https://example.com/a');
      expect(article.imageUrl, 'https://example.com/img.png');
      expect(article.fullText, 'Full text here.');
      expect(article.publishedAt.millisecondsSinceEpoch, 1700000000000);
    });

    test('falls back to the "id"/"source"/"url" JSON shape', () {
      final article = NewsArticle.fromJson({
        'id': 'xyz789',
        'title': 'Fed holds rates',
        'source': 'Bloomberg',
        'url': 'https://example.com/b',
      });

      expect(article.id, 'xyz789');
      expect(article.source, 'Bloomberg');
      expect(article.url, 'https://example.com/b');
      expect(article.imageUrl, '');
    });

    test('parses an ISO-8601 publish date string (the current /api/news shape)', () {
      final article = NewsArticle.fromJson({
        'uuid': 'iso1',
        'providerPublishTime': '2024-01-15T14:30:00Z',
      });
      expect(article.publishedAt, DateTime.parse('2024-01-15T14:30:00Z'));
    });

    test('a bare digit-string publish time is treated as epoch seconds, not a bogus date', () {
      final article = NewsArticle.fromJson({
        'uuid': 'digitstr',
        'providerPublishTime': '1700000000',
      });
      expect(article.publishedAt.millisecondsSinceEpoch, 1700000000000);
    });

    test('missing fields default to empty strings without throwing', () {
      final article = NewsArticle.fromJson({});
      expect(article.id, '');
      expect(article.title, '');
      expect(article.source, '');
      expect(article.url, '');
    });
  });

  group('SentimentLabelExtension', () {
    test('each sentiment has the expected display name and emoji', () {
      expect(SentimentLabel.bullish.displayName, 'Bullish');
      expect(SentimentLabel.bullish.emoji, '📈');
      expect(SentimentLabel.bearish.displayName, 'Bearish');
      expect(SentimentLabel.bearish.emoji, '📉');
      expect(SentimentLabel.neutral.displayName, 'Neutral');
      expect(SentimentLabel.neutral.emoji, '➡️');
    });
  });
}
