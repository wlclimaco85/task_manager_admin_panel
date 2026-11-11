import '../models/network_response.dart';
import '../config/api_links.dart';
import 'modulo_java_service.dart';
import 'network_caller.dart';

/// Filtro do topo de um dashboard (tipos: TEXTO, INTEIRO, DECIMAL, DATA, LOGICO).
class DashFiltro {
  final String nome;
  final String descricao;
  final String tipo;
  final String? padrao;

  const DashFiltro({required this.nome, required this.descricao, this.tipo = 'TEXTO', this.padrao});

  factory DashFiltro.fromJson(Map<String, dynamic> j) => DashFiltro(
        nome: j['nome']?.toString() ?? '',
        descricao: j['descricao']?.toString() ?? '',
        tipo: (j['tipo']?.toString() ?? 'TEXTO').toUpperCase(),
        padrao: j['padrao']?.toString(),
      );

  Map<String, dynamic> toJson() => {'nome': nome, 'descricao': descricao, 'tipo': tipo, 'padrao': padrao};
}

/// Componente: KPI, TABELA, LINHA, BARRAS, COLUNAS, PIZZA ou DONUT, alimentado por um SQL do servidor.
class DashComponente {
  final int? id;
  final String tipo;
  final String titulo;
  final String? sql; // so MASTER recebe o SQL
  final int ordem;
  final int largura; // 1 = meia tela, 2 = tela cheia

  const DashComponente({
    this.id,
    required this.tipo,
    required this.titulo,
    this.sql,
    this.ordem = 0,
    this.largura = 1,
  });

  factory DashComponente.fromJson(Map<String, dynamic> j) => DashComponente(
        id: (j['id'] as num?)?.toInt(),
        tipo: (j['tipo']?.toString() ?? 'TABELA').toUpperCase(),
        titulo: j['titulo']?.toString() ?? '',
        sql: j['sql']?.toString(),
        ordem: (j['ordem'] as num?)?.toInt() ?? 0,
        largura: (j['largura'] as num?)?.toInt() ?? 1,
      );

  Map<String, dynamic> toJson() => {'tipo': tipo, 'titulo': titulo, 'sql': sql, 'ordem': ordem, 'largura': largura};
}

class DashboardPersonalizado {
  final int? id;
  final String titulo;
  final String? descricao;
  final String? grupo;
  final bool ativo;
  final List<DashFiltro> filtros;
  final List<DashComponente> componentes;

  const DashboardPersonalizado({
    this.id,
    required this.titulo,
    this.descricao,
    this.grupo,
    this.ativo = true,
    this.filtros = const [],
    this.componentes = const [],
  });

  factory DashboardPersonalizado.fromJson(Map<String, dynamic> j) => DashboardPersonalizado(
        id: (j['id'] as num?)?.toInt(),
        titulo: j['titulo']?.toString() ?? '',
        descricao: j['descricao']?.toString(),
        grupo: j['grupo']?.toString(),
        ativo: j['ativo'] != false,
        filtros: ((j['parametros'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(DashFiltro.fromJson)
            .toList(),
        componentes: ((j['componentes'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(DashComponente.fromJson)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'titulo': titulo,
        'descricao': descricao,
        'grupo': grupo,
        'ativo': ativo,
        'parametros': filtros.map((f) => f.toJson()).toList(),
        'componentes': componentes.map((c) => c.toJson()).toList(),
      };
}

/// Resultado de um componente: colunas + linhas (ou o erro daquele componente).
class ResultadoDash {
  final int? id;
  final String tipo;
  final String titulo;
  final int largura;
  final List<String> colunas;
  final List<List<dynamic>> linhas;
  final bool truncado;
  final String? erro;

  const ResultadoDash({
    this.id,
    required this.tipo,
    required this.titulo,
    this.largura = 1,
    this.colunas = const [],
    this.linhas = const [],
    this.truncado = false,
    this.erro,
  });

  factory ResultadoDash.fromJson(Map<String, dynamic> j) => ResultadoDash(
        id: (j['id'] as num?)?.toInt(),
        tipo: (j['tipo']?.toString() ?? 'TABELA').toUpperCase(),
        titulo: j['titulo']?.toString() ?? '',
        largura: (j['largura'] as num?)?.toInt() ?? 1,
        colunas: ((j['colunas'] as List?) ?? const []).map((c) => c.toString()).toList(),
        linhas: ((j['linhas'] as List?) ?? const []).whereType<List>().map((l) => List<dynamic>.from(l)).toList(),
        truncado: j['truncado'] == true,
        erro: j['erro']?.toString(),
      );
}

/// Dashboards personalizados (plataforma low-code, F6).
class DashboardPersonalizadoService {
  final NetworkCaller _rede;

  DashboardPersonalizadoService({NetworkCaller? rede}) : _rede = rede ?? NetworkCaller();

  Future<List<DashboardPersonalizado>> ativos() async {
    final r = await _rede.getRequest(ApiLinks.dashboardsPersonalizados);
    _exigir(r, 'listar os dashboards');
    return listaDeResposta(r).map(DashboardPersonalizado.fromJson).toList();
  }

  Future<List<DashboardPersonalizado>> todos() async {
    final r = await _rede.getRequest(ApiLinks.dashboardsPersonalizadosTodos);
    _exigir(r, 'listar os dashboards');
    return listaDeResposta(r).map(DashboardPersonalizado.fromJson).toList();
  }

  Future<DashboardPersonalizado> buscar(int id) async {
    final r = await _rede.getRequest(ApiLinks.dashboardPersonalizado('$id'));
    _exigir(r, 'abrir o dashboard');
    return DashboardPersonalizado.fromJson(r.body!);
  }

  /// Definicao com o SQL (edicao, MASTER).
  Future<DashboardPersonalizado> buscarComSql(int id) async {
    final r = await _rede.getRequest(ApiLinks.dashboardPersonalizadoAdmin('$id'));
    _exigir(r, 'abrir o dashboard');
    return DashboardPersonalizado.fromJson(r.body!);
  }

  Future<List<ResultadoDash>> executar(int id, Map<String, dynamic> parametros) async {
    final r = await _rede.postRequest(ApiLinks.dashboardPersonalizadoExecutar('$id'), {'parametros': parametros});
    _exigir(r, 'carregar o dashboard');
    return listaDeResposta(r).map(ResultadoDash.fromJson).toList();
  }

  Future<DashboardPersonalizado> salvar(DashboardPersonalizado d) async {
    final NetworkResponse r = d.id == null
        ? await _rede.postRequest(ApiLinks.dashboardsPersonalizados, d.toJson())
        : await _rede.putRequest(ApiLinks.dashboardPersonalizado('${d.id}'), d.toJson());
    _exigir(r, 'salvar o dashboard');
    return DashboardPersonalizado.fromJson(r.body!);
  }

  Future<void> excluir(int id) async {
    final r = await _rede.deleteRequest(ApiLinks.dashboardPersonalizado('$id'));
    _exigir(r, 'excluir o dashboard');
  }

  /// Previa de um SQL (ate 50 linhas): devolve o resultado ou lanca a mensagem do servidor.
  Future<ResultadoDash> testarSql(String sql, Map<String, dynamic> parametros) async {
    final r = await _rede.postRequest(ApiLinks.dashboardsPersonalizadosTestar, {'sql': sql, 'parametros': parametros});
    _exigir(r, 'testar o SQL');
    return ResultadoDash.fromJson({...r.body!, 'tipo': 'TABELA', 'titulo': 'Prévia'});
  }

  void _exigir(NetworkResponse r, String acao) {
    if (r.isSuccess) return;
    if (r.statusCode == 403) {
      throw const ModuloJavaException('Somente o usuário MASTER pode alterar dashboards.');
    }
    throw ModuloJavaException(mensagemDeResposta(r) ?? 'Não foi possível $acao (HTTP ${r.statusCode}).');
  }
}
