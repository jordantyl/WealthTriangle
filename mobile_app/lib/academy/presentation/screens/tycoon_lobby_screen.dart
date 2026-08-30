import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../application/academy_state.dart';
import 'merchant_screen.dart'; // Merchant Master
import 'tycoon_battle_screen.dart'; // Online PvP

class TycoonLobbyScreen extends StatefulWidget {
  const TycoonLobbyScreen({super.key});

  @override
  State<TycoonLobbyScreen> createState() => _TycoonLobbyScreenState();
}

class _TycoonLobbyScreenState extends State<TycoonLobbyScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _roomCtrl = TextEditingController();
  bool _isConnecting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roomCtrl.dispose();
    super.dispose();
  }

  // ✅ UPDATED: Now shows the Mode Selector instead of auto-starting
  void _playSolo() {
    _showModeSelection(
      context,
      title: "Merchant Master",
      icon: Icons.storefront,
      color: Colors.cyanAccent,
      modes: [
        {
          "label": "🏆 Campaign",
          "desc": "20 Turns. \$20k Goal. Limited Bag.",
          "icon": Icons.flag,
          "onTap": () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MerchantScreen(mode: 'campaign')))
        },
        {
          "label": "♾️ Tycoon (Endless)",
          "desc": "Unlimited Turns & Space. Relax.",
          "icon": Icons.all_inclusive,
          "onTap": () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MerchantScreen(mode: 'endless')))
        }
      ]
    );
  }

  void _quickMatch() async {
    if (_nameCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter your name first!")));
      return;
    }
    
    setState(() => _isConnecting = true);
    final state = Provider.of<AcademyState>(context, listen: false);
    
    // Search for match...
    String roomId = await state.findRandomMatch(_nameCtrl.text);
    
    setState(() => _isConnecting = false);

    if (roomId != "error" && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => TycoonBattleScreen(roomId: roomId)));
    }
  }

  void _createOnline() async {
    if (_nameCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter your name first!")));
      return;
    }
    setState(() => _isConnecting = true);
    final state = Provider.of<AcademyState>(context, listen: false);
    String roomId = await state.createBattleRoom(_nameCtrl.text);
    setState(() => _isConnecting = false);
    
    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => TycoonBattleScreen(roomId: roomId)));
    }
  }

  void _joinOnline() async {
    if (_nameCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter your name first!")));
      return;
    }
    if (_roomCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a Room ID to join.")));
      return;
    }
    setState(() => _isConnecting = true);
    final state = Provider.of<AcademyState>(context, listen: false);
    bool success = await state.joinBattleRoom(_roomCtrl.text.trim(), _nameCtrl.text);
    setState(() => _isConnecting = false);

    if (success && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => TycoonBattleScreen(roomId: _roomCtrl.text.trim())));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Room not found!")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(title: const Text("Trading Lobby"), backgroundColor: Colors.transparent),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ===============================================
            // 1. SOLO CARD (Triggers Mode Selection)
            // ===============================================
            _buildModeCard(
              title: "MERCHANT MASTER (SOLO)", 
              desc: "Offline Campaign & Endless Modes.",
              icon: Icons.storefront, 
              color: Colors.cyanAccent, 
              onTap: _playSolo, // Calls the popup now!
            ),
            const SizedBox(height: 30),
            
            // ===============================================
            // 2. ONLINE SECTION
            // ===============================================
            Text("⚔️ ONLINE BATTLE", style: GoogleFonts.vt323(fontSize: 35, color: Colors.redAccent)),
            const SizedBox(height: 20),
            
            TextField(controller: _nameCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Your Nickname", filled: true, fillColor: Colors.white10)),
            const SizedBox(height: 20),

            // ⚡ QUICK MATCH BUTTON
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.bolt, color: Colors.white),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[900]),
                onPressed: _isConnecting ? null : _quickMatch,
                label: const Text("⚡ RANDOM MATCH", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
            
            const SizedBox(height: 20),
            const Divider(color: Colors.white24),
            const SizedBox(height: 10),
            const Text("OR JOIN MANUALLY", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 10),
            
            Row(
              children: [
                Expanded(child: ElevatedButton(onPressed: _isConnecting ? null : _createOnline, child: const Text("CREATE ROOM"))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _roomCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Room ID", filled: true, fillColor: Colors.white10))),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent), onPressed: _isConnecting ? null : _joinOnline, child: const Text("JOIN ROOM"))),
          ],
        ),
      ),
    );
  }

  Widget _buildModeCard({required String title, required String desc, required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: color.withOpacity(0.1), border: Border.all(color: color), borderRadius: BorderRadius.circular(15)),
        child: Row(
          children: [
            Icon(icon, color: color, size: 40),
            const SizedBox(width: 20),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
                Text(desc, style: const TextStyle(color: Colors.grey)),
              ]),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 20),
          ],
        ),
      ),
    );
  }

  // ✅ HELPER: Mode Selection Bottom Sheet (Copied from AcademyScreen)
  void _showModeSelection(BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required List<Map<String, dynamic>> modes, 
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a1a2e),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Icon(icon, color: color, size: 30),
                  const SizedBox(width: 10),
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
              const Divider(color: Colors.white24, height: 30),
              
              // Mode Buttons
              ...modes.map((mode) => ListTile(
                contentPadding: const EdgeInsets.all(10),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(mode['icon'] ?? Icons.play_arrow, color: color),
                ),
                title: Text(mode['label'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                subtitle: Text(mode['desc'], style: const TextStyle(color: Colors.grey)),
                trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
                onTap: () {
                  Navigator.pop(context); // Close menu
                  mode['onTap'](); // Start Game
                },
              )),
            ],
          ),
        );
      },
    );
  }
}