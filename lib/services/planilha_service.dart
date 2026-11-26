import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_links.dart';
import '../utils/tenant_context.dart';

class PlanilhaResumo {
  final int id;
  final String nome;
  const PlanilhaResumo(this.id, this.nome);
}

class PlanilhaDados {
  final int? id;
  final String nome;
  final Map<String, String> celulas;
  const PlanilhaDados({this.id, required this.nome, required this.celulas});
}

class FontePlanilha {
  final String tabela;
  final String titulo;
  const FontePlanilha(this.tabela, this.titulo);
}

class ConsultaPlanilha {
  final List<String> colunas;
  final List<List<Object?>> linhas;
  final bool truncado;
  const ConsultaPlanilha(this.colunas, this.linhas, this.truncado);
}

class PlanilhaException implements Exception {
  final String mensagem;
  const PlanilhaException(this.mensagem);
  @override
  String toString() => mensagem;
}

/// Planilhas: cadastro, importacao/exportacao Excel (feitas no servidor) e consulta aos dados do sistema.
class PlanilhaService {
  String get _raiz => ApiLinks.planilhas;

  Future<List<PlanilhaResumo>> listar() async {
    final dados = _json(await _get(_raiz), 'listar as planilhas') as List;
    return [for (final p in dados) PlanilhaResumo((p['id'] as num).toInt(), '${p['nome']}')];
  }

  Future<PlanilhaDados> abrir(int id) async =>
      _planilha(_json(await _get('$_raiz/$id'), 'abrir a planilha'));

  Future<PlanilhaDados> salvar(PlanilhaDados p) async {
    final corpo = {'nome': p.nome, 'celulas': p.celulas};
    final r = p.id == null
        ? await _enviar('POST', _raiz, corpo)
        : await _enviar('PUT', '$_raiz/${p.id}', corpo);
    return _planilha(_json(r, 'salvar a planilha'));
  }

  Future<void> excluir(int id) async {
    final r = await http.delete(Uri.parse(TenantContext.applyToUrl('$_raiz/$id')), headers: TenantContext.jsonHeaders);
    if (r.statusCode != 204) _json(r, 'excluir a planilha');
  }

  Future<Map<String, String>> importar(List<int> bytes, String nomeArquivo) async {
    final pedido = http.MultipartRequest('POST', Uri.parse(TenantContext.applyToUrl('$_raiz/importar')))
      ..headers.addAll(TenantContext.headers..remove('Accept-Encoding'))
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: nomeArquivo));
    final r = await http.Response.fromStream(await pedido.send());
    return _celulas(_json(r, 'importar o Excel')['celulas']);
  }

  Future<List<int>> exportar(PlanilhaDados p) async {
    final r = await _enviar('POST', '$_raiz/exportar', {'nome': p.nome, 'celulas': p.celulas});
    if (r.statusCode != 200) _json(r, 'exportar para Excel');
    return r.bodyBytes;
  }

  /// SELECT somente leitura (so MASTER; o servidor exige o filtro :empresaId).
  Future<ConsultaPlanilha> consultar(String sql) async {
    final j = _json(await _enviar('POST', '$_raiz/consultar', {'sql': sql}), 'executar a consulta');
    return ConsultaPlanilha(
      [for (final c in j['colunas'] as List) '$c'],
      [for (final l in j['linhas'] as List) List<Object?>.from(l as List)],
      j['truncado'] == true,
    );
  }

  /// Tabelas liberadas (mesma regra do Modulo Java), com titulo do Dicionario de Dados.
  Future<List<FontePlanilha>> fontes() async {
    final lista = _json(await _get('$_raiz/fontes'), 'listar as tabelas') as List;
    return [for (final f in lista) FontePlanilha('${f['tabela']}', '${f['titulo']}')]
      ..sort((a, b) => a.titulo.toLowerCase().compareTo(b.titulo.toLowerCase()));
  }

  /// Colunas da tabela com os rotulos do dicionario (nome -> rotulo).
  Future<Map<String, String>> campos(String tabela) async {
    final j = _json(await _get('$_raiz/fontes/$tabela'), 'listar as colunas');
    return {for (final c in j['colunas'] as List) '${c['nome']}': '${c['rotulo']}'};
  }

  static Future<http.Response> _get(String url) =>
      http.get(Uri.parse(TenantContext.applyToUrl(url)), headers: TenantContext.headers);

  static Future<http.Response> _enviar(String metodo, String url, Map<String, dynamic> corpo) {
    final uri = Uri.parse(TenantContext.applyToUrl(url));
    final json = jsonEncode(corpo);
    return metodo == 'PUT'
        ? http.put(uri, headers: TenantContext.jsonHeaders, body: json)
        : http.post(uri, headers: TenantContext.jsonHeaders, body: json);
  }

  static PlanilhaDados _planilha(dynamic j) => PlanilhaDados(
      id: (j['id'] as num?)?.toInt(), nome: '${j['nome']}', celulas: _celulas(j['celulas']));

  static Map<String, String> _celulas(dynamic j) =>
      {for (final e in (j as Map).entries) '${e.key}': '${e.value}'};

  static dynamic _json(http.Response r, String acao) {
    dynamic corpo;
    try {
      corpo = jsonDecode(utf8.decode(r.bodyBytes));
    } on FormatException {
      corpo = null;
    }
    if (r.statusCode >= 200 && r.statusCode < 300 && corpo != null) return corpo;
    if (r.statusCode == 403) {
      throw PlanilhaException('Sem permissão para $acao.');
    }
    final msg = corpo is Map ? (corpo['message'] ?? corpo['error'])?.toString() : null;
    throw PlanilhaException(msg ?? 'Não foi possível $acao (HTTP ${r.statusCode}).');
  }
}
