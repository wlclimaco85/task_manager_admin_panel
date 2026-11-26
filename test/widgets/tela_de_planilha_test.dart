import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/services/construtor_telas_service.dart';
import 'package:task_manager_admin_panel/services/planilha_service.dart';
import 'package:task_manager_admin_panel/utils/planilha_tabela.dart';
import 'package:task_manager_admin_panel/widgets/construtor_telas_view.dart';
import 'package:task_manager_admin_panel/widgets/tela_de_planilha_dialog.dart';

class _Planilhas extends PlanilhaService {
  @override
  Future<List<PlanilhaResumo>> listar() async => const [PlanilhaResumo(3, 'Clientes')];

  @override
  Future<PlanilhaDados> abrir(int id) async => const PlanilhaDados(
      id: 3, nome: 'Clientes', celulas: {'A1': 'Nome', 'B1': 'Total', 'A2': 'Ana', 'B2': '=10+5.5', 'D2': 'solto'});
}

class _Construtor extends ConstrutorTelasService {
  @override
  Future<List<TelaConstruida>> todas() async => const [
        TelaConstruida(id: 1, telaNome: 'c7_planilha_a', tabelaNome: 'planilha:a', titulo: 'Clientes'),
      ];
}

void main() {
  test('linha 1 vira colunas; formulas chegam calculadas; linha vazia e coluna sem titulo ficam de fora', () {
    final t = tabelaDaPlanilha({
      'C1': 'Total',
      'A1': 'Nome',
      'A2': 'Ana',
      'C2': '=SOMA(1;2)',
      'A4': 'Bia',
      'B3': 'sem titulo',
      'A5': "'=texto",
    });
    expect(t.colunas, ['Nome', 'Total']);
    expect(t.linhas, [
      ['Ana', '3'],
      ['Bia', ''],
      ['=texto', ''],
    ]);
    expect(t.ignoradas, ['B']);
    expect(tabelaDaPlanilha({'A2': 'x'}).colunas, isEmpty);
    expect(tabelaDaPlanilha({'A1': 'N', 'A2': '=1/0', 'A3': '#hashtag'}).comErro, ['A2']);
  });

  testWidgets('dialogo mostra campos e devolve o titulo com os valores calculados', (t) async {
    PedidoTelaDePlanilha? pedido;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => pedido = await showDialog<PedidoTelaDePlanilha>(
              context: context, builder: (_) => TelaDePlanilhaDialog(servico: _Planilhas())),
          child: const Text('abrir'),
        ),
      ),
    ));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
    await t.tap(find.byType(DropdownButtonFormField<int>));
    await t.pumpAndSettle();
    await t.tap(find.text('Clientes').last);
    await t.pumpAndSettle();
    expect(find.text('2 campo(s): Nome, Total'), findsOneWidget);
    expect(find.textContaining('ficam de fora: D'), findsOneWidget);
    await t.tap(find.text('Criar'));
    await t.pumpAndSettle();
    expect(pedido!.titulo, 'Clientes');
    expect(pedido!.tabela.linhas, [
      ['Ana', '15,5'],
    ]);
  });

  testWidgets('construtor oferece tabela e planilha e avisa que excluir apaga os registros', (t) async {
    t.view.physicalSize = const Size(375, 740);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: ConstrutorTelasView(servico: _Construtor()))));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('Dados próprios (planilha)'), findsOneWidget);
    await t.tap(find.text('Nova tela'));
    await t.pumpAndSettle();
    expect(find.text('Sobre uma tabela'), findsOneWidget);
    expect(find.text('A partir de planilha'), findsOneWidget);
    expect(find.text('A partir de modelo de planilha'), findsNothing); // o admin nao tem modelos de planilha
    await t.tapAt(const Offset(5, 700));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Excluir'));
    await t.pumpAndSettle();
    expect(find.textContaining('TODOS os registros'), findsOneWidget);
  });
}
