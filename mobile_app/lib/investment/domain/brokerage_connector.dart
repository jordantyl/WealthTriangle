/// FR 7.4 — "API connections for future brokerage integration."
///
/// The report describes this as an architectural property rather than a
/// working feature. This interface is the concrete extension point: a real
/// broker (e.g. Rakuten Trade, Interactive Brokers) would implement
/// [BrokerageConnector] against its own REST API, and every screen that
/// talks to a broker only depends on this contract — never on a specific
/// vendor SDK. [DemoBrokerageConnector] (see demo_brokerage_connector.dart)
/// is the sandboxed implementation shipped today so the connection point is
/// actually exercised, not just declared.
abstract class BrokerageConnector {
  /// Human-readable name shown in Settings, e.g. "WealthTriangle Paper Broker".
  String get brokerName;

  /// True for sandbox/demo connectors; a real connector would return false
  /// and require OAuth/API-key credentials before [connect] succeeds.
  bool get isSandbox;

  Future<bool> connect();

  Future<List<BrokerPosition>> fetchPositions();

  Future<BrokerOrderResult> placeOrder(BrokerOrderRequest request);
}

class BrokerPosition {
  final String ticker;
  final double quantity;
  final double averagePrice;

  const BrokerPosition({
    required this.ticker,
    required this.quantity,
    required this.averagePrice,
  });
}

class BrokerOrderRequest {
  final String ticker;
  final double quantity;
  final bool isBuy;

  const BrokerOrderRequest({
    required this.ticker,
    required this.quantity,
    required this.isBuy,
  });
}

class BrokerOrderResult {
  final bool success;
  final String message;
  final double? fillPrice;

  const BrokerOrderResult({
    required this.success,
    required this.message,
    this.fillPrice,
  });
}
