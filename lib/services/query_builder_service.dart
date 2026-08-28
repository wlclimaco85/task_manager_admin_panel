import '../config/api_links.dart';
import 'network_caller.dart';

/// SIS-08 Query Builder — cliente para os 4 endpoints REST expostos por
/// `QueryBuilderController` (`/api/ferramentas/query-builder`): listagem de
/// schemas/tabelas/colunas e execucao de SQL somente leitura.
///
/// Nota de seguranca (PLAN.md Fase 2, Task 12.1; ver tambem RESEARCH.md Item
/// 8 / Pitfall 4): a execucao de SQL livre (`POST .../executar`) ja e
/// protegida no backend por `@PreAuthorize("@tenantSecurity.isMaster()")` em
/// `QueryBuilderController.executarQuery` e por
/// `QueryBuilderServiceImpl.SQL_SOMENTE_LEITURA`/`PALAVRA_ESCRITA_SQL`, que
/// restringe a consulta a `SELECT`/`WITH` e bloqueia palavras de escrita
/// (INSERT/UPDATE/DELETE/DROP/...) mesmo dentro de CTEs — confirmado por
/// leitura direta de `QueryBuilderController.java` e
/// `QueryBuilderServiceImpl.java` nesta sessao (ver `SECURITY-AUDIT-W3R4.md`,
/// achados criticos 2 e 3, ja corrigidos e cobertos por
/// `QueryBuilderControllerSecurityTest`/`QueryBuilderServiceImplTest` no
/// backend). A validacao client-side em `QueryBuilderScreen` (Task 12.2) e
/// redundante — feedback mais rapido ao usuario, nao substitui a defesa do
/// backend.
class QueryBuilderService {
  QueryBuilderService({NetworkCaller? networkCaller})
      : _networkCaller = networkCaller ?? NetworkCaller();

  final NetworkCaller _networkCaller;

  Future<List<Map<String, dynamic>>> listarSchemas() async {
    final response =
        await _networkCaller.getRequest(ApiLinks.queryBuilderSchemas);
    return _extractListaAninhada(response.body);
  }

  Future<List<Map<String, dynamic>>> listarTabelas() async {
    final response =
        await _networkCaller.getRequest(ApiLinks.queryBuilderTabelas);
    return _extractListaAninhada(response.body);
  }

  Future<List<Map<String, dynamic>>> listarColunas(
      String schema, String tabela) async {
    final response = await _networkCaller
        .getRequest(ApiLinks.queryBuilderColunas(schema, tabela));
    return _extractListaAninhada(response.body);
  }

  /// Executa uma consulta `SELECT`/`WITH` contra o endpoint protegido do
  /// backend. Retorna o resultado bruto (`colunas`, `linhas`, `totalLinhas`,
  /// `pagina`, `tamanhoPagina`, `totalPaginas`) ou `{erro: mensagem}` quando
  /// o backend rejeita a consulta (SQL de escrita, erro de sintaxe, etc.).
  Future<Map<String, dynamic>> executar(
    String sql, {
    int pagina = 1,
    int tamanhoPagina = 50,
  }) async {
    final response = await _networkCaller.postRequest(
      ApiLinks.queryBuilderExecutar,
      {
        'sql': sql,
        'pagina': pagina,
        'tamanhoPagina': tamanhoPagina,
      },
    );

    final data = response.body?['data'];
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }

    if (!response.isSuccess) {
      final mensagem =
          response.body?['response']?['message']?.toString() ??
              'Erro ao executar consulta (HTTP ${response.statusCode})';
      return {'erro': mensagem};
    }

    return {'erro': 'Resposta inesperada do backend'};
  }

  /// `Response.data` do backend, para os endpoints de listagem
  /// (schemas/tabelas/colunas), e sempre `{"data": [...]}` — ver
  /// `QueryBuilderController` (`Map.of("data", lista)`). Como
  /// `NetworkResponse` ja desembrulha o corpo JSON inteiro em `body`, o
  /// resultado fica em `body['data']['data']`.
  List<Map<String, dynamic>> _extractListaAninhada(
      Map<String, dynamic>? body) {
    final data = body?['data'];
    final lista = data is Map ? data['data'] : null;
    if (lista is! List) return [];
    return lista
        .map((e) => e is Map
            ? Map<String, dynamic>.from(e)
            : <String, dynamic>{'valor': e})
        .toList();
  }
}
