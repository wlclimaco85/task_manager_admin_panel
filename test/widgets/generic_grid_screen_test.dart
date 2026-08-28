import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';
import 'package:task_manager_admin_panel/widgets/generic/field_config.dart';
import 'package:task_manager_admin_panel/widgets/generic/generic_grid_screen.dart';

const _fields = [
  FieldConfig(key: 'nome', label: 'Nome', required: true),
  FieldConfig(key: 'email', label: 'E-mail', type: FieldType.email),
];

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.darkTheme, home: child);

NetworkCaller _callerReturning(List<Map<String, dynamic>> data,
    {int statusCode = 200}) {
  final client = MockClient((request) async {
    return http.Response(
      jsonEncode({'data': data}),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
  });
  return NetworkCaller(client: client);
}

void main() {
  testWidgets('mostra estado de carregamento e depois os dados',
      (tester) async {
    final caller = _callerReturning([
      {'id': 1, 'nome': 'Contato A', 'email': 'a@x.com'},
      {'id': 2, 'nome': 'Contato B', 'email': 'b@x.com'},
    ]);

    await tester.pumpWidget(_wrap(GenericGridScreen(
      title: 'Contatos',
      listUrl: 'http://backend/api/contatos',
      createUrl: 'http://backend/api/contatos',
      updateUrl: (id) => 'http://backend/api/contatos/$id',
      deleteUrl: (id) => 'http://backend/api/contatos/$id',
      fields: _fields,
      networkCaller: caller,
    )));

    expect(find.byKey(const Key('grid_loading')), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('grid_loading')), findsNothing);
    expect(find.byKey(const Key('grid_data_table')), findsOneWidget);
    expect(find.text('Contato A'), findsOneWidget);
    expect(find.text('Contato B'), findsOneWidget);
  });

  testWidgets('mostra estado vazio quando nao ha registros', (tester) async {
    final caller = _callerReturning([]);

    await tester.pumpWidget(_wrap(GenericGridScreen(
      title: 'Contatos',
      listUrl: 'http://backend/api/contatos',
      createUrl: 'http://backend/api/contatos',
      updateUrl: (id) => 'http://backend/api/contatos/$id',
      deleteUrl: (id) => 'http://backend/api/contatos/$id',
      fields: _fields,
      networkCaller: caller,
    )));

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('grid_empty_state')), findsOneWidget);
  });

  testWidgets('mostra estado de erro quando o backend falha', (tester) async {
    final caller = _callerReturning([], statusCode: 500);

    await tester.pumpWidget(_wrap(GenericGridScreen(
      title: 'Contatos',
      listUrl: 'http://backend/api/contatos',
      createUrl: 'http://backend/api/contatos',
      updateUrl: (id) => 'http://backend/api/contatos/$id',
      deleteUrl: (id) => 'http://backend/api/contatos/$id',
      fields: _fields,
      networkCaller: caller,
    )));

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('grid_error_text')), findsOneWidget);
  });

  testWidgets('filtra localmente pelo termo de busca', (tester) async {
    final caller = _callerReturning([
      {'id': 1, 'nome': 'Ana', 'email': 'ana@x.com'},
      {'id': 2, 'nome': 'Bruno', 'email': 'bruno@x.com'},
    ]);

    await tester.pumpWidget(_wrap(GenericGridScreen(
      title: 'Contatos',
      listUrl: 'http://backend/api/contatos',
      createUrl: 'http://backend/api/contatos',
      updateUrl: (id) => 'http://backend/api/contatos/$id',
      deleteUrl: (id) => 'http://backend/api/contatos/$id',
      fields: _fields,
      networkCaller: caller,
    )));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('grid_search_field')), 'Ana');
    await tester.pumpAndSettle();

    expect(find.text('Ana'), findsWidgets);
    expect(find.text('Bruno'), findsNothing);
  });
}
