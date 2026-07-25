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
