class NewsArticle {
  final String id;
  final String title;
  final String source;
  final String url;
  final String imageUrl;
  final DateTime publishedAt;
  final String fullText;
  String? aiSummary;
  SentimentLabel? sentiment;
  String? triangleHint; // ✅ NEW
  bool isLoadingSummary;

  NewsArticle({
    required this.id,
    required this.title,
    required this.source,
    required this.url,
    this.imageUrl = '',
    required this.publishedAt,
    this.fullText = '',
    this.aiSummary,
    this.sentiment,
    this.triangleHint, // ✅ NEW
    this.isLoadingSummary = false,
  });

  factory NewsArticle.fromJson(Map<String, dynamic> json) {
    return NewsArticle(
      id: json['uuid'] ?? json['id'] ?? '',
      title: json['title'] ?? '',
      source: json['publisher'] ?? json['source'] ?? '',
      url: json['link'] ?? json['url'] ?? '',
      imageUrl: json['thumbnail']?['resolutions']?[0]?['url'] ?? '',
      publishedAt: _parsePublishedAt(json['providerPublishTime']),
      fullText: json['summary'] ?? '',
    );
  }

  // providerPublishTime arrives either as an ISO-8601 string (current
  // yfinance-backed /api/news) or a raw epoch-seconds number (older API
  // shape). A bare digit string like "1700000000" is not reliably rejected
  // by DateTime.tryParse — it can parse into a bogus date instead of
  // returning null — so digit-only values are routed straight to the
  // epoch-seconds path instead of through tryParse.
  static DateTime _parsePublishedAt(dynamic raw) {
    if (raw is num) {
      return DateTime.fromMillisecondsSinceEpoch((raw * 1000).round());
    }
    final str = raw?.toString() ?? '';
    if (RegExp(r'^\d+$').hasMatch(str)) {
      return DateTime.fromMillisecondsSinceEpoch((int.tryParse(str) ?? 0) * 1000);
    }
    return DateTime.tryParse(str) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
}

enum SentimentLabel { bullish, bearish, neutral }

extension SentimentLabelExtension on SentimentLabel {
  String get displayName {
    switch (this) {
      case SentimentLabel.bullish:
        return 'Bullish';
      case SentimentLabel.bearish:
        return 'Bearish';
      case SentimentLabel.neutral:
        return 'Neutral';
    }
  }

  String get emoji {
    switch (this) {
      case SentimentLabel.bullish:
        return '📈';
      case SentimentLabel.bearish:
        return '📉';
      case SentimentLabel.neutral:
        return '➡️';
    }
  }
}
