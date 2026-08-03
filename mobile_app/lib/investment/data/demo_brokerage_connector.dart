import '../../academy/domain/paper_trading/paper_trading_engine.dart';
import '../domain/brokerage_connector.dart';

/// Sandbox [BrokerageConnector] backed by the app's own paper-trading
/// engine, so "connect -> fetch positions -> place order" is a real,
/// working round trip today. Swapping in a live broker later means writing
/// a new class against the same interface — nothing that depends on
/// [BrokerageConnector] needs to change.
class DemoBrokerageConnector implements BrokerageConnector {
  final PaperTradingEngine _engine;
  bool _connected = false;

  DemoBrokerageConnector({PaperTradingEngine? engine})
      : _engine = engine ?? PaperTradingEngine();

  @override
  String get brokerName => 'WealthTriangle Paper Broker (Sandbox)';

  @override
  bool get isSandbox => true;

  @override
  Future<bool> connect() async {
    _engine.start();
    _connected = true;
    return true;
  }

  @override
  Future<List<BrokerPosition>> fetchPositions() async {
    if (!_connected) return [];
    return _engine.positions.values
        .map((p) => BrokerPosition(
              ticker: p.assetId,
              quantity: p.quantity,
              averagePrice: p.avgCost,
            ))
        .toList();
  }

  @override
  Future<BrokerOrderResult> placeOrder(BrokerOrderRequest request) async {
    if (!_connected) {
      return const BrokerOrderResult(
          success: false, message: 'Not connected to broker.');
    }

    final fillPrice = _engine.currentPrice(request.ticker);
    final ok = request.isBuy
        ? _engine.buy(request.ticker, request.quantity)
        : _engine.sell(request.ticker, request.quantity);

    return BrokerOrderResult(
      success: ok,
      message: ok
          ? '${request.isBuy ? 'Bought' : 'Sold'} ${request.quantity} ${request.ticker} @ ${fillPrice.toStringAsFixed(2)}'
          : request.isBuy
              ? 'Order rejected: insufficient sandbox cash.'
              : 'Order rejected: insufficient position size.',
      fillPrice: ok ? fillPrice : null,
    );
  }
}
