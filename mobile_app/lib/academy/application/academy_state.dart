import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../data/scenario_data.dart';
import '../domain/lesson.dart';
import '../../shared/backend_headers.dart';

import 'dart:convert';
import 'dart:math';

class AcademyState extends ChangeNotifier {
  // ==========================================
  // 1. DATA HOLDERS
  // ==========================================
  String _riskProfile = "Conservative";
  String get riskProfile => _riskProfile;

  int _level = 1;
  int _xp = 0;
  double _virtualCash = 10000;
  Set<String> _completedLessonIds = {};
  Set<String> get completedLessonIds => _completedLessonIds;

  List<MarketScenario> _scenarios = [];
  List<Map<String, dynamic>> _quizzes = [];
  List<Map<String, dynamic>> _flashScenarios = [];
  List<Lesson> _allLessons = [];

  List<TradeItem> _allTradeItems = [];
  List<TradeEvent> _tradeEvents = [];

  List<TradeItem> _marketItems = [];
  Map<String, int> _inventory = {};
  Map<String, double> _inventoryAvgCost = {};
  // Every item's price the last day it appeared in the 5-of-12 daily
  // rotation (see nextMerchantTurn) — lets net-worth valuation price an
  // owned item on a day it's NOT in today's rotation, instead of treating
  // it as worth $0 just because it isn't for sale today.
  Map<String, double> _lastKnownPrices = {};
  double _merchantCash = 5000;
  int _currentTurn = 1;
  int _maxTurns = 20;
  TradeEvent? _activeEvent;
  TradeEvent? _upcomingRumor;

  int _lastRobberyTurn = -1;
  int get lastRobberyTurn => _lastRobberyTurn;
  void setRobberyAcknowledged(int turn) => _lastRobberyTurn = turn;

  int get level => _level;
  int get xp => _xp;
  double get virtualCash => _virtualCash;
  List<Lesson> get allLessons => _allLessons;

  List<MarketScenario> get scenarios {
    var list = List<MarketScenario>.from(_scenarios);
    list.shuffle();
    return list.take(10).toList();
  }

  List<Map<String, dynamic>> get quizzes => _quizzes;
  List<Map<String, dynamic>> get flashScenarios => _flashScenarios;

  List<TradeItem> get marketItems => _marketItems;
  Map<String, double> get lastKnownPrices => _lastKnownPrices;
  TradeEvent? get activeEvent => _activeEvent;
  TradeEvent? get upcomingRumor => _upcomingRumor;
  Map<String, int> get inventory => _inventory;
  Map<String, double> get inventoryAvgCost => _inventoryAvgCost;
  double get merchantCash => _merchantCash;
  int get currentTurn => _currentTurn;
  int get maxTurns => _maxTurns;

  String? get currentBattleId => _currentBattleId;
  FirebaseAuth get auth => _auth;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Gates AcademyScreen's "Update Database" button — was showing to every
  // user before, only failing server-side on tap. Mirrors the backend's own
  // _require_admin_user() check (via /api/admin/status) so the two can never
  // drift apart; defaults to false until that check resolves.
  bool _isAdmin = false;
  bool get isAdmin => _isAdmin;

  AcademyState() {
    _loadUserData();
    fetchGameContent();
    seedLessons();
    _checkAdminStatus();
  }

  /// Public re-check, for callers (e.g. the web admin app) constructed
  /// before Firebase Auth resolves the signed-in user — the constructor's
  /// own _checkAdminStatus() call would otherwise run with no ID token yet
  /// and never automatically retry once login completes.
  Future<void> refreshAdminStatus() => _checkAdminStatus();

  Future<void> _checkAdminStatus() async {
    try {
      // defaultBackendBaseUrl already covers web vs native and the full
      // dart-define -> .env -> localhost fallback chain; checking dotenv
      // directly here (as this used to) bypassed the dart-define check on
      // native and could silently resolve to a stale local .env value.
      final baseUrl = defaultBackendBaseUrl;
      final headers = await authedBackendHeaders();
      final response = await http.get(Uri.parse('$baseUrl/api/admin/status'), headers: headers);
      if (response.statusCode == 200) {
        _isAdmin = json.decode(response.body)['isAdmin'] == true;
        notifyListeners();
      }
    } catch (e) {
      print("Error checking admin status: $e");
    }
  }

  int _maxInventorySlots = 20;
  int get totalInventoryCount =>
      _inventory.values.fold(0, (sum, qty) => sum + qty);
  int get maxInventorySlots => _maxInventorySlots;

  // ==========================================
  // 2. FETCH DATA
  // ==========================================
  Future<void> fetchGameContent() async {
    try {
      var scnSnapshot =
          await _db.collection('academy_scenarios').orderBy('id').get();
      _scenarios = scnSnapshot.docs.map((doc) {
        var data = doc.data();
        return MarketScenario(
          id: data['id'],
          title: data['title'] ?? 'Unknown',
          newsHeadline: data['newsHeadline'] ?? '',
          newsDescription: data['newsDescription'] ?? '',
          assetImpact: Map<String, double>.from(
              (data['assetImpact'] as Map<String, dynamic>)
                  .map((k, v) => MapEntry(k, (v as num).toDouble()))),
          aiFeedback: data['aiFeedback'] ?? '',
        );
      }).toList();

      var quizSnapshot = await _db.collection('academy_quizzes').get();
      _quizzes = quizSnapshot.docs.map((doc) => doc.data()).toList();

      var flashSnapshot = await _db.collection('academy_flash').get();
      _flashScenarios = flashSnapshot.docs.map((doc) => doc.data()).toList();

      var itemsSnapshot = await _db.collection('academy_trade_items').get();
      _allTradeItems = itemsSnapshot.docs.map((doc) {
        var data = doc.data();
        return TradeItem(
          id: data['id'],
          name: data['name'],
          category: data['category'],
          basePrice: (data['basePrice'] as num).toDouble(),
        );
      }).toList();

      var eventsSnapshot = await _db.collection('academy_trade_events').get();
      _tradeEvents = eventsSnapshot.docs.map((doc) {
        var data = doc.data();
        return TradeEvent(
          text: data['text'],
          type: data['type'],
          impact: Map<String, double>.from((data['impact'] ?? {})
              .map((k, v) => MapEntry(k, (v as num).toDouble()))),
          isGlobal: data['isGlobal'] ?? false,
          turnsDelay: data['turnsDelay'] ?? 0,
        );
      }).toList();

      notifyListeners();
    } catch (e) {
      print("❌ CRITICAL ERROR FETCHING DATA: $e");
    }
  }

  // ==========================================
  // 3. GAME LOGIC
  // ==========================================
  List<Map<String, dynamic>> getQuestionsForUser() {
    if (_quizzes.isEmpty) return [];
    var availableQuestions = _quizzes.where((q) {
      int requiredLevel = q['minLevel'] ?? 1;
      return requiredLevel <= _level;
    }).toList();
    availableQuestions.shuffle();
    return availableQuestions.take(10).toList();
  }

  List<Map<String, dynamic>> getFlashScenariosForUser() {
    if (_flashScenarios.isEmpty) return [];
    var perfectMatch = _flashScenarios.where((s) {
      int sLevel = s['minLevel'] ?? 1;
      return sLevel == _level;
    }).toList();

    if (perfectMatch.length < 5) {
      var backup = _flashScenarios.where((s) {
        int sLevel = s['minLevel'] ?? 1;
        return sLevel == _level - 1;
      }).toList();
      perfectMatch.addAll(backup);
    }
    perfectMatch.shuffle();
    return perfectMatch;
  }

  // ==========================================
  // 4. MERCHANT GAME
  // ==========================================
  void startMerchantGame() {
    _merchantCash = 5000;
    _inventory.clear();
    _inventoryAvgCost.clear();
    _lastKnownPrices.clear();
    _currentTurn = 0;
    _upcomingRumor = null;
    _lastRobberyTurn = -1;
    nextMerchantTurn();
  }

  void nextMerchantTurn() {
    if (_currentTurn >= _maxTurns) return;

    _currentTurn++;

    if (_upcomingRumor != null) {
      _activeEvent = _upcomingRumor;
      _upcomingRumor = null;
    } else {
      bool triggerBlackSwan = Random().nextDouble() < 0.10;
      var validEvents = _tradeEvents.where((e) {
        bool isSwan = e.type.contains('black_swan');
        return triggerBlackSwan ? isSwan : !isSwan;
      }).toList();

      if (validEvents.isNotEmpty) {
        _activeEvent = validEvents[Random().nextInt(validEvents.length)];
      }
    }

    if (Random().nextDouble() < 0.30 && _currentTurn < _maxTurns) {
      var futureEvents =
          _tradeEvents.where((e) => !e.type.contains('black_swan')).toList();
      if (futureEvents.isNotEmpty) {
        _upcomingRumor = futureEvents[Random().nextInt(futureEvents.length)];
      }
    }

    if (_activeEvent?.type == 'black_swan_robbery') {
      _merchantCash = 0;
    }

    List<TradeItem> todaysMarket = [];
    if (_allTradeItems.isNotEmpty) {
      List<TradeItem> pool = List.from(_allTradeItems)..shuffle();
      pool = pool.take(5).toList();

      for (var item in pool) {
        double price = item.basePrice;
        double noise = 0.8 + (Random().nextDouble() * 0.4);
        price *= noise;

        if (_activeEvent != null) {
          double multiplier = 1.0;
          if (_activeEvent!.isGlobal) {
            multiplier = _activeEvent!.impact['all'] ?? 1.0;
          } else if (_activeEvent!.impact.containsKey(item.category)) {
            multiplier = _activeEvent!.impact[item.category]!;
          }
          price *= multiplier;
        }
        _lastKnownPrices[item.id] = price;
        todaysMarket.add(item.withPrice(price));
      }
    }

    _marketItems = todaysMarket;
    notifyListeners();
  }

  void buyItem(TradeItem item) {
    if (_merchantCash < item.currentPrice) return;
    if (totalInventoryCount >= _maxInventorySlots) return;

    int oldQty = _inventory[item.id] ?? 0;
    double oldAvg = _inventoryAvgCost[item.id] ?? 0;
    // Weighted average cost — same formula PortfolioState.buyStock() uses,
    // so "Avg" here means the same thing it does in the Investment module.
    _inventoryAvgCost[item.id] =
        ((oldAvg * oldQty) + item.currentPrice) / (oldQty + 1);

    _merchantCash -= item.currentPrice;
    _inventory[item.id] = oldQty + 1;
    notifyListeners();
  }

  void sellItem(TradeItem item) {
    if ((_inventory[item.id] ?? 0) > 0) {
      _merchantCash += item.currentPrice;
      _inventory[item.id] = (_inventory[item.id]!) - 1;
      if (_inventory[item.id] == 0) {
        _inventory.remove(item.id);
        _inventoryAvgCost.remove(item.id);
      }
      notifyListeners();
    }
  }

  // ==========================================
  // 5. USER PROGRESS
  // ==========================================
  Future<void> _loadUserData() async {
    User? user = _auth.currentUser;
    if (user == null) return;
    try {
      DocumentSnapshot doc = await _db
          .collection('users')
          .doc(user.uid)
          .collection('academy')
          .doc('stats')
          .get();
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        _level = data['level'] ?? 1;
        _xp = data['xp'] ?? 0;
        _virtualCash = (data['virtualCash'] ?? 10000).toDouble();
        _completedLessonIds = Set<String>.from(data['completedLessons'] ?? []);
      }
      notifyListeners();
    } catch (e) {
      print("Error loading stats: $e");
    }
  }

  /// Marks a lesson complete, awards its XP, and persists both — replaces
  /// the old learning_path_screen.dart behavior where completion lived only
  /// in local widget state (reset on restart) and XP was never actually added.
  Future<void> completeLesson(Lesson lesson) async {
    if (_completedLessonIds.contains(lesson.id)) return;
    _completedLessonIds.add(lesson.id);
    _xp += lesson.xpReward;
    if (_xp >= _level * 1000) _level++;
    await _saveStats();
  }

  Future<void> saveTycoonResult(double finalCash) async {
    double profit = finalCash - 10000;
    int xpGained = profit > 0 ? (profit / 10).toInt() : 10;
    _virtualCash = finalCash;
    _xp += xpGained;
    if (_xp >= _level * 1000) _level++;
    await _saveStats();
  }

  Future<void> saveQuizResult(int finalScore) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String determinedProfile = 'Balanced';
    if (finalScore >= 400) {
      determinedProfile = 'Aggressive';
    } else if (finalScore <= 200) {
      determinedProfile = 'Conservative';
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'RiskProfile': determinedProfile,
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('ACADEMYPROGRESS')
          .doc('risk_quiz')
          .set({
        'ModuleID': 'risk_quiz',
        'CompletionStatus': 'Completed',
        'BadgesEarned': ['Risk Analyst'],
        'Timestamp': FieldValue.serverTimestamp(),
      });

      // ✅ NEW: also record it in the badges collection so it shows on
      // the Badges screen (BadgeService can't be used here — no context —
      // so we write the same document shape directly).
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('badges')
          .doc('risk_analyst')
          .set({
        'earnedAt': FieldValue.serverTimestamp(),
        'title': 'Risk Analyst',
      });

      // XP lives in one place (academy/stats, via _saveStats) — quiz XP
      // used to also increment a separate 'TotalXP' field on the users doc,
      // which fetchUserData() read independently. Whichever fetch resolved
      // last silently overwrote the other, so XP from lessons/quizzes could
      // appear to vanish. _saveStats() is now the single source of truth.
      _xp += finalScore;
      if (_xp >= _level * 1000) _level++;
      _riskProfile = determinedProfile;
      await _saveStats();
    } catch (e) {
      print("Error saving quiz: $e");
    }
  }

  Future<void> _saveStats() async {
    User? user = _auth.currentUser;
    if (user == null) return;
    await _db.collection('users').doc(user.uid).collection('academy').doc('stats').set({
      'level': _level,
      'xp': _xp,
      'virtualCash': _virtualCash,
      'completedLessons': _completedLessonIds.toList(),
      'lastPlayed': DateTime.now(),
    });
    notifyListeners();
  }

  void setMerchantMode(String mode) {
    if (mode == 'endless') {
      _maxTurns = 9999;
      _maxInventorySlots = 50;
    } else {
      _maxTurns = 20;
      _maxInventorySlots = 20;
    }
    notifyListeners();
  }

  // ==========================================
  // 6. SEED DATABASE
  // These are global, app-owned reference/content collections (game
  // scenarios, quiz questions, trade items) — not per-user data. Firestore
  // rules block clients from writing them directly (so no signed-in user
  // can overwrite shared content), so this sends the same content to a
  // backend endpoint instead, which writes it with the Firebase Admin SDK.
  // Every doc uses a deterministic ID, so this always upserts rather than
  // only seeding when a collection is empty — otherwise, once a collection
  // had *any* docs, adding new local content (like extra scenarios) would
  // never reach Firestore, since an "only if empty" check would skip it
  // forever. Upserting is safe here because nothing else writes to these
  // collections and the IDs are stable.
  // ==========================================
  /// [only] restricts the push to a subset of collection names (e.g. just
  /// 'academy_quizzes') instead of overwriting all five at once — lets the
  /// admin panel push one piece of content at a time. Omit for the original
  /// "seed everything" behavior.
  Future<void> seedDatabase({Set<String>? only}) async {
    final Map<String, Map<String, dynamic>> collections = {};

    // ---- academy_scenarios (from scenario_data.dart, doc ID = scn id) ----
    collections['academy_scenarios'] = {
      for (final s in gameScenarios)
        s.id: {
          'id': s.id,
          'title': s.title,
          'newsHeadline': s.newsHeadline,
          'newsDescription': s.newsDescription,
          'assetImpact': s.assetImpact,
          'aiFeedback': s.aiFeedback,
        },
    };

    // ---- academy_quizzes ----
    {
      final quizzes = <Map<String, dynamic>>[
        {
          'question': 'What is a Fixed Deposit (FD)?',
          'options': ['Free Money', 'Low-risk bank investment', 'Stock Market', 'Gambling'],
          'answer': 1,
          'explanation': 'FDs give guaranteed returns.',
          'minLevel': 1,
        },
        {
          'question': 'Bear Market means:',
          'options': ['Prices Up', 'Prices Down', 'Zoo Market', 'Stable'],
          'answer': 1,
          'explanation': 'Prices falling >20%.',
          'minLevel': 1,
        },
        {
          'question': 'Which is safest?',
          'options': ['Crypto', 'Stocks', 'Government Bonds', 'Startups'],
          'answer': 2,
          'explanation': 'Gov bonds are backed by the country.',
          'minLevel': 1,
        },
        {
          'question': 'Diversification means:',
          'options': ['Buying 1 stock', 'Spreading risk', 'Selling all', 'Saving cash'],
          'answer': 1,
          'explanation': "Don't put all eggs in one basket.",
          'minLevel': 2,
        },
        {
          'question': 'What is an ETF?',
          'options': ['Electric Fund', 'Exchange Traded Fund', 'Extra Tax', 'Energy Fund'],
          'answer': 1,
          'explanation': 'A basket of stocks trading as one.',
          'minLevel': 2,
        },
        {
          'question': 'Short Selling is:',
          'options': ['Selling fast', 'Betting price drops', 'Buying low', 'Holding long'],
          'answer': 1,
          'explanation': 'Selling borrowed assets to buy back lower.',
          'minLevel': 3,
        },
        {
          'question': 'Options & Futures are:',
          'options': ['Derivatives', 'Safe Assets', 'Cash', 'Bonds'],
          'answer': 0,
          'explanation': 'They derive value from underlying assets.',
          'minLevel': 3,
        },
      ];
      collections['academy_quizzes'] = {
        for (var i = 0; i < quizzes.length; i++)
          'quiz_${(i + 1).toString().padLeft(2, '0')}': quizzes[i],
      };
    }

    // ---- academy_flash ----
    {
      final flash = <Map<String, dynamic>>[
        {'news': 'Company Reports Record Profits', 'shouldBuy': true, 'type': 'company', 'minLevel': 1},
        {'news': 'CEO Resigns amid Scandal', 'shouldBuy': false, 'type': 'company', 'minLevel': 1},
        {'news': 'Factory Fire Halts Production', 'shouldBuy': false, 'type': 'company', 'minLevel': 1},
        {'news': 'Product Launch is a Huge Success', 'shouldBuy': true, 'type': 'tech', 'minLevel': 1},
        {'news': 'Major Lawsuit Filed Against Firm', 'shouldBuy': false, 'type': 'legal', 'minLevel': 2},
        {'news': "Analyst Upgrades Stock to 'Buy'", 'shouldBuy': true, 'type': 'market', 'minLevel': 2},
        {'news': 'Government Cuts Corporate Tax', 'shouldBuy': true, 'type': 'policy', 'minLevel': 2},
        {'news': 'Oil Prices Spike 10%', 'shouldBuy': false, 'type': 'energy', 'minLevel': 3},
        {'news': 'Inflation Data Lower Than Expected', 'shouldBuy': true, 'type': 'market', 'minLevel': 3},
        {'news': 'Fed Hikes Interest Rates by 0.75%', 'shouldBuy': false, 'type': 'policy', 'minLevel': 3},
      ];
      collections['academy_flash'] = {
        for (var i = 0; i < flash.length; i++)
          'flash_${(i + 1).toString().padLeft(2, '0')}': flash[i],
      };
    }

    // ---- academy_trade_items (doc ID = item id) ----
    {
      final items = <Map<String, dynamic>>[
        {'id': 't_01', 'name': 'Microchips', 'category': 'tech', 'basePrice': 500},
        {'id': 't_02', 'name': 'Graphics Cards', 'category': 'tech', 'basePrice': 800},
        {'id': 't_03', 'name': 'Smartphones', 'category': 'tech', 'basePrice': 1000},
        {'id': 't_04', 'name': 'Wheat', 'category': 'food', 'basePrice': 50},
        {'id': 't_05', 'name': 'Coffee Beans', 'category': 'food', 'basePrice': 120},
        {'id': 't_06', 'name': 'Rice', 'category': 'food', 'basePrice': 40},
        {'id': 't_07', 'name': 'Crude Oil', 'category': 'resource', 'basePrice': 80},
        {'id': 't_08', 'name': 'Steel Beams', 'category': 'resource', 'basePrice': 200},
        {'id': 't_09', 'name': 'Gold Bar', 'category': 'luxury', 'basePrice': 2000},
        {'id': 't_10', 'name': 'Diamond', 'category': 'luxury', 'basePrice': 5000},
        {'id': 't_11', 'name': 'Rare Earth', 'category': 'resource', 'basePrice': 300},
        {'id': 't_12', 'name': 'Luxury Watch', 'category': 'luxury', 'basePrice': 1500},
      ];
      collections['academy_trade_items'] = {
        for (final item in items) item['id'] as String: item,
      };
    }

    // ---- academy_trade_events ----
    {
      final events = <Map<String, dynamic>>[
        {'text': 'Peace Treaty signed! Resource demand drops.', 'type': 'price_change', 'impact': {'resource': 0.7}, 'isGlobal': false, 'turnsDelay': 0},
        {'text': 'Severe drought hits agricultural belts.', 'type': 'price_change', 'impact': {'food': 2.5}, 'isGlobal': false, 'turnsDelay': 0},
        {'text': 'New massive diamond mine discovered.', 'type': 'price_change', 'impact': {'luxury': 0.4}, 'isGlobal': false, 'turnsDelay': 0},
        {'text': 'Tech Giant releases revolutionary AI chip.', 'type': 'price_change', 'impact': {'tech': 1.5}, 'isGlobal': false, 'turnsDelay': 0},
        {'text': 'HYPERINFLATION! Currency value collapses.', 'type': 'black_swan_inflation', 'impact': {'all': 3}, 'isGlobal': true, 'turnsDelay': 0},
        {'text': 'BANDITS! You were robbed on the trade route.', 'type': 'black_swan_robbery', 'impact': {}, 'isGlobal': true, 'turnsDelay': 0},
      ];
      collections['academy_trade_events'] = {
        for (var i = 0; i < events.length; i++)
          'evt_${(i + 1).toString().padLeft(2, '0')}': events[i],
      };
    }

    final scopedCollections = only == null
        ? collections
        : (Map<String, Map<String, dynamic>>.from(collections)
          ..removeWhere((key, _) => !only.contains(key)));

    final baseUrl = defaultBackendBaseUrl;
    final headers = await authedBackendHeaders({'Content-Type': 'application/json'});
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/seed'),
      headers: headers,
      body: json.encode({'collections': scopedCollections}),
    );
    if (response.statusCode != 200) {
      throw Exception('Seed failed (${response.statusCode}): ${response.body}');
    }

    // Reload content so the games work immediately after seeding
    await fetchGameContent();
  }

  // ==========================================
  // 7. ONLINE BATTLE
  // ==========================================
  String? _currentBattleId;
  Stream<DocumentSnapshot>? _battleStream;
  Stream<DocumentSnapshot>? get battleStream => _battleStream;

  Future<String> createBattleRoom(String playerName) async {
    User? user = _auth.currentUser;
    if (user == null) return "error";

    var pool = List<MarketScenario>.from(_scenarios)..shuffle();
    List<String> selectedIds = pool.take(5).map((s) => s.id).toList();

    DocumentReference ref = await _db.collection('tycoon_battles').add({
      "hostId": user.uid,
      "hostName": playerName,
      "guestId": "",
      "guestName": "Waiting...",
      "scenarioIds": selectedIds,
      "currentRound": 0,
      "status": "waiting",
      "hostCash": 10000.0,
      "guestCash": 10000.0,
      "hostLocked": false,
      "guestLocked": false,
      "hostInvestments": {},
      "guestInvestments": {},
      "createdAt": FieldValue.serverTimestamp(),
    });

    _currentBattleId = ref.id;
    _battleStream = ref.snapshots();
    notifyListeners();
    return ref.id;
  }

  Future<bool> joinBattleRoom(String roomId, String playerName) async {
    User? user = _auth.currentUser;
    if (user == null) return false;

    try {
      DocumentReference ref = _db.collection('tycoon_battles').doc(roomId);
      var doc = await ref.get();
      if (!doc.exists) return false;
      var data = doc.data() as Map<String, dynamic>;
      if (data['status'] != 'waiting') return false;

      await ref.update({
        "guestId": user.uid,
        "guestName": playerName,
        "status": "active",
      });

      _currentBattleId = roomId;
      _battleStream = ref.snapshots();
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> submitBattleMove(
      double currentCash, Map<String, double> investments, bool isHost) async {
    if (_currentBattleId == null) return;
    await _db.collection('tycoon_battles').doc(_currentBattleId).update({
      isHost ? "hostCash" : "guestCash": currentCash,
      isHost ? "hostInvestments" : "guestInvestments": investments,
      isHost ? "hostLocked" : "guestLocked": true,
    });
  }

  // ==========================================
  // BOT OPPONENT — for when no real player joins a waiting room in time.
  // The bot occupies the guest slot ("guestId": "BOT"); since there's no
  // second connected client to play it, the host's own device simulates
  // the bot's move after the host locks in each round (see submitBotMove,
  // called from TycoonBattleScreen).
  // ==========================================
  Future<void> addBotOpponent() async {
    if (_currentBattleId == null) return;
    await _db.collection('tycoon_battles').doc(_currentBattleId).update({
      "guestId": "BOT",
      "guestName": "Trading Bot 🤖",
      "status": "active",
    });
  }

  Map<String, double> _generateBotAllocation(double cash) {
    final rnd = Random();
    // Random-ish but never a single-asset all-in — keeps the bot's play
    // varied round to round instead of always doing the same thing.
    final weights = List.generate(4, (_) => 0.15 + rnd.nextDouble());
    final total = weights.reduce((a, b) => a + b);
    const keys = ['Stocks', 'Bonds', 'Gold', 'Cash'];
    final alloc = <String, double>{};
    double allocated = 0;
    for (var i = 0; i < keys.length; i++) {
      double amount = (cash * weights[i] / total).roundToDouble();
      if (i == keys.length - 1) amount = cash - allocated; // absorb rounding
      alloc[keys[i]] = amount;
      allocated += amount;
    }
    return alloc;
  }

  Future<void> submitBotMove(double botCash) async {
    await submitBattleMove(botCash, _generateBotAllocation(botCash), false);
  }

  Future<void> advanceBattleRound(int currentRound) async {
    if (_currentBattleId == null) return;
    final ref = _db.collection('tycoon_battles').doc(_currentBattleId);

    // Only the host's client calls this (TycoonBattleScreen/MarketTycoonScreen
    // only show the "NEXT ROUND" button to the host), but nothing previously
    // stopped a fast double-tap from firing this twice before the first
    // call's Firestore write landed and the UI rebuilt — each call re-read
    // the same pre-advance cash/round and computed the round's profit/loss
    // from it independently, so a double-tap silently double-applied that
    // round's result. Wrapping the read+write in a transaction and checking
    // currentRound still matches what's stored makes a stale/duplicate call
    // a no-op instead.
    await _db.runTransaction((transaction) async {
      final doc = await transaction.get(ref);
      if (!doc.exists) return;

      var data = doc.data() as Map<String, dynamic>;
      if (data['currentRound'] != currentRound) {
        // Already advanced by an earlier (still in-flight or completed)
        // call — nothing left to do.
        return;
      }

      List<dynamic> scenarioIds = data['scenarioIds'];
      if (currentRound >= scenarioIds.length) return;

      String scenarioId = scenarioIds[currentRound];
      var scenario = _scenarios.firstWhere((s) => s.id == scenarioId,
          orElse: () => _scenarios[0]);

      Map<String, dynamic> hostInv = data['hostInvestments'] ?? {};
      double hostNewCash = (data['hostCash'] as num).toDouble();
      hostInv.forEach((asset, amount) {
        double multiplier = scenario.impactFor(asset);
        hostNewCash += (amount * multiplier) - amount;
      });

      Map<String, dynamic> guestInv = data['guestInvestments'] ?? {};
      double guestNewCash = (data['guestCash'] as num).toDouble();
      guestInv.forEach((asset, amount) {
        double multiplier = scenario.impactFor(asset);
        guestNewCash += (amount * multiplier) - amount;
      });

      transaction.update(ref, {
        "currentRound": currentRound + 1,
        "hostLocked": false,
        "guestLocked": false,
        "hostCash": hostNewCash,
        "guestCash": guestNewCash,
        "hostInvestments": {},
        "guestInvestments": {},
      });
    });
  }

  Future<String> findRandomMatch(String playerName) async {
    User? user = _auth.currentUser;
    if (user == null) return "error";

    try {
      var snapshot = await _db
          .collection('tycoon_battles')
          .where('status', isEqualTo: 'waiting')
          .get();

      String? validRoomId;
      for (var doc in snapshot.docs) {
        var data = doc.data();
        String guestId = data['guestId'] ?? "";
        String hostId = data['hostId'] ?? "";
        if (guestId.isEmpty && hostId != user.uid) {
          validRoomId = doc.id;
          break;
        }
      }

      if (validRoomId != null) {
        await joinBattleRoom(validRoomId, playerName);
        return validRoomId;
      } else {
        return await createBattleRoom(playerName);
      }
    } catch (e) {
      print("Error finding match: $e");
      return "error";
    }
  }

  Future<void> fetchUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      var doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        // XP comes solely from academy/stats (see _loadUserData/_saveStats) —
        // this doc's 'RiskProfile' is still the right source for risk profile.
        // Older accounts may still have 'Moderate' stored from before the
        // report-aligned rename to 'Balanced' — normalize on read so their
        // tailored lessons/coloring keep matching without a re-quiz.
        final rawProfile = data['RiskProfile'] ?? 'Conservative';
        _riskProfile = rawProfile == 'Moderate' ? 'Balanced' : rawProfile;
        notifyListeners();
      }
    } catch (e) {
      print("Error fetching Academy data: $e");
    }
  }

  List<Lesson> getPersonalizedLessons() {
    var matched = _allLessons
        .where((l) =>
            l.riskProfileMatch == _riskProfile || l.riskProfileMatch == 'All')
        .toList();

    matched.sort((a, b) {
      int rank(String d) {
        if (d == 'Beginner') return 0;
        if (d == 'Intermediate') return 1;
        return 2;
      }

      return rank(a.difficulty).compareTo(rank(b.difficulty));
    });

    return matched;
  }

  void seedLessons() {
    _allLessons = [
      Lesson(
        id: 'lesson_1',
        title: 'What is the Stock Market?',
        description: 'Learn the basics of stocks, exchanges, and how prices move.',
        difficulty: 'Beginner',
        xpReward: 50,
        riskProfileMatch: 'All',
        content: const [
          LessonSection(
            heading: 'Owning a piece of a company',
            body: 'A stock is a small ownership slice of a real company. When you '
                'buy a share of a business listed on an exchange, you own a tiny '
                'fraction of its assets and future profits. The exchange is just '
                'the marketplace — like Bursa Malaysia or the NYSE/Nasdaq — where '
                'buyers and sellers agree on a price in real time.',
          ),
          LessonSection(
            heading: 'Why prices move',
            body: 'A price moves when the balance between buyers and sellers '
                'shifts — driven by earnings reports, interest rate decisions, '
                'company news, or simply how optimistic or fearful investors feel '
                'that day. No single force controls it; it is the sum of millions '
                'of individual buy/sell decisions.',
          ),
          LessonSection(
            heading: 'Two markets, two currencies',
            body: 'This app tracks both Malaysian stocks (tickers ending in .KL, '
                'part of the KLCI, priced in RM) and US stocks (part of the '
                'S&P 500/Nasdaq, priced in USD). They also settle differently — '
                'Malaysian trades take T+2 (2 business days) to settle, US trades '
                'T+1 — which the Stock Dashboard shows per ticker.',
          ),
          LessonSection(
            heading: 'See it live',
            body: 'Open the Stock Dashboard and search any ticker (try a .KL '
                'stock and a US one back to back). You will see its live price, '
                'RSI, MACD, and a 1-year Monte Carlo forecast — all built from '
                'the same real market data this lesson just described.',
          ),
        ],
      ),
      Lesson(
        id: 'lesson_2',
        title: 'Understanding Risk & Volatility',
        description: 'Learn why prices go up and down, and how to measure risk.',
        difficulty: 'Beginner',
        xpReward: 75,
        riskProfileMatch: 'All',
        content: const [
          LessonSection(
            heading: 'Volatility is the size of the swings',
            body: 'Volatility measures how much a price moves, not which '
                'direction. A stock that swings 10% in a week is more volatile '
                'than one that drifts 1% — even if both end up flat. Higher '
                'volatility means bigger potential gains, but also bigger '
                'potential losses.',
          ),
          LessonSection(
            heading: 'How this app scores it',
            body: 'Every simulation on the Stock Dashboard produces a Risk Score '
                'and a Volatility label (Low/Medium/High), plus a Max Drawdown — '
                'the worst peak-to-trough drop the stock has actually experienced '
                'historically. A large drawdown is a concrete warning sign, not '
                'just an abstract number.',
          ),
          LessonSection(
            heading: 'RSI and MACD as momentum signals',
            body: 'RSI (Relative Strength Index) flags when a stock looks '
                'overbought (>70) or oversold (<30). MACD histogram shows whether '
                'momentum is accelerating or fading. The app blends both, plus '
                'price-vs-MA50, into a single momentum score that tags each '
                'stock Bull, Bear, or Neutral.',
          ),
          LessonSection(
            heading: 'Risk is not automatically bad',
            body: 'A Conservative investor and an Aggressive investor can look '
                'at the exact same volatile stock and reach opposite conclusions '
                '— it depends on how much risk fits their goals. That trade-off '
                'is exactly what the next lesson, the Iron Triangle, is about.',
          ),
        ],
      ),
      Lesson(
        id: 'lesson_3',
        title: 'The Iron Triangle of Wealth',
        description: 'Master the balance between Liquidity, Risk, and Return.',
        difficulty: 'Intermediate',
        xpReward: 100,
        riskProfileMatch: 'All',
        content: const [
          LessonSection(
            heading: 'Three pillars, one trade-off',
            body: 'Return, Safety, and Liquidity form a triangle because you '
                'cannot maximize all three at once. Push for higher Return and '
                'you usually give up some Safety. Demand instant Liquidity and '
                'you often accept a lower Return. Every investment sits '
                'somewhere on this triangle, never at a perfect corner.',
          ),
          LessonSection(
            heading: 'How the app scores each pillar',
            body: 'Return comes from the Expected Price / CAGR in a simulation. '
                'Safety is the inverse of the Risk Score (a lower risk score = '
                'higher safety). Liquidity comes from the Liquidity label — how '
                'easily a position can be bought or sold without moving the '
                'price.',
          ),
          LessonSection(
            heading: 'Reading the Triangle Radar chart',
            body: 'On the Stock Dashboard, after running a simulation, scroll to '
                'the 🔺 Triangle Radar chart — it plots Return, Safety, and '
                'Liquidity as one shape. A lopsided triangle tells you at a '
                'glance which pillar that stock sacrifices.',
          ),
          LessonSection(
            heading: 'Your personal profile',
            body: 'Your Conservative / Balanced / Aggressive profile (set from '
                'your risk quiz) decides how much drawdown is acceptable. If a '
                'simulation\'s Max Drawdown breaches your profile\'s threshold, '
                'the app shows a red risk-mismatch warning — that is this '
                'triangle enforcing itself in real time.',
          ),
        ],
      ),
      Lesson(
        id: 'lesson_4',
        title: 'Conservative Investing Strategies',
        description: 'Learn about bonds, fixed deposits, and low-risk ETFs.',
        difficulty: 'Intermediate',
        xpReward: 100,
        riskProfileMatch: 'Conservative',
        content: const [
          LessonSection(
            heading: 'Capital preservation comes first',
            body: 'Conservative investing prioritizes not losing money over '
                'maximizing gains. That usually means favoring assets with '
                'lower volatility and steadier income, even if the long-run '
                'return is more modest than growth stocks.',
          ),
          LessonSection(
            heading: 'Common conservative building blocks',
            body: 'Bonds and fixed deposits offer predictable, contractual '
                'returns. Low-risk index ETFs spread your money across many '
                'companies, softening single-stock shocks. KLCI blue-chip '
                'dividend stocks (banks, utilities on Bursa) add steady ~3-5% '
                'yields with relatively lower volatility.',
          ),
          LessonSection(
            heading: 'What to check on the dashboard',
            body: 'Before buying, check three Triangle Attributes on the Stock '
                'Dashboard: Settlement Term, Liquidity label, and Dividend '
                'Yield. A High-liquidity, Low-volatility stock with a solid '
                'dividend yield is the classic conservative profile.',
          ),
          LessonSection(
            heading: 'Why the risk warning fires more for you',
            body: 'Because your profile is Conservative, the app flags a risk '
                'mismatch at a Max Drawdown beyond -20% (Balanced profiles get '
                'more room, at -35%). That is not the app being overly '
                'cautious — it is enforcing the exact trade-off you chose when '
                'you set your risk profile.',
          ),
        ],
      ),
      Lesson(
        id: 'lesson_5',
        title: 'Aggressive Growth Investing',
        description: 'Learn about high-growth stocks, leverage, and momentum trading.',
        difficulty: 'Advanced',
        xpReward: 150,
        riskProfileMatch: 'Aggressive',
        content: const [
          LessonSection(
            heading: 'Chasing higher Return on purpose',
            body: 'Aggressive/growth investing deliberately accepts more '
                'volatility and drawdown risk in exchange for higher expected '
                'return — often in younger, faster-growing companies or sectors '
                'still expanding market share rather than paying dividends.',
          ),
          LessonSection(
            heading: 'Reading momentum like the app does',
            body: 'The Bull/Bear/Neutral regime tag on the Stock Dashboard is '
                'built from the same momentum score (RSI + MACD histogram + '
                'price-vs-MA50) that feeds the Monte Carlo simulation\'s drift. '
                'A "Bull" tag means recent momentum is pushing the simulation\'s '
                'forecast upward, not a guarantee.',
          ),
          LessonSection(
            heading: 'Know your real downside',
            body: 'Higher return potential comes with real downside: check Max '
                'Drawdown before committing. In Time Machine, also watch the '
                'Liquidity Penalty / slippage cost on illiquid names — exiting a '
                'volatile, thinly-traded position quickly can cost you more '
                'than the sticker price suggests.',
          ),
          LessonSection(
            heading: 'Conviction still needs position sizing',
            body: 'Even with high conviction, concentrating your entire '
                'portfolio in one volatile pick abandons the Liquidity and '
                'Safety pillars entirely. The next lesson, Building a Balanced '
                'Portfolio, covers how to keep growth bets from dominating '
                'everything else you own.',
          ),
        ],
      ),
      Lesson(
        id: 'lesson_6',
        title: 'Building a Balanced Portfolio',
        description: 'How to allocate assets based on your financial goals.',
        difficulty: 'Advanced',
        xpReward: 150,
        riskProfileMatch: 'All',
        content: const [
          LessonSection(
            heading: 'Diversification is risk management, not a slogan',
            body: 'Balance does not mean owning "a bit of everything" randomly '
                '— it means deliberately spreading Return, Safety, and '
                'Liquidity across multiple holdings so no single stock\'s bad '
                'week sinks your whole portfolio.',
          ),
          LessonSection(
            heading: 'A practical mix worth studying',
            body: 'A common core-satellite approach: an index ETF core (around '
                '70%) for broad, lower-volatility growth, plus a few individual '
                'picks (around 30%) for higher conviction. Blending KLCI '
                'dividend payers with US growth stocks also diversifies across '
                'currency (RM vs USD) and sector, not just company count.',
          ),
          LessonSection(
            heading: 'Test allocations before committing real capital',
            body: 'Use Time Machine to backtest how a ticker would have '
                'performed over a real historical stretch (including a crash '
                'year like 2020) before adding it. Comparing a few candidates '
                'this way turns "I think this is balanced" into something you '
                'actually measured.',
          ),
          LessonSection(
            heading: 'Revisit your Triangle Health Score',
            body: 'Your overall Triangle Health Score on the Profile/Home '
                'screen combines Return potential, Safety, and Liquidity across '
                'everything you hold — not just one position. Check it '
                'periodically; a portfolio that was balanced six months ago can '
                'drift as prices move.',
          ),
        ],
      ),
    ];
    notifyListeners();
  }
}