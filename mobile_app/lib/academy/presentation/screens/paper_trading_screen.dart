import 'dart:async';

import 'package:candlesticks/candlesticks.dart' as pkg;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/app_theme_colors.dart';
import '../../domain/paper_trading/paper_trading_engine.dart';
import '../../domain/paper_trading/synthetic_asset.dart';

/// Continuous, timer-ticking synthetic market — separate from the
/// turn-based Market Tycoon / Merchant Master games. Genuine paper trading:
/// real candlestick charts building up live, random news headlines nudging
/// price, and a buy/sell UI against a real portfolio/P&L.
class PaperTradingScreen extends StatefulWidget {
  const PaperTradingScreen({super.key});

  @override
  State<PaperTradingScreen> createState() => _PaperTradingScreenState();
}

class _PaperTradingScreenState extends State<PaperTradingScreen> {
  static const _bullColor = Colors.greenAccent;
  static const _bearColor = Colors.redAccent;

  late final PaperTradingEngine _engine;
  late final Timer _timer;
  late String _selectedAssetId;
  final TextEditingController _qtyController = TextEditingController(text: '1');

  final _priceFormat = NumberFormat.simpleCurrency(name: 'USD', decimalDigits: 2);
  final _cashFormat = NumberFormat.simpleCurrency(name: 'USD', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _engine = PaperTradingEngine();
    _engine.start();
    _selectedAssetId = syntheticAssets.first.id;
    // Same Timer.periodic + setState lifecycle pattern as
    // flash_trader_screen.dart — local to this screen, cancelled on
    // dispose, so the engine only runs while this screen is open.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _engine.tick();
      _engine.maybeInjectNews();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _qtyController.dispose();
    super.dispose();
  }

  SyntheticAsset get _selectedAsset =>
      syntheticAssets.firstWhere((a) => a.id == _selectedAssetId);

  List<pkg.Candle> _packageCandles(String assetId) {
    final domainCandles = _engine.candlesFor(assetId);
    // The package wants newest-first; our engine stores oldest-first.
    return domainCandles.reversed.map((c) {
      final range = (c.high - c.low).abs();
      return pkg.Candle(
        date: c.date,
        open: c.open,
        high: c.high,
        low: c.low,
        close: c.close,
        volume: 500 + range * 500,
      );
    }).toList();
  }

  void _handleBuy() {
    final qty = double.tryParse(_qtyController.text) ?? 0;
    final ok = _engine.buy(_selectedAssetId, qty);
    setState(() {});
    if (!ok) {
      _showSnack(
        qty <= 0 ? 'Enter a valid quantity.' : 'Not enough cash for that trade.',
        isError: true,
      );
    } else {
      _showSnack('Bought ${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 2)} '
          '${_selectedAsset.ticker}.');
    }
  }

  void _handleSell() {
    final qty = double.tryParse(_qtyController.text) ?? 0;
    final ok = _engine.sell(_selectedAssetId, qty);
    setState(() {});
    if (!ok) {
      _showSnack(
        qty <= 0 ? 'Enter a valid quantity.' : "You don't hold enough shares to sell that.",
        isError: true,
      );
    } else {
      _showSnack('Sold ${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 2)} '
          '${_selectedAsset.ticker}.');
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? _bearColor : null,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('📈 Paper Trading'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildTickerSelector(colors),
          const SizedBox(height: 16),
          _buildChart(colors),
          const SizedBox(height: 16),
          _buildNewsFeed(colors),
          const SizedBox(height: 16),
          _buildTradePanel(colors),
          const SizedBox(height: 16),
          _buildPortfolioPanel(colors),
        ],
      ),
    );
  }

  Widget _buildTickerSelector(AppColors colors) {
    return Row(
      children: syntheticAssets.map((asset) {
        final candles = _engine.candlesFor(asset.id);
        final isUp = candles.length >= 2
            ? candles.last.close >= candles[candles.length - 2].close
            : true;
        final selected = asset.id == _selectedAssetId;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedAssetId = asset.id),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: selected ? Colors.teal.withOpacity(0.15) : colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: selected ? Colors.teal : colors.border),
              ),
              child: Column(
                children: [
                  Text(asset.ticker,
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: colors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    _priceFormat.format(_engine.currentPrice(asset.id)),
                    style: TextStyle(
                        fontSize: 12, color: isUp ? _bullColor : _bearColor),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildChart(AppColors colors) {
    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: pkg.Candlesticks(candles: _packageCandles(_selectedAssetId)),
    );
  }

  Widget _buildNewsFeed(AppColors colors) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('📰 Market News',
              style: TextStyle(fontWeight: FontWeight.bold, color: colors.textPrimary)),
          const SizedBox(height: 8),
          if (_engine.recentNews.isEmpty)
            Text('No headlines yet — the market is quiet for now.',
                style: TextStyle(color: colors.textTertiary, fontSize: 12))
          else
            ..._engine.recentNews.take(3).map((fired) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        fired.headline.driftImpact >= 0
                            ? Icons.trending_up
                            : Icons.trending_down,
                        size: 16,
                        color: fired.headline.driftImpact >= 0 ? _bullColor : _bearColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(fired.headline.text,
                            style:
                                TextStyle(color: colors.textSecondary, fontSize: 12)),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildTradePanel(AppColors colors) {
    final price = _engine.currentPrice(_selectedAssetId);
    final qty = double.tryParse(_qtyController.text) ?? 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${_selectedAsset.name} (${_selectedAsset.ticker})',
                  style: TextStyle(fontWeight: FontWeight.bold, color: colors.textPrimary)),
              Text(_priceFormat.format(price),
                  style: TextStyle(fontWeight: FontWeight.bold, color: colors.textPrimary)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qtyController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: colors.textPrimary),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Quantity',
                    labelStyle: TextStyle(color: colors.textTertiary),
                    enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.border)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text('Est. ${_priceFormat.format(price * qty)}',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _handleBuy,
                  style: ElevatedButton.styleFrom(backgroundColor: _bullColor),
                  child: const Text('BUY', style: TextStyle(color: Colors.black)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _handleSell,
                  style: ElevatedButton.styleFrom(backgroundColor: _bearColor),
                  child: const Text('SELL', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPortfolioPanel(AppColors colors) {
    final totalPnl = _engine.totalPnl;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('💼 Portfolio',
              style: TextStyle(fontWeight: FontWeight.bold, color: colors.textPrimary)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _statColumn('Cash', _cashFormat.format(_engine.cash), colors.textPrimary, colors),
              _statColumn('Total Value', _cashFormat.format(_engine.totalPortfolioValue),
                  colors.textPrimary, colors),
              _statColumn(
                'Total P&L',
                '${totalPnl >= 0 ? '+' : ''}${_cashFormat.format(totalPnl)}',
                totalPnl >= 0 ? _bullColor : _bearColor,
                colors,
              ),
            ],
          ),
          if (_engine.positions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(color: colors.border),
            ..._engine.positions.values.map((position) {
              final asset = syntheticAssets.firstWhere((a) => a.id == position.assetId);
              final currentPrice = _engine.currentPrice(position.assetId);
              final pnl = position.unrealizedPnl(currentPrice);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${asset.ticker} · ${position.quantity.toStringAsFixed(position.quantity == position.quantity.roundToDouble() ? 0 : 2)} sh @ ${_priceFormat.format(position.avgCost)}',
                        style: TextStyle(color: colors.textSecondary, fontSize: 12),
                      ),
                    ),
                    Text(
                      '${pnl >= 0 ? '+' : ''}${_cashFormat.format(pnl)}',
                      style: TextStyle(
                          color: pnl >= 0 ? _bullColor : _bearColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _statColumn(String label, String value, Color valueColor, AppColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: colors.textTertiary, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(color: valueColor, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }
}
