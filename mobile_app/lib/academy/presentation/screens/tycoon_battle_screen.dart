import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../application/academy_state.dart';
import '../../data/scenario_data.dart';
import 'market_tycoon_screen.dart';

class TycoonBattleScreen extends StatefulWidget {
  final String roomId;
  const TycoonBattleScreen({super.key, required this.roomId});

  @override
  State<TycoonBattleScreen> createState() => _TycoonBattleScreenState();
}

class _TycoonBattleScreenState extends State<TycoonBattleScreen> {
  // Shown once a solo host has waited a while with no real opponent —
  // lets them play a practice match against a bot instead of waiting forever.
  Timer? _botOfferTimer;
  bool _botOfferReady = false;
  bool _addingBot = false;

  // Guards against scheduling more than one bot move per round (this
  // widget rebuilds on every Firestore snapshot while waiting for the
  // bot's delayed move to land).
  int? _botMoveScheduledForRound;

  @override
  void initState() {
    super.initState();
    _botOfferTimer = Timer(const Duration(seconds: 15), () {
      if (mounted) setState(() => _botOfferReady = true);
    });
  }

  @override
  void dispose() {
    _botOfferTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AcademyState>(context);
    final String? myUserId = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<DocumentSnapshot>(
      stream: state.battleStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));

        // Handle deleted room or error
        if (!snapshot.data!.exists) {
          return const Scaffold(body: Center(child: Text("Room Closed")));
        }

        var data = snapshot.data!.data() as Map<String, dynamic>;
        bool isHost = data['hostId'] == myUserId;

        // 1. LOBBY WAITING
        if (data['status'] == 'waiting') {
          return Scaffold(
            backgroundColor: const Color(0xFF1a1a2e),
            appBar: AppBar(title: Text("Room: ${widget.roomId}"), backgroundColor: Colors.transparent),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Waiting for opponent...", style: TextStyle(color: Colors.white, fontSize: 20)),
                  if (_botOfferReady) ...[
                    const SizedBox(height: 24),
                    const Text("Taking a while? Play a practice round instead.",
                        style: TextStyle(color: Colors.white54, fontSize: 13)),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _addingBot
                          ? null
                          : () async {
                              setState(() => _addingBot = true);
                              await state.addBotOpponent();
                            },
                      icon: const Icon(Icons.smart_toy),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                      label: Text(_addingBot ? "Starting..." : "Play vs Bot 🤖"),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        // 2. ACTIVE MATCH — render this round (or the game-over screen) via MarketTycoonScreen.
        int round = data['currentRound'];
        List<dynamic> scenarioIds = data['scenarioIds'];
        int totalRounds = scenarioIds.length;

        double myCash = ((isHost ? data['hostCash'] : data['guestCash']) as num).toDouble();
        double opponentCash = ((isHost ? data['guestCash'] : data['hostCash']) as num).toDouble();
        bool hostLocked = data['hostLocked'];
        bool guestLocked = data['guestLocked'];
        bool opponentLocked = isHost ? guestLocked : hostLocked;

        // The bot only ever occupies the guest slot, so only the host's
        // client (the real, connected player) needs to drive it.
        bool isBotMatch = data['guestId'] == 'BOT';
        if (isHost && isBotMatch && hostLocked && !guestLocked && round < totalRounds) {
          if (_botMoveScheduledForRound != round) {
            _botMoveScheduledForRound = round;
            final botCash = (data['guestCash'] as num).toDouble();
            // Small delay so it doesn't feel instant/robotic.
            Future.delayed(const Duration(milliseconds: 1200), () {
              if (mounted) state.submitBotMove(botCash);
            });
          }
        }

        MarketScenario scenario = state.scenarios.isNotEmpty
            ? state.scenarios[0]
            : MarketScenario(id: 'default', title: 'No Data', newsHeadline: 'Loading...', newsDescription: '', assetImpact: {}, aiFeedback: '');
        if (round < totalRounds) {
          String scenarioId = scenarioIds[round];
          scenario = state.scenarios.firstWhere((s) => s.id == scenarioId, orElse: () => scenario);
        }

        return MarketTycoonScreen(
          key: ValueKey(round),
          scenario: scenario,
          roundNumber: round,
          totalRounds: totalRounds,
          startingCash: myCash,
          opponentCash: opponentCash,
          opponentLocked: opponentLocked,
          isHost: isHost,
          onLockIn: (cash, investments) {
            state.submitBattleMove(cash, investments, isHost);
          },
          onNextRound: () {
            state.advanceBattleRound(round);
          },
        );
      },
    );
  }
}
