import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../domain/news_article.dart';
import '../data/market_intelligence_api.dart';
import '../../shared/app_theme_colors.dart';

class NewsDetailScreen extends StatefulWidget {
  final NewsArticle article;
  final MarketIntelligenceService service;
  final Function(String summary, SentimentLabel sentiment, String? hint) onSummaryGenerated;

  const NewsDetailScreen({
    super.key,
    required this.article,
    required this.service,
    required this.onSummaryGenerated,
  });

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  bool _isGenerating = false;
  String? _summary;
  SentimentLabel? _sentiment;
  String? _triangleHint;
  bool _isMockSummary = false;

  @override
  void initState() {
    super.initState();
    _summary = widget.article.aiSummary;
    _sentiment = widget.article.sentiment;
    _triangleHint = widget.article.triangleHint; // ✅ INIT HINT
    // Auto-generate if no summary yet
    if (_summary == null) _generateSummary();
  }

  Future<void> _generateSummary() async {
    if (_isGenerating) return;
    setState(() => _isGenerating = true);

    final userId = FirebaseAuth.instance.currentUser?.uid;
    final cacheRef = userId == null
        ? null
        : FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('article_summaries')
            .doc(widget.article.id);

    // Check the cache first so re-opening an already-summarized article
    // doesn't re-hit the AI backend (and burn API quota) every time.
    if (cacheRef != null) {
      try {
        final cached = await cacheRef.get();
        if (cached.exists) {
          final data = cached.data()!;
          final sentiment = widget.service.parseSentiment(data['sentiment'] ?? 'Neutral');
          if (mounted) {
            setState(() {
              _summary = data['summary'];
              _sentiment = sentiment;
              _triangleHint = data['triangle_hint'];
              _isMockSummary = data['isMock'] ?? false;
              _isGenerating = false;
            });
            widget.onSummaryGenerated(_summary!, sentiment, _triangleHint);
          }
          return;
        }
      } catch (_) {
        // Fall through and regenerate if the cache read fails.
      }
    }

    final result = await widget.service
        .requestAISummary(widget.article.fullText.isNotEmpty
            ? widget.article.fullText
            : widget.article.title);

    final sentiment = widget.service.parseSentiment(result['sentiment'] ?? 'Neutral');

    final isMock = widget.service.lastSummaryWasMock;

    if (mounted) {
      setState(() {
        _summary = result['summary'];
        _sentiment = sentiment;
        _triangleHint = result['triangle_hint']; // ✅ NEW
        _isMockSummary = isMock;
        _isGenerating = false;
      });
      widget.onSummaryGenerated(_summary!, sentiment, _triangleHint); // ✅ PASS HINT
    }

    if (cacheRef != null) {
      try {
        await cacheRef.set({
          'summary': result['summary'],
          'sentiment': sentiment.displayName,
          'triangle_hint': result['triangle_hint'],
          'isMock': isMock,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // Non-fatal — the summary still displays even if caching fails.
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: colors.textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.article.source,
          style: const TextStyle(
            color: Color(0xFF1E88E5),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.open_in_browser, color: colors.textSecondary),
            onPressed: () async {
              final uri = Uri.parse(widget.article.url);
              if (await canLaunchUrl(uri)) launchUrl(uri);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.article.imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  widget.article.imageUrl,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              widget.article.title,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.article.source} · ${_timeAgo(widget.article.publishedAt)}',
              style: TextStyle(color: colors.textTertiary, fontSize: 12),
            ),
            const SizedBox(height: 24),

            // AI Analysis Card
            _buildAICard(),

            const SizedBox(height: 24),

            // Original article text
            if (widget.article.fullText.isNotEmpty) ...[
              Text(
                'Article Preview',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.article.fullText,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Read full article button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final uri = Uri.parse(widget.article.url);
                  if (await canLaunchUrl(uri)) launchUrl(uri);
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Read Full Article'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1E88E5),
                  side: const BorderSide(color: Color(0xFF1E88E5)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAICard() {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E88E5).withOpacity(0.12),
            const Color(0xFF0D47A1).withOpacity(0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E88E5).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🤖', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text(
                'AI Beginner Summary',
                style: TextStyle(
                  color: Color(0xFF1E88E5),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              if (_isMockSummary)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.withOpacity(0.5)),
                  ),
                  child: const Text('Demo',
                      style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              if (_sentiment != null) _buildSentimentChip(_sentiment!),
            ],
          ),
          const SizedBox(height: 14),
          if (_isGenerating)
            const _TypingIndicator()
          else if (_summary != null) ...[
            Text(
              _summary!,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 12),
            // ✅ NEW: Triangle Hint
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🔺 ', style: TextStyle(fontSize: 14)),
                  Expanded(
                    child: Text(
                      _triangleHint ?? '🔺 Consider how this news affects the balance of Return, Safety, and Liquidity.',
                      style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Text(
              'Unable to generate summary. Please try again.',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ],
          if (!_isGenerating && _summary != null) ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _generateSummary,
              child: const Text(
                '↺ Regenerate',
                style: TextStyle(
                  color: Color(0xFF1E88E5),
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSentimentChip(SentimentLabel sentiment) {
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        '${sentiment.emoji} ${sentiment.displayName}',
        style: TextStyle(
            color: color, fontSize: 12, fontWeight: FontWeight.w600),
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

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Analyzing article',
          style: TextStyle(color: context.appColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(width: 4),
        ...List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) {
              final delay = i * 0.3;
              final opacity =
                  (_ctrl.value - delay).clamp(0.0, 1.0);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Opacity(
                  opacity: opacity,
                  child: const Text(
                    '.',
                    style: TextStyle(
                        color: Color(0xFF1E88E5),
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              );
            },
          );
        }),
      ],
    );
  }
}
