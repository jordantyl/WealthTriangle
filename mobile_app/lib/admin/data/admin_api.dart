import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../shared/backend_headers.dart';

/// Admin endpoints (users/content/health/stats). The admin web build is the
/// only thing that imports this package, so unlike the mobile app's API
/// calls, there's no emulator-vs-browser BACKEND_BASE_URL split to worry
/// about here — always talk to defaultBackendBaseUrl.
class AdminApi {
  static Future<Map<String, dynamic>> _get(String path) async {
    final headers = await authedBackendHeaders();
    final response =
        await http.get(Uri.parse('$defaultBackendBaseUrl$path'), headers: headers);
    if (response.statusCode != 200) {
      throw Exception('Request failed (${response.statusCode}): ${response.body}');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> fetchHealth() => _get('/api/admin/health');

  static Future<Map<String, dynamic>> fetchStats() => _get('/api/admin/stats');

  static Future<Map<String, int>> fetchContentCounts() async {
    final data = await _get('/api/admin/content_counts');
    return Map<String, int>.from(data['counts'] as Map);
  }

  static Future<List<Map<String, dynamic>>> fetchUsers() async {
    final data = await _get('/api/admin/users');
    return List<Map<String, dynamic>>.from(data['users'] as List);
  }

  static Future<Map<String, dynamic>> fetchUserDetail(String uid) =>
      _get('/api/admin/users/$uid/detail');

  static Future<List<Map<String, dynamic>>> fetchContentDocs(String collection) async {
    final data = await _get('/api/admin/content/$collection');
    return List<Map<String, dynamic>>.from(data['docs'] as List);
  }

  static Future<void> createContentDoc(String collection, Map<String, dynamic> data) async {
    final headers = await authedBackendHeaders({'Content-Type': 'application/json'});
    final response = await http.post(
      Uri.parse('$defaultBackendBaseUrl/api/admin/content/$collection'),
      headers: headers,
      body: json.encode(data),
    );
    if (response.statusCode != 200) {
      throw Exception('Create failed (${response.statusCode}): ${response.body}');
    }
  }

  static Future<void> updateContentDoc(
      String collection, String docId, Map<String, dynamic> data) async {
    final headers = await authedBackendHeaders({'Content-Type': 'application/json'});
    final response = await http.put(
      Uri.parse('$defaultBackendBaseUrl/api/admin/content/$collection/$docId'),
      headers: headers,
      body: json.encode(data),
    );
    if (response.statusCode != 200) {
      throw Exception('Update failed (${response.statusCode}): ${response.body}');
    }
  }

  static Future<List<Map<String, dynamic>>> fetchAuditLog() async {
    final data = await _get('/api/admin/audit_log');
    return List<Map<String, dynamic>>.from(data['entries'] as List);
  }

  static Future<void> promoteToAdmin(String uid) async {
    final headers = await authedBackendHeaders();
    final response = await http.post(
      Uri.parse('$defaultBackendBaseUrl/api/admin/users/$uid/promote'),
      headers: headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Promote failed (${response.statusCode}): ${response.body}');
    }
  }

  static Future<void> demoteAdmin(String uid) async {
    final headers = await authedBackendHeaders();
    final response = await http.post(
      Uri.parse('$defaultBackendBaseUrl/api/admin/users/$uid/demote'),
      headers: headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Demote failed (${response.statusCode}): ${response.body}');
    }
  }

  static Future<void> deleteContentDoc(String collection, String docId) async {
    final headers = await authedBackendHeaders();
    final response = await http.delete(
      Uri.parse('$defaultBackendBaseUrl/api/admin/content/$collection/$docId'),
      headers: headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Delete failed (${response.statusCode}): ${response.body}');
    }
  }
}
