/// Wrapper generico de resposta de rede. Copiado verbatim (sem alteracao
/// de logica) de task_manager_flutter/lib/models/network_response.dart —
/// e generico o suficiente para nao precisar de adaptacao.
class NetworkResponse {
  final bool isSuccess;
  final int statusCode;
  final Map<String, dynamic>? body;

  NetworkResponse(this.isSuccess, this.statusCode, dynamic rawBody)
      : body = _toMap(rawBody);

  /// Converte qualquer resposta JSON para `Map&lt;String, dynamic&gt;`.
  /// Se o backend retornar uma lista diretamente, envolve em `{data: [...]}`.
  static Map<String, dynamic>? _toMap(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List) return {'data': raw};
    return {'data': raw};
  }
}
