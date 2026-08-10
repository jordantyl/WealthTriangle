import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// BACKEND_BASE_URL/BACKEND_API_KEY as compile-time --dart-define values,
/// used by the hosted admin web build (see docs/DEPLOY_ADMIN.md) instead of
/// bundling lib/.env as a fetchable static asset — a plain GET to a known
/// URL on a public host is a much lower bar than decompiling the APK, so
/// the web build keeps the key out of the deployed files entirely rather
/// than just repeating the mobile app's existing (already-accepted)
/// exposure. Empty string when not passed at build time, in which case
/// these getters fall back to .env (the mobile app's normal path — bundled
/// inside the APK, not touched by this).
const String _dartDefineBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');
const String _dartDefineApiKey = String.fromEnvironment('BACKEND_API_KEY');

/// Backend base URL: the --dart-define value when the build was given one,
/// else BACKEND_BASE_URL from .env, else a local dev default. 10.0.2.2 is
/// the Android emulator's alias for the host machine's localhost —
/// meaningless in a browser, where the web admin app (and any desktop/web
/// target) needs the real loopback address instead.
String get defaultBackendBaseUrl =>
    _dartDefineBaseUrl.isNotEmpty
        ? _dartDefineBaseUrl
        : dotenv.env['BACKEND_BASE_URL'] ??
            (kIsWeb ? 'http://localhost:5000' : 'http://10.0.2.2:5000');

String get _backendApiKey =>
    _dartDefineApiKey.isNotEmpty ? _dartDefineApiKey : (dotenv.env['BACKEND_API_KEY'] ?? '');

/// Header sent with every call to our Flask backend. The backend checks
/// this against its own BACKEND_API_KEY env var (see app.py's
/// before_request hook) so a stranger who finds the server's address can't
/// use it to burn your OpenAI/RapidAPI quota for free.
///
/// Protection is opt-in on the backend: if it hasn't set BACKEND_API_KEY,
/// it accepts any value (including the empty string sent here by default).
/// To actually enable it, set matching BACKEND_API_KEY values in both
/// backend/.env (or the shell environment) and mobile_app/lib/.env.
Map<String, String> backendHeaders([Map<String, String>? extra]) {
  return {
    'X-API-Key': _backendApiKey,
    ...?extra,
  };
}

/// Like [backendHeaders], but also attaches the signed-in user's Firebase
/// ID token as a Bearer token. Every backend route now requires this on top
/// of the static X-API-Key (see _require_firebase_user() in app.py) — the
/// key alone can't authenticate a request, since it's a value bundled into
/// every client build and has to be treated as effectively public. A live
/// Firebase ID token additionally requires a real, revocable,
/// rate-limitable signed-in account.
Future<Map<String, String>> authedBackendHeaders([Map<String, String>? extra]) async {
  final token = await FirebaseAuth.instance.currentUser?.getIdToken();
  return {
    'X-API-Key': _backendApiKey,
    if (token != null) 'Authorization': 'Bearer $token',
    ...?extra,
  };
}
