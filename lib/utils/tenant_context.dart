import '../services/auth_utility.dart';

/// Contexto de tenant do usuario logado. Injeta empresa/userId em toda
/// chamada HTTP. Adaptado de task_manager_flutter/lib/utils/tenant_context.dart
/// (mesma logica de headers/query params), sem a dependencia de
/// SessionExpiredHandler do cliente — o NetworkCaller deste app trata o 401
/// diretamente via callback injetavel (ver network_caller.dart).
class TenantContext {
  TenantContext._();

  static int? get empresaId => AuthUtility.userInfo?.login?.empresa?.id;
  static int? get userId => AuthUtility.userInfo?.login?.id;

  static bool get hasEmpresa => empresaId != null;
  static bool get hasUser => userId != null;

  static bool get isMaster =>
      AuthUtility.userInfo?.login?.tipoLogin == 'MASTER';

  /// `true` se o email do login corresponde ao dono do sistema.
  /// DEBITO TECNICO conhecido (documentado em .planning/ROADMAP.md): mesma
  /// heuristica hardcoded do app cliente. Recomendado migrar para role
  /// dedicada no backend (@PreAuthorize) antes de uso em producao real.
  static bool get isAdminEmail {
    final email = AuthUtility.userInfo?.login?.email;
    return email != null && email.toLowerCase() == 'wlclimaco@gmail.com';
  }

  static bool get isAdmin => isMaster || isAdminEmail;

  static Map<String, String> get headers {
    final token = AuthUtility.userInfo?.token;
    final tenantId = empresaId?.toString();
    return {
      if (token != null) 'Authorization': 'Bearer $token',
      if (tenantId != null) 'X-Tenant-ID': tenantId,
      'Accept-Encoding': 'gzip',
    };
  }

  static Map<String, String> get jsonHeaders {
    final token = AuthUtility.userInfo?.token;
    final tenantId = empresaId?.toString();
    return {
      if (token != null) 'Authorization': 'Bearer $token',
      if (tenantId != null) 'X-Tenant-ID': tenantId,
      'Content-Type': 'application/json',
    };
  }

  /// Injeta empresaId/userId na URL quando ainda nao foram informados
  /// explicitamente (mesmos nomes de parametro aceitos pelos controllers
  /// do backend do app cliente).
  static String applyToUrl(String url) {
    final uri = Uri.parse(url);
    final params = Map<String, String>.from(uri.queryParameters);

    final hasExplicitEmpresaScope = params.containsKey('empId') ||
        params.containsKey('empresaId') ||
        params.containsKey('empresa');
    if (hasEmpresa && !hasExplicitEmpresaScope) {
      params['empId'] = empresaId.toString();
    }

    final hasExplicitUserScope = params.containsKey('userId');
    if (hasUser && !hasExplicitUserScope) {
      params['userId'] = userId.toString();
    }

    return uri.replace(queryParameters: params).toString();
  }

  static Map<String, dynamic> applyToBody(Map<String, dynamic> body) {
    final result = Map<String, dynamic>.from(body);
    if (hasEmpresa && result['empresa'] == null) {
      result['empresa'] = {'id': empresaId};
    }
    return result;
  }

  static String get debugInfo =>
      'empresaId=$empresaId | userId=$userId | admin=$isAdmin';
}
