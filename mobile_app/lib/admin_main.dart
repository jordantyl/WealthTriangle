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
  // lib/.env isn't published to this build's host (dotfiles are excluded on
  // purpose — see firebase.json — so BACKEND_API_KEY never sits at a public
  // URL). BACKEND_BASE_URL/BACKEND_API_KEY instead come from --dart-define
  // at build time (see backend_headers.dart); this just needs dotenv
  // initialized so any other dotenv.env[...] read elsewhere in
  // AcademyState/etc. doesn't throw "not initialized" instead of returning
  // null.
  try {
    await dotenv.load(fileName: 'lib/.env');
  } catch (_) {
    dotenv.loadFromString(isOptional: true);
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => AcademyState(),
      child: const AdminApp(),
    ),
  );
}
