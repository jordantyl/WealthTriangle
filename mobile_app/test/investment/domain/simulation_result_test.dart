import 'package:flutter_test/flutter_test.dart';
import 'package:wealth_triangle/investment/domain/simulation_result.dart';

void main() {
  group('SimulationResult.fromJson', () {
    test('parses a fully-populated backend response', () {
      final result = SimulationResult.fromJson({
        'symbol': 'AAPL',
        'current_price': 190.5,
        'change_percent': 1.2,
        'risk_score_volatility': 42.0,
        'trend': 'Up',
        'ai_sentiment': 'Bullish',
        'ai_reason': 'Strong momentum',
        'expected_price_1y': 210.0,
        'worst_case_1y': 150.0,
        'best_case_1y': 260.0,
        'currency_code': 'USD',
        'rsi': 65.0,
        'ma50': 185.0,
        'macd': {'macd': 1.1, 'signal': 0.9, 'histogram': 0.2},
        'max_drawdown': -12.5,
        'dividend_yield': 0.5,
        'settlement_term': 'T+1',
        'cagr': 18.0,
      });

      expect(result.ticker, 'AAPL');
      expect(result.price, 190.5);
      expect(result.trend, Trend.up);
      expect(result.macd['macd'], 1.1);
      expect(result.macd['signal'], 0.9);
      expect(result.macd['histogram'], 0.2);
      expect(result.maxDrawdown, -12.5);
      expect(result.cagr, 18.0);
    });

    test('fills in sensible defaults for a mostly-empty response', () {
      final result = SimulationResult.fromJson({});

      expect(result.ticker, 'UNKNOWN');
      expect(result.price, 0);
      expect(result.trend, Trend.neutral);
      expect(result.aiSentiment, 'Neutral');
      expect(result.currencyCode, 'USD');
      expect(result.riskScore, 50);
      expect(result.maxDrawdown, -25);
      expect(result.dividendYield, 1.5);
      expect(result.settlementTerm, 'T+1');
      expect(result.liquidityLabel, 'High');
      expect(result.macd['macd'], 0);
    });

    test('trend parsing is case-insensitive and defaults to neutral for unknown values', () {
      expect(SimulationResult.fromJson({'trend': 'UP'}).trend, Trend.up);
      expect(SimulationResult.fromJson({'trend': 'down'}).trend, Trend.down);
      expect(SimulationResult.fromJson({'trend': 'sideways'}).trend, Trend.neutral);
      expect(SimulationResult.fromJson({'trend': 'DOWN'}).trend, Trend.down);
    });
  });
}
