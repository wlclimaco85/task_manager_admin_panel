import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/config/api_links.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/screens/sistema/aplicativo_screen.dart';
import 'package:task_manager_admin_panel/widgets/generic/generic_grid_screen.dart';

void main() {
  testWidgets(
      'AplicativoScreen monta GenericGridScreen apontando para ApiLinks.allAplicativos',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: const AplicativoScreen(),
    ));
    // Um unico pump: so precisamos inspecionar as props do widget montado,
    // sem esperar a chamada de rede real resolver (sem backend no teste).
    await tester.pump();

    final grid = tester.widget<GenericGridScreen>(
      find.byType(GenericGridScreen),
    );

    expect(grid.title, 'Aplicativo');
    expect(grid.listUrl, ApiLinks.allAplicativos);
    expect(grid.createUrl, ApiLinks.createAplicativo);
    expect(grid.updateUrl('1'), ApiLinks.updateAplicativo('1'));
    expect(grid.deleteUrl('1'), ApiLinks.deleteAplicativo('1'));
    expect(grid.fields.map((f) => f.key), ['nome', 'observacao']);
  });
}
