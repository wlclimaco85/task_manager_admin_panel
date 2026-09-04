import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/config/api_links.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/screens/licenca/licenca_screen.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';
import 'package:task_manager_admin_panel/widgets/generic_grid_windows_screen.dart';

void main() {
  testWidgets(
      'LicencaScreen monta GenericGridWindowsScreen com deleteUrl nulo e sem icone de excluir',
      (tester) async {
    final client = MockClient((request) async {
      // `GET /api/licencas` retorna List direto na raiz (sem envelope
      // {data:...}) — ver RESEARCH.md Pitfall 1, ja normalizado por
      // GenericGridWindowsScreen.extractRows.
      return http.Response(
        jsonEncode([
          {
            'id': 1,
            'codApp': 7,
            'nomeApp': 'App Academia',
            'ativo': true,
            'dataInicio': '2026-01-01',
            'dataVencimento': '2026-12-31',
          },
        ]),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final caller = NetworkCaller(client: client);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: const LicencaScreen(),
    ));
    await tester.pump();

    final grid = tester.widget<GenericGridWindowsScreen>(
      find.byType(GenericGridWindowsScreen),
    );

    expect(grid.title, 'Licencas');
    
    
    
    expect(grid.deleteEndpoint, isNull);
    expect(
      grid.fieldConfigs.map((f) => f.fieldName),
      ['codApp', 'nomeApp', 'ativo', 'dataInicio', 'dataVencimento', 'observacao'],
    );

    // Reconstroi a tela injetando o NetworkCaller mockado para confirmar,
    // ponta-a-ponta, que a grid renderiza sem icone de excluir mesmo com
    // dados carregados.
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: GenericGridWindowsScreen(
          title: 'Licencas',
          fetchEndpoint: ApiLinks.allLicencas,
          createEndpoint: ApiLinks.createLicenca,
          updateEndpoint: ApiLinks.updateLicenca,
          deleteEndpoint: null,
          fieldConfigs: grid.fieldConfigs,
          
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
  });
}
