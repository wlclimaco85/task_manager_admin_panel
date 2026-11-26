import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_links.dart';
import '../utils/tenant_context.dart';

class PlanilhaResumo {
  final int id;
  final String nome;

  /// Falso quando a planilha foi compartilhada por outra pessoa.
  final bool dono;
  final bool podeEditar;
  const PlanilhaResumo(this.id, this.nome, {this.dono = true, this.podeEditar = true});
}

/// Tipo de uma coluna: texto, numero, soma, data, check, lista ou pesquisa. A celula continua guardando texto.
class ColunaPlanilha {
  final String tipo;
  final List<String> opcoes;

  /// Pesquisa em um cadastro do sistema (caminho relativo da API) e o campo mostrado.
  final String? endpoint;
  final String? campoRotulo;

  const ColunaPlanilha(this.tipo, {this.opcoes = const [], this.endpoint, this.campoRotulo});

  factory ColunaPlanilha.fromJson(Map<String, dynamic> j) => ColunaPlanilha(
        '${j['tipo']}',
        opcoes: [for (final o in (j['opcoes'] as List?) ?? const []) '$o'],
        endpoint: j['endpoint']?.toString(),
        campoRotulo: j['campoRotulo']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'tipo': tipo,
        if (opcoes.isNotEmpty) 'opcoes': opcoes,
        if (endpoint != null) 'endpoint': endpoint,
        if (campoRotulo != null) 'campoRotulo': campoRotulo,
      };
}

/// Tipo de uma coluna de tabela do sistema; [valores] traduz o valor gravado no banco para o rotulo da opcao.
class TipoDaFonte {
  final ColunaPlanilha coluna;
  final Map<String, String> valores;
  const TipoDaFonte(this.coluna, [this.valores = const {}]);
}

class PlanilhaDados {
  final int? id;
  final String nome;
  final Map<String, String> celulas;

  /// Chave = letra da coluna.
  final Map<String, ColunaPlanilha> colunas;

  /// Volta no salvar: se outra pessoa salvou antes, o servidor recusa.
  final int? versao;
  final bool dono;
  final bool podeEditar;
  const PlanilhaDados(
      {this.id,
      required this.nome,
      required this.celulas,
      this.colunas = const {},
      this.versao,
      this.dono = true,
      this.podeEditar = true});
}

class UsuarioCompartilhar {
  final int id;
  final String nome;
  final String email;
  const UsuarioCompartilhar(this.id, this.nome, this.email);
}

/// [todos] nulo = nao compartilhada com todos; senao diz se todos podem editar. [usuarios]: login -> pode editar.
class CompartilhamentoPlanilha {
  final bool? todos;
  final Map<int, bool> usuarios;
  const CompartilhamentoPlanilha({this.todos, this.usuarios = const {}});
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
  /// Consulta e rotulos usados -- o Construtor guarda como fonte do modelo.
  final String? sql;
  final Map<String, String> rotulos;

  /// Posicao da coluna no resultado -> tipo, para a coluna continuar lista, pesquisa ou caixa de marcar.
  final Map<int, ColunaPlanilha> tipos;
  const ConsultaPlanilha(this.colunas, this.linhas, this.truncado,
      {this.sql, this.rotulos = const {}, this.tipos = const {}});
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
    return [
      for (final p in dados)
        PlanilhaResumo((p['id'] as num).toInt(), '${p['nome']}',
            dono: p['dono'] != false, podeEditar: p['podeEditar'] != false)
    ];
  }

  /// Usuarios do mesmo parceiro (ou internos da empresa) com quem se pode compartilhar.
  Future<List<UsuarioCompartilhar>> usuarios() async {
    final lista = _json(await _get('$_raiz/usuarios'), 'listar os usuários') as List;
    return [
      for (final u in lista)
        UsuarioCompartilhar((u['id'] as num).toInt(), '${u['nome'] ?? u['email']}', '${u['email'] ?? ''}')
    ];
  }

  Future<CompartilhamentoPlanilha> compartilhamento(int id) async => _compartilhamento(
      _json(await _get('$_raiz/$id/compartilhamento'), 'ler o compartilhamento'));

  Future<CompartilhamentoPlanilha> compartilhar(int id, CompartilhamentoPlanilha c) async {
    final r = await _enviar('PUT', '$_raiz/$id/compartilhamento', {
      'todos': c.todos,
      'usuarios': [
        for (final e in c.usuarios.entries) {'loginId': e.key, 'podeEditar': e.value}
      ],
    });
    return _compartilhamento(_json(r, 'compartilhar a planilha'));
  }

  static CompartilhamentoPlanilha _compartilhamento(dynamic j) => CompartilhamentoPlanilha(
        todos: j['todos'] as bool?,
        usuarios: {
          for (final u in (j['usuarios'] as List?) ?? const []) (u['loginId'] as num).toInt(): u['podeEditar'] == true
        },
      );

  /// Botao de Modulo Java com os valores digitados; devolve o resultado com as celulas a preencher.
  Future<Map<String, dynamic>> executarBotao(
      int planilhaId, int acaoId, List<Map<String, dynamic>> linhas, Map<String, dynamic> parametros) async {
    final r = await _enviar('POST',
        '$_raiz/$planilhaId/acoes/$acaoId', {'linhas': linhas, 'parametros': parametros});
    return _json(r, 'executar a ação') as Map<String, dynamic>;
  }

  /// Registros de um cadastro para a coluna do tipo pesquisa: devolve o texto de [campo] de cada um.
  Future<List<String>> pesquisar(String endpoint, String campo, String termo) async {
    // so caminho relativo da propria API (o servidor tambem valida ao gravar)
    if (!endpoint.startsWith('/api/') || endpoint.contains('..')) {
      throw const PlanilhaException('Endereço de pesquisa inválido.');
    }
    final raiz = _raiz.substring(0, _raiz.length - '/api/planilhas'.length);
    final separador = endpoint.contains('?') ? '&' : '?';
    final j = _json(
        await _get('$raiz$endpoint${separador}pagina=0&tamanho=30&busca=${Uri.encodeQueryComponent(termo)}'),
        'pesquisar');
    var lista = j;
    for (final chave in const ['data', 'dados', 'content']) {
      if (lista is Map && lista[chave] != null) lista = lista[chave];
    }
    if (lista is! List) return const [];
    final filtro = termo.trim().toLowerCase();
    return {
      for (final item in lista)
        if (item is Map && item[campo] != null) '${item[campo]}'
    }.where((v) => v.toLowerCase().contains(filtro)).toList();
  }

  Future<PlanilhaDados> abrir(int id) async =>
      _planilha(_json(await _get('$_raiz/$id'), 'abrir a planilha'));

  Future<PlanilhaDados> salvar(PlanilhaDados p) async {
    final corpo = {
      'nome': p.nome,
      'celulas': p.celulas,
      'colunas': {for (final e in p.colunas.entries) e.key: e.value.toJson()},
      if (p.id != null && p.versao != null) 'versao': p.versao,
    };
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
    _tiposDasFontes[tabela] = {
      for (final c in j['colunas'] as List)
        if (c['coluna'] != null)
          '${c['nome']}': TipoDaFonte(ColunaPlanilha.fromJson(c['coluna'] as Map<String, dynamic>), {
            for (final e in ((c['valores'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'
          })
    };
    return {for (final c in j['colunas'] as List) '${c['nome']}': '${c['rotulo']}'};
  }

  final Map<String, Map<String, TipoDaFonte>> _tiposDasFontes = {};

  /// Tipos (do Dicionario) das colunas da tabela ja consultada por [campos].
  Map<String, TipoDaFonte> tiposDe(String tabela) => _tiposDasFontes[tabela] ?? const {};

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
      id: (j['id'] as num?)?.toInt(),
      nome: '${j['nome']}',
      celulas: _celulas(j['celulas']),
      colunas: {
        for (final e in ((j['colunas'] as Map?) ?? const {}).entries)
          '${e.key}': ColunaPlanilha.fromJson(e.value as Map<String, dynamic>)
      },
      versao: (j['versao'] as num?)?.toInt(),
      dono: j['dono'] != false,
      podeEditar: j['podeEditar'] != false);

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
