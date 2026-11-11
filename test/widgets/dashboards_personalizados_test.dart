import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/models/network_response.dart';
import 'package:task_manager_admin_panel/services/dashboard_personalizado_service.dart';
import 'package:task_manager_admin_panel/services/modulo_java_service.dart';
import 'package:task_manager_admin_panel/widgets/dashboard_componente_view.dart';
import 'package:task_manager_admin_panel/widgets/dashboard_construtor_view.dart';
import 'package:task_manager_admin_panel/widgets/dashboards_personalizados_view.dart';

class _ServicoFalso extends DashboardPersonalizadoService {
  List<DashboardPersonalizado> lista;
  List<ResultadoDash> resultados;
  Map<String, dynamic>? parametrosExecucao;
  final List<DashboardPersonalizado> salvos = [];
  final List<int> excluidos = [];
  String? erroTeste;
  ResultadoDash? previa;
  bool falhaListagem = false;

  _ServicoFalso({this.lista = const [], this.resultados = const []});

  @override
  Future<List<DashboardPersonalizado>> ativos() async {
    if (falhaListagem) throw const ModuloJavaException('Empresa nao identificada');
    return lista;
  }

  @override
  Future<List<DashboardPersonalizado>> todos() async {
    if (falhaListagem) throw const ModuloJavaException('Somente o usuário MASTER pode alterar dashboards.');
    return lista;
  }

  @override
  Future<DashboardPersonalizado> buscar(int id) async => lista.firstWhere((d) => d.id == id);

  @override
  Future<DashboardPersonalizado> buscarComSql(int id) async => lista.firstWhere((d) => d.id == id);

  @override
  Future<List<ResultadoDash>> executar(int id, Map<String, dynamic> parametros) async {
    parametrosExecucao = parametros;
    return resultados;
  }

  @override
  Future<DashboardPersonalizado> salvar(DashboardPersonalizado d) async {
    salvos.add(d);
    return d;
  }

  @override
  Future<void> excluir(int id) async => excluidos.add(id);

  @override
  Future<ResultadoDash> testarSql(String sql, Map<String, dynamic> parametros) async {
    if (erroTeste != null) throw ModuloJavaException(erroTeste!);
    return previa ?? const ResultadoDash(tipo: 'TABELA', titulo: 'Prévia', colunas: ['nome'], linhas: [['Camisa']]);
  }
}

const _dash = DashboardPersonalizado(
  id: 4,
  titulo: 'Vendas',
  grupo: 'Comercial',
  filtros: [DashFiltro(nome: 'minimo', descricao: 'Quantidade mínima', tipo: 'INTEIRO', padrao: '0')],
  componentes: [DashComponente(id: 1, tipo: 'KPI', titulo: 'Total')],
);

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('formatacao e modelos', () {
    test('numeros em pt-BR: milhar com ponto, decimais com virgula, texto passa direto', () {
      expect(formatarNumero(1234567), '1.234.567');
      expect(formatarNumero(1234.5), '1.234,50');
      expect(formatarNumero(-9876), '-9.876');
      expect(formatarNumero('12,5'), '12,50');
      expect(formatarNumero('abc'), 'abc');
      expect(formatarNumero(null), '-');
      expect(numeroDeCelula('3,5'), 3.5);
      expect(numeroDeCelula('x'), isNull);
    });

    test('lista do servidor vem como {data:[...]} e o resultado le colunas e linhas', () {
      final r = NetworkResponse(true, 200, [
        {'id': 1, 'tipo': 'barras', 'titulo': 'T', 'colunas': ['a', 'b'], 'linhas': [['x', 1], ['y', 2]], 'truncado': true},
      ]);
      final res = listaDeResposta(r).map(ResultadoDash.fromJson).single;
      expect(res.tipo, 'BARRAS');
      expect(res.linhas.length, 2);
      expect(res.truncado, isTrue);
      final d = DashboardPersonalizado.fromJson({
        'id': 4, 'titulo': 'V', 'parametros': [{'nome': 'a', 'descricao': 'A', 'tipo': 'data', 'padrao': 'HOJE'}],
        'componentes': [{'tipo': 'kpi', 'titulo': 'K', 'largura': 2}],
      });
      expect(d.filtros.single.tipo, 'DATA');
      expect(d.componentes.single.largura, 2);
      expect(d.toJson()['parametros'], isNotEmpty);
    });
  });

  group('ComponenteDashboardView', () {
    Future<void> mostrar(WidgetTester t, ResultadoDash r) async {
      await t.pumpWidget(_app(SingleChildScrollView(child: SizedBox(width: 600, child: ComponenteDashboardView(resultado: r)))));
      await t.pumpAndSettle();
    }

    testWidgets('KPI mostra o primeiro valor formatado', (t) async {
      await mostrar(t, const ResultadoDash(tipo: 'KPI', titulo: 'Faturamento', colunas: ['total'], linhas: [[1234567.5]]));
      expect(find.text('Faturamento'), findsOneWidget);
      expect(find.byKey(const Key('kpi_valor')), findsOneWidget);
      expect(find.text('1.234.567,50'), findsOneWidget);
    });

    testWidgets('tabela mostra colunas e linhas', (t) async {
      await mostrar(t, const ResultadoDash(tipo: 'TABELA', titulo: 'Itens', colunas: ['nome', 'qtd'], linhas: [['Camisa', 3], ['Calca', 1500]]));
      expect(find.text('nome'), findsOneWidget);
      expect(find.text('Camisa'), findsOneWidget);
      expect(find.text('1.500'), findsOneWidget);
    });

    testWidgets('cada tipo de grafico renderiza o widget certo', (t) async {
      const dados = [['jan', 10, 5], ['fev', 20, 8]];
      await mostrar(t, const ResultadoDash(tipo: 'LINHA', titulo: 'L', colunas: ['m', 'a', 'b'], linhas: dados));
      expect(find.byType(LineChart), findsOneWidget);
      await mostrar(t, const ResultadoDash(tipo: 'COLUNAS', titulo: 'C', colunas: ['m', 'a', 'b'], linhas: dados));
      expect(find.byType(BarChart), findsOneWidget);
      await mostrar(t, const ResultadoDash(tipo: 'BARRAS', titulo: 'B', colunas: ['m', 'a'], linhas: dados));
      expect(find.byType(BarChart), findsOneWidget);
      await mostrar(t, const ResultadoDash(tipo: 'PIZZA', titulo: 'P', colunas: ['m', 'a'], linhas: dados));
      expect(find.byType(PieChart), findsOneWidget);
      await mostrar(t, const ResultadoDash(tipo: 'DONUT', titulo: 'D', colunas: ['m', 'a'], linhas: dados));
      expect(find.byType(PieChart), findsOneWidget);
    });

    testWidgets('erro do componente, vazio e truncado aparecem sem quebrar', (t) async {
      await mostrar(t, const ResultadoDash(tipo: 'KPI', titulo: 'X', erro: 'Nao foi possivel carregar este componente'));
      expect(find.text('Nao foi possivel carregar este componente'), findsOneWidget);
      await mostrar(t, const ResultadoDash(tipo: 'TABELA', titulo: 'Y'));
      expect(find.text('Sem dados para o período/filtro.'), findsOneWidget);
      await mostrar(t, const ResultadoDash(tipo: 'PIZZA', titulo: 'Z', colunas: ['a', 'b'], linhas: [['x', -1]]));
      expect(find.text('Sem valores positivos para o gráfico.'), findsOneWidget);
      await mostrar(t, const ResultadoDash(tipo: 'TABELA', titulo: 'W', colunas: ['a'], linhas: [['x']], truncado: true));
      expect(find.textContaining('limitado'), findsOneWidget);
    });
  });

  group('DashboardsPersonalizadosView', () {
    testWidgets('lista, abre, mostra filtros e componentes, e envia os filtros ao aplicar', (t) async {
      final s = _ServicoFalso(lista: const [_dash], resultados: const [
        ResultadoDash(tipo: 'KPI', titulo: 'Total', colunas: ['t'], linhas: [[42]]),
        ResultadoDash(tipo: 'TABELA', titulo: 'Quebrado', erro: 'Nao foi possivel carregar este componente'),
      ]);
      await t.pumpWidget(_app(DashboardsPersonalizadosView(servico: s)));
      await t.pumpAndSettle();

      expect(find.text('Vendas'), findsOneWidget);
      await t.tap(find.text('Vendas'));
      await t.pumpAndSettle();

      expect(find.text('Quantidade mínima'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('Nao foi possivel carregar este componente'), findsOneWidget, reason: 'um componente com erro nao derruba os demais');
      expect(s.parametrosExecucao, {'minimo': '0'});

      await t.enterText(find.widgetWithText(TextField, 'Quantidade mínima'), '5');
      await t.tap(find.text('Aplicar'));
      await t.pumpAndSettle();
      expect(s.parametrosExecucao, {'minimo': '5'});

      await t.tap(find.byTooltip('Voltar'));
      await t.pumpAndSettle();
      expect(find.text('Dashboards'), findsOneWidget);
    });

    testWidgets('erro do servidor aparece em vez de lista vazia', (t) async {
      await t.pumpWidget(_app(DashboardsPersonalizadosView(servico: _ServicoFalso()..falhaListagem = true)));
      await t.pumpAndSettle();
      expect(find.text('Empresa nao identificada'), findsOneWidget);
    });
  });

  group('DashboardConstrutorView', () {
    testWidgets('lista, exclui com confirmacao e mostra erro de permissao', (t) async {
      final s = _ServicoFalso(lista: const [_dash]);
      await t.pumpWidget(_app(DashboardConstrutorView(servico: s)));
      await t.pumpAndSettle();
      expect(find.text('Comercial'), findsOneWidget);
      await t.tap(find.byTooltip('Excluir'));
      await t.pumpAndSettle();
      await t.tap(find.text('Excluir').last);
      await t.pumpAndSettle();
      expect(s.excluidos, [4]);

      await t.pumpWidget(_app(DashboardConstrutorView(key: const ValueKey('erro'), servico: _ServicoFalso()..falhaListagem = true)));
      await t.pumpAndSettle();
      expect(find.textContaining('Somente o usuário MASTER'), findsOneWidget);
    });

    testWidgets('novo dashboard: valida, testa o SQL (prévia e erro) e salva com filtro e componente', (t) async {
      t.view.physicalSize = const Size(1400, 2600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final s = _ServicoFalso();
      await t.pumpWidget(_app(DashboardConstrutorView(servico: s)));
      await t.pumpAndSettle();

      await t.tap(find.text('Novo dashboard'));
      await t.pumpAndSettle();
      await t.tap(find.text('Salvar'));
      await t.pumpAndSettle();
      expect(find.text('Informe o título'), findsOneWidget);
      expect(s.salvos, isEmpty);

      await t.enterText(find.widgetWithText(TextFormField, 'Título *'), 'Estoque');
      await t.tap(find.text('Filtro'));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextFormField, 'Nome *'), 'minimo');
      await t.enterText(find.widgetWithText(TextFormField, 'Descrição *'), 'Mínimo');
      await t.tap(find.text('Componente'));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextFormField, 'Título do componente *'), 'Itens');
      await t.enterText(find.widgetWithText(TextFormField, 'SQL (SELECT) *'), 'SELECT nome FROM item WHERE empresa_id = :empresaId');

      s.erroTeste = 'Palavra/funcao nao permitida no SQL: delete';
      await t.tap(find.text('Testar'));
      await t.pumpAndSettle();
      expect(find.text('Palavra/funcao nao permitida no SQL: delete'), findsOneWidget);

      s.erroTeste = null;
      await t.tap(find.text('Testar'));
      await t.pumpAndSettle();
      expect(find.textContaining('Prévia (1 linha(s))'), findsOneWidget);
      expect(find.text('Camisa'), findsOneWidget);

      await t.tap(find.text('Salvar'));
      await t.pumpAndSettle();
      final d = s.salvos.single;
      expect(d.titulo, 'Estoque');
      expect(d.filtros.single.nome, 'minimo');
      expect(d.componentes.single.sql, 'SELECT nome FROM item WHERE empresa_id = :empresaId');
      expect(d.componentes.single.tipo, 'TABELA');
    });
  });
}
