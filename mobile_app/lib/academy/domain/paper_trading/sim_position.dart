enum SimTransactionType { buy, sell }

/// A single buy/sell fill in the paper-trading trade log.
class SimTransaction {
  final String assetId;
  final SimTransactionType type;
  final double quantity;
  final double price;
  final DateTime timestamp;

  const SimTransaction({
    required this.assetId,
    required this.type,
    required this.quantity,
    required this.price,
    required this.timestamp,
  });
}

/// A held position in one synthetic asset. Mirrors the weighted-average-cost
/// shape used by PortfolioState.buyStock() and AcademyState's merchant game
/// (same formula, same meaning of "avgCost"), without the Firestore
/// persistence those tie into — this simulator is in-memory/ephemeral.
class SimPosition {
  final String assetId;
  double quantity;
  double avgCost;

  SimPosition({required this.assetId, required this.quantity, required this.avgCost});

  double totalCost() => quantity * avgCost;

  double marketValue(double currentPrice) => quantity * currentPrice;

  double unrealizedPnl(double currentPrice) =>
      marketValue(currentPrice) - totalCost();
}
