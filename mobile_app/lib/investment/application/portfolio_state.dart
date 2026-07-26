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

  PortfolioItem({
    required this.ticker, required this.quantity, required this.avgPrice, required this.currency,
    this.totalDividends = 0.0,
    this.riskScore = 50.0,
    this.dailyChange = 0.0,
    this.currentMarketPrice = 0.0,
  });

  double get totalValue => quantity * (currentMarketPrice > 0 ? currentMarketPrice : avgPrice);
  double get dailyGainLoss => totalValue * (dailyChange / 100);

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

  double get totalSimulatedAnnualDividend {
    double total = 0.0;
    for (var item in holdings) {
      if (item.ticker.toUpperCase().endsWith('.KL')) {
        total += item.totalValue * 0.045;
      } else {
        total += item.totalValue * 0.015;
      }
    }
    return total;
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

  void _initRealtimeListeners() {
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _holdingsRef!.snapshots().listen((snapshot) {
          _holdings = snapshot.docs.map((doc) {
            return PortfolioItem.fromFirestore(doc.data() as Map<String, dynamic>);
          }).toList();
          refreshPortfolioData();
          notifyListeners();
        });

        _historyRef!.orderBy('date', descending: true).snapshots().listen((snapshot) {
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

  // ✅ FIXED: Concurrent fetching with Future.wait
  Future<void> refreshPortfolioData() async {
    if (_holdings.isEmpty) return;

    List<Future<PortfolioItem>> futures = _holdings.map((item) async {
      try {
        final result = await _api.fetchSimulation(item.ticker);
        return PortfolioItem(
          ticker: item.ticker,
          quantity: item.quantity,
          avgPrice: item.avgPrice,
          currency: item.currency,
          totalDividends: item.totalDividends,
          riskScore: result.riskScore,
          dailyChange: result.changePercent,
          currentMarketPrice: result.price,
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