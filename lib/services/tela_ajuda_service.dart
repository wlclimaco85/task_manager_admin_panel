import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/tela_ajuda_model.dart';
import '../config/api_links.dart';
import '../utils/tenant_context.dart';

class TelaAjudaService {
  Future<TelaAjudaModel?> buscarPorTela(String telaNome) async {
    final trimmed = telaNome.trim();
    if (trimmed.isEmpty) return null;

    final response = await http.get(
      Uri.parse(TenantContext.applyToUrl(ApiLinks.telaAjudaPorTela(trimmed))),
      headers: TenantContext.jsonHeaders,
    );

    if (response.statusCode == 204 || response.statusCode == 404) {
      return null;
    }

    if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map<String, dynamic>) {
        return TelaAjudaModel.fromJson(body);
      }
      if (body is Map) {
        return TelaAjudaModel.fromJson(Map<String, dynamic>.from(body));
      }
    }

    return null;
  }
}
