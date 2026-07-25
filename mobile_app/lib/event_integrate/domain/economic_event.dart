import 'package:cloud_firestore/cloud_firestore.dart';

class EconomicEvent {
  final String id;
  final String title;
  final String? ticker; // Nullable for user events
  final EventType type;
  final DateTime eventDate;
  final String? description;
  final double? dividendAmount;
  final String? estimatedEPS;
  final String? actualEPS;
  final String? triangleNote; // ✅ NEW
  final bool isUserCreated;   // ✅ NEW
  bool isAlertEnabled;
  // Whether `ticker` is a stock the user currently holds in their portfolio,
  // as opposed to one they've merely added to their watchlist. Set after
  // fetch by EventIntegrationState.loadData() — not persisted.
  bool isHeld;

  EconomicEvent({
    required this.id,
    required this.title,
    this.ticker,
    required this.type,
    required this.eventDate,
    this.description,
    this.dividendAmount,
    this.estimatedEPS,
    this.actualEPS,
    this.triangleNote,
    this.isUserCreated = false,
    this.isAlertEnabled = false,
    this.isHeld = false,
  });

  // ✅ NEW: Factory for custom user events
  factory EconomicEvent.forUser({
    required String id,
    required String title,
    required DateTime date,
    String? description,
  }) {
    return EconomicEvent(
      id: id,
      title: title,
      type: EventType.liquidity,
      eventDate: date,
      description: description,
      isUserCreated: true,
    );
  }

  // ✅ NEW: Firestore Serialization
  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'ticker': ticker,
      'type': type.index,
      'eventDate': eventDate,
      'description': description,
      'dividendAmount': dividendAmount,
      'estimatedEPS': estimatedEPS,
      'actualEPS': actualEPS,
      'triangleNote': triangleNote,
      'isUserCreated': isUserCreated,
    };
  }

  // ✅ NEW: Firestore Deserialization
  factory EconomicEvent.fromFirestore(String id, Map<String, dynamic> data) {
    return EconomicEvent(
      id: id,
      title: data['title'] ?? 'Untitled Event',
      ticker: data['ticker'],
      type: EventType.values[data['type'] ?? EventType.other.index],
      eventDate: (data['eventDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      description: data['description'],
      dividendAmount: (data['dividendAmount'] as num?)?.toDouble(),
      estimatedEPS: data['estimatedEPS'],
      actualEPS: data['actualEPS'],
      triangleNote: data['triangleNote'],
      isUserCreated: data['isUserCreated'] ?? false,
    );
  }

  int get daysUntil => eventDate.difference(DateTime.now()).inDays;

  bool get isUpcoming => eventDate.isAfter(DateTime.now());

  bool get isThisWeek => daysUntil >= 0 && daysUntil <= 7;
}

enum EventType {
  dividendExDate,
  earningsReport,
  federalReserve,
  ipoListing,
  stockSplit,
  liquidity, // ✅ NEW
  other,
}

extension EventTypeExtension on EventType {
  String get displayName {
    switch (this) {
      case EventType.dividendExDate:
        return 'Dividend Ex-Date';
      case EventType.earningsReport:
        return 'Earnings Report';
      case EventType.federalReserve:
        return 'Fed Decision';
      case EventType.ipoListing:
        return 'IPO Listing';
      case EventType.stockSplit:
        return 'Stock Split';
      case EventType.liquidity:
        return 'Liquidity Event'; // ✅ NEW
      case EventType.other:
        return 'Event';
    }
  }

  String get icon {
    switch (this) {
      case EventType.dividendExDate:
        return '💰';
      case EventType.earningsReport:
        return '📊';
      case EventType.federalReserve:
        return '🏦';
      case EventType.ipoListing:
        return '🚀';
      case EventType.stockSplit:
        return '✂️';
      case EventType.liquidity:
        return '💧'; // ✅ NEW
      case EventType.other:
        return '📅';
    }
  }

  int get colorValue {
    switch (this) {
      case EventType.dividendExDate:
        return 0xFF4CAF50;
      case EventType.earningsReport:
        return 0xFF2196F3;
      case EventType.federalReserve:
        return 0xFF9C27B0;
      case EventType.ipoListing:
        return 0xFFFF9800;
      case EventType.stockSplit:
        return 0xFF00BCD4;
      case EventType.liquidity:
        return 0xFF4A90E2; // ✅ NEW
      case EventType.other:
        return 0xFF607D8B;
    }
  }
}
