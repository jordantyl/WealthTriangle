import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../application/academy_state.dart';
import '../../application/badge_service.dart';

class MerchantScreen extends StatefulWidget {
  final String mode;
  const MerchantScreen({super.key, this.mode = 'campaign'});

  @override
  State<MerchantScreen> createState() => _MerchantScreenState();
}

class _MerchantScreenState extends State<MerchantScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = Provider.of<AcademyState>(context, listen: false);
      state.setMerchantMode(widget.mode);
      state.startMerchantGame();
    });
  }

  String _getEmoji(String category) {
    switch (category) {
      case 'food': return '🌾';
      case 'tech': return '💾';
      case 'resource': return '🛢️';
      case 'luxury': return '💎';
      default: return '📦';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AcademyState>(context);
    final currency = NumberFormat.simpleCurrency(name: 'USD', decimalDigits: 0);
    // Was $50k (10x starting cash) in 20 turns — with typical ±15-20% daily
    // swings and a 20-slot inventory cap, that's rarely achievable without
    // very lucky event timing. $20k (4x) keeps it a real challenge without
    // being a near-guaranteed loss.
    double targetAmount = state.maxTurns > 20 ? 1000000 : 20000;

    // ✅ FIXED: Inventory valuation using currentPrice
    double inventoryValue = 0;
    state.inventory.forEach((key, qty) {
      if (state.marketItems.any((i) => i.id == key)) {
        var item = state.marketItems.firstWhere((i) => i.id == key);
        inventoryValue += item.currentPrice * qty; // ✅ NOW USING CURRENT PRICE
      }
    });
    double netWorth = state.merchantCash + inventoryValue;

    // ✅ FIXED: Robbery popup using State flag
    if (state.activeEvent?.type == 'black_swan_robbery' && state.lastRobberyTurn != state.currentTurn) {
      state.setRobberyAcknowledged(state.currentTurn);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF2D2D44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.redAccent, width: 3)),
            title: Row(children: const [Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 40), SizedBox(width: 10), Text("BANDITS!", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 24))]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("You were ambushed on the trade route.", style: TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center),
                const SizedBox(height: 20),
                const Text("CASH LOST:", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text("ALL OF IT (\$0)", style: GoogleFonts.vt323(color: Colors.red, fontSize: 40, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                const Text("(Your inventory items are safe.)", style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            actions: [Center(child: SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () => Navigator.pop(context), child: const Text("OK...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)))))],
          ),
        );
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      body: SafeArea(
        child: Column(
          children: [
            // HUD
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              decoration: BoxDecoration(
                  color: const Color(0xFF16213e),
                  border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1), width: 2))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("DAY ${state.currentTurn}/${state.maxTurns}",
                          style: GoogleFonts.vt323(color: Colors.amber, fontSize: 26, fontWeight: FontWeight.bold)),
                      Text("ASSETS: ${currency.format(netWorth)}",
                          style: GoogleFonts.vt323(color: Colors.blueGrey[200], fontSize: 18)),
                      Text("TARGET: ${currency.format(targetAmount)}",
                          style: GoogleFonts.vt323(color: Colors.greenAccent.withOpacity(0.7), fontSize: 16)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.greenAccent, width: 2)),
                    child: Column(
                      children: [
                        Text("CASH", style: GoogleFonts.vt323(color: Colors.green, fontSize: 14)),
                        Text(currency.format(state.merchantCash), style: GoogleFonts.vt323(color: Colors.greenAccent, fontSize: 28, height: 0.9)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Backpack
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.backpack, color: Colors.blueAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: LinearProgressIndicator(
                        value: state.totalInventoryCount / state.maxInventorySlots,
                        backgroundColor: Colors.white10,
                        color: state.totalInventoryCount >= state.maxInventorySlots ? Colors.red : Colors.blueAccent,
                        minHeight: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text("${state.totalInventoryCount}/${state.maxInventorySlots}", style: GoogleFonts.vt323(color: Colors.white, fontSize: 22)),
                ],
              ),
            ),
            // Event Alert
            if (state.activeEvent != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 15),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), border: Border.all(color: Colors.redAccent, width: 2), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 30),
                    const SizedBox(width: 10),
                    Expanded(child: Text(state.activeEvent!.text, style: GoogleFonts.vt323(color: Colors.white, fontSize: 20), maxLines: 2))
                  ],
                ),
              ),
            // Market
            Expanded(
              child: state.marketItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: Colors.blueAccent),
                      const SizedBox(height: 20),
                      Text("Loading Market Data...", style: GoogleFonts.vt323(color: Colors.white, fontSize: 20)),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () { state.fetchGameContent().then((_) => state.startMerchantGame()); },
                        child: const Text("Retry Connection", style: TextStyle(color: Colors.amber)),
                      )
                    ],
                  ),
                )
              : ListView.builder(
                padding: const EdgeInsets.all(15),
                itemCount: state.marketItems.length,
                itemBuilder: (context, index) {
                  final item = state.marketItems[index];
                  final ownedQty = state.inventory[item.id] ?? 0;
                  final avgCost = state.inventoryAvgCost[item.id];

                  double ratio = item.currentPrice / item.basePrice;
                  bool isCheap = ratio < 0.85;
                  bool isExpensive = ratio > 1.15;

                  Color priceColor = isCheap ? Colors.greenAccent : (isExpensive ? Colors.redAccent : Colors.white);
                  Color glowColor = isCheap ? Colors.green.withOpacity(0.3) : Colors.transparent;

                  // Compare current price against what was actually paid for
                  // it, so it's obvious whether selling now is a profit.
                  bool isProfitable = avgCost != null && item.currentPrice > avgCost;
                  bool isLosing = avgCost != null && item.currentPrice < avgCost;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFF2A2A3E), borderRadius: BorderRadius.circular(12), border: Border.all(color: isCheap ? Colors.green : Colors.white12, width: isCheap ? 2 : 1), boxShadow: [BoxShadow(color: glowColor, blurRadius: 10)]),
                    child: Row(
                      children: [
                        Container(width: 60, height: 60, alignment: Alignment.center, decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(8)), child: Text(_getEmoji(item.category), style: const TextStyle(fontSize: 35))),
                        const SizedBox(width: 15),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(item.name, style: GoogleFonts.vt323(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                          Row(children: [Text(currency.format(item.currentPrice), style: GoogleFonts.vt323(color: priceColor, fontSize: 22)), if (isCheap) Text(" (BUY!)", style: GoogleFonts.vt323(color: Colors.green, fontSize: 16)), if (isExpensive) Text(" (SELL!)", style: GoogleFonts.vt323(color: Colors.red, fontSize: 16))]),
                          if (avgCost != null)
                            Text(
                              "Avg bought: ${currency.format(avgCost)}",
                              style: GoogleFonts.vt323(
                                color: isProfitable ? Colors.greenAccent : (isLosing ? Colors.redAccent : Colors.blueGrey[200]),
                                fontSize: 15,
                              ),
                            ),
                        ])),
                        if (ownedQty > 0) _GameButton(color: Colors.redAccent, icon: Icons.sell, label: "x$ownedQty", onTap: () { state.sellItem(item); }),
                        const SizedBox(width: 8),
                        _GameButton(color: state.totalInventoryCount >= state.maxInventorySlots ? Colors.grey : Colors.green, icon: Icons.add, label: "BUY", onTap: () { if (state.totalInventoryCount < state.maxInventorySlots) { state.buyItem(item); } else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Inventory Full! Sell something first."), duration: Duration(milliseconds: 500))); } }),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Next Turn
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 5,
                  ),
                  onPressed: () {
                    if (state.currentTurn >= state.maxTurns) {
                       bool isWin = netWorth >= targetAmount;
                       if (isWin) BadgeService.award(context, 'master_merchant');
                       _showGameOverDialog(context, isWin, netWorth, targetAmount);
                    } else {
                       state.nextMerchantTurn();
                    }
                  },
                  child: Text(
                      state.currentTurn >= state.maxTurns ? "FINISH GAME" : "SLEEP (NEXT DAY) ➡",
                      style: GoogleFonts.vt323(color: Colors.white, fontSize: 28, letterSpacing: 2)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGameOverDialog(BuildContext context, bool isWin, double finalScore, double target) {
     final currency = NumberFormat.simpleCurrency(name: 'USD', decimalDigits: 0);

     showDialog(
       context: context,
       barrierDismissible: false,
       builder: (context) => AlertDialog(
         backgroundColor: const Color(0xFF2D2D44),
         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isWin ? Colors.green : Colors.red, width: 3)),
         title: Center(child: Text(isWin ? "🏆 MISSION COMPLETE!" : "💀 MISSION FAILED", style: GoogleFonts.vt323(fontSize: 35, color: isWin ? Colors.greenAccent : Colors.redAccent, fontWeight: FontWeight.bold))),
         content: Column(
           mainAxisSize: MainAxisSize.min,
           children: [
             Text(isWin ? "You are a Master Merchant!" : "You didn't reach the target.", style: const TextStyle(color: Colors.white70)),
             const SizedBox(height: 20),
             const Text("FINAL ASSETS:", style: TextStyle(color: Colors.grey)),
             Text(currency.format(finalScore), style: GoogleFonts.vt323(fontSize: 40, color: Colors.white, fontWeight: FontWeight.bold)),
             const SizedBox(height: 10),
             Text("Target: ${currency.format(target)}", style: TextStyle(color: isWin ? Colors.green : Colors.red)),
           ],
         ),
         actions: [
           Center(
             child: ElevatedButton(
               style: ElevatedButton.styleFrom(backgroundColor: isWin ? Colors.green : Colors.red),
               onPressed: () {
                 Navigator.pop(context);
                 Navigator.pop(context);
               },
               child: const Text("BACK TO MENU", style: TextStyle(color: Colors.white)),
             ),
           )
         ],
       ),
     );
  }
}

class _GameButton extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _GameButton({required this.color, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(color: color.withOpacity(0.2), border: Border.all(color: color, width: 2), borderRadius: BorderRadius.circular(8)),
        child: Column(children: [Icon(icon, color: color, size: 20), Text(label, style: GoogleFonts.vt323(color: color, fontWeight: FontWeight.bold, fontSize: 16))]),
      ),
    );
  }
}