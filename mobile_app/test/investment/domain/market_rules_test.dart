import 'package:flutter_test/flutter_test.dart';
import 'package:wealth_triangle/investment/domain/market_rules.dart';

void main() {
  group('MarketRules.forTicker', () {
    test('.KL tickers get strict 100-share board-lot rules', () {
      final rules = MarketRules.forTicker('1234.KL');
      expect(rules.minTradeQty, 100);
      expect(rules.boardLotSize, 100);
      expect(rules.fractionalAllowed, false);
      expect(rules.oddLotAllowed, false);
    });

    test('.HK tickers get 200-share semi-strict rules with odd lots allowed', () {
      final rules = MarketRules.forTicker('0700.HK');
      expect(rules.minTradeQty, 200);
      expect(rules.boardLotSize, 200);
      expect(rules.fractionalAllowed, false);
      expect(rules.oddLotAllowed, true);
    });

    test('US / unrecognized tickers default to flexible fractional rules', () {
      final rules = MarketRules.forTicker('AAPL');
      expect(rules.minTradeQty, 1);
      expect(rules.fractionalAllowed, true);
      expect(rules.oddLotAllowed, true);
    });

    test('suffix matching is case-insensitive', () {
      final rules = MarketRules.forTicker('1234.kl');
      expect(rules.minTradeQty, 100);
    });
  });

  group('MarketRules.validateQuantity', () {
    final klRules = MarketRules.forTicker('1234.KL');
    final usRules = MarketRules.forTicker('AAPL');

    test('rejects empty input', () {
      expect(klRules.validateQuantity(''), isNotNull);
      expect(klRules.validateQuantity(null), isNotNull);
    });

    test('rejects non-numeric input', () {
      expect(klRules.validateQuantity('abc'), isNotNull);
    });

    test('rejects zero or negative quantities', () {
      expect(klRules.validateQuantity('0'), isNotNull);
      expect(klRules.validateQuantity('-5'), isNotNull);
    });

    test('.KL rejects quantities below the 100-share minimum', () {
      expect(klRules.validateQuantity('50'), isNotNull);
    });

    test('.KL rejects quantities that are not multiples of the board lot', () {
      expect(klRules.validateQuantity('150'), isNotNull);
    });

    test('.KL accepts a valid board-lot multiple', () {
      expect(klRules.validateQuantity('200'), isNull);
    });

    test('.KL rejects fractional shares', () {
      expect(klRules.validateQuantity('100.5'), isNotNull);
    });

    test('US allows fractional share quantities', () {
      expect(usRules.validateQuantity('1.5'), isNull);
    });
  });

  group('MarketRules.validateSell', () {
    final klRules = MarketRules.forTicker('1234.KL');
    final usRules = MarketRules.forTicker('AAPL');

    test('rejects selling more than owned', () {
      expect(klRules.validateSell('200', 100), isNotNull);
    });

    test('allows selling exactly what is owned', () {
      expect(klRules.validateSell('100', 100), isNull);
    });

    test('rejects fractional sells where fractional is disallowed', () {
      expect(klRules.validateSell('10.5', 100), isNotNull);
    });

    test('allows fractional sells where fractional is allowed', () {
      expect(usRules.validateSell('2.5', 10), isNull);
    });

    test('rejects zero or invalid sell quantity', () {
      expect(klRules.validateSell('0', 100), isNotNull);
      expect(klRules.validateSell('nope', 100), isNotNull);
      expect(klRules.validateSell('', 100), isNotNull);
    });
  });
}
