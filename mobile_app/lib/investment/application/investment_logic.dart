import '../data/stock_api.dart';
import '../domain/simulation_result.dart';

class InvestmentLogic {
  final StockApi _api = StockApi();

  // The UI calls this simple function
  Future<SimulationResult?> getPrediction(String ticker, {String period = '1y'}) async {
    if (ticker.isEmpty) return null;
    return await _api.fetchSimulation(ticker);
  }
}