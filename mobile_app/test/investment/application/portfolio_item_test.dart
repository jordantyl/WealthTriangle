import 'package:flutter_test/flutter_test.dart';
import 'package:wealth_triangle/investment/application/portfolio_state.dart';

void main() {
  group('PortfolioItem.totalValue', () {
    test('uses currentMarketPrice when available', () {
      final item = PortfolioItem(
        ticker: 'AAPL',
        quantity: 10,
        avgPrice: 100,
        currency: 'USD',
        currentMarketPrice: 150,
      );
      expect(item.totalValue, 1500);
    });

    test('falls back to avgPrice when currentMarketPrice is not set (0.0)', () {
      final item = PortfolioItem(
        ticker: 'AAPL',
        quantity: 10,
        avgPrice: 100,
        currency: 'USD',
      );
      expect(item.totalValue, 1000);
    });
  });

  group('PortfolioItem.annualDividendIncome', () {
    // Report FR/passive-income: this replaced a flat guessed 4.5%(.KL)/1.5%
    // rate applied to every holding regardless of the actual stock — now
    // uses the real dividendYield fetched per-ticker from the backend.
    test('is totalValue x real dividendYield percentage, not a flat guessed rate', () {
      final item = PortfolioItem(
        ticker: '1155.KL',
        quantity: 100,
        avgPrice: 8.0,
        currency: 'MYR',
        currentMarketPrice: 10.0,
        dividendYield: 5.0, // 5% real trailing yield
      );
      // totalValue = 100 * 10.0 = 1000; 5% of that = 50.
      expect(item.annualDividendIncome, closeTo(50.0, 0.001));
    });

    test('is zero for a genuinely non-dividend-paying stock, not a fallback guess', () {
      final item = PortfolioItem(
        ticker: 'TSLA',
        quantity: 5,
        avgPrice: 200,
        currency: 'USD',
        currentMarketPrice: 250,
        dividendYield: 0.0,
      );
      expect(item.annualDividendIncome, 0.0);
    });

    test('defaults to zero before the holding has ever been refreshed', () {
      final item = PortfolioItem(
        ticker: 'AAPL',
        quantity: 10,
        avgPrice: 100,
        currency: 'USD',
      );
      expect(item.dividendYield, 0.0);
      expect(item.annualDividendIncome, 0.0);
    });
  });
}
