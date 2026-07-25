import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/economic_event.dart';
import '../../firestore/constants/firestore_constants.dart';
import '../../shared/backend_headers.dart';

class EventIntegrationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ✅ SECURITY FIX: No more RapidAPI/OpenAI keys on the device.
  // All third-party calls now go through YOUR Flask backend, which
  // holds the keys as server environment variables.
  static String get _baseUrl =>
      dotenv.env['BACKEND_BASE_URL'] ?? 'http://10.0.2.2:5000';

  // Set right before returning by fetchEventsForWatchlist(), so callers can
  // tell fallback demo events apart from real ones without changing the
  // method's return type.
  bool lastFetchWasMock = false;

  Future<List<EconomicEvent>> fetchEventsForWatchlist(
      List<String> tickers) async {
    final List<EconomicEvent> events = [];

    // Bumped from 5 since callers now pass held + watchlist tickers combined.
    for (final ticker in tickers.take(8)) {
      try {
        final response = await http
            .get(Uri.parse('$_baseUrl/api/calendar_events?ticker=$ticker'), headers: backendHeaders())
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final calData = data['body']?['calendarEvents'];
          if (calData != null) {
            final earningsTs =
                calData['earnings']?['earningsDate']?[0]?['raw'];
            if (earningsTs != null) {
              events.add(EconomicEvent(
                id: '${ticker}_earnings',
                title: '$ticker Earnings Report',
                ticker: ticker,
                type: EventType.earningsReport,
                eventDate:
                    DateTime.fromMillisecondsSinceEpoch(earningsTs * 1000),
                estimatedEPS: calData['earnings']?['earningsAverage']?['fmt']
                    ?.toString(),
                description:
                    'Quarterly earnings release for $ticker. Watch for EPS surprise impact.',
              ));
            }

            final exDivTs = calData['exDividendDate']?['raw'];
            final divAmount = (calData['trailingAnnualDividendRate']?['raw'] as num?)
                ?.toDouble();
            if (exDivTs != null) {
              events.add(EconomicEvent(
                id: '${ticker}_dividend',
                title: '$ticker Dividend Ex-Date',
                ticker: ticker,
                type: EventType.dividendExDate,
                eventDate:
                    DateTime.fromMillisecondsSinceEpoch(exDivTs * 1000),
                dividendAmount: divAmount,
                description:
                    'You must own $ticker shares before this date to receive the dividend.',
              ));
            }
          }
        }
      } catch (_) {
        // Continue with next ticker
      }
    }

    lastFetchWasMock = events.isEmpty;
    return events.isEmpty ? _getMockEvents(tickers) : events;
  }

  Future<void> toggleEventAlert(
      String userId, EconomicEvent event, bool enabled) async {
    final ref = _db
        .collection('users')
        .doc(userId)
        .collection('event_alerts')
        .doc(event.id);
    if (enabled) {
      await ref.set({
        'eventId': event.id,
        'title': event.title,
        'ticker': event.ticker,
        'eventDate': event.eventDate.toIso8601String(),
        'type': event.type.name,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.delete();
    }
  }

  Future<Set<String>> loadUserAlerts(String userId) async {
    try {
      final snap = await _db
          .collection('users')
          .doc(userId)
          .collection('event_alerts')
          .get();
      return snap.docs.map((d) => d.id).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<String> exportSimulationAsCSV(String userId) async {
    try {
      // ✅ FIXED: now reads the SAME collection the Time Machine writes to
      // (was 'simulation_history' hardcoded while the history screen read
      // 'SIMULATIONHISTORY' — two different collections).
      final snap = await _db
          .collection(FirestoreConstants.usersCollection)
          .doc(userId)
          .collection(FirestoreConstants.simulationHistorySubCollection)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      final buffer = StringBuffer();
      buffer.writeln(
          'Date,Ticker,Start Date,End Date,Initial Capital,Final Capital,CAGR (%),Max Drawdown (%),Liquidity,Slippage (%)');

      for (final doc in snap.docs) {
        final d = doc.data();
        final created = d['createdAt'] is Timestamp
            ? (d['createdAt'] as Timestamp).toDate().toIso8601String()
            : '';
        buffer.writeln(
          '$created,'
          '${d['stockTicker'] ?? ''},'
          '${d['startDate'] ?? ''},'
          '${d['endDate'] ?? ''},'
          '${d['initialCapital'] ?? ''},'
          '${d['finalCapital'] ?? ''},'
          // ✅ FIXED: cagr/maxDrawdown are already stored as percentages;
          // the old code multiplied by 100 again.
          '${d['cagr'] ?? 0},'
          '${d['maxDrawdown'] ?? 0},'
          '${d['liquidityLabel'] ?? ''},'
          '${d['slippagePct'] ?? 0}',
        );
      }

      return buffer.toString();
    } catch (_) {
      return 'Date,Ticker,Start Date,End Date,Initial Capital,Final Capital,CAGR (%),Max Drawdown (%),Liquidity,Slippage (%)\n'
          '${DateTime.now()},AAPL,2020-01-01,2023-01-01,10000,15234,14.5,-23.1,High,0.01\n';
    }
  }

  List<EconomicEvent> _getMockEvents(List<String> tickers) {
    final now = DateTime.now();
    return [
      EconomicEvent(
        id: 'aapl_earnings',
        title: 'AAPL Earnings Report',
        ticker: 'AAPL',
        type: EventType.earningsReport,
        eventDate: now.add(const Duration(days: 3)),
        estimatedEPS: '\$1.58',
        description:
            'Apple Q3 earnings release. Analysts expect strong iPhone revenue.',
        triangleNote:
            'A positive earnings surprise could boost RETURN, but may increase short-term volatility, affecting SAFETY.',
      ),
      EconomicEvent(
        id: 'msft_dividend',
        title: 'MSFT Dividend Ex-Date',
        ticker: 'MSFT',
        type: EventType.dividendExDate,
        eventDate: now.add(const Duration(days: 7)),
        dividendAmount: 0.75,
        description:
            'Own MSFT before this date to receive the \$0.75/share dividend.',
        triangleNote:
            'Dividends enhance RETURN. As a mega-cap, MSFT generally has high LIQUIDITY and SAFETY.',
      ),
      EconomicEvent(
        id: 'fed_rate',
        title: 'Federal Reserve Rate Decision',
        ticker: 'MARKET',
        type: EventType.federalReserve,
        eventDate: now.add(const Duration(days: 12)),
        description:
            'FOMC meeting outcome. High impact on all equities and bonds.',
        triangleNote:
            'Rate hikes improve RETURN on cash but can hurt stock/bond SAFETY. LIQUIDITY may tighten across the market.',
      ),
      EconomicEvent(
        id: 'tsla_earnings',
        title: 'TSLA Earnings Report',
        ticker: 'TSLA',
        type: EventType.earningsReport,
        eventDate: now.add(const Duration(days: 18)),
        estimatedEPS: '\$0.82',
        description:
            'Tesla Q3 delivery figures and margin outlook will be key.',
        triangleNote:
            'High-growth stocks like TSLA offer high RETURN potential but often come with lower SAFETY (higher volatility).',
      ),
      EconomicEvent(
        id: 'googl_split',
        title: 'GOOGL Stock Split',
        ticker: 'GOOGL',
        type: EventType.stockSplit,
        eventDate: now.add(const Duration(days: 25)),
        description: '20-for-1 stock split effective date.',
        triangleNote:
            'A stock split primarily affects LIQUIDITY by making shares more accessible to smaller investors. It does not directly change RETURN or SAFETY.',
      ),
      EconomicEvent(
        id: 'nvda_earnings',
        title: 'NVDA Earnings Report',
        ticker: 'NVDA',
        type: EventType.earningsReport,
        eventDate: now.add(const Duration(days: 30)),
        estimatedEPS: '\$5.12',
        description:
            'NVIDIA data center and AI chip revenue will be closely watched.',
        triangleNote:
            'Exceptional growth can lead to high RETURN, but dependence on a hot sector (AI) adds risk, impacting SAFETY.',
      ),
    ];
  }
}