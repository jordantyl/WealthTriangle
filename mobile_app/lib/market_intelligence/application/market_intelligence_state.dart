import 'package:flutter/material.dart';
import '../domain/news_article.dart';
import '../data/market_intelligence_api.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MarketIntelligenceState extends ChangeNotifier {
  final MarketIntelligenceService _api = MarketIntelligenceService();
  
  List<NewsArticle> _articles = [];
  bool _isLoading = false;
  String _filterSentiment = 'All';
  bool _isMockNews = false;

  // Getters for the UI to read
  List<NewsArticle> get articles => _articles;
  bool get isLoading => _isLoading;
  String get filterSentiment => _filterSentiment;
  // True when the current article list is fallback demo content, not a
  // real backend response (e.g. the backend is unreachable or returned no data).
  bool get isMockNews => _isMockNews;
  // expose underlying service for screens that need direct access
  MarketIntelligenceService get service => _api;

  List<NewsArticle> get filteredArticles {
    if (_filterSentiment == 'All') return _articles;
    return _articles.where((a) => a.sentiment?.displayName == _filterSentiment).toList();
  }

  // Load news from the API. Held (portfolio) tickers matter more than ones
  // merely on the watchlist, so they go first in the fetch list — the
  // backend only queries the first 5 tickers, and dedup keeps whichever
  // ticker's query surfaced an article first — then any article tagged with
  // a held ticker is sorted to the top of the feed. Same "held first"
  // convention as EventIntegrationState.loadData().
  Future<void> loadNews(List<String> watchlistTickers, {List<String> heldTickers = const []}) async {
    _isLoading = true;
    notifyListeners();

    final tickerSet = <String>{...heldTickers, ...watchlistTickers};
    final heldSet = heldTickers.map((t) => t.toUpperCase()).toSet();

    try {
      final fetched = await _api.fetchWatchlistNews(tickerSet.toList());
      for (final article in fetched) {
        article.isHeld = heldSet.contains(article.relatedTicker.toUpperCase());
      }
      fetched.sort((a, b) {
        if (a.isHeld != b.isHeld) return a.isHeld ? -1 : 1;
        return b.publishedAt.compareTo(a.publishedAt);
      });
      _articles = fetched;
      _isMockNews = _api.lastNewsFetchWasMock;

      // Classify the whole feed's sentiment right away (one batched AI
      // call) so cards show a Bullish/Bearish/Neutral badge immediately
      // instead of requiring a tap into each article. Best-effort: articles
      // stay unclassified (falls back to "Tap for AI analysis") if this
      // fails rather than blocking the feed from showing at all.
      if (!_isMockNews) {
        final sentiments = await _api.classifyArticles(fetched);
        for (final article in fetched) {
          final sentiment = sentiments[article.id];
          if (sentiment != null) article.sentiment = sentiment;
        }
      }
    } catch (e) {
      print("Error loading news: $e");
      _isMockNews = true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update filter
  void setFilter(String filter) {
    _filterSentiment = filter;
    notifyListeners();
  }

  // Generate AI Summary and update state
  Future<void> generateSummaryForArticle(NewsArticle article, String userId) async {
    if (article.isLoadingSummary) return;
    article.isLoadingSummary = true;
    notifyListeners();

    try {
      final result = await _api.requestAISummary(article.fullText.isNotEmpty ? article.fullText : article.title);
      article.aiSummary = result['summary'];
      article.sentiment = _api.parseSentiment(result['sentiment'] ?? 'Neutral');
      article.triangleHint = result['triangle_hint']; // ✅ SAVE HINT

      // ✅ SAVE TO FIRESTORE SO IT DOESN'T REGENERATE
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('article_summaries')
          .doc(article.id)
          .set({
        'summary': article.aiSummary,
        'sentiment': article.sentiment!.displayName,
        'triangle_hint': article.triangleHint, // ✅ SAVE HINT TO DB
        'timestamp': FieldValue.serverTimestamp(),
      });
      } finally {
      article.isLoadingSummary = false;
      notifyListeners();
      }
      }

      void updateArticleSummary(String articleId, String summary, SentimentLabel sentiment, String? hint) {
      final index = _articles.indexWhere((a) => a.id == articleId);
      if (index != -1) {
      _articles[index].aiSummary = summary;
      _articles[index].sentiment = sentiment;
      _articles[index].triangleHint = hint; // ✅ UPDATE HINT
      notifyListeners(); // ✅ TRIGGERS UI REFRESH
      }
      }
}