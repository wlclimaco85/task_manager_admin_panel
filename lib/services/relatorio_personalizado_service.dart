import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/network_response.dart';
import '../config/api_links.dart';
import '../utils/tenant_context.dart';
import 'dashboard_personalizado_service.dart' show DashFiltro, ResultadoDash;
import 'modulo_java_service.dart';
import 'network_caller.dart';

/// Configuracao de uma coluna do relatorio: rotulo, formato (TEXTO, NUMERO, MOEDA, PERCENTUAL, DATA) e se soma no total.
class RelColuna {
  final String nome;
  final String rotulo;
  final String formato;
  final bool total;

  const RelColuna({required this.nome, required this.rotulo, this.formato = 'TEXTO', this.total = false});

  factory RelColuna.fromJson(Map<String, dynamic> j) => RelColuna(
        nome: j['nome']?.toString() ?? '',
        rotulo: j['rotulo']?.toString() ?? '',
        formato: (j['formato']?.toString() ?? 'TEXTO').toUpperCase(),
        total: j['total'] == true,
      );

  Map<String, dynamic> toJson() => {'nome': nome, 'rotulo': rotulo, 'formato': formato, 'total': total};
}

const Object _manter = Object();

/// Elemento posicionado numa banda (pontos, origem no canto superior esquerdo da banda).
/// tipos: TEXTO, CAMPO, LINHA, RETANGULO, PAGINA.
class RelElemento {
  final String tipo;
  final double x;
  final double y;
  final double largura;
  final double altura;
  final String? texto;
  final String? campo;
  final String? formato;
  final String? agregado;
  final double tamanho;
  final bool negrito;
  final String alinhamento; // ESQUERDA | CENTRO | DIREITA
  final String? cor; // #RRGGBB
  final String? fundo;

  const RelElemento({
    required this.tipo,
    this.x = 0,
    this.y = 0,
    this.largura = 100,
    this.altura = 14,
    this.texto,
    this.campo,
    this.formato,
    this.agregado,
    this.tamanho = 9,
    this.negrito = false,
    this.alinhamento = 'ESQUERDA',
    this.cor,
    this.fundo,
  });

  RelElemento copiar({
    double? x,
    double? y,
    double? largura,
    double? altura,
    Object? texto = _manter,
    Object? campo = _manter,
    Object? formato = _manter,
    Object? agregado = _manter,
    double? tamanho,
    bool? negrito,
    String? alinhamento,
    Object? cor = _manter,
    Object? fundo = _manter,
  }) =>
      RelElemento(
        tipo: tipo,
        x: x ?? this.x,
        y: y ?? this.y,
        largura: largura ?? this.largura,
        altura: altura ?? this.altura,
        texto: identical(texto, _manter) ? this.texto : texto as String?,
        campo: identical(campo, _manter) ? this.campo : campo as String?,
        formato: identical(formato, _manter) ? this.formato : formato as String?,
        agregado: identical(agregado, _manter) ? this.agregado : agregado as String?,
        tamanho: tamanho ?? this.tamanho,
        negrito: negrito ?? this.negrito,
        alinhamento: alinhamento ?? this.alinhamento,
        cor: identical(cor, _manter) ? this.cor : cor as String?,
        fundo: identical(fundo, _manter) ? this.fundo : fundo as String?,
      );

  factory RelElemento.fromJson(Map<String, dynamic> j) => RelElemento(
        tipo: (j['tipo']?.toString() ?? 'TEXTO').toUpperCase(),
        x: (j['x'] as num?)?.toDouble() ?? 0,
        y: (j['y'] as num?)?.toDouble() ?? 0,
        largura: (j['largura'] as num?)?.toDouble() ?? 100,
        altura: (j['altura'] as num?)?.toDouble() ?? 14,
        texto: j['texto']?.toString(),
        campo: j['campo']?.toString(),
        formato: j['formato']?.toString(),
        agregado: j['agregado']?.toString(),
        tamanho: (j['tamanho'] as num?)?.toDouble() ?? 9,
        negrito: j['negrito'] == true,
        alinhamento: (j['alinhamento']?.toString() ?? 'ESQUERDA').toUpperCase(),
        cor: j['cor']?.toString(),
        fundo: j['fundo']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'tipo': tipo,
        'x': x,
        'y': y,
        'largura': largura,
        'altura': altura,
        'texto': texto,
        'campo': campo,
        'formato': formato,
        'agregado': agregado,
        'tamanho': tamanho,
        'negrito': negrito,
        'alinhamento': alinhamento,
        'cor': cor,
        'fundo': fundo,
      };
}

class RelBanda {
  final double altura;
  final List<RelElemento> elementos;

  const RelBanda({this.altura = 20, this.elementos = const []});

  RelBanda copiar({double? altura, List<RelElemento>? elementos}) =>
      RelBanda(altura: altura ?? this.altura, elementos: elementos ?? this.elementos);

  factory RelBanda.fromJson(Map<String, dynamic>? j) => j == null
      ? const RelBanda()
      : RelBanda(
          altura: (j['altura'] as num?)?.toDouble() ?? 20,
          elementos: ((j['elementos'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(RelElemento.fromJson).toList(),
        );

  Map<String, dynamic> toJson() => {'altura': altura, 'elementos': elementos.map((e) => e.toJson()).toList()};
}

/// Layout por bandas do relatorio avancado.
class RelLayout {
  final RelBanda? titulo;
  final RelBanda? cabecalhoPagina;
  final RelBanda detalhe;
  final RelBanda? resumo;
  final RelBanda? rodapePagina;

  const RelLayout({this.titulo, this.cabecalhoPagina, this.detalhe = const RelBanda(altura: 16), this.resumo, this.rodapePagina});

  static const nomes = ['titulo', 'cabecalhoPagina', 'detalhe', 'resumo', 'rodapePagina'];

  RelBanda? banda(String nome) => switch (nome) {
        'titulo' => titulo,
        'cabecalhoPagina' => cabecalhoPagina,
        'detalhe' => detalhe,
        'resumo' => resumo,
        _ => rodapePagina,
      };

  RelLayout comBanda(String nome, RelBanda? b) => RelLayout(
        titulo: nome == 'titulo' ? b : titulo,
        cabecalhoPagina: nome == 'cabecalhoPagina' ? b : cabecalhoPagina,
        detalhe: nome == 'detalhe' ? (b ?? detalhe) : detalhe,
        resumo: nome == 'resumo' ? b : resumo,
        rodapePagina: nome == 'rodapePagina' ? b : rodapePagina,
      );

  factory RelLayout.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const RelLayout();
    RelBanda? b(String k) => j[k] is Map<String, dynamic> ? RelBanda.fromJson(j[k] as Map<String, dynamic>) : null;
    return RelLayout(
      titulo: b('titulo'),
      cabecalhoPagina: b('cabecalhoPagina'),
      detalhe: b('detalhe') ?? const RelBanda(altura: 16),
      resumo: b('resumo'),
      rodapePagina: b('rodapePagina'),
    );
  }

  Map<String, dynamic> toJson() => {
        'titulo': titulo?.toJson(),
        'cabecalhoPagina': cabecalhoPagina?.toJson(),
        'detalhe': detalhe.toJson(),
        'resumo': resumo?.toJson(),
        'rodapePagina': rodapePagina?.toJson(),
      };
}

/// Layout do relatorio (orientacao, subtitulo, rodape, agrupamento e colunas).
class RelConfig {
  final String orientacao; // RETRATO | PAISAGEM
  final String? subtitulo;
  final String? rodape;
  final String? agruparPor;
  final List<RelColuna> colunas;
  final String modo; // SIMPLES | AVANCADO
  final RelLayout? layout;

  const RelConfig({
    this.orientacao = 'RETRATO',
    this.subtitulo,
    this.rodape,
    this.agruparPor,
    this.colunas = const [],
    this.modo = 'SIMPLES',
    this.layout,
  });

  bool get avancado => modo == 'AVANCADO';

  RelConfig copiar({String? orientacao, String? modo, RelLayout? layout}) => RelConfig(
        orientacao: orientacao ?? this.orientacao,
        subtitulo: subtitulo,
        rodape: rodape,
        agruparPor: agruparPor,
        colunas: colunas,
        modo: modo ?? this.modo,
        layout: layout ?? this.layout,
      );

  factory RelConfig.fromJson(Map<String, dynamic>? j) => j == null
      ? const RelConfig()
      : RelConfig(
          orientacao: (j['orientacao']?.toString() ?? 'RETRATO').toUpperCase(),
          subtitulo: j['subtitulo']?.toString(),
          rodape: j['rodape']?.toString(),
          agruparPor: j['agruparPor']?.toString(),
          colunas: ((j['colunas'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(RelColuna.fromJson).toList(),
          modo: (j['modo']?.toString() ?? 'SIMPLES').toUpperCase(),
          layout: j['layout'] is Map<String, dynamic> ? RelLayout.fromJson(j['layout'] as Map<String, dynamic>) : null,
        );

  Map<String, dynamic> toJson() => {
        'orientacao': orientacao,
        'subtitulo': subtitulo,
        'rodape': rodape,
        'agruparPor': agruparPor,
        'colunas': colunas.map((c) => c.toJson()).toList(),
        'modo': modo,
        'layout': layout?.toJson(),
      };
}

class RelatorioPersonalizado {
  final int? id;
  final String titulo;
  final String? descricao;
  final String? grupo;
  final bool ativo;
  final String? sql; // so MASTER recebe o SQL
  final List<DashFiltro> filtros;
  final RelConfig config;

  const RelatorioPersonalizado({
    this.id,
    required this.titulo,
    this.descricao,
    this.grupo,
    this.ativo = true,
    this.sql,
    this.filtros = const [],
    this.config = const RelConfig(),
  });

  factory RelatorioPersonalizado.fromJson(Map<String, dynamic> j) => RelatorioPersonalizado(
        id: (j['id'] as num?)?.toInt(),
        titulo: j['titulo']?.toString() ?? '',
        descricao: j['descricao']?.toString(),
        grupo: j['grupo']?.toString(),
        ativo: j['ativo'] != false,
        sql: j['sql']?.toString(),
        filtros: ((j['parametros'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(DashFiltro.fromJson)
            .toList(),
        config: RelConfig.fromJson(j['config'] is Map<String, dynamic> ? j['config'] as Map<String, dynamic> : null),
      );

  Map<String, dynamic> toJson() => {
        'titulo': titulo,
        'descricao': descricao,
        'grupo': grupo,
        'ativo': ativo,
        'sql': sql,
        'parametros': filtros.map((f) => f.toJson()).toList(),
        'config': config.toJson(),
      };
}

/// PDF gerado: bytes + nome sugerido pelo servidor.
class PdfRelatorio {
  final Uint8List bytes;
  final String nomeArquivo;

  const PdfRelatorio(this.bytes, this.nomeArquivo);
}

/// Extrai o nome do arquivo do cabecalho Content-Disposition (ou devolve o padrao).
String nomeArquivoDoCabecalho(String? contentDisposition, String padrao) {
  if (contentDisposition == null) return padrao;
  final m = RegExp(r'filename\*?=(?:UTF-8\x27\x27)?"?([^";]+)"?', caseSensitive: false).firstMatch(contentDisposition);
  return m == null ? padrao : Uri.decodeComponent(m.group(1)!.trim());
}

/// Relatorios PDF personalizados (plataforma low-code, F7).
class RelatorioPersonalizadoService {
  final NetworkCaller _rede;

  RelatorioPersonalizadoService({NetworkCaller? rede}) : _rede = rede ?? NetworkCaller();

  Future<List<RelatorioPersonalizado>> ativos() async {
    final r = await _rede.getRequest(ApiLinks.relatoriosPersonalizados);
    _exigir(r, 'listar os relatórios');
    return listaDeResposta(r).map(RelatorioPersonalizado.fromJson).toList();
  }

  Future<List<RelatorioPersonalizado>> todos() async {
    final r = await _rede.getRequest(ApiLinks.relatoriosPersonalizadosTodos);
    _exigir(r, 'listar os relatórios');
    return listaDeResposta(r).map(RelatorioPersonalizado.fromJson).toList();
  }

  Future<RelatorioPersonalizado> buscar(int id) async {
    final r = await _rede.getRequest(ApiLinks.relatorioPersonalizado('$id'));
    _exigir(r, 'abrir o relatório');
    return RelatorioPersonalizado.fromJson(r.body!);
  }

  Future<RelatorioPersonalizado> buscarComSql(int id) async {
    final r = await _rede.getRequest(ApiLinks.relatorioPersonalizadoAdmin('$id'));
    _exigir(r, 'abrir o relatório');
    return RelatorioPersonalizado.fromJson(r.body!);
  }

  /// Gera o PDF no servidor (os filtros viram parametros tipados do SQL).
  Future<PdfRelatorio> gerarPdf(int id, Map<String, dynamic> parametros, {String nomePadrao = 'relatorio.pdf'}) async {
    final r = await http.post(
      Uri.parse(TenantContext.applyToUrl(ApiLinks.relatorioPersonalizadoPdf('$id'))),
      headers: TenantContext.jsonHeaders,
      body: jsonEncode(TenantContext.applyToBody({'parametros': parametros})),
    );
    if (r.statusCode != 200) {
      throw ModuloJavaException(_mensagemDeCorpo(r.body) ?? 'Não foi possível gerar o relatório (HTTP ${r.statusCode}).');
    }
    return PdfRelatorio(r.bodyBytes, nomeArquivoDoCabecalho(r.headers['content-disposition'], nomePadrao));
  }

  Future<RelatorioPersonalizado> salvar(RelatorioPersonalizado rel) async {
    final NetworkResponse r = rel.id == null
        ? await _rede.postRequest(ApiLinks.relatoriosPersonalizados, rel.toJson())
        : await _rede.putRequest(ApiLinks.relatorioPersonalizado('${rel.id}'), rel.toJson());
    _exigir(r, 'salvar o relatório');
    return RelatorioPersonalizado.fromJson(r.body!);
  }

  Future<void> excluir(int id) async {
    final r = await _rede.deleteRequest(ApiLinks.relatorioPersonalizado('$id'));
    _exigir(r, 'excluir o relatório');
  }

  /// Previa do SQL (ate 50 linhas): serve tambem para descobrir as colunas do relatorio.
  Future<ResultadoDash> testarSql(String sql, Map<String, dynamic> parametros) async {
    final r = await _rede.postRequest(ApiLinks.relatoriosPersonalizadosTestar, {'sql': sql, 'parametros': parametros});
    _exigir(r, 'testar o SQL');
    return ResultadoDash.fromJson({...r.body!, 'tipo': 'TABELA', 'titulo': 'Prévia'});
  }

  /// Previa em PDF do SQL + layout ainda nao salvos (construtor, MASTER): ate 50 linhas.
  Future<PdfRelatorio> previaPdf(String titulo, String sql, Map<String, dynamic> parametros, RelConfig config) async {
    final r = await http.post(
      Uri.parse(TenantContext.applyToUrl(ApiLinks.relatoriosPersonalizadosPrevia)),
      headers: TenantContext.jsonHeaders,
      body: jsonEncode(TenantContext.applyToBody(
          {'titulo': titulo, 'sql': sql, 'parametros': parametros, 'config': config.toJson()})),
    );
    if (r.statusCode != 200) {
      throw ModuloJavaException(_mensagemDeCorpo(r.body) ?? 'Não foi possível gerar a prévia (HTTP ${r.statusCode}).');
    }
    return PdfRelatorio(r.bodyBytes, 'previa.pdf');
  }

  void _exigir(NetworkResponse r, String acao) {
    if (r.isSuccess) return;
    if (r.statusCode == 403) {
      throw const ModuloJavaException('Somente o usuário MASTER pode alterar relatórios.');
    }
    throw ModuloJavaException(mensagemDeResposta(r) ?? 'Não foi possível $acao (HTTP ${r.statusCode}).');
  }

  static String? _mensagemDeCorpo(String corpo) {
    final m = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(corpo);
    return m?.group(1);
  }
}
