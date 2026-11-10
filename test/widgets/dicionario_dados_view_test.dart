import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/services/acao_java_service.dart';
import 'package:task_manager_admin_panel/services/dicionario_campo_service.dart';
import 'package:task_manager_admin_panel/services/modulo_java_service.dart';
import 'package:task_manager_admin_panel/widgets/dicionario_dados_view.dart';

class _AcoesFalso extends AcaoJavaService {
  final List<AcaoJava> acoes;
  final List<EventoJava> eventos;
  final List<AcaoJava> salvasAcoes = [];
  final List<EventoJava> salvosEventos = [];
  String? telaConsultada;
  String? tabelaConsultada;
  bool falhaListagem = false;

  _AcoesFalso({this.acoes = const [], this.eventos = const []});

  @override
  Future<List<AcaoJava>> listarTodas(String telaNome) async {
    telaConsultada = telaNome;
    if (falhaListagem) throw const ModuloJavaException('Somente o usuário MASTER pode gerenciar ações e eventos Java.');
    return acoes;
  }

  @override
  Future<List<EventoJava>> listarEventos(String tabela) async {
    tabelaConsultada = tabela;
    return eventos;
  }

  @override
  Future<List<ClasseModulo>> listarClasses(int moduloId) async => const [
        ClasseModulo('br.com.dhara.CobrancaAcao', 'ACAO'),
        ClasseModulo('br.com.dhara.StatusEvento', 'EVENTO'),
      ];

  @override
  Future<AcaoJava> salvarAcao(AcaoJava a) async {
    salvasAcoes.add(a);
    return a;
  }

  @override
  Future<EventoJava> salvarEvento(EventoJava e) async {
    salvosEventos.add(e);
    return e;
  }
}

class _CamposFalso extends DicionarioCampoService {
  List<CampoDicionario> lista = const [
    CampoDicionario(id: 1, fieldName: 'nome', label: 'Nome', labelOriginal: 'Nome', fieldType: 'text'),
    CampoDicionario(
        id: 2,
        fieldName: 'codParceiro',
        label: 'Parceiro',
        labelOriginal: 'Parceiro',
        fieldType: 'number',
        ligacao: LigacaoCampo(campo: 'codParceiro', tabelaDestino: 'parceiro', endpoint: '/api/parceiro')),
  ];
  String? telaConsultada;
  final List<List<String>> labelsAlterados = [];
  final List<List<String>> camposIncluidos = [];
  final List<LigacaoCampo> ligacoesSalvas = [];
  final List<String> ligacoesRemovidas = [];
  bool falhaInclusao = false;

  @override
  Future<List<CampoDicionario>> campos(String tela) async {
    telaConsultada = tela;
    return lista;
  }

  @override
  Future<CampoDicionario> alterarLabel(String tela, String campo, String label) async {
    labelsAlterados.add([tela, campo, label]);
    return lista.first;
  }

  @override
  Future<CampoDicionario> incluirCampo(String tela, String fieldName, String label, String fieldType) async {
    if (falhaInclusao) throw const ModuloJavaException('Esta tela é compartilhada entre empresas');
    camposIncluidos.add([tela, fieldName, label, fieldType]);
    return lista.first;
  }

  @override
  Future<LigacaoCampo> salvarLigacao(String tela, LigacaoCampo l) async {
    ligacoesSalvas.add(l);
    return l;
  }

  @override
  Future<void> excluirLigacao(String tela, String campo) async => ligacoesRemovidas.add(campo);
}

class _ModulosFalso extends ModuloJavaService {
  @override
  Future<List<ModuloJava>> listar() async => const [
        ModuloJava(id: 8, identificador: 'dhara-agro-cobrancainterna-1.0.0', descricao: 'Cobrança Interna'),
      ];
}

Widget _app(_AcoesFalso a, [_CamposFalso? c]) => MaterialApp(
      home: Scaffold(body: DicionarioDadosView(acoes: a, modulos: _ModulosFalso(), campos: c ?? _CamposFalso())),
    );

Future<void> _irPara(WidgetTester tester, String aba) async {
  await tester.tap(find.text(aba));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('aba Acoes: exige a tela, carrega e lista com classe e parametros', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = _AcoesFalso(acoes: const [
      AcaoJava(
          id: 1,
          telaNome: 'produto',
          label: 'Gerar nota de saída',
          classe: 'br.com.dhara.CobrancaAcao',
          tabelaNome: 'produto',
          params: [AcaoJavaParam(descricao: 'Cliente', nome: 'cliente')]),
    ]);
    await tester.pumpWidget(_app(s));
    await _irPara(tester, 'Ações');

    await tester.tap(find.text('Carregar').first);
    await tester.pumpAndSettle();
    expect(find.text('Informe o nome da tela.'), findsOneWidget);
    expect(s.telaConsultada, isNull);

    await tester.enterText(find.byType(TextField).first, 'produto');
    await tester.tap(find.text('Carregar').first);
    await tester.pumpAndSettle();

    expect(s.telaConsultada, 'produto');
    expect(find.text('Gerar nota de saída'), findsOneWidget);
    expect(find.textContaining('br.com.dhara.CobrancaAcao'), findsOneWidget);
    expect(find.textContaining('1 parâmetro(s)'), findsOneWidget);
    expect(find.text('Nova ação'), findsOneWidget);
  });

  testWidgets('erro do servidor (nao MASTER) aparece em vez de lista vazia', (tester) async {
    final s = _AcoesFalso()..falhaListagem = true;
    await tester.pumpWidget(_app(s));
    await _irPara(tester, 'Ações');
    await tester.enterText(find.byType(TextField).first, 'produto');
    await tester.tap(find.text('Carregar').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Somente o usuário MASTER'), findsOneWidget);
  });

  testWidgets('nova acao: valida campos, escolhe modulo/classe e salva com parametro', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = _AcoesFalso();
    await tester.pumpWidget(_app(s));
    await _irPara(tester, 'Ações');
    await tester.enterText(find.byType(TextField).first, 'produto');
    await tester.tap(find.text('Carregar').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nova ação'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Informe a descrição'), findsOneWidget);
    expect(find.text('Escolha o módulo'), findsOneWidget);
    expect(s.salvasAcoes, isEmpty);

    await tester.enterText(find.widgetWithText(TextFormField, 'Descrição (texto do botão) *'), 'Gerar nota');
    await tester.tap(find.text('Módulo Java *'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('8 - Cobrança Interna').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Classe Java *'));
    await tester.pumpAndSettle();
    expect(find.text('br.com.dhara.StatusEvento'), findsNothing, reason: 'so classes de acao aparecem');
    await tester.tap(find.text('br.com.dhara.CobrancaAcao').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Parâmetro'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Descrição *'), 'Cliente');
    await tester.enterText(find.widgetWithText(TextFormField, 'Nome *'), 'cliente');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(s.salvasAcoes, hasLength(1));
    final a = s.salvasAcoes.single;
    expect(a.telaNome, 'produto');
    expect(a.label, 'Gerar nota');
    expect(a.moduloJavaId, 8);
    expect(a.classe, 'br.com.dhara.CobrancaAcao');
    expect(a.tabelaNome, 'produto');
    expect(a.params.single.nome, 'cliente');
  });

  testWidgets('aba Eventos: lista e cria evento (antes/inserir) com classe de evento', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = _AcoesFalso(eventos: const [
      EventoJava(id: 1, tabelaNome: 'produto', numEvento: 1, descricao: 'Marcar status C', classe: 'br.com.dhara.StatusEvento'),
    ]);
    await tester.pumpWidget(_app(s));
    await _irPara(tester, 'Eventos');
    await tester.enterText(find.byType(TextField).last, 'produto');
    await tester.tap(find.text('Carregar').last);
    await tester.pumpAndSettle();

    expect(s.tabelaConsultada, 'produto');
    expect(find.text('Marcar status C'), findsOneWidget);
    expect(find.textContaining('ANTES INSERT'), findsOneWidget);

    await tester.tap(find.text('Novo evento'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Descrição *'), 'Novo');
    await tester.tap(find.text('Módulo Java *'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('8 - Cobrança Interna').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Classe Java *'));
    await tester.pumpAndSettle();
    expect(find.text('br.com.dhara.CobrancaAcao'), findsNothing, reason: 'so classes de evento aparecem');
    await tester.tap(find.text('br.com.dhara.StatusEvento').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    final e = s.salvosEventos.single;
    expect(e.tabelaNome, 'produto');
    expect(e.momento, 'ANTES');
    expect(e.operacao, 'INSERT');
    expect(e.classe, 'br.com.dhara.StatusEvento');
    expect(e.abortaEmErro, isTrue);
  });

  testWidgets('aba Campos: lista com rotulo, altera so o rotulo e inclui campo; erro 409 aparece', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = _CamposFalso();
    await tester.pumpWidget(_app(_AcoesFalso(), c));

    await tester.tap(find.text('Carregar').first);
    await tester.pumpAndSettle();
    expect(find.text('Informe o nome da tela.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'produto');
    await tester.tap(find.text('Carregar').first);
    await tester.pumpAndSettle();
    expect(c.telaConsultada, 'produto');
    expect(find.text('nome · text'), findsOneWidget);
    expect(find.text('codParceiro · number'), findsOneWidget);

    await tester.tap(find.byTooltip('Alterar rótulo').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('O tipo e o nome do campo não mudam'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Rótulo'), 'Descrição do produto');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(c.labelsAlterados.single, ['produto', 'nome', 'Descrição do produto']);

    c.falhaInclusao = true;
    await tester.tap(find.text('Incluir campo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Incluir'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Comece com letra minúscula'), findsOneWidget, reason: 'nome do campo e validado');
    await tester.enterText(find.widgetWithText(TextFormField, 'Nome do campo *'), 'observacao');
    await tester.enterText(find.widgetWithText(TextFormField, 'Rótulo *'), 'Observação');
    await tester.tap(find.text('Incluir'));
    await tester.pumpAndSettle();
    expect(find.text('Esta tela é compartilhada entre empresas'), findsOneWidget);
    expect(c.camposIncluidos, isEmpty);

    c.falhaInclusao = false;
    await tester.tap(find.text('Incluir campo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Nome do campo *'), 'observacao');
    await tester.enterText(find.widgetWithText(TextFormField, 'Rótulo *'), 'Observação');
    await tester.tap(find.text('Incluir'));
    await tester.pumpAndSettle();
    expect(c.camposIncluidos.single, ['produto', 'observacao', 'Observação', 'text']);
  });

  testWidgets('aba Ligacoes: mostra FK existente, valida endpoint interno, salva e remove', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = _CamposFalso();
    await tester.pumpWidget(_app(_AcoesFalso(), c));
    await _irPara(tester, 'Ligações');
    await tester.enterText(find.byType(TextField).first, 'produto');
    await tester.tap(find.text('Carregar').first);
    await tester.pumpAndSettle();

    expect(find.text('nome · sem ligação'), findsOneWidget);
    expect(find.textContaining('codParceiro → parceiro (/api/parceiro)'), findsOneWidget);

    await tester.tap(find.byTooltip('Editar ligação').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Tabela de destino *'), 'parceiro');
    await tester.enterText(find.widgetWithText(TextFormField, 'Endpoint da lista *'), 'https://evil.com/x');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Use um caminho interno, ex.: /api/parceiro'), findsOneWidget);
    expect(c.ligacoesSalvas, isEmpty);
    await tester.enterText(find.widgetWithText(TextFormField, 'Endpoint da lista *'), '/api/parceiro');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(c.ligacoesSalvas.single.campo, 'nome');
    expect(c.ligacoesSalvas.single.endpoint, '/api/parceiro');

    await tester.tap(find.byTooltip('Editar ligação').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remover'));
    await tester.pumpAndSettle();
    expect(c.ligacoesRemovidas, ['codParceiro']);
  });
}
