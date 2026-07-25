import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wealth_triangle/academy/domain/paper_trading/news_headline.dart';
import 'package:wealth_triangle/academy/domain/paper_trading/paper_trading_engine.dart';
import 'package:wealth_triangle/academy/domain/paper_trading/synthetic_asset.dart';

void main() {
  PaperTradingEngine startedEngine([int seed = 42]) {
    final engine = PaperTradingEngine(random: Random(seed));
    engine.start();
    return engine;
  }

  group('start()', () {
    test('backfills history so the chart is never empty on first open', () {
      final engine = startedEngine();
      for (final asset in syntheticAssets) {
        final candles = engine.candlesFor(asset.id);
        // backfillCandles completed + 1 in-progress candle.
        expect(candles.length, PaperTradingEngine.backfillCandles + 1);
        expect(engine.currentPrice(asset.id), greaterThan(0));
      }
    });

    test('every candle has internally consistent OHLC bounds', () {
      final engine = startedEngine();
      for (final asset in syntheticAssets) {
        for (final candle in engine.candlesFor(asset.id)) {
          expect(candle.high, greaterThanOrEqualTo(candle.open));
          expect(candle.high, greaterThanOrEqualTo(candle.close));
          expect(candle.low, lessThanOrEqualTo(candle.open));
          expect(candle.low, lessThanOrEqualTo(candle.close));
          expect(candle.high, greaterThanOrEqualTo(candle.low));
        }
      }
    });
  });

  group('tick() candle rollover', () {
    test('does not add a new candle until ticksPerCandle ticks have passed', () {
      final engine = startedEngine();
      final before = engine.candlesFor('aqua').length;
      for (var i = 0; i < PaperTradingEngine.ticksPerCandle - 1; i++) {
        engine.tick();
      }
      expect(engine.candlesFor('aqua').length, before);
    });

    test('adds exactly one new candle every ticksPerCandle ticks', () {
      final engine = startedEngine();
      final before = engine.candlesFor('aqua').length;
      for (var i = 0; i < PaperTradingEngine.ticksPerCandle; i++) {
        engine.tick();
      }
      expect(engine.candlesFor('aqua').length, before + 1);
    });

    test('the new candle opens at the price the previous candle closed at', () {
      final engine = startedEngine();
      for (var i = 0; i < PaperTradingEngine.ticksPerCandle; i++) {
        engine.tick();
      }
      final candles = engine.candlesFor('aqua');
      final finalized = candles[candles.length - 2];
      final inProgress = candles.last;
      expect(inProgress.open, finalized.close);
    });
  });

  group('maybeInjectNews()', () {
    test('fires at least once over many attempts and respects the cap', () {
      final engine = startedEngine();
      for (var i = 0; i < 500; i++) {
        engine.maybeInjectNews();
      }
      expect(engine.recentNews, isNotEmpty);
      expect(engine.recentNews.length, lessThanOrEqualTo(PaperTradingEngine.maxRecentNews));
      for (final fired in engine.recentNews) {
        expect(newsHeadlineCatalog, contains(fired.headline));
      }
    });
  });

  group('news drift effect (deterministic, via applyNewsForTesting)', () {
    test('a positive-impact headline measurably pushes the target asset price up', () {
      final withNews = startedEngine(7);
      final baseline = startedEngine(7);

      const bullishHeadline = NewsHeadline(
        text: 'test headline',
        targetAssetId: 'aqua',
        driftImpact: 0.05, // large, deliberately way above normal volatility
      );
      withNews.applyNewsForTesting(bullishHeadline);

      for (var i = 0; i < PaperTradingEngine.driftBoostDurationTicks; i++) {
        withNews.tick();
        baseline.tick();
      }

      expect(withNews.currentPrice('aqua'), greaterThan(baseline.currentPrice('aqua')));
    });

    test("'all' target applies the drift boost to every asset", () {
      final engine = startedEngine(3);
      const headline = NewsHeadline(text: 'macro news', targetAssetId: 'all', driftImpact: 0.05);
      engine.applyNewsForTesting(headline);

      final before = {for (final a in syntheticAssets) a.id: engine.currentPrice(a.id)};
      engine.tick();
      for (final asset in syntheticAssets) {
        // With such a large boost relative to per-tick volatility, price should
        // rise for every asset despite the random shock component.
        expect(engine.currentPrice(asset.id), greaterThan(before[asset.id]!));
      }
    });

    test('the drift boost expires after driftBoostDurationTicks', () {
      final withNews = startedEngine(11);
      final baseline = startedEngine(11);

      const headline = NewsHeadline(text: 'test', targetAssetId: 'aqua', driftImpact: 0.05);
      withNews.applyNewsForTesting(headline);

      for (var i = 0; i < PaperTradingEngine.driftBoostDurationTicks; i++) {
        withNews.tick();
        baseline.tick();
      }
      final priceRightAfterBoost = withNews.currentPrice('aqua');

      // One more tick after the boost has expired: both engines share the
      // same seed and should now be back to identical random-walk math, so
      // the *absolute* prices should match exactly (no more artificial push).
      withNews.tick();
      baseline.tick();
      // baseline never had the boost, so re-apply the same relative check:
      // the gap between the two should stop growing once the boost expires.
      final gapAtExpiry = priceRightAfterBoost - baseline.currentPrice('aqua');
      withNews.tick();
      baseline.tick();
      final gapOneTickLater = withNews.currentPrice('aqua') - baseline.currentPrice('aqua');
      expect((gapOneTickLater - gapAtExpiry).abs(), lessThan(gapAtExpiry.abs() * 0.5 + 1));
    });
  });

  group('buy()', () {
    test('succeeds and deducts cash at the current price', () {
      final engine = startedEngine();
      final price = engine.currentPrice('aqua');
      final ok = engine.buy('aqua', 10);

      expect(ok, isTrue);
      expect(engine.cash, closeTo(PaperTradingEngine.startingCash - price * 10, 0.001));
      expect(engine.positions['aqua']!.quantity, 10);
      expect(engine.positions['aqua']!.avgCost, closeTo(price, 0.001));
    });

    test('a second buy at a different price updates avgCost with weighted average', () {
      final engine = startedEngine();
      final price1 = engine.currentPrice('aqua');
      engine.buy('aqua', 10);

      engine.tick(); // price moves
      final price2 = engine.currentPrice('aqua');
      engine.buy('aqua', 10);

      final expectedAvg = ((price1 * 10) + (price2 * 10)) / 20;
      expect(engine.positions['aqua']!.quantity, 20);
      expect(engine.positions['aqua']!.avgCost, closeTo(expectedAvg, 0.001));
    });

    test('fails and changes nothing when cost exceeds cash', () {
      final engine = startedEngine();
      final cashBefore = engine.cash;
      // Way more than startingCash could ever afford.
      final ok = engine.buy('nova', 100000);

      expect(ok, isFalse);
      expect(engine.cash, cashBefore);
      expect(engine.positions.containsKey('nova'), isFalse);
    });

    test('rejects a non-positive quantity', () {
      final engine = startedEngine();
      expect(engine.buy('aqua', 0), isFalse);
      expect(engine.buy('aqua', -5), isFalse);
    });
  });

  group('sell()', () {
    test('succeeds, credits cash, and reduces quantity without touching avgCost', () {
      final engine = startedEngine();
      final buyPrice = engine.currentPrice('aqua');
      engine.buy('aqua', 10);
      engine.tick();
      final sellPrice = engine.currentPrice('aqua');
      final cashBeforeSell = engine.cash;

      final ok = engine.sell('aqua', 4);

      expect(ok, isTrue);
      expect(engine.cash, closeTo(cashBeforeSell + sellPrice * 4, 0.001));
      expect(engine.positions['aqua']!.quantity, 6);
      expect(engine.positions['aqua']!.avgCost, closeTo(buyPrice, 0.001));
    });

    test('removes the position entirely once fully sold', () {
      final engine = startedEngine();
      engine.buy('aqua', 5);
      engine.sell('aqua', 5);
      expect(engine.positions.containsKey('aqua'), isFalse);
    });

    test('fails when selling more than held', () {
      final engine = startedEngine();
      engine.buy('aqua', 5);
      final ok = engine.sell('aqua', 6);
      expect(ok, isFalse);
      expect(engine.positions['aqua']!.quantity, 5);
    });

    test('fails when there is no position at all', () {
      final engine = startedEngine();
      expect(engine.sell('aqua', 1), isFalse);
    });
  });

  group('portfolio value / P&L', () {
    test('totalPortfolioValue equals cash plus market value of holdings', () {
      final engine = startedEngine();
      engine.buy('aqua', 10);
      engine.tick();

      final expected = engine.cash + 10 * engine.currentPrice('aqua');
      expect(engine.totalPortfolioValue, closeTo(expected, 0.001));
    });

    test('totalPnl is zero before any trades (value == starting cash)', () {
      final engine = startedEngine();
      expect(engine.totalPnl, closeTo(0, 0.001));
    });

    test('totalPnl reflects portfolio value moving away from starting cash', () {
      final engine = startedEngine();
      engine.buy('aqua', 10);
      expect(engine.totalPnl, closeTo(engine.totalPortfolioValue - PaperTradingEngine.startingCash, 0.001));
    });
  });
}
