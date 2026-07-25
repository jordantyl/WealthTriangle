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

  // Load news from the API
  Future<void> loadNews(List<String> watchlistTickers) async {
    _isLoading = true;
    notifyListeners();

    try {
      _articles = await _api.fetchWatchlistNews(watchlistTickers);
      _isMockNews = _api.lastNewsFetchWasMock;
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