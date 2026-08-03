import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../application/wealth_state.dart';
import '../../application/theme_service.dart';
import '../../../investment/application/portfolio_state.dart';
import '../../../academy/application/academy_state.dart';
import '../../../ai/presentation/ai_chat_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'alerts_banner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Fetch the database data the moment the app opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AcademyState>(context, listen: false).fetchUserData();
      Provider.of<WealthState>(context, listen: false).syncFromCloud();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 1. Listen to all your system Brains
    final user = FirebaseAuth.instance.currentUser;
    final wealthState = Provider.of<WealthState>(context);
    final themeService = Provider.of<ThemeService>(context);
    final portfolio = Provider.of<PortfolioState>(context);
    final academyState = Provider.of<AcademyState>(context);

    // Calculate real passive income
    double monthlyDividendIncome =
        portfolio.totalAnnualDividendIncome / 12;
    double totalMonthlyIncome =
        wealthState.totalPassiveIncome + monthlyDividendIncome;

    return Scaffold(
      appBar: AppBar(
        title: const Text("WealthTriangle",
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(
                themeService.isDarkMode ? Icons.light_mode : Icons.dark_mode),
            onPressed: () {
              themeService.toggleTheme(!themeService.isDarkMode);
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // WELCOME HEADER
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                "Welcome, \n${user?.email?.split('@')[0] ?? 'User'}!",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ),

            const AlertsBanner(),
            const SizedBox(height: 15),

            const Text("Your Financial Snapshot",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),

            // LIVE SUMMARY CARD
            _buildSummaryCard(
                context, wealthState, academyState, totalMonthlyIncome),

            const SizedBox(height: 30),
            const Text("Modules",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)),
            const SizedBox(height: 15),

            // UPGRADED 5-MODULE LAYOUT
            // Row 1: Core Investment & Education
            Row(
              children: [
                Expanded(
                    child: _buildModuleCard(context,
                        title: "Investment Lab",
                        icon: Icons.show_chart,
                        color: Colors.blueAccent,
                        route: '/investment')),
                const SizedBox(width: 15),
                Expanded(
                    child: _buildModuleCard(context,
                        title: "Academy",
                        icon: Icons.school,
                        color: Colors.purpleAccent,
                        route: '/academy')),
              ],
            ),
            const SizedBox(height: 15),

            // Row 2: ⭐ NEW Market Intelligence & Events
            Row(
              children: [
                Expanded(
                    child: _buildModuleCard(context,
                        title: "Market Intel",
                        icon: Icons.newspaper,
                        color: Colors.orangeAccent,
                        route: '/intelligence')),
                const SizedBox(width: 15),
                Expanded(
                    child: _buildModuleCard(context,
                        title: "Events",
                        icon: Icons.event,
                        color: Colors.pinkAccent,
                        route: '/calendar')),
              ],
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: _buildModuleCard(context,
                  title: "⏳ Time Machine",
                  icon: Icons.history_toggle_off,
                  color: Colors.amberAccent,
                  route: '/timemachine'),
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: _buildModuleCard(context,
                  title: "📈 Paper Trading",
                  icon: Icons.candlestick_chart,
                  color: Colors.tealAccent,
                  route: '/papertrading'),
            ),
            const SizedBox(height: 15),

            // Row 3: Passive Income Banner
            SizedBox(
              width: double.infinity,
              child: _buildModuleCard(context,
                  title: "Passive Income",
                  icon: Icons.attach_money,
                  color: Colors.greenAccent,
                  route: '/income'),
            ),

            const SizedBox(height: 20),
            // Replaces the old "Monthly Brief" dialog (income/expenses/savings
            // as read-only text you could only close) — the Performance
            // Report's Financial Situation section covers the same ground
            // plus the Iron Triangle, holdings, and Academy progress, and is
            // actually shareable/exportable instead of a dead-end dialog.
            SizedBox(
              width: double.infinity,
              child: _buildModuleCard(context,
                  title: "📊 Performance Report",
                  icon: Icons.description,
                  color: Colors.blueAccent,
                  route: '/report'),
            ),

            const SizedBox(height: 40),

            // LOGOUT BUTTON
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const LoginScreen()),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("LOG OUT",
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const AIChatScreen()));
        },
        child: const Icon(Icons.smart_toy),
        backgroundColor: Colors.deepPurple,
      ),
    );
  }

  // --- HELPER WIDGETS ---

  Widget _buildSummaryCard(BuildContext context, WealthState state,
      AcademyState academy, double totalIncome) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 5))
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMiniStat(
                  context,
                  "Safety",
                  "${state.safetyScore.toStringAsFixed(0)}%",
                  Colors.greenAccent),
              _buildMiniStat(
                  context, "Profile", academy.riskProfile, Colors.orangeAccent),
              _buildMiniStat(context, "Passive",
                  "RM ${totalIncome.toStringAsFixed(0)}", Colors.blueAccent),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: Theme.of(context).dividerColor),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Academy Progress",
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              Text("${academy.xp} XP",
                  style: const TextStyle(
                      color: Colors.purpleAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: (academy.xp / 1000).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.grey.withOpacity(0.2),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Colors.purpleAccent),
            ),
          ),
          if (state.financialGoal != null && state.financialGoal! > 0) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Goal Progress",
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                Text(
                  "${(state.goalProgress * 100).toStringAsFixed(0)}% of RM ${state.financialGoal!.toStringAsFixed(0)}",
                  style: const TextStyle(
                      color: Colors.blueAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: state.goalProgress,
                minHeight: 8,
                backgroundColor: Colors.grey.withOpacity(0.2),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniStat(
      BuildContext context, String label, String value, Color color) {
    Color textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 5),
        Text(value,
            style: TextStyle(
                color:
                    textColor == Colors.white ? color : color.withOpacity(0.8),
                fontSize: 16,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildModuleCard(BuildContext context,
      {required String title,
      required IconData icon,
      required Color color,
      required String route}) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        if (route.isNotEmpty) {
          Navigator.pushNamed(context, route);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 15),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.5)),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.1), blurRadius: 10, spreadRadius: 2)
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 15),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87)),
          ],
        ),
      ),
    );
  }
}
