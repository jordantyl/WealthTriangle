import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'admin/presentation/admin_app.dart';
import 'academy/application/academy_state.dart';
import 'firebase_options_web.dart';

/// Separate entry point for the web-only admin panel — build/run it with
/// `flutter run -d chrome -t lib/admin_main.dart` (or `flutter build web
/// -t lib/admin_main.dart`), never bundled into the mobile app. Reuses
/// AcademyState as-is (isAdmin gating + seedDatabase) rather than
/// duplicating that logic in a second codebase.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await dotenv.load(fileName: 'lib/.env');

  runApp(
    ChangeNotifierProvider(
      create: (_) => AcademyState(),
      child: const AdminApp(),
    ),
  );
}
