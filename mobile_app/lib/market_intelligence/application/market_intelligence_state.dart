import 'dart:async';
import 'package:flutter/material.dart';
import '../domain/news_article.dart';
import '../data/market_intelligence_api.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Which subset of fetched articles to show. Independent of the sentiment
// filter and of the ticker-level narrowing below — a ticker can be held
// without being watchlisted, or vice versa, so these aren't just two ends
// of one boolean.
enum NewsScope { all, watchlist, holdings }

class MarketIntelligenceState extends ChangeNotifier {
  final MarketIntelligenceService _api = MarketIntelligenceService();

  List<NewsArticle> _articles = [];
  bool _isLoading = false;
  String _filterSentiment = 'All';
  NewsScope _scope = NewsScope.all;
  Set<String> _selectedTickers = {};
  bool _isMockNews = false;

  // The watchlist/holdings tickers behind the most recent full loadNews()
  // call — kept so a later ticker-specific selection can re-fetch scoped to
  // just those tickers (see loadNewsForTickers) without the caller having
  // to pass everything again, and so isHeld/isWatchlisted can still be
  // computed correctly against the *full* lists even on a scoped fetch.
  List<String> _lastWatchlistTickers = [];
  List<String> _lastHeldTickers = [];

  // Guards against fast filter-switching (scope/ticker taps before the
  // previous fetch has returned) firing overlapping requests whose
  // responses can land out of order — without this, an earlier (now-stale)
  // request finishing *after* a newer one would overwrite fresh results
  // with old ones, and if that stale request happened to fail/time out, it
  // could flip the feed to demo data even though the latest request already
  // succeeded. Every _fetch() call captures the generation it was started
  // at and discards its own result if a newer call has since begun.
  int _requestGeneration = 0;
  // Also collapses genuinely rapid re-taps (e.g. mashing ticker chips) into
  // a single request instead of firing one per tap, cutting real request
  // volume rather than just fixing the ordering after the fact.
  Timer? _debounce;

  // Getters for the UI to read
  List<NewsArticle> get articles => _articles;
  bool get isLoading => _isLoading;
  String get filterSentiment => _filterSentiment;
  NewsScope get scope => _scope;
  Set<String> get selectedTickers => _selectedTickers;
  // All tickers available to filter by within the current scope — used to
  // build the ticker chip row.
  List<String> get tickersForCurrentScope {
    switch (_scope) {
      case NewsScope.watchlist:
        return _lastWatchlistTickers;
      case NewsScope.holdings:
        return _lastHeldTickers;
      case NewsScope.all:
        return <String>{..._lastHeldTickers, ..._lastWatchlistTickers}.toList();
    }
  }
  // True when the current article list is fallback demo content, not a
  // real backend response (e.g. the backend is unreachable or returned no data).
  bool get isMockNews => _isMockNews;
  // expose underlying service for screens that need direct access
  MarketIntelligenceService get service => _api;

  // Scope + ticker-chip narrowing only, no sentiment filter — used by the
  // Market Pulse header so its Bullish/Bearish/Neutral breakdown reflects
  // the current scope/tickers without also being narrowed by whichever
  // sentiment sub-tab is selected (that would e.g. zero out Bearish/Neutral
  // counts whenever the "Bullish" sub-tab is active).
  List<NewsArticle> get articlesInScope {
    var list = _articles;
    switch (_scope) {
      case NewsScope.watchlist:
        list = list.where((a) => a.isWatchlisted).toList();
        break;
      case NewsScope.holdings:
        list = list.where((a) => a.isHeld).toList();
        break;
      case NewsScope.all:
        break;
    }
    if (_selectedTickers.isNotEmpty) {
      list = list.where((a) => _selectedTickers.contains(a.relatedTicker.toUpperCase())).toList();
    }
    return list;
  }

  List<NewsArticle> get filteredArticles {
    var list = articlesInScope;
    if (_filterSentiment != 'All') {
      list = list.where((a) => a.sentiment?.displayName == _filterSentiment).toList();
    }
    return list;
  }

  // Load news from the API. Held (portfolio) tickers matter more than ones
  // merely on the watchlist, so they go first in the fetch list — the
  // backend only queries the first 5 tickers, and dedup keeps whichever
  // ticker's query surfaced an article first — then any article tagged with
  // a held ticker is sorted to the top of the feed. Same "held first"
  // convention as EventIntegrationState.loadData().
  Future<void> loadNews(List<String> watchlistTickers, {List<String> heldTickers = const []}) async {
    _lastWatchlistTickers = watchlistTickers;
    _lastHeldTickers = heldTickers;
    _selectedTickers = {};
    final tickerSet = <String>{...heldTickers, ...watchlistTickers};
    await _fetch(tickerSet.toList());
  }

  // Re-fetch scoped to exactly the given tickers — used when the user picks
  // specific ticker(s) to filter by, so those tickers are guaranteed to
  // actually get queried instead of possibly being past the backend's
  // first-5 cutoff in the combined watchlist+holdings list. Debounced so
  // quickly tapping through several ticker chips fires one request for
  // wherever you land, not one per tap.
  void loadNewsForTickers(Set<String> tickers) {
    _selectedTickers = tickers;
    notifyListeners(); // reflect the chip selection immediately even before the debounced fetch lands
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final targets = tickers.isEmpty
          ? <String>{..._lastHeldTickers, ..._lastWatchlistTickers}.toList()
          : tickers.toList();
      _fetch(targets);
    });
  }

  Future<void> _fetch(List<String> tickersToQuery) async {
    final myGeneration = ++_requestGeneration;
    _isLoading = true;
    notifyListeners();

    final heldSet = _lastHeldTickers.map((t) => t.toUpperCase()).toSet();
    final watchlistSet = _lastWatchlistTickers.map((t) => t.toUpperCase()).toSet();

    try {
      final fetched = await _api.fetchWatchlistNews(tickersToQuery);
      if (myGeneration != _requestGeneration) return; // superseded by a newer request — discard

      for (final article in fetched) {
        final ticker = article.relatedTicker.toUpperCase();
        article.isHeld = heldSet.contains(ticker);
        article.isWatchlisted = watchlistSet.contains(ticker);
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
        if (myGeneration != _requestGeneration) return; // superseded mid-classification — discard
        for (final article in fetched) {
          final sentiment = sentiments[article.id];
          if (sentiment != null) article.sentiment = sentiment;
        }
      }
    } catch (e) {
      print("Error loading news: $e");
      if (myGeneration != _requestGeneration) return; // superseded — don't flip a fresher feed to demo data
      _isMockNews = true;
    } finally {
      if (myGeneration == _requestGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  // Update filter
  void setFilter(String filter) {
    _filterSentiment = filter;
    notifyListeners();
  }

  void setScope(NewsScope value) {
    _scope = value;
    // If a ticker-narrowed fetch was active, _articles only holds that
    // narrow set — switching scope needs the full held+watchlist set back,
    // not just a client-side refilter of the narrow data.
    final wasNarrowed = _selectedTickers.isNotEmpty;
    _selectedTickers = {};
    if (wasNarrowed) {
      _fetch(<String>{..._lastHeldTickers, ..._lastWatchlistTickers}.toList());
    } else {
      notifyListeners();
    }
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

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}