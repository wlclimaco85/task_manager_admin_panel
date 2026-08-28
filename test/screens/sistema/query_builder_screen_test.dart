import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/screens/sistema/query_builder_screen.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';
import 'package:task_manager_admin_panel/services/query_builder_service.dart';

void main() {
  QueryBuilderService buildServiceComSchemasVazios() {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'data': {'data': []},
          'response': {'error': false, 'message': 'ok', 'status': 200},
        }),
        200,
      );
    });
    return QueryBuilderService(networkCaller: NetworkCaller(client: client));
  }

  testWidgets(
      'botao Executar comeca desabilitado e permanece desabilitado para DML',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: QueryBuilderScreen(service: buildServiceComSchemasVazios()),
    ));
    await tester.pumpAndSettle();

    ElevatedButton getButton() => tester.widget<ElevatedButton>(
          find.byKey(const Key('query_builder_executar_button')),
        );

    expect(getButton().onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('query_builder_sql_field')),
      'DELETE FROM login',
    );
    await tester.pump();

    expect(getButton().onPressed, isNull);
  });

  testWidgets('botao Executar habilita para SELECT e WITH', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: QueryBuilderScreen(service: buildServiceComSchemasVazios()),
    ));
    await tester.pumpAndSettle();

    ElevatedButton getButton() => tester.widget<ElevatedButton>(
          find.byKey(const Key('query_builder_executar_button')),
        );

    await tester.enterText(
      find.byKey(const Key('query_builder_sql_field')),
      'SELECT * FROM login',
    );
    await tester.pump();
    expect(getButton().onPressed, isNotNull);

    await tester.enterText(
      find.byKey(const Key('query_builder_sql_field')),
      'WITH cte AS (SELECT 1) SELECT * FROM cte',
    );
    await tester.pump();
    expect(getButton().onPressed, isNotNull);
  });

  testWidgets('executa SELECT e renderiza grid de resultados', (tester) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/schemas')) {
        return http.Response(
          jsonEncode({
            'data': {
              'data': [
                {'schema_name': 'public'}
              ]
            },
            'response': {'error': false, 'message': 'ok', 'status': 200},
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/executar')) {
        return http.Response(
          jsonEncode({
            'data': {
              'colunas': [
                {'column_name': 'id'}
              ],
              'linhas': [
                [1]
              ],
              'totalLinhas': 1,
            },
            'response': {'error': false, 'message': 'ok', 'status': 200},
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'data': {'data': []},
          'response': {'error': false, 'message': 'ok', 'status': 200},
        }),
        200,
      );
    });
    final service =
        QueryBuilderService(networkCaller: NetworkCaller(client: client));

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: QueryBuilderScreen(service: service),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('query_builder_sql_field')),
      'SELECT * FROM login',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('query_builder_executar_button')));
    await tester.pumpAndSettle();

    expect(find.text('id'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('exibe schemas carregados no explorer', (tester) async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'data': {
            'data': [
              {'schema_name': 'public'}
            ]
          },
          'response': {'error': false, 'message': 'ok', 'status': 200},
        }),
        200,
      );
    });
    final service =
        QueryBuilderService(networkCaller: NetworkCaller(client: client));

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: QueryBuilderScreen(service: service),
    ));
    await tester.pumpAndSettle();

    expect(find.text('public'), findsOneWidget);
  });
}
