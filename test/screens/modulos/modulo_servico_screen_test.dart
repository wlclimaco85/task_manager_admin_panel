import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/config/api_links.dart';
import 'package:task_manager_admin_panel/screens/modulos/modulo_servico_screen.dart';
import 'package:task_manager_admin_panel/widgets/generic/generic_grid_screen.dart';

void main() {
  testWidgets(
      'ModuloServicoScreen monta GenericGridScreen com CRUD completo (deleteUrl nao nulo)',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ModuloServicoScreen(),
    ));
    await tester.pump();

    final grid = tester.widget<GenericGridScreen>(
      find.byType(GenericGridScreen),
    );

    expect(grid.title, 'Modulos (catalogo)');
    expect(grid.listUrl, ApiLinks.allModulosServico);
    expect(grid.createUrl, ApiLinks.createModuloServico);
    expect(grid.updateUrl('1'), ApiLinks.updateModuloServico('1'));
    expect(grid.deleteUrl, isNotNull);
    expect(grid.deleteUrl!('1'), ApiLinks.deleteModuloServico('1'));
    expect(grid.fields.map((f) => f.key), ['nome', 'descricao', 'ativo']);
  });
}
