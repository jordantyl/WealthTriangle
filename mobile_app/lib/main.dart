import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'user/application/wealth_state.dart';
import 'user/application/theme_service.dart'; // NEW IMPORT
import 'user/presentation/screens/login_screen.dart';
import 'user/presentation/screens/profile_screen.dart';

import 'academy/presentation/screens/academy_screen.dart';
import 'academy/application/academy_state.dart';

import 'income/presentation/screens/income_screen.dart';


import 'investment/presentation/screens/stock_dashboard.dart';
import 'investment/application/portfolio_state.dart';

import 'market_intelligence/application/market_intelligence_state.dart';
import 'event_integrate/application/event_intelligence_state.dart';

import 'market_intelligence/presentation/market_intelligence_screen.dart';
import 'event_integrate/presentation/event_calendar_screen.dart';

import 'investment/presentation/screens/time_machine_screen.dart';
import 'user/presentation/screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await dotenv.load(fileName: "lib/.env");
  runApp(const WealthTriangleApp());
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
              '/settings': (context) => const SettingsScreen(),
            },
          );
        },
      ),
    );
  }
}