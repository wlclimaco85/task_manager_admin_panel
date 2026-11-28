import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/services/dashboard_personalizado_service.dart';
import 'package:task_manager_admin_panel/services/relatorio_personalizado_service.dart';
import 'package:task_manager_admin_panel/utils/campo_calculado.dart';
import 'package:task_manager_admin_panel/widgets/dashboard_componente_view.dart';
import 'package:task_manager_admin_panel/widgets/dashboard_construtor_view.dart';
import 'package:task_manager_admin_panel/widgets/relatorio_construtor_view.dart';

const _sql = 'SELECT codigo, qtd FROM item';

ResultadoDash _resultado(List<CampoCalculado> campos) => ResultadoDash(
    tipo: 'TABELA',
    titulo: 'Prévia',
    colunas: ['codigo', 'qtd', for (final c in campos) c.coluna],
    linhas: [
      [10, 2, for (final _ in campos) 'Cafe'],
      [20, 3, for (final _ in campos) 'Pao'],
    ]);

class _Dash extends DashboardPersonalizadoService {
  DashboardPersonalizado? salvo;

  @override
  Future<List<DashboardPersonalizado>> todos() async => const [];

  @override
  Future<DashboardPersonalizado> salvar(DashboardPersonalizado d) async => salvo = d;

  @override
  Future<ResultadoDash> testarSql(String sql, Map<String, dynamic> parametros) async => _resultado(const []);

  @override
  Future<ResultadoDash> testarComCampos(String sql, Map<String, dynamic> parametros, List<CampoCalculado> campos) async =>
      _resultado(campos);
}

class _Rel extends RelatorioPersonalizadoService {
  RelatorioPersonalizado? salvo;

  @override
  Future<List<RelatorioPersonalizado>> todos() async => const [];

  @override
  Future<RelatorioPersonalizado> salvar(RelatorioPersonalizado r) async => salvo = r;

  @override
  Future<ResultadoDash> testarComCampos(String sql, Map<String, dynamic> parametros, List<CampoCalculado> campos) async =>
      _resultado(campos);
}

void _tela(WidgetTester t) {
  t.view.physicalSize = const Size(1400, 3200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> _tocar(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> _criarColuna(WidgetTester t) async {
  await _tocar(t, find.text('Coluna por SELECT'));
  await t.enterText(find.byKey(const Key('coluna-nome')), 'produto');
  await t.enterText(find.byKey(const Key('coluna-sql')), 'SELECT nome FROM produto WHERE id = :cod');
  await t.pump();
  await _tocar(t, find.text('Salvar coluna'));
  expect(find.text('Escolha a coluna de cada parâmetro.'), findsOneWidget);
  await _tocar(t, find.byKey(const ValueKey('origem-cod')));
  await t.tap(find.text('codigo').last);
  await t.pumpAndSettle();
  await _tocar(t, find.text('Salvar coluna'));
}

void main() {
  testWidgets('dashboard: coluna por SELECT e soma sao testadas e salvas no componente', (t) async {
    _tela(t);
    final s = _Dash();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: DashboardConstrutorView(servico: s))));
    await t.pumpAndSettle();
    await _tocar(t, find.text('Novo dashboard'));
    await t.enterText(find.widgetWithText(TextFormField, 'Título *'), 'Estoque');
    await _tocar(t, find.text('Componente'));
    await t.enterText(find.widgetWithText(TextFormField, 'Título do componente *'), 'Itens');
    await t.enterText(find.widgetWithText(TextFormField, 'SQL (SELECT) ou planilha *'), _sql);

    // sem testar nao ha colunas para escolher
    await _tocar(t, find.text('Coluna por SELECT'));
    expect(find.textContaining('Clique em "Testar" antes'), findsOneWidget);
    await _tocar(t, find.text('Testar'));
    await _criarColuna(t);
    expect(find.text('Cafe'), findsOneWidget);

    await _tocar(t, find.byKey(const ValueKey('somar-qtd')));
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);

    await _tocar(t, find.text('Salvar'));
    final c = s.salvo!.componentes.single;
    expect(c.somas, ['qtd']);
    expect(c.campos.single.coluna, 'produto');
    expect(c.campos.single.parametros, {'cod': 'codigo'});
    final volta = DashComponente.fromJson(c.toJson());
    expect(volta.somas, ['qtd']);
    expect(volta.campos.single.parametros, {'cod': 'codigo'});
  });

  testWidgets('relatorio: coluna por SELECT entra na configuracao salva', (t) async {
    _tela(t);
    final s = _Rel();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: RelatorioConstrutorView(servico: s))));
    await t.pumpAndSettle();
    await _tocar(t, find.text('Novo relatório'));
    await t.enterText(find.widgetWithText(TextFormField, 'Título *'), 'Estoque');
    await t.enterText(find.widgetWithText(TextFormField, 'SQL (SELECT) *'), _sql);
    await _tocar(t, find.text('Testar'));
    await _criarColuna(t);
    expect(find.text('Cafe'), findsOneWidget);

    await _tocar(t, find.text('Salvar'));
    expect(s.salvo!.config.campos.single.coluna, 'produto');
    expect(RelConfig.fromJson(s.salvo!.config.toJson()).campos.single.parametros, {'cod': 'codigo'});
  });

  testWidgets('grafico mostra o total da coluna somada', (t) async {
    await t.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: ComponenteDashboardView(
                resultado: ResultadoDash(tipo: 'BARRAS', titulo: 'Vendas', colunas: [
      'mes',
      'valor'
    ], linhas: [
      ['jan', 1000],
      ['fev', 500]
    ], somas: [
      'VALOR'
    ])))));
    await t.pumpAndSettle();
    expect(find.text('Total valor: 1.500'), findsOneWidget);
  });
}
