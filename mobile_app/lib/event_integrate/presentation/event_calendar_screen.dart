import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../application/event_intelligence_state.dart';
import '../domain/economic_event.dart';
import '../../investment/application/portfolio_state.dart';
import '../../shared/app_theme_colors.dart';
import 'add_liquidity_event.dart';



class EventCalendarScreen extends StatefulWidget {
  final String userId;
  final List<String> watchlistTickers;

  const EventCalendarScreen({
    super.key,
    required this.userId,
    this.watchlistTickers = const ['AAPL', 'MSFT', 'TSLA', 'GOOGL'],
  });

  @override
  State<EventCalendarScreen> createState() => _EventCalendarScreenState();
}

class _EventCalendarScreenState extends State<EventCalendarScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reloadData());
  }

  List<String> get _heldTickers => Provider.of<PortfolioState>(context, listen: false)
      .holdings
      .map((h) => h.ticker)
      .toList();

  void _reloadData() {
    Provider.of<EventIntegrationState>(context, listen: false)
        .loadData(widget.userId, widget.watchlistTickers, heldTickers: _heldTickers);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<EventIntegrationState>(context);
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        title: const Text('Economic Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddLiquidityEventScreen()),
              );
              if (mounted) _reloadData();
            },
            tooltip: 'Add Liquidity Event',
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: colors.textSecondary),
            onPressed: _reloadData,
          ),

        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF1E88E5),
          labelColor: const Color(0xFF1E88E5),
          unselectedLabelColor: colors.textTertiary,
          tabs: const [
            Tab(text: 'Calendar'),
            Tab(text: 'Alerts'),
          ],
        ),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1E88E5)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCalendarTab(state),
                _buildAlertsTab(state),
              ],
            ),
    );
  }

  Widget _buildCalendarTab(EventIntegrationState state) {
    final colors = context.appColors;
    final filtered = state.filteredEvents;
    final thisWeek = filtered.where((e) => e.isThisWeek).toList();
    final upcoming = filtered.where((e) => !e.isThisWeek).toList();

    return Column(
      children: [
        if (state.isMockEvents) _buildDemoDataBanner(),
        if (state.skippedTickerCount > 0) _buildSkippedTickersBanner(state.skippedTickerCount),
        _buildHeldOnlyToggle(state),
        _buildEventTypeFilter(state),
        _buildCountdownBanner(state),
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyState()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (thisWeek.isNotEmpty) ...[
                      _buildSectionLabel('⚡ This Week', const Color(0xFFFF9800)),
                      ...thisWeek.map((e) => _buildEventCard(e, state)),
                      const SizedBox(height: 8),
                    ],
                    if (upcoming.isNotEmpty) ...[
                      _buildSectionLabel('📅 Upcoming', colors.textTertiary),
                      ...upcoming.map((e) => _buildEventCard(e, state)),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildAlertsTab(EventIntegrationState state) {
    final colors = context.appColors;
    final alerted = state.events.where((e) => e.isAlertEnabled).toList();
    if (alerted.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🔔', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text('No alerts set', style: TextStyle(color: colors.textPrimary, fontSize: 16)),
            const SizedBox(height: 8),
            Text('Tap the bell icon on any event\nto get notified before it happens.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textTertiary, fontSize: 13)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: alerted.length,
      itemBuilder: (context, i) => _buildEventCard(alerted[i], state),
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
              'Showing demo earnings/dividend events — backend calendar API isn\'t reachable or configured.',
              style: TextStyle(color: Colors.amber, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkippedTickersBanner(int count) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueGrey.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.blueGrey, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Showing events for your first 8 held/watchlist tickers — $count more ${count == 1 ? "isn't" : "aren't"} included.',
              style: const TextStyle(color: Colors.blueGrey, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
    );
  }

  Widget _buildCountdownBanner(EventIntegrationState state) {
    final colors = context.appColors;
    final next = state.events.where((e) => e.isUpcoming).firstOrNull;
    if (next == null) return const SizedBox.shrink();

    final typeColor = Color(next.type.colorValue);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [typeColor.withOpacity(0.2), typeColor.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: typeColor.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Text(next.type.icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Next Event in ${next.daysUntil} day${next.daysUntil == 1 ? '' : 's'}',
                    style: TextStyle(color: colors.textSecondary, fontSize: 11)),
                Text(next.title, style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Text(DateFormat('MMM d').format(next.eventDate),
              style: TextStyle(color: typeColor, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  // The "market filter" — narrows events down to tickers the user actually
  // holds (event.isHeld), alongside the existing event-type filter. The
  // isHeld data already fed the 📌 Held badge on event cards; this is the
  // first place it's exposed as an actual filter toggle.
  Widget _buildHeldOnlyToggle(EventIntegrationState state) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: GestureDetector(
        onTap: () => state.setHeldOnly(!state.heldOnly),
        child: Row(
          children: [
            Icon(
              state.heldOnly ? Icons.check_box : Icons.check_box_outline_blank,
              size: 18,
              color: state.heldOnly ? const Color(0xFFFFA726) : colors.textTertiary,
            ),
            const SizedBox(width: 6),
            Text(
              'Held tickers only',
              style: TextStyle(
                color: state.heldOnly ? const Color(0xFFFFA726) : colors.textSecondary,
                fontSize: 13,
                fontWeight: state.heldOnly ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventTypeFilter(EventIntegrationState state) {
    final colors = context.appColors;
    final types = [null, ...EventType.values];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: types.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final type = types[i];
          final isSelected = state.selectedFilter == type;
          final label = type == null ? 'All' : type.displayName;

          return GestureDetector(
            onTap: () => state.setFilter(type),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF1E88E5) : colors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSelected ? const Color(0xFF1E88E5) : colors.border),
              ),
              child: Text(
                type != null ? '${type.icon} $label' : label,
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

  Widget _buildEventCard(EconomicEvent event, EventIntegrationState state) {
    final colors = context.appColors;
    final typeColor = Color(event.type.colorValue);
    final isThisWeek = event.isThisWeek;
    // Only stock-specific events have a meaningful held/watchlist distinction —
    // market-wide events (Fed decisions, etc.) have no ticker.
    final hasOwnershipBadge = event.ticker != null && event.ticker != 'MARKET';

    // Built with a plain Row/Column instead of ListTile: ListTile assumes a
    // fixed subtitle height (roughly 2 lines), but this subtitle's line count
    // varies with the data (description + triangle note + tags row can add
    // up to 4+ lines), which overflowed ListTile's box by a pixel or two.
    // A Column sizes to its actual content, so this can't happen.
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isThisWeek ? typeColor.withOpacity(0.5) : colors.border,
          width: isThisWeek ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: typeColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Text(event.type.icon, style: const TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title, style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                if (event.description != null) ...[
                  const SizedBox(height: 4),
                  Text(event.description!, style: TextStyle(color: colors.textSecondary, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
                if (event.triangleNote != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🔺', style: TextStyle(fontSize: 11, color: Colors.amber.withOpacity(0.8))),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          event.triangleNote!,
                          style: TextStyle(color: Colors.amber.withOpacity(0.8), fontSize: 11, fontStyle: FontStyle.italic),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (hasOwnershipBadge)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: (event.isHeld ? const Color(0xFF4CAF50) : Colors.blueGrey)
                              .withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          event.isHeld ? '📌 Held' : '👁 Watchlist',
                          style: TextStyle(
                            color: event.isHeld ? const Color(0xFF4CAF50) : Colors.blueGrey[200],
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: typeColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(event.type.displayName,
                          style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.w600)),
                    ),
                    if (event.dividendAmount != null)
                      Text('\$${event.dividendAmount!.toStringAsFixed(2)}/share',
                          style: const TextStyle(color: Color(0xFF4CAF50), fontSize: 11)),
                    if (event.estimatedEPS != null)
                      Text('Est. EPS: ${event.estimatedEPS}',
                          style: TextStyle(color: colors.textTertiary, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: () => _toggleAlert(event, state),
                child: Icon(
                  event.isAlertEnabled ? Icons.notifications_active : Icons.notifications_none,
                  color: event.isAlertEnabled ? const Color(0xFFFFB300) : colors.textTertiary,
                  size: 20,
                ),
              ),
              const SizedBox(height: 4),
              Text(DateFormat('MMM d').format(event.eventDate),
                  style: TextStyle(color: colors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
              Text(event.daysUntil == 0 ? 'Today' : '${event.daysUntil}d',
                  style: TextStyle(color: event.daysUntil <= 3 ? const Color(0xFFFF9800) : colors.textTertiary, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final colors = context.appColors;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('📅', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text('No upcoming events', style: TextStyle(color: colors.textPrimary, fontSize: 16)),
          const SizedBox(height: 8),
          Text('Add stocks to your watchlist\nto see their upcoming events.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textTertiary, fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _toggleAlert(EconomicEvent event, EventIntegrationState state) async {
    try {
      await state.toggleAlert(widget.userId, event);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(event.isAlertEnabled ? '🔔 Alert set for ${event.title}' : '🔕 Alert removed for ${event.title}'),
            backgroundColor: context.appColors.surface,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't update the alert — check your connection and try again."),
            backgroundColor: Color(0xFFE53935),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }
}
