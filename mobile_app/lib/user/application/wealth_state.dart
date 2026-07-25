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

  final List<IncomeSource> _incomeSources = [];
  final List<String> _incomeSourceIds = []; // ✅ Track Firestore doc IDs

  double get monthlySalary => _monthlySalary;
  double get monthlyExpenses => _monthlyExpenses;
  double get currentSavings => _currentSavings;
  double get riskTolerance => _riskTolerance;
  List<IncomeSource> get incomeSources => _incomeSources;
  List<String> _watchlist = ['AAPL', 'MSFT', 'TSLA', 'GOOGL'];
  List<String> get watchlist => _watchlist;
  TrianglePreference get trianglePreference => _trianglePreference;

  double? get financialGoal => _financialGoal;
  DateTime? get goalDate => _goalDate;

  double get triangleHealthScore {
    // 1. Safety Factor (Emergency Fund)
    double safetyFactor = safetyScore; 
    
    // 2. Return Potential (Simulated Dividends / Income)
    // Assuming a healthy passive income goal is $10,000/year
    double returnFactor = (_portfolioState.totalSimulatedAnnualDividend / 10000.0 * 100).clamp(0, 100);

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
    if (_monthlyExpenses == 0) return 100.0;

    // 1. Emergency Fund Score (50%)
    double survivalMonths = _currentSavings / _monthlyExpenses;
    double emergencyFundScore = (survivalMonths / 6.0).clamp(0.0, 1.0) * 50;

    // 2. Portfolio Risk Score (50%)
    double portfolioValue = _portfolioState.holdings.fold(0, (sum, item) => sum + item.totalValue);
    // Lower ratio of savings-to-portfolio is riskier
    double riskRatio = (portfolioValue > 0) ? _currentSavings / portfolioValue : 1.0;
    double portfolioRiskScore = (riskRatio / 0.5).clamp(0.0, 1.0) * 50; // Assumes a healthy ratio is 50% cash
    
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

    double totalDividends = _portfolioState.totalSimulatedAnnualDividend;
    double totalReturns = (totalPassiveIncome * 12) + totalDividends;

    double returnRatio = totalReturns / (totalIncome * 12); // Ratio of returns to total salary
    return (returnRatio / 0.1).clamp(0.0, 1.0) * 100; // 10% return ratio is a good target for a 100 score
  }

  void updateRiskTolerance(double newTolerance) {
    _riskTolerance = newTolerance;
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

  Future<void> updateWatchlist(List<String> newList) async {
    _watchlist = newList;
    await _pushToCloud(); // Already saves to Firestore
    notifyListeners();
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
        // ✅ LOAD WATCHLIST
        if (data.containsKey('watchlist')) {
          _watchlist = List<String>.from(data['watchlist']);
        }
        // ✅ LOAD PREFERENCE
        final prefIndex = data['trianglePreference'];
        if (prefIndex is int &&
            prefIndex >= 0 &&
            prefIndex < TrianglePreference.values.length) {
          _trianglePreference = TrianglePreference.values[prefIndex];
        }
      }
    } catch (e) {
      print("Failed to load wealth profile: $e");
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

  Future<void> _pushToCloud() async {
    User? user = _auth.currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).set({
        'salary': _monthlySalary,
        'expenses': _monthlyExpenses,
        'savings': _currentSavings,
        'risk': _riskTolerance,
        'financialGoal': _financialGoal,
        'goalDate': _goalDate?.toIso8601String(),
        'watchlist': _watchlist, // ✅ SAVE WATCHLIST
        'trianglePreference': _trianglePreference.index, // ✅ SAVE PREFERENCE
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
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

  String generateMonthlyBrief() {
    double monthlyIncome = _monthlySalary + totalPassiveIncome;
    double savingsMonths = _monthlyExpenses > 0 ? _currentSavings / _monthlyExpenses : 0;
    
    String brief = "";
    brief += "📊 Monthly Financial Brief\n";
    brief += "━━━━━━━━━━━━━━━━━━━━━\n";
    brief += "Income: \$${monthlyIncome.toStringAsFixed(0)}/mo\n";
    brief += "Expenses: \$${_monthlyExpenses.toStringAsFixed(0)}/mo\n";
    brief += "Savings: \$${_currentSavings.toStringAsFixed(0)}\n";
    brief += "Safety Score: ${safetyScore.toStringAsFixed(0)}/100\n\n";
    
    if (savingsMonths >= 6) {
      brief += "✅ Your emergency fund covers ${savingsMonths.toStringAsFixed(1)} months (Good).\n";
    } else if (savingsMonths >= 3) {
      brief += "⚠️ Your emergency fund covers ${savingsMonths.toStringAsFixed(1)} months. Aim for 6 months.\n";
    } else {
      brief += "🔴 Your emergency fund is low. Please prioritize building 3-6 months of expenses.\n";
    }

    if (totalPassiveIncome > 0) {
      brief += "✅ You have passive income of \$${totalPassiveIncome.toStringAsFixed(0)}/mo. Keep growing this!\n";
    } else {
      brief += "💡 You have no passive income yet. Consider investing in dividend stocks or bonds.\n";
    }

    return brief;
  }
}