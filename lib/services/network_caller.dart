import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/network_response.dart';
import '../utils/tenant_context.dart';

/// Callback opcional chamado quando o backend responde 401 fora de rotas
/// publicas — normalmente dispara logout + navegacao para a tela de login.
/// Injetavel para manter este servico testavel sem depender de
/// Navigator/BuildContext.
typedef UnauthorizedHandler = void Function();

/// Wrapper HTTP com autenticacao Bearer + tenant automatico. Adaptado de
/// task_manager_flutter/lib/services/network_caller.dart (mesmo contrato:
/// GET/POST/PUT/DELETE injetando TenantContext.headers e tratando 401 fora
/// de rotas publicas), sem a dependencia do widget de popup de login do
/// cliente.
class NetworkCaller {
  NetworkCaller({http.Client? client, this.onUnauthorized})
      : _client = client ?? http.Client();

  final http.Client _client;
  final UnauthorizedHandler? onUnauthorized;

  static const _publicRoutePatterns = [
    '/rest/auth/',
    '/api/public/',
  ];

  void _handleUnauthorized(int statusCode, String url) {
    if (statusCode != 401) return;
    final path = Uri.tryParse(url)?.path ?? url;
    if (_publicRoutePatterns.any((p) => path.contains(p))) return;
    onUnauthorized?.call();
  }

  Future<NetworkResponse> getRequest(String url) async {
    final enrichedUrl = TenantContext.applyToUrl(url);
    final response =
        await _client.get(Uri.parse(enrichedUrl), headers: TenantContext.headers);
    _handleUnauthorized(response.statusCode, enrichedUrl);
    return _toNetworkResponse(response);
  }

  Future<NetworkResponse> postRequest(
      String url, Map<String, dynamic> body) async {
    final enrichedUrl = TenantContext.applyToUrl(url);
    final response = await _client.post(
      Uri.parse(enrichedUrl),
      headers: TenantContext.jsonHeaders,
      body: jsonEncode(TenantContext.applyToBody(body)),
    );
    _handleUnauthorized(response.statusCode, enrichedUrl);
    return _toNetworkResponse(response);
  }

  Future<NetworkResponse> putRequest(
      String url, Map<String, dynamic> body) async {
    final enrichedUrl = TenantContext.applyToUrl(url);
    final response = await _client.put(
      Uri.parse(enrichedUrl),
      headers: TenantContext.jsonHeaders,
      body: jsonEncode(TenantContext.applyToBody(body)),
    );
    _handleUnauthorized(response.statusCode, enrichedUrl);
    return _toNetworkResponse(response);
  }

  Future<NetworkResponse> deleteRequest(String url) async {
    final enrichedUrl = TenantContext.applyToUrl(url);
    final response = await _client.delete(
      Uri.parse(enrichedUrl),
      headers: TenantContext.jsonHeaders,
    );
    _handleUnauthorized(response.statusCode, enrichedUrl);
    return _toNetworkResponse(response);
  }

  NetworkResponse _toNetworkResponse(http.Response response) {
    dynamic decoded;
    try {
      decoded = response.body.isNotEmpty ? jsonDecode(response.body) : null;
    } catch (_) {
      decoded = null;
    }
    final isSuccess = response.statusCode >= 200 && response.statusCode < 300;
    return NetworkResponse(isSuccess, response.statusCode, decoded);
  }
}
