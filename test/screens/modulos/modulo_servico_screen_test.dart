import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/config/api_links.dart';
import 'package:task_manager_admin_panel/screens/modulos/modulo_servico_screen.dart';
import 'package:task_manager_admin_panel/widgets/generic_grid_windows_screen.dart';

void main() {
  testWidgets(
      'ModuloServicoScreen monta GenericGridWindowsScreen com CRUD completo (deleteUrl nao nulo)',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ModuloServicoScreen(),
    ));
    await tester.pump();

    final grid = tester.widget<GenericGridWindowsScreen>(
      find.byType(GenericGridWindowsScreen),
    );

    expect(grid.title, 'Modulos (catalogo)');
    
    
    
    expect(grid.deleteEndpoint, isNotNull);
    
    expect(grid.fieldConfigs.map((f) => f.fieldName), ['nome', 'descricao', 'ativo']);
  });
}
