import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/screens/sistema/tela_editor_screen.dart';
import 'package:task_manager_admin_panel/screens/sistema/tela_field_editor_screen.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.darkTheme, home: child);

NetworkCaller _callerReturningBody(Map<String, dynamic> body, {int statusCode = 200}) {
  final client = MockClient((request) async {
    return http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
  });
  return NetworkCaller(client: client);
}

void main() {
  testWidgets('mostra estado de carregamento e depois a lista de telas',
      (tester) async {
    final caller = _callerReturningBody({
      'data': [
        {
          'id': 1,
          'nome': 'aplicativo',
          'titulo': 'Aplicativo',
          'fields': [
            {'id': 10, 'label': 'Nome'},
            {'id': 11, 'label': 'Observação'},
          ],
        },
      ],
    });

    await tester
        .pumpWidget(_wrap(TelaEditorScreen(networkCaller: caller)));

    expect(find.byKey(const Key('tela_editor_loading')), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tela_editor_loading')), findsNothing);
    expect(find.byKey(const Key('tela_editor_list')), findsOneWidget);
    expect(find.text('Aplicativo'), findsOneWidget);
    expect(find.text('2 campos'), findsOneWidget);
  });

  testWidgets(
      'popula lista quando data e um Map aninhado ({data:{dados:[...],total:N}})',
      (tester) async {
    final caller = _callerReturningBody({
      'data': {
        'dados': [
          {'id': 2, 'nome': 'contatos', 'titulo': 'Contatos', 'fields': []},
        ],
        'total': 1,
      },
    });

    await tester
        .pumpWidget(_wrap(TelaEditorScreen(networkCaller: caller)));
    await tester.pumpAndSettle();

    expect(find.text('Contatos'), findsOneWidget);
  });

  testWidgets('popula lista quando dados vem direto na raiz ({dados:[...]})',
      (tester) async {
    final caller = _callerReturningBody({
      'dados': [
        {'id': 3, 'nome': 'nfe', 'titulo': 'NFe', 'fields': []},
      ],
    });

    await tester
        .pumpWidget(_wrap(TelaEditorScreen(networkCaller: caller)));
    await tester.pumpAndSettle();

    expect(find.text('NFe'), findsOneWidget);
  });

  testWidgets('mostra estado vazio quando nao ha telas', (tester) async {
    final caller = _callerReturningBody({'data': []});

    await tester
        .pumpWidget(_wrap(TelaEditorScreen(networkCaller: caller)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tela_editor_empty_state')), findsOneWidget);
  });

  testWidgets('mostra estado de erro quando o backend falha', (tester) async {
    final caller = _callerReturningBody({}, statusCode: 500);

    await tester
        .pumpWidget(_wrap(TelaEditorScreen(networkCaller: caller)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tela_editor_error_text')), findsOneWidget);
  });

  testWidgets('filtra localmente pelo termo de busca (nome ou titulo)',
      (tester) async {
    final caller = _callerReturningBody({
      'data': [
        {'id': 1, 'nome': 'aplicativo', 'titulo': 'Aplicativo', 'fields': []},
        {'id': 2, 'nome': 'contatos', 'titulo': 'Contatos', 'fields': []},
      ],
    });

    await tester
        .pumpWidget(_wrap(TelaEditorScreen(networkCaller: caller)));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('tela_editor_search_field')), 'contato');
    await tester.pumpAndSettle();

    expect(find.text('Contatos'), findsOneWidget);
    expect(find.text('Aplicativo'), findsNothing);
  });

  testWidgets('botao Editar navega para TelaFieldEditorScreen', (tester) async {
    final caller = _callerReturningBody({
      'data': [
        {'id': 1, 'nome': 'aplicativo', 'titulo': 'Aplicativo', 'fields': []},
      ],
      'fields': [],
    });

    await tester
        .pumpWidget(_wrap(TelaEditorScreen(networkCaller: caller)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('tela_editor_edit_button_1')));
    await tester.pumpAndSettle();

    expect(find.byType(TelaFieldEditorScreen), findsOneWidget);
  });
}
