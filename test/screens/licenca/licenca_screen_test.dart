import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/config/api_links.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/screens/licenca/licenca_screen.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';
import 'package:task_manager_admin_panel/widgets/generic/generic_grid_screen.dart';

void main() {
  testWidgets(
      'LicencaScreen monta GenericGridScreen com deleteUrl nulo e sem icone de excluir',
      (tester) async {
    final client = MockClient((request) async {
      // `GET /api/licencas` retorna List direto na raiz (sem envelope
      // {data:...}) — ver RESEARCH.md Pitfall 1, ja normalizado por
      // GenericGridScreen.extractRows.
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

    final grid = tester.widget<GenericGridScreen>(
      find.byType(GenericGridScreen),
    );

    expect(grid.title, 'Licencas');
    expect(grid.listUrl, ApiLinks.allLicencas);
    expect(grid.createUrl, ApiLinks.createLicenca);
    expect(grid.updateUrl('1'), ApiLinks.updateLicenca('1'));
    expect(grid.deleteUrl, isNull);
    expect(
      grid.fields.map((f) => f.key),
      ['codApp', 'nomeApp', 'ativo', 'dataInicio', 'dataVencimento', 'observacao'],
    );

    // Reconstroi a tela injetando o NetworkCaller mockado para confirmar,
    // ponta-a-ponta, que a grid renderiza sem icone de excluir mesmo com
    // dados carregados.
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: GenericGridScreen(
          title: 'Licencas',
          listUrl: ApiLinks.allLicencas,
          createUrl: ApiLinks.createLicenca,
          updateUrl: ApiLinks.updateLicenca,
          deleteUrl: null,
          fields: grid.fields,
          networkCaller: caller,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
  });
}
