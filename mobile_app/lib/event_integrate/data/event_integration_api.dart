import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
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

  /// Shared data source for both CSV and PDF exports — reads the SAME
  /// collection the Time Machine writes to (was 'simulation_history'
  /// hardcoded while the history screen read 'SIMULATIONHISTORY' — two
  /// different collections).
  Future<List<Map<String, dynamic>>> fetchSimulationHistoryForExport(
      String userId) async {
    try {
      final snap = await _db
          .collection(FirestoreConstants.usersCollection)
          .doc(userId)
          .collection(FirestoreConstants.simulationHistorySubCollection)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      return snap.docs.map((doc) {
        final d = doc.data();
        final created = d['createdAt'] is Timestamp
            ? (d['createdAt'] as Timestamp).toDate().toIso8601String()
            : '';
        return {
          'date': created,
          'ticker': d['stockTicker'] ?? '',
          'startDate': d['startDate'] ?? '',
          'endDate': d['endDate'] ?? '',
          'initialCapital': d['initialCapital'] ?? 0,
          'finalCapital': d['finalCapital'] ?? 0,
          // ✅ FIXED: cagr/maxDrawdown are already stored as percentages;
          // the old code multiplied by 100 again.
          'cagr': d['cagr'] ?? 0,
          'maxDrawdown': d['maxDrawdown'] ?? 0,
          'liquidityLabel': d['liquidityLabel'] ?? '',
          'slippagePct': d['slippagePct'] ?? 0,
        };
      }).toList();
    } catch (_) {
      return [
        {
          'date': DateTime.now().toIso8601String(),
          'ticker': 'AAPL',
          'startDate': '2020-01-01',
          'endDate': '2023-01-01',
          'initialCapital': 10000,
          'finalCapital': 15234,
          'cagr': 14.5,
          'maxDrawdown': -23.1,
          'liquidityLabel': 'High',
          'slippagePct': 0.01,
        }
      ];
    }
  }

  Future<String> exportSimulationAsCSV(String userId) async {
    final rows = await fetchSimulationHistoryForExport(userId);

    final buffer = StringBuffer();
    buffer.writeln(
        'Date,Ticker,Start Date,End Date,Initial Capital,Final Capital,CAGR (%),Max Drawdown (%),Liquidity,Slippage (%)');

    for (final r in rows) {
      buffer.writeln(
        '${r['date']},'
        '${r['ticker']},'
        '${r['startDate']},'
        '${r['endDate']},'
        '${r['initialCapital']},'
        '${r['finalCapital']},'
        '${r['cagr']},'
        '${r['maxDrawdown']},'
        '${r['liquidityLabel']},'
        '${r['slippagePct']}',
      );
    }

    return buffer.toString();
  }

  /// Renders the same simulation history into a formatted PDF report
  /// (Report §1.6.1.1 Event & Integration Module — "export of performance
  /// reports"). Returns raw PDF bytes ready to write to a file and share.
  Future<Uint8List> exportSimulationAsPDF(String userId) async {
    final rows = await fetchSimulationHistoryForExport(userId);
    final doc = pw.Document();

    final headers = [
      'Date',
      'Ticker',
      'Start',
      'End',
      'Initial (\$)',
      'Final (\$)',
      'CAGR (%)',
      'Max DD (%)',
      'Liquidity',
      'Slippage (%)',
    ];

    final data = rows.map((r) {
      final dateStr = (r['date'] as String).isNotEmpty
          ? (r['date'] as String).split('T').first
          : '-';
      return [
        dateStr,
        '${r['ticker']}',
        '${r['startDate']}',
        '${r['endDate']}',
        '${r['initialCapital']}',
        '${r['finalCapital']}',
        '${r['cagr']}',
        '${r['maxDrawdown']}',
        '${r['liquidityLabel']}',
        '${r['slippagePct']}',
      ];
    }).toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'WealthTriangle — Performance Report',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Time Machine simulation history & Iron Triangle metrics',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Generated ${DateTime.now().toIso8601String().split('T').first}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
            pw.Divider(),
          ],
        ),
        build: (context) => [
          if (data.isEmpty)
            pw.Text('No simulation history found for this account.')
          else
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: data,
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 9,
                  color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blue800),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding:
                  const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            ),
        ],
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
      ),
    );

    return doc.save();
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