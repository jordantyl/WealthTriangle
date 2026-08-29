import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Add Provider
import '../domain/news_article.dart';
import '../application/market_intelligence_state.dart';
import '../../shared/app_theme_colors.dart';
import '../../investment/application/portfolio_state.dart';
import 'news_detail_screen.dart';

class MarketIntelligenceScreen extends StatefulWidget {
  final List<String> watchlistTickers;

  const MarketIntelligenceScreen({
    super.key,
    this.watchlistTickers = const ['AAPL', 'TSLA', 'MSFT', 'GOOGL'],
  });

  @override
  State<MarketIntelligenceScreen> createState() =>
      _MarketIntelligenceScreenState();
}

class _MarketIntelligenceScreenState extends State<MarketIntelligenceScreen> {
  // Held tickers this screen's last news fetch was scoped to — compared
  // against the live portfolio on every build (see build()) so a holding
  // that hadn't loaded yet when initState() first fired (PortfolioState's
  // Firestore snapshot is async and can easily lose that race) still gets
  // picked up as soon as it does, instead of being permanently missing
  // from the feed until the user manually refreshes.
  List<String> _fetchedHeldTickers = [];

  List<String> _heldTickersFrom(PortfolioState portfolio) =>
      portfolio.holdings.map((h) => h.ticker).toList();

  void _load(List<String> heldTickers) {
    _fetchedHeldTickers = heldTickers;
    Provider.of<MarketIntelligenceState>(context, listen: false)
        .loadNews(widget.watchlistTickers, heldTickers: heldTickers);
  }

  bool _sameTickers(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    // Fetch data using Provider on load
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _load(_heldTickersFrom(Provider.of<PortfolioState>(context, listen: false))));
  }

  @override
  Widget build(BuildContext context) {
    // Listen to the Application State
    final state = Provider.of<MarketIntelligenceState>(context);
    final colors = context.appColors;

    // Watching PortfolioState (not listen: false) so this rebuilds once the
    // holdings snapshot actually arrives — re-fetching then if it differs
    // from what the last fetch was scoped to.
    final currentHeldTickers = _heldTickersFrom(Provider.of<PortfolioState>(context));
    if (!_sameTickers(currentHeldTickers, _fetchedHeldTickers)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(currentHeldTickers));
    }

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        title: const Text('Market Intelligence'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: colors.textSecondary),
            onPressed: () => _load(currentHeldTickers),
          ),
        ],
      ),
      body: Column(
        children: [
          if (state.isMockNews) _buildDemoDataBanner(),
          _buildScopeSelector(state),
          if (state.tickersForCurrentScope.isNotEmpty) ...[
            _buildTickerChips(state),
            const SizedBox(height: 8),
          ],
          _buildSentimentFilterBar(state),
          _buildMarketPulseHeader(state),
          Expanded(
            child: state.isLoading
                ? _buildLoadingState()
                : state.filteredArticles.isEmpty
                    ? _buildEmptyState(state.filterSentiment)
                    : _buildNewsFeed(state),
          ),
        ],
      ),
    );
  }

  Widget _buildDemoDataBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withOpacity(0.4)),
      ),
      child: Row(
        children: const [
          Icon(Icons.info_outline, color: Colors.amber, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Showing demo data — backend news API isn\'t reachable or configured.',
              style: TextStyle(color: Colors.amber, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarketPulseHeader(MarketIntelligenceState state) {
    final colors = context.appColors;
    // Scoped to articlesInScope (not the raw state.articles) so this
    // reflects whichever scope/ticker filter is currently selected — it
    // used to always show the full unfiltered feed's counts, making it
    // look identical across All/Watchlist/Holdings. Deliberately not using
    // filteredArticles here since that also applies the sentiment sub-tab,
    // which would zero out two of the three counts whenever a sentiment
    // other than "All" is selected.
    final scopedArticles = state.articlesInScope;
    final bullishCount = scopedArticles
        .where((a) => a.sentiment == SentimentLabel.bullish)
        .length;
    final bearishCount = scopedArticles
        .where((a) => a.sentiment == SentimentLabel.bearish)
        .length;
    final total = scopedArticles.where((a) => a.sentiment != null).length;
    final neutralCount = total - bullishCount - bearishCount;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Market Pulse',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildPulseChip('Bullish', bullishCount, const Color(0xFF4CAF50)),
              const SizedBox(width: 8),
              _buildPulseChip('Bearish', bearishCount, const Color(0xFFE53935)),
              const SizedBox(width: 8),
              _buildPulseChip('Neutral', neutralCount, const Color(0xFF607D8B)),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 6,
                child: Row(
                  children: [
                    if (bullishCount > 0)
                      Expanded(
                        flex: bullishCount,
                        child: Container(color: const Color(0xFF4CAF50)),
                      ),
                    if (neutralCount > 0)
                      Expanded(
                        flex: neutralCount,
                        child: Container(color: const Color(0xFF607D8B)),
                      ),
                    if (bearishCount > 0)
                      Expanded(
                        flex: bearishCount,
                        child: Container(color: const Color(0xFFE53935)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              total > 0
                  ? bullishCount > bearishCount
                      ? '📈 Overall Bullish Sentiment'
                      : bearishCount > bullishCount
                          ? '📉 Overall Bearish Sentiment'
                          : '➡️ Mixed Sentiment'
                  : 'Tap articles to generate AI summaries',
              style: TextStyle(color: colors.textSecondary, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPulseChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            '$label ($count)',
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // Scope selector — Watchlist and Holdings are independent sets (a ticker
  // can be one, the other, both, or neither), so this replaced a single
  // "Held tickers only" checkbox that could only express one of them.
  Widget _buildScopeSelector(MarketIntelligenceState state) {
    final colors = context.appColors;
    const scopes = [
      (NewsScope.all, 'All', Icons.dynamic_feed),
      (NewsScope.watchlist, 'Watchlist', Icons.visibility_outlined),
      (NewsScope.holdings, 'Holdings', Icons.pie_chart_outline),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          for (final (value, label, icon) in scopes) ...[
            Expanded(
              child: GestureDetector(
                onTap: () => state.setScope(value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: state.scope == value ? const Color(0xFFFFA726) : colors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: state.scope == value ? const Color(0xFFFFA726) : colors.border,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(icon,
                          size: 16,
                          color: state.scope == value ? Colors.white : colors.textSecondary),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        style: TextStyle(
                          color: state.scope == value ? Colors.white : colors.textSecondary,
                          fontSize: 11,
                          fontWeight: state.scope == value ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (value != NewsScope.holdings) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  // Narrows further to specific ticker(s) within the current scope.
  // Selecting one re-fetches scoped to just the picked tickers (see
  // MarketIntelligenceState.loadNewsForTickers) so it isn't at the mercy of
  // the backend's first-5-tickers cap when the full list is longer than that.
  Widget _buildTickerChips(MarketIntelligenceState state) {
    final colors = context.appColors;
    final tickers = state.tickersForCurrentScope;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        scrollDirection: Axis.horizontal,
        itemCount: tickers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final ticker = tickers[i].toUpperCase();
          final isSelected = state.selectedTickers.contains(ticker);
          return GestureDetector(
            onTap: () {
              final next = Set<String>.from(state.selectedTickers);
              isSelected ? next.remove(ticker) : next.add(ticker);
              state.loadNewsForTickers(next);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF1E88E5) : colors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? const Color(0xFF1E88E5) : colors.border,
                ),
              ),
              child: Text(
                ticker,
                style: TextStyle(
                  color: isSelected ? Colors.white : colors.textSecondary,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSentimentFilterBar(MarketIntelligenceState state) {
    final colors = context.appColors;
    const filters = ['All', 'Bullish', 'Bearish', 'Neutral'];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final isSelected = state.filterSentiment == filters[i];
          return GestureDetector(
            onTap: () => state.setFilter(filters[i]),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF1E88E5) : colors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? const Color(0xFF1E88E5) : colors.border,
                ),
              ),
              child: Text(
                filters[i],
                style: TextStyle(
                  color: isSelected ? Colors.white : colors.textSecondary,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNewsFeed(MarketIntelligenceState state) {
    final colors = context.appColors;
    return RefreshIndicator(
      onRefresh: () async =>
          _load(_heldTickersFrom(Provider.of<PortfolioState>(context, listen: false))),
      color: const Color(0xFF1E88E5),
      backgroundColor: colors.surface,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: state.filteredArticles.length,
        itemBuilder: (context, index) =>
            _buildNewsCard(state.filteredArticles[index], state),
      ),
    );
  }

  Widget _buildNewsCard(NewsArticle article, MarketIntelligenceState state) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NewsDetailScreen(
            article: article,
            service: state.service,
            onSummaryGenerated: (summary, sentiment, hint) {
              // ✅ Update central state instead of local setState
              state.updateArticleSummary(article.id, summary, sentiment, hint);
            },
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (article.imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: Image.network(
                  article.imageUrl,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Held/watchlist + source + sentiment badge row
                  Row(
                    children: [
                      if (article.isHeld) ...[
                        _buildHeldBadge(),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        article.source.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF1E88E5),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const Spacer(),
                      if (article.sentiment != null)
                        _buildSentimentBadge(article.sentiment!)
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: colors.surfaceAlt,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Tap for AI analysis',
                            style:
                                TextStyle(color: colors.textTertiary, fontSize: 10),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    article.title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // AI Summary preview
                  if (article.aiSummary != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.surfaceAlt,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFF1E88E5).withOpacity(0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('🤖 ', style: TextStyle(fontSize: 12)),
                          Expanded(
                            child: Text(
                              article.aiSummary!,
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 12,
                                height: 1.4,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  // ✅ NEW: Triangle Hint
                  if (article.triangleHint != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.surfaceAlt,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFF4A90E2).withOpacity(0.4)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('🔺 ', style: TextStyle(fontSize: 12)),
                          Expanded(
                            child: Text(
                              article.triangleHint!,
                              style: const TextStyle(
                                color: Color(0xFF4A90E2),
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                                height: 1.4,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    _timeAgo(article.publishedAt),
                    style: TextStyle(color: colors.textTertiary, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Same "📌 Held" convention as event_calendar_screen.dart's held/watchlist
  // badge — marks news whose relatedTicker is something the user owns.
  Widget _buildHeldBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFA726).withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFA726).withOpacity(0.5)),
      ),
      child: const Text(
        '📌 Held',
        style: TextStyle(
          color: Color(0xFFFFA726),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildSentimentBadge(SentimentLabel sentiment) {
    final Color color;
    switch (sentiment) {
      case SentimentLabel.bullish:
        color = const Color(0xFF4CAF50);
        break;
      case SentimentLabel.bearish:
        color = const Color(0xFFE53935);
        break;
      case SentimentLabel.neutral:
        color = const Color(0xFF607D8B);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        '${sentiment.emoji} ${sentiment.displayName}',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    final colors = context.appColors;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 140,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: CircularProgressIndicator(
            color: Color(0xFF1E88E5),
            strokeWidth: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String filterSentiment) {
    final colors = context.appColors;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('📰', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(
            filterSentiment == 'All'
                ? 'No news available'
                : 'No $filterSentiment articles yet',
            style: TextStyle(color: colors.textPrimary, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap articles to generate AI summaries\nand build your sentiment feed.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textTertiary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
