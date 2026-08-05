import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../domain/economic_event.dart';
import '../data/event_integration_api.dart';

class EventIntegrationState extends ChangeNotifier {
  final EventIntegrationService _api = EventIntegrationService();

  List<EconomicEvent> _events = [];
  Set<String> _alertedEventIds = {};
  bool _isLoading = false;
  EventType? _selectedFilter;
  bool _heldOnly = false;
  bool _isMockEvents = false;

  List<EconomicEvent> get events => _events;
  bool get isLoading => _isLoading;
  EventType? get selectedFilter => _selectedFilter;
  // "Held" = the event's ticker is one the user actually owns (e.isHeld,
  // set from heldTickers in loadData below) — the market filter requested
  // alongside the existing event-type filter above.
  bool get heldOnly => _heldOnly;
  // True when the stock-specific events (earnings/dividends) are fallback
  // demo content rather than real Yahoo data — user-created liquidity
  // events are always real regardless of this flag.
  bool get isMockEvents => _isMockEvents;

  List<EconomicEvent> get filteredEvents {
    var list = _events.where((e) => e.isUpcoming).toList();
    if (_heldOnly) list = list.where((e) => e.isHeld).toList();
    if (_selectedFilter != null) {
      list = list.where((e) => e.type == _selectedFilter).toList();
    }
    return list;
  }

  CollectionReference? get _userEventsRef {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('user_events');
  }

  Future<void> loadData(String userId, List<String> watchlistTickers,
      {List<String> heldTickers = const []}) async {
    _isLoading = true;
    notifyListeners();

    // Held stocks matter more than ones merely on the watchlist, so make
    // sure they're never truncated out — put them first in the fetch list.
    final tickerSet = <String>{...heldTickers, ...watchlistTickers};

    try {
      final results = await Future.wait([
        _api.fetchEventsForWatchlist(tickerSet.toList()),
        _api.loadUserAlerts(userId),
        _userEventsRef?.get() ?? Future.value(null),
        FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('liquidity_events')
            .get(),
      ]);

      final fetchedEvents = results[0] as List<EconomicEvent>;
      _isMockEvents = _api.lastFetchWasMock;
      _alertedEventIds = results[1] as Set<String>;
      final userEventsSnapshot = results[2] as QuerySnapshot?;
      // ✅ FIXED: this line was missing — liquiditySnapshot was used
      // below but never assigned, causing a compile error.
      final liquiditySnapshot = results[3] as QuerySnapshot;

      final List<EconomicEvent> userEvents = [];
      if (userEventsSnapshot != null) {
        for (final doc in userEventsSnapshot.docs) {
          userEvents.add(EconomicEvent.fromFirestore(
              doc.id, doc.data() as Map<String, dynamic>));
        }
      }

      for (final doc in liquiditySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        userEvents.add(EconomicEvent(
          id: data['id'] ?? doc.id,
          title: data['title'] ?? 'Liquidity Event',
          type: EventType.liquidity,
          eventDate: DateTime.tryParse(data['maturityDate'] ?? '') ??
              DateTime.now(),
          description: 'Amount: \$${data['amount']}',
          triangleNote:
              'Increases LIQUIDITY upon maturity. Keep an eye on reinvestment options.',
          isUserCreated: true,
        ));
      }

      final allEvents = [...fetchedEvents, ...userEvents];

      for (final e in allEvents) {
        e.isAlertEnabled = _alertedEventIds.contains(e.id);
        e.isHeld = e.ticker != null && heldTickers.contains(e.ticker);
      }

      allEvents.sort((a, b) => a.eventDate.compareTo(b.eventDate));
      _events = allEvents;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addLiquidityEvent({
    required String title,
    required DateTime date,
    String? description,
  }) async {
    if (_userEventsRef == null) return;

    final event = EconomicEvent.forUser(
      id: const Uuid().v4(),
      title: title,
      date: date,
      description: description,
    );

    _events.add(event);
    _events.sort((a, b) => a.eventDate.compareTo(b.eventDate));
    notifyListeners();

    await _userEventsRef!.doc(event.id).set(event.toFirestore());
  }

  void setFilter(EventType? filter) {
    _selectedFilter = filter;
    notifyListeners();
  }

  void setHeldOnly(bool value) {
    _heldOnly = value;
    notifyListeners();
  }

  Future<void> toggleAlert(String userId, EconomicEvent event) async {
    if (event.isUserCreated) return;

    final newState = !event.isAlertEnabled;
    event.isAlertEnabled = newState;
    notifyListeners();

    await _api.toggleEventAlert(userId, event, newState);
  }

  EventIntegrationService get api => _api;
}