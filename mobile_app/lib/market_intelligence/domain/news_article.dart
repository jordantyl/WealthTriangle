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
      publishedAt: DateTime.tryParse(json['providerPublishTime']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(
              (json['providerPublishTime'] ?? 0) * 1000),
      fullText: json['summary'] ?? '',
    );
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
