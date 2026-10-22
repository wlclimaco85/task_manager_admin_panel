import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_links.dart';

/// Registro de acessos do painel do dono (usuarios por aplicacao, plataforma e versao, e acessos por dia).
class AcessosService {
  final http.Client _client;
  AcessosService({http.Client? client}) : _client = client ?? http.Client();

  String get _base => '${ApiLinks.baseUrl}/api/acessos';

  Map<String, String> _headers(String token) =>
      {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};

  Future<List<Map<String, dynamic>>> usuarios(String token, {String? aplicacao, int limite = 200}) async {
    final query = {'limite': '$limite', if (aplicacao != null && aplicacao.isNotEmpty) 'aplicacao': aplicacao};
    final uri = Uri.parse('$_base/usuarios').replace(queryParameters: query);
    return _lista(await _client.get(uri, headers: _headers(token)));
  }

  /// Totais (total, ultimos 7 dias e hoje) e os mesmos totais por aplicacao.
  Future<Map<String, dynamic>> resumo(String token) async {
    final response = await _client.get(Uri.parse('$_base/resumo'), headers: _headers(token));
    if (response.statusCode != 200) {
      throw Exception('Falha ao carregar o resumo de acessos (HTTP ${response.statusCode}).');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<List<Map<String, dynamic>>> diario(String token, {int dias = 30}) async {
    final uri = Uri.parse('$_base/diario').replace(queryParameters: {'dias': '$dias'});
    return _lista(await _client.get(uri, headers: _headers(token)));
  }

  List<Map<String, dynamic>> _lista(http.Response response) {
    if (response.statusCode != 200) {
      throw Exception('Falha ao carregar acessos (HTTP ${response.statusCode}).');
    }
    return (jsonDecode(response.body) as List).whereType<Map<String, dynamic>>().toList();
  }
}
