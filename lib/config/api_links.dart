/// Links de API do Painel do Dono (task_manager_admin_panel).
///
/// Reaproveita o MESMO backend/contrato JWT do app cliente
/// (task_manager_flutter/lib/utils/api_links.dart) — mesmo host, mesmo
/// context-path, mesmo endpoint de login.
///
/// ATENCAO (incidente historico documentado no CLAUDE.md do workspace):
/// `_backendUrl`, `_backendContextPath` e `_windowsDownloadUrl` usam
/// `String.fromEnvironment(...)`, que SO funciona como const constructor.
/// Declarar como `final` compila mas quebra em RUNTIME no DDC (flutter run
/// debug web) com "Unsupported operation: String.fromEnvironment can only
/// be used as a const constructor" — isso ja quebrou login em producao por
/// 8 dias no app cliente (2026-08-13/21). Antes de qualquer find-replace de
/// modificador `const`->`final` neste arquivo, rodar
/// `grep -n ".fromEnvironment(" lib/config/api_links.dart` e manter esses
/// 3 campos como `const`.
class ApiLinks {
  ApiLinks._();

  static const String _backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://127.0.0.1:9001',
  );

  static const String _backendContextPath = String.fromEnvironment(
    'BACKEND_CONTEXT_PATH',
    defaultValue: '/boletobancos',
  );

  static final String _baseUrl = '$_backendUrl$_backendContextPath';

  static String get baseUrl => _baseUrl;

  // Auth — mesmo endpoint do app cliente.
  static String get login => '$_baseUrl/rest/auth/login';

  // Exemplo de dominio de demonstracao (Fase 1: prova grid/form/detail).
  // Endpoints reais de Contatos/Licenca/OS/Modulos entram na Fase 3.
  static String get allContatos => '$_baseUrl/api/contatos';
  static String get createContato => '$_baseUrl/api/contatos';
  static String updateContato(String id) => '$_baseUrl/api/contatos/$id';
  static String deleteContato(String id) => '$_baseUrl/api/contatos/$id';
}
