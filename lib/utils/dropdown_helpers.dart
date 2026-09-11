import '../config/api_links.dart';
import '../services/network_caller.dart';
import '../widgets/searchable_dropdown.dart' show PaginaDropdown;

/// Helper centralizado para carregar dropdowns comuns e buscas remotas paginadas
class DropdownHelpers {
  static Future<List<Map<String, dynamic>>> load(
    String url, {
    String displayField = 'nome',
  }) async {
    try {
      final resp = await NetworkCaller().getRequest(url);
      if (!resp.isSuccess || resp.body == null) return [];
      dynamic raw = resp.body;
      List lista = [];
      if (raw is List) {
        lista = raw;
      } else if (raw is Map) {
        final d = raw['data'] ?? raw['dados'] ?? raw['items'] ?? raw['content'];
        if (d is List) {
          lista = d;
        } else if (d is Map) {
          final inner = d['content'] ?? d['dados'] ?? d['items'];
          if (inner is List) lista = inner;
        }
      }
      final items = lista.whereType<Map>().map((e) {
        final item = Map<String, dynamic>.from(e);
        if (item[displayField] == null ||
            item[displayField].toString().isEmpty) {
          item[displayField] = item['nome'] ??
              item['razaoSocial'] ??
              item['descricao'] ??
              item['codigo'] ??
              item['name'] ??
              item['id']?.toString() ??
              '';
        }
        return item;
      }).toList();

      // Ordenar alfabeticamente por padrao
      items.sort((a, b) {
        final valA = (a[displayField] ?? '').toString().toLowerCase();
        final valB = (b[displayField] ?? '').toString().toLowerCase();
        return valA.compareTo(valB);
      });

      return items;
    } catch (_) {
      return [];
    }
  }

  // ---- Loaders especificos ----
  static Future<List<Map<String, dynamic>>> empresas() =>
      load(ApiLinks.allEmpresas, displayField: 'nome');

  static Future<List<Map<String, dynamic>>> parceiros() =>
      load(ApiLinks.allParceiros, displayField: 'nome');

  static Future<List<Map<String, dynamic>>> aplicativos() =>
      load(ApiLinks.allAplicativos, displayField: 'nome');

  static Future<List<Map<String, dynamic>>> setores() =>
      load(ApiLinks.allSetores, displayField: 'descricao');

  static Future<List<Map<String, dynamic>>> roles() =>
      load(ApiLinks.allRoles, displayField: 'description');

  /// Carrega parceiros filtrados pela empresa fornecida.
  static Future<List<Map<String, dynamic>>> parceirosPorEmpresa(
      String? empresaId) {
    if (empresaId == null || empresaId.isEmpty) return parceiros();
    return load('?empresaId=',
        displayField: 'nome');
  }

  /// Busca paginada + server-side (LIKE multi-campo: nome, razao social,
  /// CPF/CNPJ, email) de parceiros em lotes de 20 em 20.
  static Future<PaginaDropdown> parceirosBusca({
    String? busca,
    required int pagina,
    int tamanho = 20,
    String? empresaId,
    String? tipoParceiro,
  }) async {
    final url = '';
    try {
      final resp = await NetworkCaller().getRequest(url);
      if (!resp.isSuccess || resp.body == null) {
        return PaginaDropdown([], 0,
            erro: 'Erro ao buscar (status \).');
      }
      return parsePaginaDropdown(resp.body);
    } catch (e) {
      return PaginaDropdown([], 0, erro: 'Erro ao buscar: ');
    }
  }

  /// Monta a query string (?pagina=...&tamanho=...[&busca=...][&empresaId=...][&tipoParceiro=...])
  static String buildParceirosBuscaQuery({
    String? busca,
    required int pagina,
    int tamanho = 20,
    String? empresaId,
    String? tipoParceiro,
  }) {
    final termo = busca?.trim();
    final query = StringBuffer('?pagina=\&tamanho=');
    if (termo != null && termo.isNotEmpty) {
      query.write('&busca=');
    }
    if (empresaId != null && empresaId.isNotEmpty) {
      query.write('&empresaId=');
    }
    if (tipoParceiro != null && tipoParceiro.isNotEmpty) {
      query.write('&tipoParceiro=');
    }
    return query.toString();
  }

  /// Busca paginada + server-side de Empresa em lotes de 20 em 20.
  static Future<PaginaDropdown> empresasBusca({
    String? busca,
    required int pagina,
    int tamanho = 20,
  }) async {
    final url =
        '';
    try {
      final resp = await NetworkCaller().getRequest(url);
      if (!resp.isSuccess || resp.body == null) {
        return PaginaDropdown([], 0,
            erro: 'Erro ao buscar (status \).');
      }
      return parsePaginaDropdown(resp.body);
    } catch (e) {
      return PaginaDropdown([], 0, erro: 'Erro ao buscar: ');
    }
  }

  /// Monta a query string (?pagina=...&tamanho=...[&busca=...])
  static String buildEmpresasBuscaQuery({
    String? busca,
    required int pagina,
    int tamanho = 20,
  }) {
    final termo = busca?.trim();
    final query = StringBuffer('?pagina=\&tamanho=');
    if (termo != null && termo.isNotEmpty) {
      query.write('&busca=');
    }
    return query.toString();
  }

  /// Converte o corpo {data: {dados: [...], totalElements: N}} retornado
  /// pelo backend em [PaginaDropdown].
  static PaginaDropdown parsePaginaDropdown(dynamic raw) {
    if (raw is! Map) return const PaginaDropdown([], 0);
    final data = raw['data'] is Map ? raw['data'] : raw;
    if (data is! Map) return const PaginaDropdown([], 0);
    final lista = (data['dados'] as List?) ?? (data['items'] as List?) ?? (data['content'] as List?) ?? const [];
    final total = (data['totalElements'] as num?)?.toInt() ??
        (data['total'] as num?)?.toInt() ??
        lista.length;
    final items = lista.whereType<Map>().map((e) {
      final item = Map<String, dynamic>.from(e);
      if (item['nome'] == null || item['nome'].toString().isEmpty) {
        item['nome'] =
            item['razaoSocial'] ?? item['descricao'] ?? item['email'] ?? item['id']?.toString() ?? '';
      }
      return item;
    }).toList();
    return PaginaDropdown(items, total);
  }

  /// Resolve o rotulo de exibicao de um parceiro pelo id.
  static Future<String?> parceiroLabelPorId(String id) async {
    try {
      final resp =
          await NetworkCaller().getRequest('/');
      if (!resp.isSuccess || resp.body == null) return null;
      return parseParceiroLabel(resp.body);
    } catch (_) {
      return null;
    }
  }

  /// Extrai o rotulo de exibicao do parceiro.
  static String? parseParceiroLabel(dynamic raw) {
    if (raw is! Map) return null;
    final data = raw['data'] is Map ? raw['data'] : raw;
    if (data is! Map) return null;
    final nome = data['nome']?.toString();
    if (nome != null && nome.isNotEmpty) return nome;
    final razaoSocial = data['razaoSocial']?.toString();
    if (razaoSocial != null && razaoSocial.isNotEmpty) return razaoSocial;
    return data['email']?.toString();
  }

  /// Resolve o rotulo de exibicao de uma empresa pelo id.
  static Future<String?> empresaLabelPorId(String id) async {
    try {
      final resp =
          await NetworkCaller().getRequest('/');
      if (!resp.isSuccess || resp.body == null) return null;
      return parseEmpresaLabel(resp.body);
    } catch (_) {
      return null;
    }
  }

  /// Extrai o rotulo de exibicao da empresa.
  static String? parseEmpresaLabel(dynamic raw) {
    if (raw is! Map) return null;
    final data = raw['data'] is Map ? raw['data'] : raw;
    final map = data is Map ? data : raw;
    final nome = map['nome']?.toString();
    if (nome != null && nome.isNotEmpty) return nome;
    final razaoSocial = map['razaoSocial']?.toString();
    if (razaoSocial != null && razaoSocial.isNotEmpty) return razaoSocial;
    return map['email']?.toString();
  }
}
