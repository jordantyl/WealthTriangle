import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../income/domain/income_source.dart';
import '../../investment/application/portfolio_state.dart';

enum TrianglePreference { balanced, safety, liquidity, return_ }

class WealthState extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final PortfolioState _portfolioState; // ✅ DEPENDENCY

  WealthState(this._portfolioState) { // ✅ UPDATED CONSTRUCTOR
    _portfolioState.addListener(_onPortfolioChanged);
  }

  // When portfolio changes, our scores might change too
  void _onPortfolioChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    _portfolioState.removeListener(_onPortfolioChanged);
    super.dispose();
  }

  double _monthlySalary = 3000.0;
  double _riskTolerance = 50.0;
  double _monthlyExpenses = 2000.0;
  double _currentSavings = 10000.0;
  double? _financialGoal;
  DateTime? _goalDate;
  TrianglePreference _trianglePreference = TrianglePreference.balanced; // ✅ NEW

  // ✅ NEW: Personalized Investor Profile (Report §1.4.2 item 5 — avatar +
  // preferred sectors, alongside the financial goal already tracked above).
  String _avatarEmoji = '🧑‍💼';
  List<String> _preferredSectors = [];

  final List<IncomeSource> _incomeSources = [];
  final List<String> _incomeSourceIds = []; // ✅ Track Firestore doc IDs

  double get monthlySalary => _monthlySalary;
  double get monthlyExpenses => _monthlyExpenses;
  double get currentSavings => _currentSavings;
  double get riskTolerance => _riskTolerance;
  List<IncomeSource> get incomeSources => _incomeSources;

  // The starter tickers every new user sees. Kept structurally protected —
  // see updateWatchlist below — so neither a manual edit nor the AI
  // assistant's remove_from_watchlist tool can ever drop them, only add on
  // top of them.
  static const List<String> defaultWatchlist = ['AAPL', 'MSFT', 'TSLA', 'GOOGL'];
  List<String> _watchlist = List<String>.from(defaultWatchlist);
  List<String> get watchlist => _watchlist;
  bool isDefaultTicker(String ticker) => defaultWatchlist.contains(ticker.toUpperCase());
  TrianglePreference get trianglePreference => _trianglePreference;

  double? get financialGoal => _financialGoal;
  DateTime? get goalDate => _goalDate;

  String get avatarEmoji => _avatarEmoji;
  List<String> get preferredSectors => _preferredSectors;

  static const List<String> availableSectors = [
    'Technology',
    'Healthcare',
    'Financials',
    'Energy',
    'Consumer',
    'Real Estate',
    'Industrials',
    'Utilities',
    'Crypto / Web3',
    'Index Funds',
  ];

  static const List<String> availableAvatars = [
    '🧑‍💼', '👩‍💼', '🧑‍🎓', '👩‍🎓', '🧑‍🚀', '🦁', '🐢', '🦉', '🐺', '🐸',
  ];

  Future<void> updateAvatarEmoji(String emoji) async {
    _avatarEmoji = emoji;
    notifyListeners();
    await _pushToCloud();
  }

  Future<void> updatePreferredSectors(List<String> sectors) async {
    _preferredSectors = sectors;
    notifyListeners();
    await _pushToCloud();
  }

  double get triangleHealthScore {
    // 1. Safety Factor (Emergency Fund)
    double safetyFactor = safetyScore; 
    
    // 2. Return Potential (Dividend Income)
    // Assuming a healthy passive income goal is $10,000/year
    double returnFactor = (_portfolioState.totalAnnualDividendIncome / 10000.0 * 100).clamp(0, 100);

    // 3. Liquidity Factor (Cash vs Expenses)
    double liquidityFactor = (_monthlyExpenses > 0) 
        ? ((_currentSavings / _monthlyExpenses) / 6.0 * 100).clamp(0, 100) 
        : 50.0;

    // Average them for a holistic score
    return (safetyFactor + returnFactor + liquidityFactor) / 3.0;
  }

  Future<void> updateTrianglePreference(TrianglePreference newPref) async {
    _trianglePreference = newPref;
    notifyListeners();
    // Goes through the same key/format _pushToCloud() and syncFromCloud()
    // already agree on ('trianglePreference', enum index) — a separate
    // direct write here previously used a different key ('TrianglePreference',
    // enum name) that syncFromCloud never read back, so the choice silently
    // reverted on next app open.
    await _pushToCloud();
  }

  CollectionReference get _incomeRef {
    final user = _auth.currentUser;
    if (user == null) throw Exception("Not logged in");
    return _db.collection('users').doc(user.uid).collection('income_sources');
  }

  double get totalPassiveIncome {
    double total = 0;
    for (var source in _incomeSources) {
      total += source.isMonthly ? source.amount : (source.amount / 12);
    }
    return total;
  }

  // True once the user has entered any real financial data — a fresh
  // signup defaults salary/expenses/savings to 0, and safetyScore used to
  // read that as "100% safe" (no expenses = no risk), which is a false
  // green light for someone who just hasn't filled in their Profile yet.
  bool get hasFinancialData =>
      _monthlySalary != 0 || _monthlyExpenses != 0 || _currentSavings != 0;

  /// SAFETY: How resilient are you to shocks?
  /// Balances emergency fund against expenses AND portfolio risk.
  double get safetyScore {
    if (!hasFinancialData) return 0.0;

    // 1. Emergency Fund Score (50%) — months of expenses your savings could
    // cover, capped at 6 months. With no expenses there's no burn rate to
    // measure against, so this half instead rewards actually holding a cash
    // buffer, rather than defaulting to a flat 50 regardless of savings —
    // that's what let this hit 100 with $0 savings and $0 everything else.
    double emergencyFundScore;
    if (_monthlyExpenses > 0) {
      double survivalMonths = _currentSavings / _monthlyExpenses;
      emergencyFundScore = (survivalMonths / 6.0).clamp(0.0, 1.0) * 50;
    } else {
      emergencyFundScore = _currentSavings > 0 ? 50.0 : 0.0;
    }

    // 2. Portfolio Risk Score (50%) — what fraction of total assets (cash +
    // invested) is sitting in cash; a healthy cushion is ~50% cash. Having
    // NO assets at all (no savings, no portfolio) is the riskiest position,
    // not the safest, so that case scores 0 instead of defaulting to a flat
    // "fully safe" whenever there's simply no portfolio yet.
    double portfolioValue = _portfolioState.holdings.fold(0.0, (sum, item) => sum + item.totalValue);
    double totalAssets = _currentSavings + portfolioValue;
    double cashRatio = totalAssets > 0 ? _currentSavings / totalAssets : 0.0;
    double portfolioRiskScore = (cashRatio / 0.5).clamp(0.0, 1.0) * 50;

    return (emergencyFundScore + portfolioRiskScore).clamp(0.0, 100.0);
  }

  /// LIQUIDITY: How quickly can you access cash?
  /// Measures uninvested savings.
  double get liquidityScore {
    double totalValue = _currentSavings + _portfolioState.holdings.fold(0, (sum, item) => sum + item.totalValue);
    if (totalValue == 0) return 0.0;
    double liquidityRatio = _currentSavings / totalValue;
    return (liquidityRatio * 100).clamp(0.0, 100.0);
  }

  /// RETURN: How well are your assets generating more assets?
  /// Considers passive income and portfolio dividends.
  double get returnScore {
    double totalIncome = _monthlySalary + totalPassiveIncome;
    if (totalIncome == 0) return 0;

    double totalDividends = _portfolioState.totalAnnualDividendIncome;
    double totalReturns = (totalPassiveIncome * 12) + totalDividends;

    double returnRatio = totalReturns / (totalIncome * 12); // Ratio of returns to total salary
    return (returnRatio / 0.1).clamp(0.0, 1.0) * 100; // 10% return ratio is a good target for a 100 score
  }

  void updateRiskTolerance(double newTolerance) {
    _riskTolerance = newTolerance;
    // Was missing here (every sibling setter has it) — the Profile screen's
    // slider and the AI's set_risk_tolerance tool both updated the UI
    // immediately but silently reverted to whatever was last saved (or the
    // 50.0 default) on next app open, since nothing ever wrote it back.
    _pushToCloud();
    notifyListeners();
  }


  // ✅ FIXED: Saves to Firestore
  void addIncomeSource(String name, double amount, bool isMonthly) async {
    final newSource = IncomeSource(name: name, amount: amount, isMonthly: isMonthly);
    _incomeSources.add(newSource);
    notifyListeners();

    try {
      final docRef = await _incomeRef.add({
        'name': name,
        'amount': amount,
        'isMonthly': isMonthly,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _incomeSourceIds.add(docRef.id);
    } catch (e) {
      print("Failed to save income source: $e");
    }
  }

  // ✅ NEW: Delete method
  void removeIncomeSource(int index) async {
    if (index < 0 || index >= _incomeSources.length) return;

    final docId = _incomeSourceIds[index];
    _incomeSources.removeAt(index);
    _incomeSourceIds.removeAt(index);
    notifyListeners();

    try {
      await _incomeRef.doc(docId).delete();
    } catch (e) {
      print("Failed to delete income source: $e");
    }
  }

  /// Replaces the watchlist wholesale, but the default starter tickers
  /// (defaultWatchlist) are always unioned back in — this is the single
  /// write path every caller (manual edits, AI assistant tools) goes
  /// through, so it's the one place that needs to enforce "defaults can
  /// never be removed" rather than trusting every call site to remember.
  Future<void> updateWatchlist(List<String> newList) async {
    final upper = newList.map((t) => t.toUpperCase()).toSet();
    _watchlist = [...defaultWatchlist, ...upper.difference(defaultWatchlist.toSet())];
    await _pushToCloud(); // Already saves to Firestore
    notifyListeners();
  }

  Future<void> addToWatchlist(String ticker) async {
    final t = ticker.toUpperCase();
    if (_watchlist.contains(t)) return;
    await updateWatchlist([..._watchlist, t]);
  }

  /// Throws [WatchlistProtectedException] for a default ticker instead of
  /// silently no-op'ing, so both the manual-edit screen and the AI
  /// assistant can surface a clear "can't remove that" message.
  Future<void> removeFromWatchlist(String ticker) async {
    final t = ticker.toUpperCase();
    if (defaultWatchlist.contains(t)) {
      throw WatchlistProtectedException(t);
    }
    await updateWatchlist(_watchlist.where((x) => x != t).toList());
  }

  // ✅ FIXED: Loads income sources from Firestore
  Future<void> syncFromCloud() async {
    User? user = _auth.currentUser;
    if (user == null) return;

    try {
      DocumentSnapshot doc = await _db.collection('users').doc(user.uid).get();
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        _monthlySalary = (data['salary'] ?? 3000.0).toDouble();
        _monthlyExpenses = (data['expenses'] ?? 2000.0).toDouble();
        _currentSavings = (data['savings'] ?? 10000.0).toDouble();
        _riskTolerance = (data['risk'] ?? 50.0).toDouble();
        _financialGoal = (data['financialGoal'] as num?)?.toDouble();
        String? goalDateStr = data['goalDate'];
        _goalDate = goalDateStr != null ? DateTime.tryParse(goalDateStr) : null;
        // These four used to only be assigned `if (data.containsKey(...))`,
        // which left whatever was already in memory untouched for an
        // account whose doc predates that field (e.g. any account created
        // before avatars/sectors existed, or a brand-new signup — neither
        // login_screen.dart's nor signup_screen.dart's initial doc write
        // includes them). Since WealthState is a single long-lived Provider
        // instance that outlives sign-out (see main.dart), that stale
        // in-memory value was a PREVIOUS signed-in user's data leaking into
        // the newly signed-in account — always assign a real value
        // (falling back to the field's own default) so every sign-in starts
        // from a clean, correct state regardless of what was in memory.
        _watchlist = data.containsKey('watchlist')
            ? List<String>.from(data['watchlist'])
            : List<String>.from(defaultWatchlist);
        _avatarEmoji = data['avatarEmoji'] ?? '🧑‍💼';
        _preferredSectors = data.containsKey('preferredSectors')
            ? List<String>.from(data['preferredSectors'])
            : [];
        final prefIndex = data['trianglePreference'];
        _trianglePreference = (prefIndex is int &&
                prefIndex >= 0 &&
                prefIndex < TrianglePreference.values.length)
            ? TrianglePreference.values[prefIndex]
            : TrianglePreference.balanced;
      } else {
        // No Firestore doc yet for this uid (signup/first-login's own write
        // hasn't landed, or failed) — reset to defaults rather than leaving
        // a previous account's in-memory values in place.
        _monthlySalary = 3000.0;
        _monthlyExpenses = 2000.0;
        _currentSavings = 10000.0;
        _riskTolerance = 50.0;
        _financialGoal = null;
        _goalDate = null;
        _watchlist = List<String>.from(defaultWatchlist);
        _avatarEmoji = '🧑‍💼';
        _preferredSectors = [];
        _trianglePreference = TrianglePreference.balanced;
      }
    } catch (e) {
      // The financial fields' in-memory defaults (line 29-32 above) are
      // realistic-looking placeholder numbers, not zeros — fine as a
      // starting point before the first successful sync, but if THIS sync
      // fails (network blip, permission hiccup) they're left untouched and
      // get shown on Home's Financial Snapshot card as if they were the
      // user's real data, with a plausible-looking computed Safety%% and
      // risk profile and no indication any of it is fake. Reset to the same
      // safe/empty defaults the "no doc yet" branch above already uses, and
      // surface the failure the same way _pushToCloud() already does, so
      // Profile's existing sync-error banner picks it up.
      print("Failed to load wealth profile: $e");
      _monthlySalary = 0.0;
      _monthlyExpenses = 0.0;
      _currentSavings = 0.0;
      _lastSyncError = "Couldn't load your saved data — check your connection.";
    }

    try {
      final snapshot = await _incomeRef.get();
      _incomeSources.clear();
      _incomeSourceIds.clear();
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        _incomeSources.add(IncomeSource(
          name: data['name'] ?? 'Unknown',
          amount: (data['amount'] ?? 0).toDouble(),
          isMonthly: data['isMonthly'] ?? true,
        ));
        _incomeSourceIds.add(doc.id);
      }
    } catch (e) {
      print("Failed to load income sources: $e");
    }

    notifyListeners();
  }

  // Was completely invisible on failure — every setter below calls
  // _pushToCloud() without awaiting or catching it, so an offline/permission
  // write failure was silently swallowed: the in-memory value (and thus the
  // UI) already looked "saved" with nothing to indicate the change never
  // actually reached Firestore. Now exposed here so a screen that cares
  // (Profile, where every one of these setters is actually exercised via
  // UI) can show it and offer a retry, without every call site needing to
  // start awaiting/catching a previously-fire-and-forget void method.
  String? _lastSyncError;
  String? get lastSyncError => _lastSyncError;

  Future<void> _pushToCloud() async {
    User? user = _auth.currentUser;
    if (user == null) return;
    try {
      await _db.collection('users').doc(user.uid).set({
        'salary': _monthlySalary,
        'expenses': _monthlyExpenses,
        'savings': _currentSavings,
        'risk': _riskTolerance,
        'financialGoal': _financialGoal,
        'goalDate': _goalDate?.toIso8601String(),
        'watchlist': _watchlist, // ✅ SAVE WATCHLIST
        'trianglePreference': _trianglePreference.index, // ✅ SAVE PREFERENCE
        'avatarEmoji': _avatarEmoji, // ✅ SAVE PERSONALIZED PROFILE
        'preferredSectors': _preferredSectors,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (_lastSyncError != null) {
        _lastSyncError = null;
        notifyListeners();
      }
    } catch (e) {
      _lastSyncError = "Couldn't save your latest change — check your connection.";
      notifyListeners();
    }
  }

  /// Lets a "sync failed" banner offer a real retry instead of just a
  /// dismiss, since the underlying write is otherwise silently dropped.
  Future<void> retrySync() => _pushToCloud();

  void dismissSyncError() {
    if (_lastSyncError == null) return;
    _lastSyncError = null;
    notifyListeners();
  }

  void updateSalary(double value) {
    _monthlySalary = value;
    _pushToCloud();
    notifyListeners();
  }

  void updateExpenses(double value) {
    _monthlyExpenses = value;
    _pushToCloud();
    notifyListeners();
  }

  void updateSavings(double value) {
    _currentSavings = value;
    _pushToCloud();
    notifyListeners();
  }

  void setFinancialGoal(double goal, DateTime date) {
    _financialGoal = goal;
    _goalDate = date;
    _pushToCloud();
    notifyListeners();
  }

  double get goalProgress {
    if (_financialGoal == null || _financialGoal == 0) return 0;
    return (_currentSavings / _financialGoal!).clamp(0.0, 1.0);
  }
}

class WatchlistProtectedException implements Exception {
  final String ticker;
  const WatchlistProtectedException(this.ticker);

  @override
  String toString() => '$ticker is a default watchlist ticker and cannot be removed.';
}