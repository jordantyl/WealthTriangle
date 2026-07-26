import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../application/portfolio_state.dart';
import '../../../user/application/wealth_state.dart';

/// 🎯 Recommends investment TYPES based on the user's classified profile
/// (from PortfolioState.investorType) and their Triangle preference.
/// This is education, not financial advice — the card says so.
///
/// HOW TO ADD: in home_screen.dart, below the summary card:
///
///   const SizedBox(height: 15),
///   const InvestRecommendationCard(),
class InvestRecommendationCard extends StatelessWidget {
  const InvestRecommendationCard({super.key});

  @override
  Widget build(BuildContext context) {
    final portfolio = Provider.of<PortfolioState>(context);
    final wealth = Provider.of<WealthState>(context);

    final profile = portfolio.investorType; // e.g. "Conservative 🛡️"
    final rec = _recommendationFor(profile, wealth.trianglePreference);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: rec.color.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(rec.icon, color: rec.color, size: 22),
              const SizedBox(width: 8),
              Text('Suggested for a $profile investor',
                  style: TextStyle(
                      color: rec.color,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          ...rec.suggestions.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ',
                        style: TextStyle(
                            color: rec.color, fontWeight: FontWeight.bold)),
                    Expanded(
                        child: Text(s,
                            style: const TextStyle(
                                fontSize: 12.5, height: 1.4))),
                  ],
                ),
              )),
          const SizedBox(height: 6),
          Text(
            '🔺 ${rec.triangleNote}',
            style: const TextStyle(
                color: Colors.amber, fontSize: 11, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 6),
          const Text(
            'Educational suggestions only — not financial advice. Test any idea in the Time Machine first!',
            style: TextStyle(color: Colors.grey, fontSize: 10),
          ),
        ],
      ),
    );
  }

  _Rec _recommendationFor(String profile, TrianglePreference pref) {
    // Base recommendation by classified risk profile
    _Rec rec;
    if (profile.startsWith("Conservative")) {
      rec = _Rec(
        icon: Icons.shield,
        color: Colors.greenAccent,
        suggestions: [
          "KLCI blue-chip dividend stocks (e.g. banks, utilities on Bursa) — steady ~3-5% yields",
          "Broad index ETFs (S&P 500 trackers) for diversified, lower-volatility growth",
          "Fixed deposits / bonds for your emergency fund — track them in the Events calendar",
        ],
        triangleNote:
            "Your profile prioritizes SAFETY. Accept lower Return in exchange for smaller drawdowns.",
      );
    } else if (profile.startsWith("Aggressive")) {
      rec = _Rec(
        icon: Icons.rocket_launch,
        color: Colors.redAccent,
        suggestions: [
          "US growth/tech stocks (high Return potential, high volatility — check Max Drawdown first)",
          "Sector ETFs in themes you understand (semiconductors, AI) rather than single hype stocks",
          "Keep 3-6 months expenses in cash so volatility never forces you to sell at the bottom",
        ],
        triangleNote:
            "Your profile chases RETURN. Watch the Safety corner — run a Time Machine test through 2020 or 2022 before committing.",
      );
    } else if (profile.startsWith("Balanced")) {
      rec = _Rec(
        icon: Icons.balance,
        color: Colors.orangeAccent,
        suggestions: [
          "A core-satellite mix: index ETF core (70%) + a few individual picks (30%)",
          "Blend KLCI dividend payers with US growth for currency + sector diversification",
          "Rebalance yearly — sell a little of what grew, top up what lagged",
        ],
        triangleNote:
            "Your profile balances all three corners. Consistency beats timing.",
      );
    } else {
      // "New Investor" — no holdings yet
      rec = _Rec(
        icon: Icons.school,
        color: Colors.blueAccent,
        suggestions: [
          "Start in the Academy — complete the quiz to unlock your risk profile",
          "Run your first Time Machine simulation (try AAPL 2020→2023) to feel a real crash safely",
          "Add 2-3 stocks to your watchlist to activate news and event alerts",
        ],
        triangleNote:
            "Learn the Triangle before risking anything — that's the whole point of this app.",
      );
    }

    // Nudge based on the user's stated Triangle preference
    switch (pref) {
      case TrianglePreference.liquidity:
        rec.suggestions.add(
            "You prefer LIQUIDITY: favor large-cap, high-volume stocks you can exit quickly; avoid lock-in products.");
        break;
      case TrianglePreference.safety:
        rec.suggestions.add(
            "You prefer SAFETY: check the Max Drawdown of anything before buying — the Time Machine shows it instantly.");
        break;
      case TrianglePreference.return_:
        rec.suggestions.add(
            "You prefer RETURN: compare CAGR across candidates in the Time Machine, but never ignore the drawdown next to it.");
        break;
      case TrianglePreference.balanced:
        break;
    }

    return rec;
  }
}

class _Rec {
  final IconData icon;
  final Color color;
  final List<String> suggestions;
  final String triangleNote;
  _Rec(
      {required this.icon,
      required this.color,
      required this.suggestions,
      required this.triangleNote});
}