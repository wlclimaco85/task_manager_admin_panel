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

/// Layout do relatorio (orientacao, subtitulo, rodape, agrupamento e colunas).
class RelConfig {
  final String orientacao; // RETRATO | PAISAGEM
  final String? subtitulo;
  final String? rodape;
  final String? agruparPor;
  final List<RelColuna> colunas;

  const RelConfig({this.orientacao = 'RETRATO', this.subtitulo, this.rodape, this.agruparPor, this.colunas = const []});

  factory RelConfig.fromJson(Map<String, dynamic>? j) => j == null
      ? const RelConfig()
      : RelConfig(
          orientacao: (j['orientacao']?.toString() ?? 'RETRATO').toUpperCase(),
          subtitulo: j['subtitulo']?.toString(),
          rodape: j['rodape']?.toString(),
          agruparPor: j['agruparPor']?.toString(),
          colunas: ((j['colunas'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(RelColuna.fromJson).toList(),
        );

  Map<String, dynamic> toJson() => {
        'orientacao': orientacao,
        'subtitulo': subtitulo,
        'rodape': rodape,
        'agruparPor': agruparPor,
        'colunas': colunas.map((c) => c.toJson()).toList(),
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
