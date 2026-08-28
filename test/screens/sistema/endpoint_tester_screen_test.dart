import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/screens/sistema/endpoint_tester_screen.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: AppTheme.darkTheme, home: child);

void main() {
  testWidgets(
      'metodo GET nao exige corpo: botao Executar habilitado com body vazio',
      (tester) async {
    http.Request? capturedRequest;
    final client = MockClient((request) async {
      capturedRequest = request;
      return http.Response(
        jsonEncode({'data': const []}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final caller = NetworkCaller(client: client);

    await tester.pumpWidget(
      _wrap(EndpointTesterScreen(networkCaller: caller)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('endpoint_tester_path_field')),
      '/api/aplicativo',
    );
    await tester.pump();

    final executeButton = tester.widget<ElevatedButton>(
      find.byKey(const Key('endpoint_tester_execute_button')),
    );
    expect(executeButton.onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('endpoint_tester_execute_button')));
    await tester.pumpAndSettle();

    expect(capturedRequest, isNotNull);
    expect(capturedRequest!.method, 'GET');
    expect(capturedRequest!.url.path, contains('/api/aplicativo'));
    expect(find.byKey(const Key('endpoint_tester_status_text')), findsOneWidget);
    expect(find.textContaining('Status: 200'), findsOneWidget);
  });

  testWidgets(
      'corpo JSON invalido em POST bloqueia o botao Executar',
      (tester) async {
    final caller = NetworkCaller(
      client: MockClient((request) async => http.Response('{}', 200)),
    );

    await tester.pumpWidget(
      _wrap(EndpointTesterScreen(networkCaller: caller)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('endpoint_tester_path_field')),
      '/api/aplicativo',
    );
    await tester.tap(find.byKey(const Key('endpoint_tester_verb_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('POST').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('endpoint_tester_body_field')),
      '{invalido',
    );
    await tester.pump();

    final executeButton = tester.widget<ElevatedButton>(
      find.byKey(const Key('endpoint_tester_execute_button')),
    );
    expect(executeButton.onPressed, isNull);
    expect(find.text('JSON invalido'), findsOneWidget);
  });

  testWidgets(
      'corpo JSON valido em POST habilita o botao e envia o corpo enviado',
      (tester) async {
    http.Request? capturedRequest;
    final client = MockClient((request) async {
      capturedRequest = request;
      return http.Response(jsonEncode({'id': 1}), 201);
    });
    final caller = NetworkCaller(client: client);

    await tester.pumpWidget(
      _wrap(EndpointTesterScreen(networkCaller: caller)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('endpoint_tester_path_field')),
      '/api/aplicativo',
    );
    await tester.tap(find.byKey(const Key('endpoint_tester_verb_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('POST').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('endpoint_tester_body_field')),
      '{"nome": "Teste"}',
    );
    await tester.pump();

    final executeButton = tester.widget<ElevatedButton>(
      find.byKey(const Key('endpoint_tester_execute_button')),
    );
    expect(executeButton.onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('endpoint_tester_execute_button')));
    await tester.pumpAndSettle();

    expect(capturedRequest, isNotNull);
    expect(capturedRequest!.method, 'POST');
    expect(jsonDecode(capturedRequest!.body), {'nome': 'Teste'});
    expect(find.textContaining('Status: 201'), findsOneWidget);
  });

  testWidgets('path vazio mantem o botao Executar desabilitado',
      (tester) async {
    final caller = NetworkCaller(
      client: MockClient((request) async => http.Response('{}', 200)),
    );

    await tester.pumpWidget(
      _wrap(EndpointTesterScreen(networkCaller: caller)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('endpoint_tester_path_field')),
      '',
    );
    await tester.pump();

    final executeButton = tester.widget<ElevatedButton>(
      find.byKey(const Key('endpoint_tester_execute_button')),
    );
    expect(executeButton.onPressed, isNull);
  });
}
