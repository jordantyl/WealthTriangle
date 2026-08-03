enum Trend { up, down, neutral }

class SimulationResult {
  final String ticker;
  final double price;
  final double expected;
  final double worst;
  final double best;
  final double riskScore;
  final double changePercent;
  final Trend trend;           // up, down, neutral
  final String aiSentiment;    // "Bullish", "Bearish"
  final String aiReason;       // "High volume detected..."
  final String currencyCode;
  final double rsi;
  final double ma50;
  final Map<String, double> macd;
  final double maxDrawdown;
  final double dividendYield;
  final String settlementTerm;
  final String volatilityLabel; // "Low", "Medium", "High"
  final String liquidityLabel;
  final double cagr;
  final double momentumScore;  // -1..1, blends RSI/MACD/MA50 (report 3.1.1)
  final String marketRegime;   // "Bull", "Bear", "Neutral" (FR 2.3)

  SimulationResult({
    required this.ticker,
    required this.price,
    required this.expected,
    required this.worst,
    required this.best,
    required this.riskScore,
    required this.trend,
    required this.aiSentiment,
    required this.aiReason,
    required this.changePercent,
    required this.currencyCode,
    required this.rsi,
    required this.ma50,
    required this.macd,
    required this.maxDrawdown,
    required this.dividendYield,
    required this.settlementTerm,
    required this.volatilityLabel,
    required this.liquidityLabel,
    required this.cagr,
    required this.momentumScore,
    required this.marketRegime,
  });

  factory SimulationResult.fromJson(Map<String, dynamic> json) {
    final macdData = json['macd'] as Map<String, dynamic>? ?? {};
    return SimulationResult(
      ticker: json['symbol'] ?? 'UNKNOWN',
      price: (json['current_price'] ?? 0).toDouble(),
      changePercent: (json['change_percent'] ?? 0).toDouble(),
      riskScore: (json['risk_score_volatility'] ?? 50).toDouble(),
      trend: _parseTrend(json['trend'] ?? 'neutral'),
      aiSentiment: json['ai_sentiment'] ?? 'Neutral',
      aiReason: json['ai_reason'] ?? 'No data available.',
      expected: (json['expected_price_1y'] ?? 0).toDouble(),
      worst: (json['worst_case_1y'] ?? 0).toDouble(),
      best: (json['best_case_1y'] ?? 0).toDouble(),
      currencyCode: json['currency_code'] ?? 'USD',
      rsi: (json['rsi'] ?? 50).toDouble(),
      ma50: (json['ma50'] ?? 0).toDouble(),
      macd: {
        'macd': (macdData['macd'] ?? 0).toDouble(),
        'signal': (macdData['signal'] ?? 0).toDouble(),
        'histogram': (macdData['histogram'] ?? 0).toDouble(),
      },
      // ✅ Parse new fields (with defaults if missing)
      maxDrawdown: (json['max_drawdown'] ?? -25).toDouble(),
      dividendYield: (json['dividend_yield'] ?? 1.5).toDouble(),
      settlementTerm: json['settlement_term'] ?? 'T+1',
      volatilityLabel: json['volatility_label'] ?? 'Medium',
      liquidityLabel: json['liquidity_label'] ?? 'High',
      cagr: (json['cagr'] ?? 0).toDouble(),
      momentumScore: (json['momentum_score'] ?? 0).toDouble(),
      marketRegime: json['market_regime'] ?? 'Neutral',
    );
  }

  static Trend _parseTrend(String val) {
    if (val.toLowerCase() == 'up') return Trend.up;
    if (val.toLowerCase() == 'down') return Trend.down;
    return Trend.neutral;
  }
}