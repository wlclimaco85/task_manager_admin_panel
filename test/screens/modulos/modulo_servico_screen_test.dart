import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_manager_admin_panel/screens/modulos/modulo_servico_screen.dart';
import 'package:task_manager_admin_panel/widgets/generic_grid_windows_screen.dart';

import '../../helpers/drenar_widget.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'ModuloServicoScreen monta GenericGridWindowsScreen com CRUD completo (deleteEndpoint preenchido)',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ModuloServicoScreen(),
    ));
    await tester.pump();

    final grid = tester.widget<GenericGridWindowsScreen>(
      find.byType(GenericGridWindowsScreen),
    );

    expect(grid.title, 'Modulos (catalogo)');
    expect(grid.deleteEndpoint, isNotEmpty);
    expect(grid.fieldConfigs.map((f) => f.fieldName),
        ['nome', 'descricao', 'ativo']);

    await desmontarEDrenar(tester);
  });
}
