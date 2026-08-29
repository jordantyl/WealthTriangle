import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/stock_api.dart';

enum TransactionType { buy, sell, dividend, correction }

class Transaction {
  final String ticker;
  final TransactionType type;
  final int qty;
  final double price;
  final double totalValue;
  final double? realizedPnL;
  final DateTime date;

  Transaction({
    required this.ticker, required this.type, required this.qty, required this.price,
    required this.totalValue, this.realizedPnL, required this.date,
  });

  Map<String, dynamic> toFirestore() => {
    'ticker': ticker,
    'type': type.index,
    'qty': qty,
    'price': price,
    'totalValue': totalValue,
    'realizedPnL': realizedPnL,
    'date': Timestamp.fromDate(date),
  };

  factory Transaction.fromFirestore(Map<String, dynamic> json) {
    return Transaction(
      ticker: json['ticker'] ?? 'UNKNOWN',
      type: TransactionType.values[json['type'] ?? 0],
      qty: json['qty'] ?? 0,
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      totalValue: (json['totalValue'] as num?)?.toDouble() ?? 0.0,
      realizedPnL: (json['realizedPnL'] as num?)?.toDouble(),
      date: (json['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class PortfolioItem {
  final String ticker;
  final int quantity;
  final double avgPrice;
  final String currency;
  final double totalDividends;
  final double riskScore;
  final double dailyChange;
  final double currentMarketPrice;
  // Real trailing dividend yield (%) from the backend's /api/stock (same
  // field Stock Dashboard's Triangle Attributes shows), refreshed alongside
  // riskScore/dailyChange/currentMarketPrice in refreshPortfolioData(). 0.0
  // is a legitimate value for non-dividend-paying stocks, not just "not
  // fetched yet" — no flat guessed rate is applied on top of it.
  final double dividendYield;
  // Real payment-schedule-based dividend data (backend/app.py:
  // dividend_history), refreshed alongside dividendYield. frequencyPerYear
  // == 0 means either no dividend history was fetched yet or the ticker
  // doesn't pay one — annualDividendIncome falls back to the yield-based
  // estimate in that case so a fetch failure never zeroes out the number.
  final int dividendFrequencyPerYear;
  final double projectedAnnualDividendPerShare;
  // Estimated per-share dividend still to come this calendar year — see
  // DividendHistory.remainingThisYearPerShare. 0.0 whenever
  // dividendFrequencyPerYear is 0 (no real history to estimate from).
  final double remainingThisYearPerShare;
  final List<UpcomingDividendPayment> upcomingPayments;

  PortfolioItem({
    required this.ticker, required this.quantity, required this.avgPrice, required this.currency,
    this.totalDividends = 0.0,
    this.riskScore = 50.0,
    this.dailyChange = 0.0,
    this.currentMarketPrice = 0.0,
    this.dividendYield = 0.0,
    this.dividendFrequencyPerYear = 0,
    this.projectedAnnualDividendPerShare = 0.0,
    this.remainingThisYearPerShare = 0.0,
    this.upcomingPayments = const [],
  });

  double get totalValue => quantity * (currentMarketPrice > 0 ? currentMarketPrice : avgPrice);
  double get dailyGainLoss => totalValue * (dailyChange / 100);

  /// Real payment-history-based estimate (most recent per-share dividend x
  /// how many times/year this ticker actually pays) when available;
  /// otherwise falls back to the old trailing-yield x value approximation.
  double get annualDividendIncome {
    if (dividendFrequencyPerYear > 0) {
      return quantity * projectedAnnualDividendPerShare;
    }
    return totalValue * (dividendYield / 100);
  }

  double get remainingDividendThisYear => quantity * remainingThisYearPerShare;

  bool get usesRealDividendHistory => dividendFrequencyPerYear > 0;

  Map<String, dynamic> toFirestore() => {
    'ticker': ticker,
    'quantity': quantity,
    'avgPrice': avgPrice,
    'currency': currency,
    'totalDividends': totalDividends,
  };

  factory PortfolioItem.fromFirestore(Map<String, dynamic> json) {
    return PortfolioItem(
      ticker: json['ticker'] ?? 'UNKNOWN',
      quantity: json['quantity'] ?? 0,
      avgPrice: (json['avgPrice'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] ?? 'USD',
      totalDividends: (json['totalDividends'] as num?)?.toDouble() ?? 0.0,
      riskScore: (json['riskScore'] as num?)?.toDouble() ?? 50.0,
      dailyChange: (json['dailyChange'] as num?)?.toDouble() ?? 0.0,
      currentMarketPrice: (json['currentMarketPrice'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// One holding's contribution to totalAnnualDividendIncome — feeds the
/// dividend breakdown UI (Cash Flow Analysis) so the lump sum isn't a black
/// box.
class DividendBreakdownItem {
  final String ticker;
  final String currency;
  final double dividendYield;
  final double annualDividend;
  final int dividendFrequencyPerYear;
  final bool usesRealDividendHistory;

  const DividendBreakdownItem({
    required this.ticker,
    required this.currency,
    required this.dividendYield,
    required this.annualDividend,
    this.dividendFrequencyPerYear = 0,
    this.usesRealDividendHistory = false,
  });
}

/// One flattened, quantity-scaled upcoming payment row for the Passive
/// Income screen — a holding can contribute more than one of these (e.g. a
/// quarterly payer with 2 remaining slots this year).
class UpcomingDividendRow {
  final String ticker;
  final DateTime expectedDate;
  final double amountPerShare;
  final double totalAmount;

  const UpcomingDividendRow({
    required this.ticker,
    required this.expectedDate,
    required this.amountPerShare,
    required this.totalAmount,
  });
}

class PendingTrade {
  final String ticker;
  final int qty;
  final double price;
  final String rawMessage;
  PendingTrade({required this.ticker, required this.qty, required this.price, required this.rawMessage});
}

class PortfolioState extends ChangeNotifier {
  List<PortfolioItem> _holdings = [];
  List<PortfolioItem> get holdings => _holdings;

  // Real per-holding trailing dividend yield x current value — no flat
  // guessed rate. Ticker order matches `holdings` (held-first via wherever
  // the caller sorts it, unchanged here).
  List<DividendBreakdownItem> get dividendBreakdown {
    return holdings
        .map((item) => DividendBreakdownItem(
              ticker: item.ticker,
              currency: item.currency,
              dividendYield: item.dividendYield,
              annualDividend: item.annualDividendIncome,
              dividendFrequencyPerYear: item.dividendFrequencyPerYear,
              usesRealDividendHistory: item.usesRealDividendHistory,
            ))
        .toList();
  }

  double get totalAnnualDividendIncome =>
      holdings.fold(0.0, (total, item) => total + item.annualDividendIncome);

  double get totalRemainingDividendThisYear =>
      holdings.fold(0.0, (total, item) => total + item.remainingDividendThisYear);

  // Every holding's estimated upcoming payment(s), flattened and sorted by
  // date — drives the Passive Income screen's "Upcoming Dividends" list.
  List<UpcomingDividendRow> get upcomingDividendPayments {
    final rows = <UpcomingDividendRow>[
      for (final h in holdings)
        for (final p in h.upcomingPayments)
          UpcomingDividendRow(
            ticker: h.ticker,
            expectedDate: p.expectedDate,
            amountPerShare: p.amountPerShare,
            totalAmount: p.amountPerShare * h.quantity,
          ),
    ];
    rows.sort((a, b) => a.expectedDate.compareTo(b.expectedDate));
    return rows;
  }

  List<Transaction> _transactions = [];
  List<Transaction> get transactions => _transactions;

  final List<PendingTrade> _pendingTrades = [];
  List<PendingTrade> get pendingTrades => _pendingTrades;

  final StockApi _api = StockApi();

  User? get _user => FirebaseAuth.instance.currentUser;

  CollectionReference? get _holdingsRef {
    if (_user == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(_user!.uid).collection('holdings');
  }

  CollectionReference? get _historyRef {
    if (_user == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(_user!.uid).collection('history');
  }

  PortfolioState() {
    _initRealtimeListeners();
  }

  String get investorType {
    if (_holdings.isEmpty) return "New Investor";
    double totalRisk = 0;
    double totalVal = 0;
    for (var item in _holdings) {
      double val = item.totalValue;
      totalRisk += (item.riskScore * val);
      totalVal += val;
    }
    if (totalVal == 0) return "New Investor";
    double avgRisk = totalRisk / totalVal;
    if (avgRisk < 30) return "Conservative 🛡️";
    if (avgRisk < 60) return "Balanced ⚖️";
    return "Aggressive 🚀";
  }

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot>? _holdingsSub;
  StreamSubscription<QuerySnapshot>? _historySub;

  void _initRealtimeListeners() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      // Cancel any listeners from a previous signed-in user first —
      // authStateChanges can fire more than once per app session (sign out
      // then back in), and without this, each firing stacked another pair
      // of live Firestore listeners on top of the last instead of
      // replacing them.
      _holdingsSub?.cancel();
      _historySub?.cancel();

      if (user != null) {
        _holdingsSub = _holdingsRef!.snapshots().listen((snapshot) {
          _holdings = snapshot.docs.map((doc) {
            return PortfolioItem.fromFirestore(doc.data() as Map<String, dynamic>);
          }).toList();
          refreshPortfolioData();
          notifyListeners();
        });

        _historySub = _historyRef!.orderBy('date', descending: true).snapshots().listen((snapshot) {
          _transactions = snapshot.docs.map((doc) {
            return Transaction.fromFirestore(doc.data() as Map<String, dynamic>);
          }).toList();
          notifyListeners();
        });
      } else {
        _holdings = [];
        _transactions = [];
        notifyListeners();
      }
    });
  }

  // Was missing entirely — none of the three subscriptions above were ever
  // canceled, so tearing down this notifier while a user was signed in
  // (e.g. a widget-tree rebuild) left the Firestore listeners running
  // against a disposed ChangeNotifier. The next snapshot to arrive called
  // notifyListeners() on it and threw ("used after being disposed"),
  // confirmed live via the integration test harness rebuilding app.main().
  @override
  void dispose() {
    _authSub?.cancel();
    _holdingsSub?.cancel();
    _historySub?.cancel();
    super.dispose();
  }

  // ✅ FIXED: Concurrent fetching with Future.wait
  Future<void> refreshPortfolioData() async {
    if (_holdings.isEmpty) return;

    List<Future<PortfolioItem>> futures = _holdings.map((item) async {
      try {
        final result = await _api.fetchSimulation(item.ticker);
        // Fetched separately/best-effort: a dividend-history failure (e.g.
        // ticker never paid one) shouldn't fail the whole price refresh —
        // it just falls back to the yield-based estimate via DividendHistory.none.
        final divHistory = await _api.fetchDividendHistory(item.ticker);
        return PortfolioItem(
          ticker: item.ticker,
          quantity: item.quantity,
          avgPrice: item.avgPrice,
          currency: item.currency,
          totalDividends: item.totalDividends,
          riskScore: result.riskScore,
          dailyChange: result.changePercent,
          currentMarketPrice: result.price,
          dividendYield: result.dividendYield,
          dividendFrequencyPerYear: divHistory.frequencyPerYear,
          projectedAnnualDividendPerShare: divHistory.projectedAnnualPerShare,
          remainingThisYearPerShare: divHistory.remainingThisYearPerShare,
          upcomingPayments: divHistory.upcomingPayments,
        );
      } catch (e) {
        print("Failed to refresh ${item.ticker}: $e");
        return item;
      }
    }).toList();

    final updatedList = await Future.wait(futures);
    _holdings = updatedList;
    notifyListeners();
  }

  // ✅ FIXED: Buy with Transaction
  Future<void> buyStock(String ticker, int qty, double price, String currency) async {
    if (_holdingsRef == null) return;
    final ref = _holdingsRef!.doc(ticker);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      DocumentSnapshot snapshot = await transaction.get(ref);
      if (snapshot.exists) {
        int oldQty = (snapshot.get('quantity') as num).toInt();
        double oldAvg = (snapshot.get('avgPrice') as num).toDouble();
        int newQty = oldQty + qty;
        double newAvg = ((oldQty * oldAvg) + (qty * price)) / newQty;
        transaction.update(ref, {'quantity': newQty, 'avgPrice': newAvg});
      } else {
        transaction.set(ref, {
          'ticker': ticker,
          'quantity': qty,
          'avgPrice': price,
          'currency': currency,
          'totalDividends': 0.0,
        });
      }
    });
    _recordTransaction(ticker, TransactionType.buy, qty, price, 0);
  }

  // ✅ FIXED: Sell with Transaction
  Future<String?> sellStock(String ticker, int sellQty, double sellPrice) async {
    if (_holdingsRef == null) return "Not logged in";
    final ref = _holdingsRef!.doc(ticker);

    try {
      String? error;
      double? pnl;
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(ref);
        if (!snapshot.exists) {
          error = "You don't own this stock.";
          return;
        }

        int currentQty = (snapshot.get('quantity') as num).toInt();
        double avgPrice = (snapshot.get('avgPrice') as num).toDouble();

        if (sellQty > currentQty) {
          error = "Insufficient shares.";
          return;
        }

        double cost = avgPrice * sellQty;
        double revenue = sellPrice * sellQty;
        pnl = revenue - cost;

        int newQty = currentQty - sellQty;

        if (newQty == 0) {
          transaction.delete(ref);
        } else {
          transaction.update(ref, {'quantity': newQty});
        }
      });
      // Record only once the transaction has actually committed — doing this
      // inside the callback above would re-run it (and double-log history)
      // every time Firestore retries the transaction on write contention.
      if (error == null && pnl != null) {
        _recordTransaction(ticker, TransactionType.sell, sellQty, sellPrice, pnl!);
      }
      return error;
    } catch (e) {
      return "Transaction failed: $e";
    }
  }

  Future<void> deleteHolding(String ticker) async {
    if (_holdingsRef == null) return;
    await _holdingsRef!.doc(ticker).delete();
    _recordTransaction(ticker, TransactionType.correction, 0, 0, 0);
  }

  Future<void> _recordTransaction(String ticker, TransactionType type, int qty, double price, double pnl) async {
    if (_historyRef == null) return;
    var tx = Transaction(
      ticker: ticker, type: type, qty: qty, price: price,
      totalValue: qty * price, realizedPnL: pnl, date: DateTime.now()
    );
    await _historyRef!.add(tx.toFirestore());
  }

  // ✅ IMPROVED: Generic parsing with Regex
  void parseNotification(String title, String body) {
    // Regex to find: A ticker (e.g., AAPL), a quantity (e.g., 10), and a price (e.g., 150.75)
    final regExp = RegExp(r'([A-Z]{1,5})\s+(\d+)\s+@\s+([\d\.]+)');
    final match = regExp.firstMatch(body);

    if (match != null) {
      final ticker = match.group(1);
      final qty = int.tryParse(match.group(2) ?? '0');
      final price = double.tryParse(match.group(3) ?? '0.0');

      if (ticker != null && qty != null && price != null && qty > 0) {
        _pendingTrades.add(PendingTrade(
          ticker: ticker,
          qty: qty,
          price: price,
          rawMessage: body,
        ));
        notifyListeners();
      }
    }
  }
  void confirmTrade(int index) {
    final trade = _pendingTrades[index];
    buyStock(trade.ticker, trade.qty, trade.price, "USD");
    _pendingTrades.removeAt(index);
    notifyListeners();
  }
  void rejectTrade(int index) {
    _pendingTrades.removeAt(index);
    notifyListeners();
  }
}