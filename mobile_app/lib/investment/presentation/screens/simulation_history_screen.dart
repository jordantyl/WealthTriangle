import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../../firestore/constants/firestore_constants.dart';

class SimulationHistoryScreen extends StatelessWidget {
  const SimulationHistoryScreen({super.key});

  // Same rule the backend uses (app.py): .KL tickers are Malaysia (KLCI) and
  // priced in MYR, everything else (e.g. US/S&P500 tickers) is USD.
  static String _currencyCodeForTicker(String ticker) {
    return ticker.toUpperCase().endsWith('.KL') ? 'MYR' : 'USD';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text("My Simulation History")),
      body: user == null
          ? const Center(child: Text("Please log in to view history."))
          : StreamBuilder<QuerySnapshot>(
              // ✅ FIXED: now uses the same collection + field names that
              // TimeMachineScreen writes and the CSV export reads.
              stream: FirebaseFirestore.instance
                  .collection(FirestoreConstants.usersCollection)
                  .doc(user.uid)
                  .collection(FirestoreConstants.simulationHistorySubCollection)
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                        "No history found. Run a Time Machine simulation first!",
                        style: TextStyle(color: Colors.grey)),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(15),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    var data = snapshot.data!.docs[index].data()
                        as Map<String, dynamic>;

                    final double initial =
                        (data['initialCapital'] as num?)?.toDouble() ?? 0;
                    // dividendsReceived is 0 for entries saved before this
                    // field existed — matches the live result screen's
                    // total (finalCapital + dividendsReceived), so a run
                    // shown as a win/loss live can't flip when viewed here.
                    final double dividendsReceived =
                        (data['dividendsReceived'] as num?)?.toDouble() ?? 0;
                    final double finalCap =
                        ((data['finalCapital'] as num?)?.toDouble() ?? 0) +
                            dividendsReceived;
                    final bool isWin = finalCap >= initial;
                    final currencyFormat = NumberFormat.simpleCurrency(
                        name: _currencyCodeForTicker(
                            (data['stockTicker'] ?? '').toString()));

                    return Card(
                      color: const Color(0xFF2D2D44),
                      margin: const EdgeInsets.only(bottom: 15),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(15),
                        leading: CircleAvatar(
                          backgroundColor: (isWin
                                  ? Colors.greenAccent
                                  : Colors.redAccent)
                              .withOpacity(0.2),
                          child: Text(
                            () {
                              final t = (data['stockTicker'] ?? '?').toString();
                              return t.isEmpty ? '?' : t.substring(0, 1);
                            }(),
                            style: TextStyle(
                                color: isWin
                                    ? Colors.greenAccent
                                    : Colors.redAccent),
                          ),
                        ),
                        title: Text(
                          "${data['stockTicker'] ?? 'UNKNOWN'}  (${data['startDate'] ?? ''} → ${data['endDate'] ?? ''})",
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 14),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 5),
                            Text(
                              "${currencyFormat.format(initial)} → ${currencyFormat.format(finalCap)}",
                              style: TextStyle(
                                  color: isWin
                                      ? Colors.greenAccent
                                      : Colors.redAccent,
                                  fontWeight: FontWeight.bold),
                            ),
                            Text(
                                "CAGR: ${data['cagr'] ?? 0}%  |  Max DD: ${data['maxDrawdown'] ?? 0}%",
                                style:
                                    const TextStyle(color: Colors.orangeAccent)),
                            if (data['liquidityLabel'] != null)
                              Text("Liquidity: ${data['liquidityLabel']}",
                                  style:
                                      const TextStyle(color: Colors.cyanAccent)),
                          ],
                        ),
                        trailing: data['createdAt'] != null
                            ? Text(
                                DateFormat('MMM dd').format(
                                    (data['createdAt'] as Timestamp)
                                        .toDate()
                                        .toLocal()),
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 12))
                            : const SizedBox.shrink(),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}