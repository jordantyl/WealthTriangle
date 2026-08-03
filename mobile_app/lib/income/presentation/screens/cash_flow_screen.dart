import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../user/application/wealth_state.dart';
import '../../../investment/application/portfolio_state.dart';
import '../../../shared/app_theme_colors.dart';

/// Report §3.2.1 (4.2): "The system shall allow the user to view a Cash
/// Flow Analysis to distinguish between capital gains and passive income."
///
/// Capital gains (realized P&L from selling holdings) and passive income
/// (dividends + manual side income) were already tracked separately in
/// PortfolioState and WealthState — this screen is the missing unified view
/// that puts them side by side and explains the difference: capital gains
/// are one-off events tied to a sale, passive income keeps recurring
/// whether or not you trade.
class CashFlowScreen extends StatelessWidget {
  const CashFlowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final wealthState = Provider.of<WealthState>(context);
    final portfolio = Provider.of<PortfolioState>(context);

    final sells = portfolio.transactions
        .where((t) => t.type == TransactionType.sell)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final totalRealizedGains =
        sells.fold<double>(0.0, (sum, t) => sum + (t.realizedPnL ?? 0.0));

    final monthlyDividendIncome =
        portfolio.totalAnnualDividendIncome / 12;
    final totalMonthlyPassiveIncome =
        wealthState.totalPassiveIncome + monthlyDividendIncome;
    // Annualized, so it's on the same time basis as realized gains (which
    // accumulate from whenever the user started trading).
    final totalAnnualPassiveIncome = totalMonthlyPassiveIncome * 12;

    final totalCashFlow = totalRealizedGains.abs() + totalAnnualPassiveIncome;
    final gainsShare =
        totalCashFlow > 0 ? totalRealizedGains.abs() / totalCashFlow : 0.5;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        title: Text('Cash Flow Analysis',
            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.border),
            ),
            child: Text(
              'Capital gains are one-time profits from selling an asset. '
              'Passive income keeps flowing every month whether you trade or not. '
              'A healthy long-term strategy leans on both — but shouldn\'t depend '
              'on constantly harvesting gains to stay afloat.',
              style: TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.5),
            ),
          ),
          const SizedBox(height: 20),

          _buildComparisonBar(colors, gainsShare, totalRealizedGains, totalAnnualPassiveIncome),
          const SizedBox(height: 24),

          _sectionHeader(colors, 'CAPITAL GAINS (REALIZED)'),
          const SizedBox(height: 10),
          _buildSummaryCard(
            colors,
            icon: Icons.trending_up,
            iconColor: totalRealizedGains >= 0 ? Colors.greenAccent : Colors.redAccent,
            label: 'Total Realized P&L (all-time)',
            value: '${totalRealizedGains >= 0 ? '+' : ''}\$${totalRealizedGains.toStringAsFixed(2)}',
            valueColor: totalRealizedGains >= 0 ? Colors.greenAccent : Colors.redAccent,
          ),
          const SizedBox(height: 12),
          if (sells.isEmpty)
            _emptyState(colors, 'No sales yet. Capital gains show up here once you sell a holding in Investment Lab.')
          else
            ...sells.take(10).map((t) => _buildGainRow(colors, t)),

          const SizedBox(height: 28),
          _sectionHeader(colors, 'PASSIVE INCOME (RECURRING)'),
          const SizedBox(height: 10),
          _buildSummaryCard(
            colors,
            icon: Icons.autorenew,
            iconColor: Colors.blueAccent,
            label: 'Total Recurring Income',
            value: 'RM ${totalMonthlyPassiveIncome.toStringAsFixed(2)} / mo',
            valueColor: Colors.blueAccent,
          ),
          const SizedBox(height: 12),
          if (monthlyDividendIncome > 0) ...[
            Text('Stock Dividends (from your holdings)',
                style: TextStyle(color: colors.textTertiary, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            ..._buildDividendBreakdown(colors, portfolio.dividendBreakdown),
            const SizedBox(height: 6),
          ],
          for (final source in wealthState.incomeSources)
            _buildIncomeRow(
              colors,
              source.name,
              source.isMonthly ? source.amount : source.amount / 12,
            ),
          if (wealthState.incomeSources.isEmpty && monthlyDividendIncome == 0)
            _emptyState(colors, 'No passive income sources yet. Add one from the Passive Income tab, '
                'or buy a dividend-paying stock in Investment Lab.'),
        ],
      ),
    );
  }

  Widget _sectionHeader(AppColors colors, String title) => Text(
        title,
        style: TextStyle(color: colors.textTertiary, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.bold),
      );

  Widget _buildComparisonBar(AppColors colors, double gainsShare, double totalGains, double totalAnnualIncome) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Where your cash flow comes from',
              style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  Expanded(
                    flex: (gainsShare * 1000).round().clamp(1, 999),
                    child: Container(color: const Color(0xFFFFB300)),
                  ),
                  Expanded(
                    flex: ((1 - gainsShare) * 1000).round().clamp(1, 999),
                    child: Container(color: const Color(0xFF1E88E5)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _legendDot(colors, const Color(0xFFFFB300), 'Capital Gains', totalGains),
              _legendDot(colors, const Color(0xFF1E88E5), 'Passive Income (annualized)', totalAnnualIncome),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(AppColors colors, Color color, String label, double value) {
    return Expanded(
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 11)),
                Text('\$${value.toStringAsFixed(0)}',
                    style: TextStyle(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    AppColors colors, {
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: iconColor.withOpacity(0.15), shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 12)),
          ),
          Text(value, style: TextStyle(color: valueColor, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildGainRow(AppColors colors, Transaction t) {
    final gain = t.realizedPnL ?? 0.0;
    final color = gain >= 0 ? Colors.greenAccent : Colors.redAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: colors.border)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.ticker, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold)),
                Text('Sold ${t.qty}x on ${DateFormat('MMM d, yyyy').format(t.date)}',
                    style: TextStyle(color: colors.textTertiary, fontSize: 11)),
              ],
            ),
          ),
          Text('${gain >= 0 ? '+' : ''}\$${gain.toStringAsFixed(2)}',
              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // Per-stock breakdown of totalAnnualDividendIncome — real trailing yield x
  // current value per holding, not a single opaque lump sum.
  List<Widget> _buildDividendBreakdown(AppColors colors, List<DividendBreakdownItem> breakdown) {
    final payers = breakdown.where((item) => item.annualDividend > 0).toList()
      ..sort((a, b) => b.annualDividend.compareTo(a.annualDividend));

    if (payers.isEmpty) {
      return [_emptyState(colors, "None of your current holdings show a dividend yield right now.")];
    }

    return payers.map((item) {
      final monthly = item.annualDividend / 12;
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: colors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: colors.border)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.ticker, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold)),
                  Text('${item.dividendYield.toStringAsFixed(2)}% trailing yield',
                      style: TextStyle(color: colors.textTertiary, fontSize: 11)),
                ],
              ),
            ),
            Text('+${item.currency} ${monthly.toStringAsFixed(2)}/mo',
                style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildIncomeRow(AppColors colors, String name, double monthlyAmount) {
    if (monthlyAmount == 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: colors.border)),
      child: Row(
        children: [
          Expanded(child: Text(name, style: TextStyle(color: colors.textPrimary))),
          Text('+RM ${monthlyAmount.toStringAsFixed(2)}/mo',
              style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _emptyState(AppColors colors, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(text, style: TextStyle(color: colors.textTertiary, fontSize: 12)),
    );
  }
}
