import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/services/acao_java_service.dart';
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

class _ModulosFalso extends ModuloJavaService {
  @override
  Future<List<ModuloJava>> listar() async => const [
        ModuloJava(id: 8, identificador: 'dhara-agro-cobrancainterna-1.0.0', descricao: 'Cobrança Interna'),
      ];
}

Widget _app(_AcoesFalso a) => MaterialApp(
      home: Scaffold(body: DicionarioDadosView(acoes: a, modulos: _ModulosFalso())),
    );

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
    await tester.tap(find.text('Eventos'));
    await tester.pumpAndSettle();
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
}
