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

  Map<String, dynamic> toJson() => {
    'assetId': assetId,
    'type': type.name,
    'quantity': quantity,
    'price': price,
    'timestamp': timestamp.toIso8601String(),
  };

  factory SimTransaction.fromJson(Map<String, dynamic> json) => SimTransaction(
    assetId: json['assetId'] as String,
    type: SimTransactionType.values.firstWhere((t) => t.name == json['type']),
    quantity: (json['quantity'] as num).toDouble(),
    price: (json['price'] as num).toDouble(),
    timestamp: DateTime.parse(json['timestamp'] as String),
  );
}

/// A held position in one synthetic asset. Mirrors the weighted-average-cost
/// shape used by PortfolioState.buyStock() and AcademyState's merchant game
/// (same formula, same meaning of "avgCost").
class SimPosition {
  final String assetId;
  double quantity;
  double avgCost;

  SimPosition({required this.assetId, required this.quantity, required this.avgCost});

  double totalCost() => quantity * avgCost;

  double marketValue(double currentPrice) => quantity * currentPrice;

  double unrealizedPnl(double currentPrice) =>
      marketValue(currentPrice) - totalCost();

  Map<String, dynamic> toJson() => {
    'assetId': assetId,
    'quantity': quantity,
    'avgCost': avgCost,
  };

  factory SimPosition.fromJson(Map<String, dynamic> json) => SimPosition(
    assetId: json['assetId'] as String,
    quantity: (json['quantity'] as num).toDouble(),
    avgCost: (json['avgCost'] as num).toDouble(),
  );
}
