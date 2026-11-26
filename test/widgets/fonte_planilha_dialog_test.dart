import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/services/planilha_service.dart';
import 'package:task_manager_admin_panel/widgets/fonte_planilha_dialog.dart';

class _Falso extends PlanilhaService {
  @override
  Future<List<PlanilhaResumo>> listar() async => const [PlanilhaResumo(12, 'Vendas')];

  @override
  Future<PlanilhaDados> abrir(int id) async =>
      const PlanilhaDados(id: 12, nome: 'Vendas', celulas: {'A1': 'Mês', 'C1': 'Total', 'A2': 'Jan', 'C2': '10'});
}

void main() {
  testWidgets('devolve a fonte com as colunas na ordem marcada', (t) async {
    String? fonte;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => fonte = await showDialog<String>(
              context: context, builder: (_) => FontePlanilhaDialog(servico: _Falso())),
          child: const Text('abrir'),
        ),
      ),
    ));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
    await t.tap(find.byType(DropdownButtonFormField<int>));
    await t.pumpAndSettle();
    await t.tap(find.text('Vendas').last);
    await t.pumpAndSettle();
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Usar')).onPressed, isNull);
    await t.tap(find.text('Total'));
    await t.pumpAndSettle();
    await t.tap(find.text('Mês'));
    await t.pumpAndSettle();
    await t.tap(find.text('Usar'));
    await t.pumpAndSettle();
    expect(fonte, 'planilha:12:C,A');
  });
}
