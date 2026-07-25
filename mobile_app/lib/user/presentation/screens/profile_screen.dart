import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../application/wealth_state.dart';
import '../../../academy/application/academy_state.dart'; // Make sure path is correct
import 'login_screen.dart';
import '../../application/theme_service.dart';
import '../../../academy/application/badge_service.dart';

import 'package:intl/intl.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _showEditDialog(BuildContext context, String title, double currentValue, Function(double) onSave) {
    final controller = TextEditingController(text: currentValue.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D44),
        title: Text("Update $title", style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          autofocus: true,
          decoration: InputDecoration(
            prefixText: "\$ ",
            prefixStyle: const TextStyle(color: Colors.white),
            labelText: "Enter Amount",
            labelStyle: const TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent.withOpacity(0.5))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null) {
                onSave(val);
              }
              Navigator.pop(ctx);
            },
            child: const Text("SAVE"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wealthState = Provider.of<WealthState>(context);
    final academyState = Provider.of<AcademyState>(context);
    final user = FirebaseAuth.instance.currentUser;
    final String displayName = user?.email?.split('@')[0] ?? "User"; 

    // Dynamic coloring based on their Academy assessment
    Color profileColor = Colors.greenAccent;
    if (academyState.riskProfile == 'Aggressive') profileColor = Colors.redAccent;
    if (academyState.riskProfile == 'Moderate') profileColor = Colors.orangeAccent;

    return Scaffold(
      appBar: AppBar(title: const Text("My Profile")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // USER HEADER
            const Center(
              child: CircleAvatar(
                radius: 50,
                backgroundColor: Colors.blueAccent,
                child: Icon(Icons.person, size: 60, color: Colors.white),
              ),
            ),
            const SizedBox(height: 15),
            Text(displayName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            
            const SizedBox(height: 10),
            // OFFICIAL ACADEMY RANK
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              decoration: BoxDecoration(
                color: profileColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: profileColor.withOpacity(0.5)),
              ),
              child: Text(
                "${academyState.riskProfile} Investor • ${academyState.xp} XP", 
                style: TextStyle(color: profileColor, fontWeight: FontWeight.bold, fontSize: 14)
              ),
            ),
            const SizedBox(height: 30),

            _buildSectionHeader("Financial Foundation"),

            _buildActionTile(
              context, icon: Icons.attach_money, title: "Monthly Salary",
              value: "\$${wealthState.monthlySalary.toStringAsFixed(0)}",
              onTap: () => _showEditDialog(context, "Salary", wealthState.monthlySalary, wealthState.updateSalary),
            ),

            _buildActionTile(
              context, icon: Icons.shopping_cart, title: "Monthly Expenses",
              value: "\$${wealthState.monthlyExpenses.toStringAsFixed(0)}",
              onTap: () => _showEditDialog(context, "Expenses", wealthState.monthlyExpenses, wealthState.updateExpenses),
            ),

            _buildActionTile(
              context, icon: Icons.account_balance_wallet, title: "Current Savings",
              value: "\$${wealthState.currentSavings.toStringAsFixed(0)}",
              onTap: () => _showEditDialog(context, "Savings", wealthState.currentSavings, wealthState.updateSavings),
            ),

            const SizedBox(height: 20),
            const Text("IRON TRIANGLE PROFILE", style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1.5)),
            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: const Color(0xFF2D2D44), borderRadius: BorderRadius.circular(15)),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.health_and_safety, color: Colors.greenAccent),
                    title: const Text("Triangle Health Score", style: TextStyle(color: Colors.white)),
                    trailing: Text(
                      wealthState.triangleHealthScore.toStringAsFixed(1), 
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.greenAccent)
                    ),
                  ),
                  const Divider(color: Colors.white24),
                  ListTile(
                    leading: const Icon(Icons.tune, color: Colors.blueAccent),
                    title: const Text("Investment Focus", style: TextStyle(color: Colors.white)),
                    trailing: DropdownButton<TrianglePreference>(
                      value: wealthState.trianglePreference,
                      dropdownColor: const Color(0xFF1E1E2C),
                      style: const TextStyle(color: Colors.white),
                      items: TrianglePreference.values.map((pref) {
                        return DropdownMenuItem(
                          value: pref,
                          child: Text(pref.name.toUpperCase()),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) wealthState.updateTrianglePreference(val);
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            _buildSectionHeader("Financial Goals"),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Target Savings Goal", style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        wealthState.financialGoal != null
                            ? "\$${wealthState.financialGoal!.toStringAsFixed(0)}"
                            : "Not set",
                        style: TextStyle(
                          color: wealthState.financialGoal != null ? Colors.greenAccent : Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (wealthState.goalDate != null)
                    Text(
                      "Target Date: ${DateFormat('MMM yyyy').format(wealthState.goalDate!)}",
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showGoalDialog(context, wealthState),
                      icon: const Icon(Icons.track_changes),
                      label: Text(wealthState.financialGoal != null ? "Update Goal" : "Set Goal"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),
            _buildSectionHeader("App Settings"),
            
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SwitchListTile(
                title: const Text("Dark Mode"),
                secondary: const Icon(Icons.dark_mode),
                value: Provider.of<ThemeService>(context).isDarkMode,
                onChanged: (val) {
                  Provider.of<ThemeService>(context, listen: false).toggleTheme(val);
                },
              ),
            ),

            const SizedBox(height: 20),
            _buildSectionHeader("My Risk Perception"),

            // YOUR ORIGINAL IDEA RETURNED: The Self-Assessed Slider
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.psychology, color: Colors.blueAccent),
                      SizedBox(width: 15),
                      Text("Self-Assessed Tolerance", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Slider(
                    value: wealthState.riskTolerance,
                    min: 0,
                    max: 100,
                    divisions: 10,
                    activeColor: Colors.blueAccent,
                    label: wealthState.riskTolerance.round().toString(),
                    onChanged: (newValue) => wealthState.updateRiskTolerance(newValue),
                  ),
                  Text(
                    "How much risk do YOU think you can handle? The app combines this with your Academy Rank to tailor the Investment Lab.",
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // LOGOUT BUTTON
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
                      (route) => false,
                    );
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                child: const Text("LOG OUT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(title, style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildActionTile(BuildContext context, {required IconData icon, required String title, required String value, required VoidCallback onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Icon(icon, color: Colors.blueAccent),
        title: Text(title, style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value, style: const TextStyle(color: Colors.grey, fontSize: 16)),
            const SizedBox(width: 10),
            const Icon(Icons.edit, size: 16, color: Colors.grey),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  void _showGoalDialog(BuildContext context, WealthState wealthState) {
    final controller = TextEditingController(
      text: wealthState.financialGoal?.toStringAsFixed(0) ?? '',
    );
    DateTime selectedDate = wealthState.goalDate ?? DateTime.now().add(const Duration(days: 365));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D44),
        title: const Text("Set Financial Goal", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                prefixText: "\$ ",
                prefixStyle: TextStyle(color: Colors.white),
                labelText: "Target Amount",
                labelStyle: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 10),
            ListTile(
              title: Text(
                "Target Date: ${DateFormat('MMM yyyy').format(selectedDate)}",
                style: const TextStyle(color: Colors.white),
              ),
              trailing: const Icon(Icons.calendar_today, color: Colors.white),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: selectedDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 20)),
                );
                if (date != null) {
                  selectedDate = date;
                  Navigator.pop(ctx);
                  _showGoalDialog(context, wealthState); // Reopen with new date
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () {
              final goal = double.tryParse(controller.text);
              if (goal != null && goal > 0) {
                wealthState.setFinancialGoal(goal, selectedDate);
                BadgeService.award(context, 'goal_setter');
              }
              Navigator.pop(ctx);
            },
            child: const Text("SAVE"),
          ),
        ],
      ),
    );
  }
}