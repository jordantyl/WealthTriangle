import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'user/application/wealth_state.dart';
import 'user/application/theme_service.dart'; // NEW IMPORT
import 'user/presentation/screens/login_screen.dart';
import 'user/presentation/screens/profile_screen.dart';

import 'academy/presentation/screens/academy_screen.dart';
import 'academy/presentation/screens/paper_trading_screen.dart';
import 'academy/application/academy_state.dart';

import 'income/presentation/screens/income_screen.dart';


import 'investment/presentation/screens/stock_dashboard.dart';
import 'investment/application/portfolio_state.dart';

import 'market_intelligence/application/market_intelligence_state.dart';
import 'event_integrate/application/event_intelligence_state.dart';

import 'market_intelligence/presentation/market_intelligence_screen.dart';
import 'event_integrate/presentation/event_calendar_screen.dart';
import 'event_integrate/presentation/export_report_screen.dart';

import 'investment/presentation/screens/time_machine_screen.dart';
import 'user/presentation/screens/settings_screen.dart';
import 'floating_assistant/floating_assistant_bridge.dart';
import 'floating_assistant/overlay_main.dart' as floating_assistant_overlay;

// The floating assistant bubble runs in its own Flutter engine, hosted by
// flutter_overlay_window's Service/WindowManager window. The plugin's
// native side launches it by looking up a top-level function named
// "overlayMain" — but only within *this* file's library, not wherever it's
// actually defined, so the pragma-marked function must live here and just
// forward to the real implementation.
@pragma('vm:entry-point')
void overlayMain() {
  floating_assistant_overlay.runOverlayIsolate();
}

void main() async {
  // runZonedGuarded catches async errors that happen outside Flutter's own
  // error zone (e.g. inside a bare Future that nothing awaits) so those
  // reach Crashlytics too, not just widget-build/layout errors.
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await dotenv.load(fileName: "lib/.env");

    // Android only — the floating assistant bubble uses a
    // SYSTEM_ALERT_WINDOW overlay, which has no web/iOS equivalent.
    if (!kIsWeb) {
      FloatingAssistantBridge.init();
    }

    // Crashlytics has no web implementation — this project currently only
    // ships Android + a web build, so gate it off there.
    if (!kIsWeb) {
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      // Don't spam the Firebase console with local debug-run crashes.
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
    }

    runApp(const WealthTriangleApp());
  }, (error, stack) {
    if (!kIsWeb) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    }
  });
}

class WealthTriangleApp extends StatelessWidget {
  const WealthTriangleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeService()),
        ChangeNotifierProvider(create: (_) => PortfolioState()),
        ChangeNotifierProvider(create: (_) => AcademyState()),
        ChangeNotifierProvider(create: (_) => MarketIntelligenceState()),
        ChangeNotifierProvider(create: (_) => EventIntegrationState()),
        // ✅ WealthState now depends on PortfolioState to calculate the Triangle Health Score
        ChangeNotifierProxyProvider<PortfolioState, WealthState>(
          // Creates WealthState for the first time
          create: (context) => WealthState(context.read<PortfolioState>()),
          // This is called when PortfolioState updates.
          // The `wealth` instance is the same one from `create`.
          // We don't need to return a new instance because WealthState
          // already listens to PortfolioState internally.
          update: (context, portfolio, wealth) => wealth!,
        ),
      ],
      child: Consumer<ThemeService>(
        builder: (context, themeService, child) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Wealth Triangle',
            
            // --- 1. LIGHT THEME DEFINITION ---
            theme: ThemeData(
              brightness: Brightness.light,
              scaffoldBackgroundColor: Colors.grey[100], // Soft white
              primaryColor: Colors.blueAccent,
              appBarTheme: const AppBarTheme(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black, // Dark text on white app bar
                elevation: 0,
              ),
              cardColor: Colors.white,
              // Fix the "Black Button" issue by defining a global style
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
              ),
              useMaterial3: true,
            ),

            // --- 2. DARK THEME DEFINITION ---
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              scaffoldBackgroundColor: const Color(0xFF1E1E2C), // Deep dark blue
              primaryColor: Colors.blueAccent,
              appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xFF1E1E2C),
                foregroundColor: Colors.white,
              ),
              cardColor: const Color(0xFF2D2D44), // The card color you liked
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
              ),
              useMaterial3: true,
            ),

            // --- 3. ACTIVE MODE ---
            themeMode: themeService.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            
            home: const LoginScreen(),
            routes: {
              // The Keys must match the 'route' strings in home_screen.dart
              '/investment': (context) => const StockDashboard(), // Assumes class name is StockScreen
              '/academy': (context) => const AcademyScreen(),
              '/income': (context) => const IncomeScreen(),
              '/profile': (context) => const ProfileScreen(),
              '/intelligence': (context) => MarketIntelligenceScreen(
                watchlistTickers: Provider.of<WealthState>(context, listen: false).watchlist,
                ),
              '/calendar': (context) => EventCalendarScreen(
                userId: FirebaseAuth.instance.currentUser?.uid ?? 'guest',
                watchlistTickers:Provider.of<WealthState>(context, listen: false).watchlist,
                ),
              '/timemachine': (context) => const TimeMachineScreen(),
              '/papertrading': (context) => const PaperTradingScreen(),
              '/settings': (context) => const SettingsScreen(),
              '/report': (context) => ExportReportScreen(
                userId: FirebaseAuth.instance.currentUser?.uid ?? 'guest',
                service: Provider.of<EventIntegrationState>(context, listen: false).api,
                ),
            },
          );
        },
      ),
    );
  }
}