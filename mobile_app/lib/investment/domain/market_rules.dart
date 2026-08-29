class MarketRules {
  final int minTradeQty;
  final int boardLotSize;
  final bool fractionalAllowed;
  final bool oddLotAllowed;

  MarketRules({
    required this.minTradeQty,
    required this.boardLotSize,
    required this.fractionalAllowed,
    required this.oddLotAllowed,
  });

  // FACTORY: Assign rules based on Ticker Suffix
  factory MarketRules.forTicker(String ticker) {
    final t = ticker.toUpperCase();
    
    // 🇲🇾 MALAYSIA (.KL) -> Strict Rules
    if (t.endsWith(".KL")) {
      return MarketRules(
        minTradeQty: 100, 
        boardLotSize: 100, 
        fractionalAllowed: false,
        oddLotAllowed: false
      );
    }
    
    // 🇭🇰 HONG KONG (.HK) -> Semi-Strict
    if (t.endsWith(".HK")) {
      return MarketRules(
        minTradeQty: 200, // Example from your request
        boardLotSize: 200, 
        fractionalAllowed: false,
        oddLotAllowed: true
      );
    }

    // 🇺🇸 US / DEFAULT -> Flexible
    //
    // fractionalAllowed was previously true here, but PortfolioState.buyStock
    // /sellStock (and the whole portfolio data model behind them) only ever
    // took an `int` qty — there was no fractional-share support downstream
    // at all. The UI advertised it anyway (decimal keypad, "2.5" accepted by
    // validation), so a submitted fractional quantity got silently
    // int-truncated on buy/sell while the Sell P&L preview (built with
    // int.tryParse, which returns null for "2.5") showed $0.00 — the
    // executed trade never matched what the user saw or asked for. Until
    // fractional shares are actually implemented end-to-end, don't let the
    // UI promise something the system can't deliver.
    return MarketRules(
      minTradeQty: 1,
      boardLotSize: 1,
      fractionalAllowed: false,
      oddLotAllowed: true
    );
  }

  // VALIDATION LOGIC
  String? validateQuantity(String? value) {
    if (value == null || value.isEmpty) return 'Quantity is required';
    
    final qty = double.tryParse(value);
    if (qty == null) return 'Quantity must be a number';
    if (qty <= 0) return 'Quantity must be greater than 0';

    // Rule 3: Respect market minimum
    if (qty < minTradeQty) {
      return 'Minimum quantity for this stock is $minTradeQty';
    }

    // Rule 4a: Fractional Checks
    if (!fractionalAllowed) {
      if (qty % 1 != 0) return 'Fractional shares are not allowed';
    }

    // Rule 4b: Board Lot / Odd Lot Checks
    // If Odd Lots are NOT allowed, you must buy in multiples of Board Lot
    if (!oddLotAllowed) {
       if (qty % boardLotSize != 0) {
         return 'Quantity must be in multiples of $boardLotSize';
       }
    }

    return null; // Valid
  }

  String? validateSell(String? value, int ownedQty) {
    if (value == null || value.isEmpty) return 'Enter quantity';

    final qty = double.tryParse(value);
    if (qty == null) return 'Invalid number';
    if (qty <= 0) return 'Sell quantity must be > 0';

    // Rule: Cannot sell more than owned
    if (qty > ownedQty) {
      return 'Cannot sell more than owned ($ownedQty)';
    }

    // Rule: Fractional check (Selling 10.5 shares when disallowed)
    if (!fractionalAllowed && qty % 1 != 0) {
      return 'Fractional selling not allowed';
    }

    return null; // Valid
  }
}