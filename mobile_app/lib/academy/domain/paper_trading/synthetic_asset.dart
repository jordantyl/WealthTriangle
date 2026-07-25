/// One OHLC candle in the paper-trading engine's own price history.
/// Deliberately independent of the `candlesticks` package's `Candle` type —
/// converted to that at the UI boundary — so the engine has no Flutter/UI
/// dependency and stays a plain, unit-testable Dart class.
class Candle {
  final DateTime date;
  final double open;
  double high;
  double low;
  double close;

  Candle({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });

  /// Folds a new tick price into this in-progress candle.
  void applyTick(double price) {
    if (price > high) high = price;
    if (price < low) low = price;
    close = price;
  }
}

/// A fictional tradeable instrument in the paper-trading simulator. Each
/// asset has its own volatility/drift personality so the three tickers feel
/// distinct rather than being copies of the same random walk.
class SyntheticAsset {
  final String id;
  final String ticker;
  final String name;
  final double startingPrice;

  /// Per-tick volatility as a fraction (e.g. 0.01 = ~1% typical move).
  final double volatility;

  /// Per-tick baseline drift as a fraction (0 = pure random walk).
  final double baseDrift;

  const SyntheticAsset({
    required this.id,
    required this.ticker,
    required this.name,
    required this.startingPrice,
    required this.volatility,
    required this.baseDrift,
  });
}

/// The three synthetic tickers available in the simulator — deliberately
/// different volatility personalities (steady / balanced / volatile) so
/// there's a real portfolio-construction choice, echoing the app's
/// Return-Safety-Liquidity framing without over-fitting the metaphor.
const List<SyntheticAsset> syntheticAssets = [
  SyntheticAsset(
    id: 'aqua',
    ticker: 'AQUA',
    name: 'Aqua Utilities',
    startingPrice: 40.0,
    volatility: 0.003,
    baseDrift: 0.0001,
  ),
  SyntheticAsset(
    id: 'blaze',
    ticker: 'BLAZE',
    name: 'Blaze Energy Corp',
    startingPrice: 70.0,
    volatility: 0.008,
    baseDrift: 0.0002,
  ),
  SyntheticAsset(
    id: 'nova',
    ticker: 'NOVA',
    name: 'Nova Technologies',
    startingPrice: 100.0,
    volatility: 0.013,
    baseDrift: 0.0006,
  ),
];
