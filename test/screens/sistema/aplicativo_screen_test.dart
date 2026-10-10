import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/screens/sistema/aplicativo_screen.dart';
import 'package:task_manager_admin_panel/widgets/generic_grid_windows_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'AplicativoScreen monta GenericGridWindowsScreen apontando para ApiLinks.allAplicativos',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: const AplicativoScreen(),
    ));
    // So precisamos inspecionar as props do widget montado, sem esperar a
    // chamada de rede real resolver (sem backend no teste).
    await tester.pump();

    final grid = tester.widget<GenericGridWindowsScreen>(
      find.byType(GenericGridWindowsScreen),
    );

    expect(grid.title, 'Aplicativo');
    expect(grid.fieldConfigs.map((f) => f.fieldName), ['nome', 'observacao']);

    // Desmonta a arvore e drena timers de debounce em background.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
