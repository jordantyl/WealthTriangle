import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Header sent with every call to our Flask backend. The backend checks
/// this against its own BACKEND_API_KEY env var (see app.py's
/// before_request hook) so a stranger who finds the server's address can't
/// use it to burn our OpenAI/RapidAPI quota for free.
///
/// Protection is opt-in on the backend: if it hasn't set BACKEND_API_KEY,
/// it accepts any value (including the empty string sent here by default).
/// To actually enable it, set matching BACKEND_API_KEY values in both
/// backend/.env (or the shell environment) and mobile_app/lib/.env.
Map<String, String> backendHeaders([Map<String, String>? extra]) {
  return {
    'X-API-Key': dotenv.env['BACKEND_API_KEY'] ?? '',
    ...?extra,
  };
}

/// Like [backendHeaders], but also attaches the signed-in user's Firebase
/// ID token as a Bearer token. Use this for endpoints that cost real AI
/// quota or can write shared data (/api/assistant, /api/summarize,
/// /api/admin/seed) — the backend requires this token on those routes once
/// Firebase Admin is configured server-side. The static X-API-Key alone
/// isn't a real secret against a determined actor, since lib/.env ships
/// inside the app as a bundled asset (extractable from the APK, or
/// directly fetchable by URL if the Flutter web build is ever hosted); a
/// live Firebase ID token additionally requires a real, revocable,
/// rate-limitable user account.
Future<Map<String, String>> authedBackendHeaders([Map<String, String>? extra]) async {
  final token = await FirebaseAuth.instance.currentUser?.getIdToken();
  return {
    'X-API-Key': dotenv.env['BACKEND_API_KEY'] ?? '',
    if (token != null) 'Authorization': 'Bearer $token',
    ...?extra,
  };
}
