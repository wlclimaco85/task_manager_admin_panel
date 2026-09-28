import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/services/system_test_run_service.dart';
import 'package:task_manager_admin_panel/widgets/system_test_run_panel.dart';

void main() {
  testWidgets('executar tudo envia o grupo TODOS em homologacao',
      (tester) async {
    Map<String, dynamic>? startBody;
    final service = SystemTestRunService(client: MockClient((request) async {
      if (request.method == 'POST' && request.url.path.endsWith('/runs')) {
        startBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(_run('RUNNING')), 202);
      }
      if (request.url.path.endsWith('/events')) {
        return http.Response('[]', 200);
      }
      return http.Response(jsonEncode(_run('COMPLETED')), 200);
    }));

    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
            body: SystemTestRunPanel(service: service, token: 'token-test'))));

    final selector = find.byKey(const Key('system_test_group_selector'));
    await tester.ensureVisible(selector);
    final decorator = tester.widget<InputDecorator>(find.descendant(
      of: selector,
      matching: find.byType(InputDecorator),
    ));
    expect(decorator.decoration.fillColor, Colors.white);

    final dropdown = tester.widget<DropdownButton<String>>(find.descendant(
      of: selector,
      matching: find.byType(DropdownButton<String>),
    ));
    final option = dropdown.items!
        .map((item) => item.child)
        .whereType<Text>()
        .singleWhere((text) => text.data == 'Tudo: fases 1 e 2');
    expect(option.style?.color, const Color(0xFF17211B));
    dropdown.onChanged!('TODOS');
    await tester.pump();
    await tester.tap(find.byKey(const Key('system_test_start_button')));
    await tester.pumpAndSettle();

    expect(startBody, {
      'environment': 'HOMOLOGACAO',
      'groups': ['TODOS']
    });
  });

  testWidgets('mostra erro completo copiavel depois de continuar o fluxo',
      (tester) async {
    const error = 'POST /api/role retornou 400: Role duplicada';
    final service = SystemTestRunService(client: MockClient((request) async {
      if (request.method == 'POST') {
        return http.Response(jsonEncode(_run('RUNNING')), 202);
      }
      if (request.url.path.endsWith('/events')) {
        return http.Response(
            jsonEncode([
              {
                'eventSequence': 13,
                'stepName': 'Role - ERRO',
                'level': 'ERROR',
                'message': error,
              },
              {
                'eventSequence': 14,
                'stepName': 'Setor - POST',
                'level': 'SUCCESS',
                'message': 'Setor - POST concluido',
              }
            ]),
            200);
      }
      return http.Response(
          jsonEncode({
            ..._run('FAILED'),
            'progressPercent': 100,
            'completedOperations': 10,
            'failureCount': 1,
            'skippedCount': 5,
            'lastError': error,
          }),
          200);
    }));

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SystemTestRunPanel(service: service, token: 'token-test'))));
    await tester.tap(find.byKey(const Key('system_test_start_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('system_test_error_summary')), findsOneWidget);
    expect(find.text(error), findsWidgets);
    expect(find.text('Setor - POST'), findsOneWidget);
    expect(find.text('Ignorados 5'), findsOneWidget);
    expect(find.byKey(const Key('system_test_error_copy')), findsOneWidget);
  });
}

Map<String, dynamic> _run(String status) => {
      'runId': 'run-widget',
      'marker': 'E2E-WIDGET',
      'environment': 'HOMOLOGACAO',
      'status': status,
      'progressPercent': status == 'COMPLETED' ? 100 : 1,
      'totalOperations': 10,
      'completedOperations': status == 'COMPLETED' ? 10 : 1,
      'successCount': status == 'COMPLETED' ? 10 : 1,
      'failureCount': 0,
      'cleanedCount': status == 'COMPLETED' ? 2 : 0,
      'residueCount': 0,
    };
