import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../application/theme_service.dart';
import '../../../investment/domain/brokerage_connector.dart';
import '../../../investment/data/demo_brokerage_connector.dart';
import 'login_screen.dart';
import 'forget_password_screen.dart';
import '../../../floating_assistant/floating_assistant_launcher.dart';

/// ⚙️ Fulfills report requirement 1.4:
/// "The system shall allow the user to manage application settings
///  and privacy preferences."
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;

  // FR 7.4: REST-ready brokerage connection point (see BrokerageConnector).
  final BrokerageConnector _broker = DemoBrokerageConnector();
  bool _brokerConnected = false;
  bool _brokerConnecting = false;

  bool _floatingAssistantEnabled = false;
  bool _floatingAssistantBusy = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadFloatingAssistantState();
  }

  Future<void> _loadFloatingAssistantState() async {
    final running = await FloatingAssistantLauncher.isRunning();
    if (!mounted) return;
    setState(() => _floatingAssistantEnabled = running);
  }

  Future<void> _setFloatingAssistant(bool value) async {
    setState(() => _floatingAssistantBusy = true);
    if (value) {
      final started = await FloatingAssistantLauncher.requestPermissionsAndStart();
      if (!mounted) return;
      setState(() {
        _floatingAssistantEnabled = started;
        _floatingAssistantBusy = false;
      });
      if (!started) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Overlay, microphone, and camera permissions are all needed for the floating assistant.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } else {
      await FloatingAssistantLauncher.stop();
      if (!mounted) return;
      setState(() {
        _floatingAssistantEnabled = false;
        _floatingAssistantBusy = false;
      });
    }
  }

  Future<void> _connectBroker() async {
    setState(() => _brokerConnecting = true);
    final ok = await _broker.connect();
    if (!mounted) return;
    setState(() {
      _brokerConnected = ok;
      _brokerConnecting = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Connected to ${_broker.brokerName}'
            : 'Could not connect to ${_broker.brokerName}'),
        backgroundColor: ok ? Colors.green : Colors.redAccent,
      ),
    );
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
    });
  }

  Future<void> _setNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notificationsEnabled', value);
    setState(() => _notificationsEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text("⚙️ Settings")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---------- ACCOUNT ----------
          _sectionLabel("ACCOUNT"),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person, color: Colors.blueAccent),
                  title: Text(user?.email ?? "Not logged in"),
                  subtitle: const Text("Signed in account"),
                ),
                const Divider(height: 1),
                ListTile(
                  leading:
                      const Icon(Icons.lock_reset, color: Colors.orangeAccent),
                  title: const Text("Change / Reset Password"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ForgotPasswordScreen()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ---------- APPEARANCE ----------
          _sectionLabel("APPEARANCE"),
          Card(
            child: SwitchListTile(
              secondary: Icon(
                themeService.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                color: Colors.purpleAccent,
              ),
              title: const Text("Dark Mode"),
              subtitle: const Text("Easier on the eyes for market watching"),
              value: themeService.isDarkMode,
              onChanged: (v) => themeService.toggleTheme(v),
            ),
          ),
          const SizedBox(height: 20),

          // ---------- NOTIFICATIONS ----------
          _sectionLabel("NOTIFICATIONS"),
          Card(
            child: SwitchListTile(
              secondary:
                  const Icon(Icons.notifications, color: Colors.amber),
              title: const Text("Event Alerts"),
              subtitle:
                  const Text("Earnings, dividends & trend notifications"),
              value: _notificationsEnabled,
              onChanged: _setNotifications,
            ),
          ),
          const SizedBox(height: 20),

          // ---------- FLOATING ASSISTANT ----------
          _sectionLabel("FLOATING ASSISTANT"),
          Card(
            child: SwitchListTile(
              secondary: _floatingAssistantBusy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome, color: Colors.deepPurpleAccent),
              title: const Text("Floating Quick-Ask Bubble"),
              subtitle: const Text(
                  "Ask by voice or photo over any app, without opening WealthTriangle. Android only."),
              value: _floatingAssistantEnabled,
              onChanged: _floatingAssistantBusy ? null : _setFloatingAssistant,
            ),
          ),
          const SizedBox(height: 20),

          // ---------- BROKERAGE (FR 7.4) ----------
          _sectionLabel("BROKERAGE"),
          Card(
            child: ListTile(
              leading: Icon(
                _brokerConnected ? Icons.link : Icons.link_off,
                color: _brokerConnected ? Colors.greenAccent : Colors.grey,
              ),
              title: Text(_broker.brokerName),
              subtitle: Text(_brokerConnected
                  ? "Connected • sandbox (paper trades only)"
                  : "Not connected • REST-ready for a real broker later"),
              trailing: _brokerConnecting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(
                      onPressed: _brokerConnected ? null : _connectBroker,
                      child: Text(_brokerConnected ? "CONNECTED" : "CONNECT"),
                    ),
            ),
          ),
          const SizedBox(height: 20),

          // ---------- PRIVACY ----------
          _sectionLabel("PRIVACY & LEGAL"),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.privacy_tip,
                      color: Colors.greenAccent),
                  title: const Text("Privacy Policy"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showPolicyDialog(
                    context,
                    "Privacy Policy",
                    "WealthTriangle is an EDUCATIONAL simulation app.\n\n"
                        "• We store your email, wealth profile (salary, savings, expenses), "
                        "simulated portfolio, and learning progress in Firebase to sync "
                        "across your devices.\n\n"
                        "• We do NOT collect real banking or brokerage credentials.\n\n"
                        "• Your data is never sold to third parties.\n\n"
                        "• You may request account deletion at any time, which removes "
                        "all your data from our servers.",
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading:
                      const Icon(Icons.gavel, color: Colors.blueGrey),
                  title: const Text("Disclaimer"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showPolicyDialog(
                    context,
                    "Disclaimer",
                    "WealthTriangle provides SIMULATED results for educational "
                        "purposes only.\n\n"
                        "Nothing in this app constitutes financial advice. Past "
                        "performance (including Time Machine backtests) does not "
                        "guarantee future results. Always do your own research "
                        "before investing real money.",
                  ),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.info_outline, color: Colors.grey),
                  title: Text("About"),
                  subtitle: Text(
                      "WealthTriangle v1.0 — FYP by Tan Yong Le, TARUMT 2025/26"),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),

          // ---------- LOGOUT ----------
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              },
              icon: const Icon(Icons.logout),
              label: const Text("LOG OUT"),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
            color: Colors.grey,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2),
      ),
    );
  }

  void _showPolicyDialog(BuildContext context, String title, String body) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CLOSE"),
          ),
        ],
      ),
    );
  }
}