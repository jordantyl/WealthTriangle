import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../application/academy_state.dart';
import '../../application/badge_service.dart';

class FlashTraderScreen extends StatefulWidget {
  final String mode;
  const FlashTraderScreen({super.key, this.mode = 'blitz'});

  @override
  State<FlashTraderScreen> createState() => _FlashTraderScreenState();
}

class _FlashTraderScreenState extends State<FlashTraderScreen> {
  int _streak = 0;
  Map<String, dynamic>? _currentScenario;
  
  // Timer State
  Timer? _timer;
  int _timeLeft = 5; // ⚡ 5 Seconds per card!
  double _timeProgress = 1.0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // Pick a card based on User Level
  void _loadNextScenario() {
    // Guards the Future.delayed callback in _handleDecision below — if the
    // user backs out of this screen within that 300ms window, this would
    // otherwise run against a disposed State's context (Provider.of / setState
    // after dispose), which throws.
    if (!mounted) return;
    final academyState = Provider.of<AcademyState>(context, listen: false);
    
    // ✅ NEW: Use the filtered list
    final scenarios = academyState.getFlashScenariosForUser();

    if (scenarios.isNotEmpty) {
      setState(() {
        _currentScenario = scenarios[Random().nextInt(scenarios.length)];
        _decided = false;
        _startTimer(); // Restart the clock
      });
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timeLeft = 5; // Reset to 5 seconds
    _timeProgress = 1.0;
    
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_timeLeft > 0) {
          _timeLeft--;
          _timeProgress = _timeLeft / 5;
        } else {
          // Time ran out!
          _timer?.cancel();
          _handleDecision(null); // Pass null to indicate timeout
        }
      });
    });
  }

  bool _decided = false;

  void _handleDecision(bool? bought) {
    if (_currentScenario == null || _decided) return;
    _decided = true;
    _timer?.cancel();

    // If bought is null, it means Timeout
    bool shouldBuy = _currentScenario!['shouldBuy'];
    bool isCorrect = (bought != null) && (bought == shouldBuy);
    
    if (isCorrect) {
      setState(() => _streak++);
      if (_streak >= 5) BadgeService.award(context, 'flash_streak_5');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("⚡ FAST HANDS! +1 Streak"), 
        duration: Duration(milliseconds: 300), 
        backgroundColor: Colors.green
      ));
    } else {
      if (widget.mode == 'sudden_death') {
          _timer?.cancel();
          _showGameOverDialog(); // Create a simple alert dialog
          return;
       }
      String msg = bought == null ? "⏰ TOO SLOW!" : "📉 BAD TRADE!";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), 
        duration: const Duration(milliseconds: 500), 
        backgroundColor: Colors.red
      ));
      setState(() => _streak = 0);
    }
    
    // Slight delay before next card so user sees the result
    Future.delayed(const Duration(milliseconds: 300), _loadNextScenario);
  }

  // Helper: Get Icon based on News Type
  IconData _getIconForType(String? type) {
    switch (type) {
      case 'tech': return Icons.laptop_mac;
      case 'energy': return Icons.oil_barrel;
      case 'policy': return Icons.account_balance; // Gov/Bank
      case 'legal': return Icons.gavel; // Lawsuit
      case 'company': return Icons.business;
      case 'market': return Icons.show_chart;
      default: return Icons.newspaper; // Fallback
    }
  }

  void _showGameOverDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.red.shade900,
        title: const Text("💀 GAME OVER", style: TextStyle(color: Colors.white)),
        content: const Text("Sudden Death means ZERO mistakes allowed!", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(context); Navigator.pop(context); }, 
            child: const Text("EXIT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          )
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final academyState = Provider.of<AcademyState>(context);
    
    // 1. Loading State
    if (academyState.flashScenarios.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Flash Trader ⚡")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // 2. Initial Load
    if (_currentScenario == null) {
       // We need to use a post-frame callback to avoid setState during build
       WidgetsBinding.instance.addPostFrameCallback((_) => _loadNextScenario());
       return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: Text("Streak: 🔥 $_streak")),
      body: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ⏰ TIMER BAR
            LinearProgressIndicator(
              value: _timeProgress,
              color: _timeProgress > 0.4 ? Colors.amber : Colors.red,
              backgroundColor: Colors.grey[800],
              minHeight: 8,
            ),
            const SizedBox(height: 40),

            // THE CARD
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  // ✅ NO MORE GREEN/RED BACKGROUND
                  color: const Color(0xFF2D2D44), 
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                  boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0,5))]
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ✅ DYNAMIC ICON (Based on Topic, not Direction)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getIconForType(_currentScenario!['type']), 
                        size: 60, 
                        color: Colors.blueAccent
                      ),
                    ),
                    const SizedBox(height: 30),
                    
                    Text(
                      _currentScenario!['news'], 
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.3),
                      textAlign: TextAlign.center,
                    ),
                    
                    const SizedBox(height: 20),
                    // Hint
                    Text(
                      "Read the headline carefully...", 
                      style: TextStyle(color: Colors.grey[400], fontSize: 12, fontStyle: FontStyle.italic)
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),

            // BUTTONS
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 80,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.8)),
                      onPressed: () => _handleDecision(false), // Pass
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [Icon(Icons.close, size: 30), Text("PASS")],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: SizedBox(
                    height: 80,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green.withOpacity(0.8)),
                      onPressed: () => _handleDecision(true), // Buy
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [Icon(Icons.check, size: 30), Text("BUY")],
                      ),
                    ),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}