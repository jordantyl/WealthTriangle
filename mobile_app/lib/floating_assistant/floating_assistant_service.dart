import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../shared/backend_headers.dart';

/// Talks to the same Flask backend as AIAssistantService, but for the
/// floating overlay: single-shot text or image queries with no chat
/// history and no app-control tools (record_holding, set_salary, etc.) —
/// the overlay is a "glance and go" quick-check, not a place to run
/// mutating actions from.
class FloatingAssistantService {
  static String get _baseUrl =>
      dotenv.env['BACKEND_BASE_URL'] ?? 'http://10.0.2.2:5000';

  Future<String> askText(String prompt) async {
    try {
      final headers = await authedBackendHeaders({'Content-Type': 'application/json'});
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/assistant'),
            headers: headers,
            body: json.encode({'prompt': prompt}),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['response'] as String;
      }
      return _errorMessage(response);
    } catch (e) {
      return 'Could not reach the assistant. Check your connection and try again.';
    }
  }

  Future<String> askImage(List<int> imageBytes, {String? prompt, String mimeType = 'image/jpeg'}) async {
    try {
      final headers = await authedBackendHeaders({'Content-Type': 'application/json'});
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/assistant/vision'),
            headers: headers,
            body: json.encode({
              'prompt': prompt ?? 'What is in this image?',
              'image_base64': base64Encode(imageBytes),
              'mime_type': mimeType,
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['response'] as String;
      }
      return _errorMessage(response);
    } catch (e) {
      return 'Could not reach the assistant. Check your connection and try again.';
    }
  }

  String _errorMessage(http.Response response) {
    try {
      final data = json.decode(response.body);
      return data['error']?.toString() ?? 'The assistant is temporarily unavailable.';
    } catch (_) {
      return 'The assistant is temporarily unavailable.';
    }
  }
}
