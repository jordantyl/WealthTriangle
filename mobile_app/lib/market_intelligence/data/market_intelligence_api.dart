import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../domain/news_article.dart';
import '../../shared/backend_headers.dart';

class MarketIntelligenceService {
  // ✅ SECURITY FIX: OpenAI + RapidAPI keys removed from the app.
  // Everything goes through your Flask backend now.
  static String get _baseUrl =>
      dotenv.env['BACKEND_BASE_URL'] ?? 'http://10.0.2.2:5000';

  // Set right before returning, by both requestAISummary() and
  // fetchWatchlistNews(), so callers (and the UI) can tell fallback demo
  // content apart from a real backend response without changing either
  // method's return type.
  bool lastSummaryWasMock = false;
  bool lastNewsFetchWasMock = false;

  Future<Map<String, dynamic>> requestAISummary(String articleText) async {
    try {
      final headers = await authedBackendHeaders({'Content-Type': 'application/json'});
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/summarize'),
            headers: headers,
            body: json.encode({'text': articleText}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final parsed = json.decode(response.body);
        lastSummaryWasMock = false;
        return {
          'summary': parsed['summary'] ?? '',
          'sentiment': parsed['sentiment'] ?? 'Neutral',
          'triangle_hint': parsed['triangle_hint'] ??
              'Consider how this news affects the balance of Return, Safety, and Liquidity.',
        };
      }
    } catch (_) {
      // Fall through to mock response
    }

    // Mock response for development / offline demo
    lastSummaryWasMock = true;
    return {
      'summary':
          'This article discusses recent market developments that may impact investor portfolios. '
              'Analysts suggest monitoring key support levels before making any major investment decisions.',
      'sentiment': 'Neutral',
      'triangle_hint':
          '🔺 Market uncertainty affects Safety (volatility increases), but Liquidity remains high for large-cap stocks.',
    };
  }

  Future<List<NewsArticle>> fetchWatchlistNews(List<String> tickers) async {
    if (tickers.isEmpty) {
      lastNewsFetchWasMock = false;
      return [];
    }

    final symbols = tickers.join(',');

    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/news?symbols=$symbols'), headers: await authedBackendHeaders())
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final body = data['body'];
        if (body is List) {
          lastNewsFetchWasMock = false;
          return body.map((item) => NewsArticle.fromJson(item)).toList();
        }
        lastNewsFetchWasMock = true;
        return _getMockNews();
      } else {
        print("API Error fetching news: Status ${response.statusCode}");
        lastNewsFetchWasMock = true;
        return _getMockNews();
      }
    } catch (e) {
      print("Error fetching watchlist news: $e");
      lastNewsFetchWasMock = true;
      return _getMockNews();
    }
  }

  /// Classifies a whole batch of articles as Bullish/Bearish/Neutral in ONE
  /// AI call (see backend's /api/classify_news) instead of one call per
  /// article — auto-runs right after fetchWatchlistNews() so the feed shows
  /// sentiment badges immediately, without the user tapping into each
  /// article individually. Returns an id -> SentimentLabel map; missing/failed
  /// entries are simply absent (callers leave those articles unclassified
  /// rather than showing a guessed sentiment).
  Future<Map<String, SentimentLabel>> classifyArticles(List<NewsArticle> articles) async {
    if (articles.isEmpty) return {};
    try {
      final headers = await authedBackendHeaders({'Content-Type': 'application/json'});
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/classify_news'),
            headers: headers,
            body: json.encode({
              'articles': articles
                  .map((a) => {
                        'id': a.id,
                        'title': a.title,
                        'text': a.fullText,
                      })
                  .toList(),
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'];
        if (results is List) {
          final map = <String, SentimentLabel>{};
          for (final entry in results) {
            final id = entry['id']?.toString();
            final sentiment = entry['sentiment']?.toString();
            if (id != null && sentiment != null) {
              map[id] = parseSentiment(sentiment);
            }
          }
          return map;
        }
      }
    } catch (e) {
      print("Error classifying news: $e");
    }
    return {};
  }

  SentimentLabel parseSentiment(String raw) {
    switch (raw.toLowerCase()) {
      case 'bullish':
        return SentimentLabel.bullish;
      case 'bearish':
        return SentimentLabel.bearish;
      default:
        return SentimentLabel.neutral;
    }
  }

  List<NewsArticle> _getMockNews() {
    return [
      NewsArticle(
        id: '1',
        title: 'Fed Holds Interest Rates Steady Amid Inflation Concerns',
        source: 'Reuters',
        url: 'https://reuters.com',
        publishedAt: DateTime.now().subtract(const Duration(hours: 2)),
        fullText:
            'The Federal Reserve held interest rates steady at its latest meeting, citing ongoing concerns about the pace of economic recovery and persistent inflation. While the job market has shown signs of improvement, the central bank is taking a cautious approach before making any changes to its monetary policy.',
      ),
      NewsArticle(
        id: '2',
        title: 'Tech Stocks Rally on Strong Earnings Reports',
        source: 'Bloomberg',
        url: 'https://bloomberg.com',
        publishedAt: DateTime.now().subtract(const Duration(hours: 5)),
        fullText:
            'Major technology companies reported better-than-expected earnings this quarter, driving a significant rally in the Nasdaq. Investors are optimistic about the sector\'s growth prospects, despite broader market volatility.',
      ),
      NewsArticle(
        id: '3',
        title: 'Oil Prices Fluctuate as OPEC+ Debates Production Levels',
        source: 'Wall Street Journal',
        url: 'https://wsj.com',
        publishedAt: DateTime.now().subtract(const Duration(days: 1)),
        fullText:
            'Crude oil prices saw significant fluctuation this week as OPEC+ members engaged in heated debates over future production quotas. The outcome of these talks could have a major impact on global energy markets and inflation.',
      ),
    ];
  }
}