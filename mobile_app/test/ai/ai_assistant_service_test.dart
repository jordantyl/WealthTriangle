import 'package:flutter_test/flutter_test.dart';
import 'package:wealth_triangle/ai/ai_assistant_service.dart';

// AIAssistantService.validateTradeQuantity is a pure, Firebase-independent
// wrapper around MarketRules.validateQuantity/validateSell — it's what
// _recordHolding/_sellHolding now run an AI-requested trade through before
// executing it, so the assistant can no longer bypass the same board-lot /
// min-quantity / no-fractional-shares rules the manual Add Transaction
// screen enforces. See ai_assistant_service.dart's _recordHolding/
// _sellHolding for the call sites.
void main() {
  group('AIAssistantService.validateTradeQuantity (buy)', () {
    test('rejects a .KL buy quantity below the 100-share minimum', () {
      final error = AIAssistantService.validateTradeQuantity(
        ticker: '1234.KL',
        qty: 50,
        isSell: false,
      );
      expect(error, isNotNull);
      expect(error, contains("Couldn't record"));
    });

    test('rejects a .KL buy quantity that is not a board-lot multiple', () {
      final error = AIAssistantService.validateTradeQuantity(
        ticker: '1234.KL',
        qty: 150,
        isSell: false,
      );
      expect(error, isNotNull);
    });

    test('allows a valid .KL board-lot buy quantity', () {
      final error = AIAssistantService.validateTradeQuantity(
        ticker: '1234.KL',
        qty: 200,
        isSell: false,
      );
      expect(error, isNull);
    });

    test('allows any positive whole-share buy quantity for US tickers', () {
      final error = AIAssistantService.validateTradeQuantity(
        ticker: 'AAPL',
        qty: 3,
        isSell: false,
      );
      expect(error, isNull);
    });
  });

  group('AIAssistantService.validateTradeQuantity (sell)', () {
    test('rejects selling more than owned', () {
      final error = AIAssistantService.validateTradeQuantity(
        ticker: 'AAPL',
        qty: 10,
        isSell: true,
        ownedQty: 5,
      );
      expect(error, isNotNull);
      expect(error, contains("Couldn't sell"));
    });

    test('allows selling exactly what is owned', () {
      final error = AIAssistantService.validateTradeQuantity(
        ticker: 'AAPL',
        qty: 5,
        isSell: true,
        ownedQty: 5,
      );
      expect(error, isNull);
    });

    test('rejects a .HK sell that is not an allowed quantity for owned shares', () {
      // .HK requires whole shares; 3 shares owned but the AI tries to sell
      // more than owned.
      final error = AIAssistantService.validateTradeQuantity(
        ticker: '0700.HK',
        qty: 500,
        isSell: true,
        ownedQty: 200,
      );
      expect(error, isNotNull);
    });
  });
}
