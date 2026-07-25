import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../application/academy_state.dart';
import '../../data/scenario_data.dart';

class MarketTycoonScreen extends StatefulWidget {
  // Multiplayer wiring: when `scenario` is provided, the screen renders a
  // single Firestore-synced round instead of driving its own solo campaign.
  final MarketScenario? scenario;
  final int? roundNumber;
  final int? totalRounds;
  final double? startingCash;
  final double? opponentCash;
  final bool opponentLocked;
  final bool isHost;
  final void Function(double cash, Map<String, double> investments)? onLockIn;
  final VoidCallback? onNextRound;

  const MarketTycoonScreen({
    super.key,
    this.scenario,
    this.roundNumber,
    this.totalRounds,
    this.startingCash,
    this.opponentCash,
    this.opponentLocked = false,
    this.isHost = false,
    this.onLockIn,
    this.onNextRound,
  });

  bool get isMultiplayer => scenario != null;

  @override
  State<MarketTycoonScreen> createState() => _MarketTycoonScreenState();
}

class _MarketTycoonScreenState extends State<MarketTycoonScreen> {
  int _currentLevel = 0;
  double _cash = 10000;
  bool _hasInvested = false;
  List<MarketScenario> _scenarios = [];
  bool _isLoading = true;
  bool _showPopup = false;

  // ✅ NEW: Permanent Portfolio Assets
  final Map<String, double> _investments = {
    "Stocks": 0, // Risky, High Return
    "Bonds": 0,  // Safe, Low Return
    "Gold": 0,   // Safe Haven, Hedge
    "Cash": 0,   // Liquid, No Return
  };

  // Track previous event to show popups
  String _lastEventResult = "";

  @override
  void initState() {
    super.initState();
    if (widget.isMultiplayer) {
      _cash = widget.startingCash ?? 10000;
      _isLoading = false;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final academyState = Provider.of<AcademyState>(context, listen: false);
        setState(() {
          _scenarios = academyState.scenarios;
          _isLoading = false;
        });
      });
    }
  }

  MarketScenario get _scenario {
    if (widget.isMultiplayer) return widget.scenario!;
    if (_currentLevel < _scenarios.length) return _scenarios[_currentLevel];
    return _scenarios.isNotEmpty ? _scenarios.last : MarketScenario(
      id: 'default', title: 'No Data', newsHeadline: 'Loading...', newsDescription: '', assetImpact: {}, aiFeedback: ''
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.simpleCurrency(name: 'USD', decimalDigits: 0);

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    bool isGameOver = widget.isMultiplayer
        ? widget.roundNumber! >= widget.totalRounds!
        : _currentLevel >= _scenarios.length;
    if (isGameOver) {
      return _buildGameOverScreen(currency);
    }

    Widget bodyContent;
    if (!_hasInvested) {
      bodyContent = _buildInvestmentControls();
    } else if (widget.isMultiplayer && !widget.opponentLocked) {
      bodyContent = _buildWaitingForOpponent();
    } else {
      bodyContent = _buildResultView(currency);
    }

    int roundDisplay = widget.isMultiplayer ? widget.roundNumber! : _currentLevel;
    int totalDisplay = widget.isMultiplayer ? widget.totalRounds! : _scenarios.length;

    return Scaffold(
      appBar: AppBar(
        title: Text("Round ${roundDisplay + 1}/$totalDisplay"),
        backgroundColor: Colors.indigo,
        actions: [
          if (widget.isMultiplayer)
            Center(child: Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Text(_hasInvested ? "✅ LOCKED" : "🤔 THINKING", style: TextStyle(color: _hasInvested ? Colors.greenAccent : Colors.amber)),
            ))
          else
            Center(child: Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Text(currency.format(_cash), style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)),
            ))
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (widget.isMultiplayer) ...[
              _buildScoreboard(currency),
              const SizedBox(height: 20),
            ],
            _buildNewsCard(),
            const SizedBox(height: 20),
            bodyContent,
          ],
        ),
      ),
    );
  }

  Widget _buildScoreboard(NumberFormat fmt) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        Column(children: [
          const Text("YOU", style: TextStyle(color: Colors.green)),
          Text(fmt.format(_cash), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ]),
        const Text("VS", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Column(children: [
          const Text("OPPONENT", style: TextStyle(color: Colors.red)),
          Text(fmt.format(widget.opponentCash ?? 0), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ]),
      ],
    );
  }

  Widget _buildWaitingForOpponent() {
    return const Padding(
      padding: EdgeInsets.all(20),
      child: Text("Waiting for opponent...", style: TextStyle(fontSize: 18)),
    );
  }

  Widget _buildNewsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.1),
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.newspaper, color: Colors.redAccent),
              SizedBox(width: 10),
              Text("MARKET NEWS", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))
            ]
          ),
          const SizedBox(height: 10),
          Text(
            _scenario.newsHeadline,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            textAlign: TextAlign.center
          ),
          const SizedBox(height: 10),
          Text(
            _scenario.newsDescription,
            style: const TextStyle(color: Colors.white70),
            textAlign: TextAlign.center
          ),
          // ✅ NEW: Legend for the 4 assets
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              _buildLegendChip("Stocks", "High Risk/High Return", Colors.redAccent),
              _buildLegendChip("Bonds", "Safe/Low Return", Colors.blueAccent),
              _buildLegendChip("Gold", "Safe Haven/Hedge", Colors.amber),
              _buildLegendChip("Cash", "Liquid/No Return", Colors.green),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendChip(String label, String desc, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        "$label ($desc)",
        style: TextStyle(color: color, fontSize: 10),
      ),
    );
  }

  Widget _buildInvestmentControls() {
    double totalAllocated = _investments.values.reduce((a, b) => a + b);
    double remaining = _cash - totalAllocated;

    return Column(
      children: [
        const Text("Allocate your 'Permanent Portfolio':", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        const Text("Stocks (Return) | Bonds (Safety) | Gold (Hedge) | Cash (Liquidity)", style: TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 10),
        ..._investments.keys.map((asset) {
          Color assetColor = asset == "Stocks" ? Colors.redAccent : (asset == "Bonds" ? Colors.blueAccent : (asset == "Gold" ? Colors.amber : Colors.green));
          return Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: assetColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Text(asset, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Text("\$${_investments[asset]!.toInt()}", style: TextStyle(color: assetColor)),
                ],
              ),
              Slider(
                value: _investments[asset]!,
                min: 0,
                max: _cash,
                activeColor: assetColor,
                onChanged: (val) {
                  setState(() {
                    double otherAssetsTotal = totalAllocated - _investments[asset]!;
                    if (val + otherAssetsTotal <= _cash) {
                      _investments[asset] = val;
                    }
                  });
                },
              ),
            ],
          );
        }).toList(),
        const SizedBox(height: 20),
        Text("Remaining Cash: \$${remaining.toInt()}", style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 10),
        Text(
          "Tip: A classic Permanent Portfolio is 25% in each asset.",
          style: TextStyle(color: Colors.amber.withValues(alpha: 0.7), fontSize: 12, fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: totalAllocated > 0 ? () {
              if (widget.isMultiplayer) {
                widget.onLockIn?.call(_cash, _investments);
              }
              setState(() => _hasInvested = true);
            } : null,
            child: const Text("LOCK IN ALLOCATION", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        )
      ],
    );
  }

  Widget _buildResultView(NumberFormat fmt) {
    double totalReturn = 0;
    double totalInvested = _investments.values.reduce((a, b) => a + b);
    double cashLeft = _cash - totalInvested;

    // Show the popup once when results are displayed
    if (!_showPopup && _hasInvested) {
      _showPopup = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showTrianglePopup(fmt);
      });
    }

    return Column(
      children: [
        const Text("MARKET RESULTS", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        ..._investments.keys.map((asset) {
          double invested = _investments[asset]!;
          if (invested == 0) return const SizedBox.shrink();

          // Map the new assets to the scenario's assetImpact (which still has Tech/Airlines/Gold/Oil)
          // We map: Stocks -> Tech (growth), Bonds -> Banks (safe), Gold -> Gold, Cash -> stays cash (no impact)
          String mappedAsset = asset;
          if (asset == "Stocks") mappedAsset = "Tech";
          else if (asset == "Bonds") mappedAsset = "Banks";
          // Gold stays Gold, Cash is not impacted

          double multiplier = 1.0;
          if (asset == "Cash") {
            multiplier = 1.0; // Cash doesn't grow
          } else {
            multiplier = _scenario.assetImpact[mappedAsset] ?? 1.0;
          }

          double newValue = invested * multiplier;
          double profit = newValue - invested;
          totalReturn += profit;

          Color assetColor = asset == "Stocks" ? Colors.redAccent : (asset == "Bonds" ? Colors.blueAccent : (asset == "Gold" ? Colors.amber : Colors.green));

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: assetColor, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(asset, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                Text("${(multiplier * 100 - 100).toStringAsFixed(0)}%",
                  style: TextStyle(color: multiplier >= 1 ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                Text(fmt.format(newValue), style: const TextStyle(color: Colors.white)),
              ],
            ),
          );
        }).toList(),
        if (cashLeft > 0)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(width: 12, height: 12, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    const Text("Cash (Uninvested)", style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const Text("0%", style: TextStyle(color: Colors.grey)),
                Text(fmt.format(cashLeft), style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        const Divider(height: 30),
        // AI Feedback
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: Colors.purple.withOpacity(0.2), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.purple)),
          child: Column(
            children: [
              Row(children: const [Icon(Icons.psychology, color: Colors.purpleAccent), SizedBox(width: 10), Text("AI ANALYSIS", style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold))]),
              const SizedBox(height: 10),
              Text(_scenario.aiFeedback, style: const TextStyle(fontStyle: FontStyle.italic)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (widget.isMultiplayer)
          widget.isHost
            ? SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => widget.onNextRound?.call(),
                  child: const Text("NEXT ROUND ->"),
                ),
              )
            : const Padding(
                padding: EdgeInsets.all(10),
                child: Text("Waiting for host to continue...", style: TextStyle(color: Colors.grey)),
              )
        else
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  // Apply profits to cash
                  _cash = (_cash - totalInvested) + totalInvested + totalReturn;
                  _investments.updateAll((key, val) => 0);
                  _currentLevel++;
                  _hasInvested = false;
                  _showPopup = false;
                });
              },
              child: const Text("NEXT SCENARIO ->"),
            ),
          )
      ],
    );
  }

  // ✅ NEW: Educational Popup
  void _showTrianglePopup(NumberFormat fmt) {
    double totalAllocated = _investments.values.reduce((a, b) => a + b);
    double cashHeld = _cash - totalAllocated;
    double stocksRatio = (_investments["Stocks"] ?? 0) / _cash;
    double cashRatio = cashHeld / _cash;

    String popupMessage = "The market reacted to the news.\n\n";
    popupMessage += "Your current allocation:\n";
    popupMessage += "• Stocks: ${(_investments["Stocks"]! / _cash * 100).toStringAsFixed(0)}%\n";
    popupMessage += "• Bonds: ${(_investments["Bonds"]! / _cash * 100).toStringAsFixed(0)}%\n";
    popupMessage += "• Gold: ${(_investments["Gold"]! / _cash * 100).toStringAsFixed(0)}%\n";
    popupMessage += "• Cash: ${(cashHeld / _cash * 100).toStringAsFixed(0)}%\n\n";

    if (stocksRatio > 0.5) {
      popupMessage += "⚠️ You are heavily in Stocks. You sacrificed safety and liquidity for potential high returns.\n\n";
      popupMessage += "💡 In a crash, this portfolio would suffer. Consider increasing Cash or Bonds.";
    } else if (cashRatio > 0.5) {
      popupMessage += "🛡️ You held mostly Cash. You sacrificed potential returns for safety and liquidity.\n\n";
      popupMessage += "💡 You're safe from crashes, but inflation will eat your purchasing power.";
    } else if ((_investments["Gold"]! / _cash) > 0.3) {
      popupMessage += "🔶 You hold significant Gold. It acts as a hedge against uncertainty.\n\n";
      popupMessage += "💡 Gold doesn't produce income, but protects against inflation and crises.";
    } else {
      popupMessage += "⚖️ You have a balanced 'Permanent Portfolio' approach.\n\n";
      popupMessage += "💡 This allocation aims to perform well in any economic environment (Growth, Inflation, Deflation, Crisis).";
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.amber, width: 2)),
        title: Row(
          children: const [
            Icon(Icons.lightbulb_outline, color: Colors.amber),
            SizedBox(width: 10),
            Text("Triangle Tradeoff", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              popupMessage,
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
              ),
              child: const Text(
                "🔺 The 'Impossible Trinity': You cannot maximize Return, Safety, and Liquidity all at once. You must trade off one to get more of another.",
                style: TextStyle(color: Colors.blueAccent, fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
              child: const Text("GOT IT!"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameOverScreen(NumberFormat fmt) {
    bool isWin = widget.isMultiplayer ? _cash > (widget.opponentCash ?? 0) : _cash > 12000;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isWin ? Icons.emoji_events : Icons.sentiment_dissatisfied, size: 80, color: isWin ? Colors.amber : Colors.grey),
            const SizedBox(height: 20),
            Text(
              widget.isMultiplayer
                ? (isWin ? "VICTORY!" : "DEFEAT")
                : (isWin ? "YOU ARE A TYCOON!" : "BANKRUPT..."),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text("Final Capital: ${fmt.format(_cash)}"),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: Text(widget.isMultiplayer ? "LEAVE" : "Back to Academy")
            )
          ],
        ),
      ),
    );
  }
}
