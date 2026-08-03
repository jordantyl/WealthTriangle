import 'dart:math';

import 'news_headline.dart';
import 'sim_position.dart';
import 'synthetic_asset.dart';

/// Pure Dart engine for the paper-trading simulator — no Flutter/widget
/// dependency, so it's fully unit-testable on its own. The screen wraps
/// this in a Timer.periodic + setState(), the same lifecycle pattern
/// flash_trader_screen.dart uses for its countdown (local StatefulWidget
/// state, not a global ChangeNotifier/Provider) — the engine only runs
/// while the screen is actually open.
class PaperTradingEngine {
  static const int ticksPerCandle = 5;
  static const double startingCash = 10000.0;
  static const int backfillCandles = 30;
  static const double newsChancePerTick = 0.08;
  static const int driftBoostDurationTicks = 5;
  static const int maxRecentNews = 20;

  final Random _random;

  final Map<String, double> _currentPrice = {};
  final Map<String, List<Candle>> _history = {};
  final Map<String, Candle> _currentCandle = {};
  final Map<String, int> _ticksInCurrentCandle = {};
  final Map<String, double> _activeDriftBoost = {};
  final Map<String, int> _driftBoostTicksRemaining = {};

  double cash = startingCash;
  final Map<String, SimPosition> positions = {};
  final List<SimTransaction> tradeLog = [];
  final List<FiredNewsHeadline> recentNews = [];

  // Cap on how many trade log entries get persisted (see toJson) — the
  // in-memory tradeLog itself stays unbounded so the on-screen history is
  // never truncated by save/restore.
  static const int maxPersistedTradeLog = 50;

  PaperTradingEngine({Random? random}) : _random = random ?? Random();

  /// Portfolio state only (cash, positions, a capped trade log) — not price
  /// history/candles, which regenerate fresh from start() on every session.
  Map<String, dynamic> toJson() => {
    'cash': cash,
    'positions': positions.values.map((p) => p.toJson()).toList(),
    'tradeLog': tradeLog.take(maxPersistedTradeLog).map((t) => t.toJson()).toList(),
  };

  /// Applies previously-saved portfolio state on top of a fresh start().
  /// Price/candle history is intentionally NOT restored — the simulator
  /// picks back up live from wherever start() re-seeded prices.
  void restoreFrom(Map<String, dynamic> json) {
    cash = (json['cash'] as num?)?.toDouble() ?? startingCash;

    positions.clear();
    final rawPositions = json['positions'] as List<dynamic>? ?? [];
    for (final raw in rawPositions) {
      final position = SimPosition.fromJson(raw as Map<String, dynamic>);
      positions[position.assetId] = position;
    }

    tradeLog.clear();
    final rawTrades = json['tradeLog'] as List<dynamic>? ?? [];
    tradeLog.addAll(rawTrades.map((raw) => SimTransaction.fromJson(raw as Map<String, dynamic>)));
  }

  double currentPrice(String assetId) => _currentPrice[assetId] ?? 0;

  /// Full candle history for an asset, oldest first, including the
  /// currently-forming candle at the end.
  List<Candle> candlesFor(String assetId) {
    final history = _history[assetId] ?? const [];
    final current = _currentCandle[assetId];
    return current == null ? List.unmodifiable(history) : [...history, current];
  }

  double get totalPortfolioValue {
    var value = cash;
    for (final position in positions.values) {
      value += position.marketValue(currentPrice(position.assetId));
    }
    return value;
  }

  double get totalPnl => totalPortfolioValue - startingCash;

  double get totalUnrealizedPnl {
    var pnl = 0.0;
    for (final position in positions.values) {
      pnl += position.unrealizedPnl(currentPrice(position.assetId));
    }
    return pnl;
  }

  /// Seeds starting prices and backfills history so the chart isn't empty
  /// on first open, then starts the live in-progress candle for each asset.
  void start() {
    for (final asset in syntheticAssets) {
      _currentPrice[asset.id] = asset.startingPrice;
      _history[asset.id] = [];
      _currentCandle[asset.id] = Candle(
        date: DateTime.now(),
        open: asset.startingPrice,
        high: asset.startingPrice,
        low: asset.startingPrice,
        close: asset.startingPrice,
      );
      _ticksInCurrentCandle[asset.id] = 0;

      for (var i = 0; i < backfillCandles * ticksPerCandle; i++) {
        _stepPrice(asset);
      }
    }
  }

  /// Advances every asset's price by one tick and rolls candles over.
  void tick() {
    for (final asset in syntheticAssets) {
      _stepPrice(asset);
    }
  }

  void _stepPrice(SyntheticAsset asset) {
    final boost = _activeDriftBoost[asset.id] ?? 0;
    final drift = asset.baseDrift + boost;
    final shock = asset.volatility * (_random.nextDouble() * 2 - 1);
    final price = _currentPrice[asset.id] ?? asset.startingPrice;
    final newPrice = max(price * (1 + drift + shock), 0.01);
    _currentPrice[asset.id] = newPrice;

    _currentCandle[asset.id]!.applyTick(newPrice);
    final ticks = (_ticksInCurrentCandle[asset.id] ?? 0) + 1;
    if (ticks >= ticksPerCandle) {
      _history[asset.id]!.add(_currentCandle[asset.id]!);
      _currentCandle[asset.id] = Candle(
        date: DateTime.now(),
        open: newPrice,
        high: newPrice,
        low: newPrice,
        close: newPrice,
      );
      _ticksInCurrentCandle[asset.id] = 0;
    } else {
      _ticksInCurrentCandle[asset.id] = ticks;
    }

    if (_driftBoostTicksRemaining.containsKey(asset.id)) {
      final remaining = _driftBoostTicksRemaining[asset.id]! - 1;
      if (remaining <= 0) {
        _driftBoostTicksRemaining.remove(asset.id);
        _activeDriftBoost.remove(asset.id);
      } else {
        _driftBoostTicksRemaining[asset.id] = remaining;
      }
    }
  }

  /// Rolls the dice for a random headline firing this tick. Call once per
  /// live tick (not during backfill — headlines shouldn't appear "in the
  /// past" relative to when the user opened the screen).
  void maybeInjectNews() {
    if (_random.nextDouble() > newsChancePerTick) return;
    final headline = newsHeadlineCatalog[_random.nextInt(newsHeadlineCatalog.length)];
    _applyNews(headline);
  }

  /// Exposed only so tests can deterministically trigger a specific
  /// headline (maybeInjectNews() picks randomly, which isn't practical to
  /// pin down in a test). Not used by production code.
  void applyNewsForTesting(NewsHeadline headline) => _applyNews(headline);

  void _applyNews(NewsHeadline headline) {
    final targets = headline.targetAssetId == 'all'
        ? syntheticAssets.map((a) => a.id)
        : [headline.targetAssetId];
    for (final assetId in targets) {
      _activeDriftBoost[assetId] = headline.driftImpact;
      _driftBoostTicksRemaining[assetId] = driftBoostDurationTicks;
    }
    recentNews.insert(0, FiredNewsHeadline(headline: headline, firedAt: DateTime.now()));
    if (recentNews.length > maxRecentNews) {
      recentNews.removeRange(maxRecentNews, recentNews.length);
    }
  }

  /// Returns true if the buy succeeded (enough cash), false otherwise.
  bool buy(String assetId, double quantity) {
    if (quantity <= 0) return false;
    final price = currentPrice(assetId);
    final cost = price * quantity;
    if (cost > cash) return false;

    cash -= cost;
    final existing = positions[assetId];
    if (existing == null) {
      positions[assetId] = SimPosition(assetId: assetId, quantity: quantity, avgCost: price);
    } else {
      final newQty = existing.quantity + quantity;
      existing.avgCost = ((existing.avgCost * existing.quantity) + (price * quantity)) / newQty;
      existing.quantity = newQty;
    }
    tradeLog.insert(
      0,
      SimTransaction(
        assetId: assetId,
        type: SimTransactionType.buy,
        quantity: quantity,
        price: price,
        timestamp: DateTime.now(),
      ),
    );
    return true;
  }

  /// Returns true if the sell succeeded (enough shares held), false otherwise.
  bool sell(String assetId, double quantity) {
    if (quantity <= 0) return false;
    final position = positions[assetId];
    if (position == null || position.quantity < quantity) return false;

    final price = currentPrice(assetId);
    cash += price * quantity;
    position.quantity -= quantity;
    if (position.quantity <= 0) {
      positions.remove(assetId);
    }
    tradeLog.insert(
      0,
      SimTransaction(
        assetId: assetId,
        type: SimTransactionType.sell,
        quantity: quantity,
        price: price,
        timestamp: DateTime.now(),
      ),
    );
    return true;
  }
}
