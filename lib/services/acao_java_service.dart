import '../models/network_response.dart';
import '../config/api_links.dart';
import 'modulo_java_service.dart';
import 'network_caller.dart';

/// Parametro do popup de uma acao Java (tipos: TEXTO, INTEIRO, DECIMAL, LOGICO, DATA, LISTA).
class AcaoJavaParam {
  final int? id;
  final String descricao;
  final String nome;
  final String tipo;
  final bool obrigatorio;
  final bool sugerirUltimo;
  final String? opcoes;

  const AcaoJavaParam({
    this.id,
    required this.descricao,
    required this.nome,
    this.tipo = 'TEXTO',
    this.obrigatorio = false,
    this.sugerirUltimo = false,
    this.opcoes,
  });

  factory AcaoJavaParam.fromJson(Map<String, dynamic> j) => AcaoJavaParam(
        id: (j['id'] as num?)?.toInt(),
        descricao: j['descricao']?.toString() ?? '',
        nome: j['nome']?.toString() ?? '',
        tipo: (j['tipo']?.toString() ?? 'TEXTO').toUpperCase(),
        obrigatorio: j['obrigatorio'] == true,
        sugerirUltimo: j['sugerirUltimo'] == true,
        opcoes: j['opcoes']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'descricao': descricao,
        'nome': nome,
        'tipo': tipo,
        'obrigatorio': obrigatorio,
        'sugerirUltimo': sugerirUltimo,
        'opcoes': opcoes,
      };

  List<String> get listaOpcoes => (opcoes ?? '')
      .split(';')
      .map((o) => o.trim())
      .where((o) => o.isNotEmpty)
      .toList();
}

/// Botao de acao de uma tela que executa uma rotina Java (ver ARQUITETURA_PLATAFORMA_LOWCODE.md).
class AcaoJava {
  final int? id;
  final String telaNome;
  final String label;
  final String icon;
  final String? confirmMessage;
  final int? moduloJavaId;
  final String classe;
  final String? tabelaNome;
  final String idColuna;
  final bool exigeSelecao;
  final bool ativo;
  final int ordem;
  final List<AcaoJavaParam> params;

  const AcaoJava({
    this.id,
    required this.telaNome,
    required this.label,
    this.icon = 'bolt',
    this.confirmMessage,
    this.moduloJavaId,
    this.classe = '',
    this.tabelaNome,
    this.idColuna = 'id',
    this.exigeSelecao = true,
    this.ativo = true,
    this.ordem = 0,
    this.params = const [],
  });

  factory AcaoJava.fromJson(Map<String, dynamic> j) => AcaoJava(
        id: (j['id'] as num?)?.toInt(),
        telaNome: j['telaNome']?.toString() ?? '',
        label: j['label']?.toString() ?? 'Ação',
        icon: j['icon']?.toString() ?? 'bolt',
        confirmMessage: j['confirmMessage']?.toString(),
        moduloJavaId: (j['moduloJavaId'] as num?)?.toInt(),
        classe: j['classe']?.toString() ?? '',
        tabelaNome: j['tabelaNome']?.toString(),
        idColuna: j['idColuna']?.toString() ?? 'id',
        exigeSelecao: j['exigeSelecao'] != false,
        ativo: j['ativo'] != false,
        ordem: (j['ordem'] as num?)?.toInt() ?? 0,
        params: ((j['params'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AcaoJavaParam.fromJson)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'telaNome': telaNome,
        'label': label,
        'icon': icon,
        'confirmMessage': confirmMessage,
        'moduloJavaId': moduloJavaId,
        'classe': classe,
        'tabelaNome': tabelaNome,
        'idColuna': idColuna,
        'exigeSelecao': exigeSelecao,
        'ativo': ativo,
        'ordem': ordem,
        'params': params.map((p) => p.toJson()).toList(),
      };
}

class AcaoJavaResultado {
  final bool sucesso;
  final String mensagem;
  final bool recarregar;

  const AcaoJavaResultado(
      {required this.sucesso, required this.mensagem, required this.recarregar});

  factory AcaoJavaResultado.fromJson(Map<String, dynamic> j) =>
      AcaoJavaResultado(
        sucesso: j['sucesso'] == true,
        mensagem: j['mensagem']?.toString() ?? '',
        recarregar: j['recarregar'] == true,
      );
}

/// Evento de tabela (aba Eventos): chama uma classe EventoJava em insert/update/delete.
class EventoJava {
  final int? id;
  final String tabelaNome;
  final int? numEvento;
  final String descricao;
  final String momento; // ANTES | DEPOIS
  final String operacao; // INSERT | UPDATE | DELETE
  final int? moduloJavaId;
  final String classe;
  final bool ativo;
  final int ordem;
  final bool abortaEmErro;

  const EventoJava({
    this.id,
    required this.tabelaNome,
    this.numEvento,
    required this.descricao,
    this.momento = 'ANTES',
    this.operacao = 'INSERT',
    this.moduloJavaId,
    this.classe = '',
    this.ativo = true,
    this.ordem = 0,
    this.abortaEmErro = true,
  });

  factory EventoJava.fromJson(Map<String, dynamic> j) => EventoJava(
        id: (j['id'] as num?)?.toInt(),
        tabelaNome: j['tabelaNome']?.toString() ?? '',
        numEvento: (j['numEvento'] as num?)?.toInt(),
        descricao: j['descricao']?.toString() ?? '',
        momento: j['momento']?.toString() ?? 'ANTES',
        operacao: j['operacao']?.toString() ?? 'INSERT',
        moduloJavaId: (j['moduloJavaId'] as num?)?.toInt(),
        classe: j['classe']?.toString() ?? '',
        ativo: j['ativo'] != false,
        ordem: (j['ordem'] as num?)?.toInt() ?? 0,
        abortaEmErro: j['abortaEmErro'] != false,
      );

  Map<String, dynamic> toJson() => {
        'tabelaNome': tabelaNome,
        'numEvento': numEvento,
        'descricao': descricao,
        'momento': momento,
        'operacao': operacao,
        'moduloJavaId': moduloJavaId,
        'classe': classe,
        'ativo': ativo,
        'ordem': ordem,
        'abortaEmErro': abortaEmErro,
      };
}

/// Classe (acao/evento) inventariada de um jar do modulo.
class ClasseModulo {
  final String nome;
  final String tipo; // ACAO | EVENTO

  const ClasseModulo(this.nome, this.tipo);

  factory ClasseModulo.fromJson(Map<String, dynamic> j) =>
      ClasseModulo(j['nome']?.toString() ?? '', j['tipo']?.toString() ?? '');
}

/// Acoes e eventos Java (plataforma low-code, Etapas F2 e F3): execucao pelas telas e cadastro pelo Dicionario.
class AcaoJavaService {
  final NetworkCaller _rede;

  AcaoJavaService({NetworkCaller? rede}) : _rede = rede ?? NetworkCaller();

  // ------------------------------------------------------------ execucao (qualquer usuario)

  Future<List<AcaoJava>> listarAtivas(String telaNome) async {
    final r = await _rede.getRequest(ApiLinks.acoesJavaDaTela(telaNome));
    _exigir(r, 'listar as ações da tela');
    return _lista(r).map(AcaoJava.fromJson).toList();
  }

  Future<AcaoJavaResultado> executar(
      int acaoId, List<Object?> ids, Map<String, dynamic> parametros) async {
    final r = await _rede.postRequest(ApiLinks.acaoJavaExecutar('$acaoId'), {
      'ids': ids,
      'parametros': parametros,
    });
    if (!r.isSuccess) {
      throw ModuloJavaException(_mensagemErro(r, 'executar a ação'));
    }
    return AcaoJavaResultado.fromJson(r.body as Map<String, dynamic>);
  }

  // ------------------------------------------------------------ cadastro (MASTER): Acoes

  Future<List<AcaoJava>> listarTodas(String telaNome) async {
    final r = await _rede.getRequest(ApiLinks.acoesJavaAdmin(telaNome));
    _exigir(r, 'listar as ações');
    return _lista(r).map(AcaoJava.fromJson).toList();
  }

  Future<AcaoJava> salvarAcao(AcaoJava a) async {
    final NetworkResponse r = a.id == null
        ? await _rede.postRequest(ApiLinks.acoesJava, a.toJson())
        : await _rede.putRequest(ApiLinks.acaoJava('${a.id}'), a.toJson());
    _exigir(r, 'salvar a ação');
    return AcaoJava.fromJson(r.body as Map<String, dynamic>);
  }

  Future<void> excluirAcao(int id) async {
    final r = await _rede.deleteRequest(ApiLinks.acaoJava('$id'));
    _exigir(r, 'excluir a ação');
  }

  // ------------------------------------------------------------ cadastro (MASTER): Eventos

  Future<List<EventoJava>> listarEventos(String tabela) async {
    final r = await _rede.getRequest(ApiLinks.eventosTabela(tabela));
    _exigir(r, 'listar os eventos');
    return _lista(r).map(EventoJava.fromJson).toList();
  }

  Future<EventoJava> salvarEvento(EventoJava e) async {
    final NetworkResponse r = e.id == null
        ? await _rede.postRequest(ApiLinks.eventosTabelaRaiz, e.toJson())
        : await _rede.putRequest(ApiLinks.eventoTabela('${e.id}'), e.toJson());
    _exigir(r, 'salvar o evento');
    return EventoJava.fromJson(r.body as Map<String, dynamic>);
  }

  Future<void> excluirEvento(int id) async {
    final r = await _rede.deleteRequest(ApiLinks.eventoTabela('$id'));
    _exigir(r, 'excluir o evento');
  }

  // ------------------------------------------------------------ apoio

  Future<List<ClasseModulo>> listarClasses(int moduloId) async {
    final r = await _rede.getRequest(ApiLinks.moduloJavaClasses('$moduloId'));
    _exigir(r, 'listar as classes do módulo');
    return _lista(r).map(ClasseModulo.fromJson).toList();
  }

  List<Map<String, dynamic>> _lista(NetworkResponse r) => listaDeResposta(r);

  void _exigir(NetworkResponse r, String acao) {
    if (!r.isSuccess) throw ModuloJavaException(_mensagemErro(r, acao));
  }

  static String _mensagemErro(NetworkResponse r, String acao) {
    if (r.statusCode == 403) {
      return 'Somente o usuário MASTER pode gerenciar ações e eventos Java.';
    }
    return mensagemDeResposta(r) ?? 'Não foi possível $acao (HTTP ${r.statusCode}).';
  }
}
