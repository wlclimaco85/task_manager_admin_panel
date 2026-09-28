import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/system_test_run_model.dart';
import '../config/api_links.dart';

class SystemTestRunService {
  final http.Client _client;
  SystemTestRunService({http.Client? client})
      : _client = client ?? http.Client();
  String get _base => '${ApiLinks.baseUrl}/api/system-tests/runs';
  Map<String, String> _headers(String token) =>
      {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};

  Future<SystemTestRunModel> start(
          String token, List<String> groups) async =>
      _run(
          await _client.post(Uri.parse(_base),
              headers: _headers(token),
              body:
                  jsonEncode({'environment': 'HOMOLOGACAO', 'groups': groups})),
          const {202, 409});
  Future<SystemTestRunModel> status(String token, String id) async => _run(
      await _client.get(Uri.parse('$_base/$id'), headers: _headers(token)),
      const {200});
  Future<List<SystemTestEventModel>> events(String token, String id) async {
    final response = await _client.get(Uri.parse('$_base/$id/events'),
        headers: _headers(token));
    _success(response, const {200});
    return (jsonDecode(response.body) as List)
        .whereType<Map<String, dynamic>>()
        .map(SystemTestEventModel.fromJson)
        .toList();
  }

  Future<void> cancel(String token, String id) async => _success(
      await _client.delete(Uri.parse('$_base/$id'), headers: _headers(token)),
      const {202});
  Future<SystemTestRunModel> retryCleanup(String token, String id) async =>
      _run(
          await _client.post(Uri.parse('$_base/$id/retry-cleanup'),
              headers: _headers(token)),
          const {200});

  SystemTestRunModel _run(http.Response response, Set<int> expected) {
    _success(response, expected);
    return SystemTestRunModel.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  void _success(http.Response response, Set<int> expected) {
    if (!expected.contains(response.statusCode)) {
      throw StateError('Erro ${response.statusCode}: ${response.body}');
    }
  }
}
