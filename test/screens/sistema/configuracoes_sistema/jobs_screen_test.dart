import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/screens/sistema/configuracoes_sistema/jobs_screen.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(body: child),
    );

class _RecordingCallerResult {
  _RecordingCallerResult(this.caller, this.calls);
  final NetworkCaller caller;
  final List<String> calls;
}

final _jobsFixture = [
  {
    'nome': 'scraper-cotacoes',
    'status': 'ativo',
    'ultimaExecucao': '2026-08-27T03:00:00',
    'descricao': 'Baixa cotacoes diarias',
  },
  {
    'nome': 'alertas-vencimento',
    'status': 'ativo',
    'ultimaExecucao': '2026-08-28T06:00:00',
  },
  {
    'nome': 'certificados-nfce',
    'status': 'inativo',
  },
];

_RecordingCallerResult _recordingCaller({
  List<Map<String, dynamic>>? jobs,
  Map<String, dynamic>? historico,
}) {
  final calls = <String>[];
  final client = MockClient((request) async {
    calls.add('${request.method} ${request.url}');
    if (request.method == 'GET' &&
        request.url.path.endsWith('/api/admin/jobs')) {
      return http.Response(
        jsonEncode({
          'data': {'dados': jobs ?? _jobsFixture, 'total': (jobs ?? _jobsFixture).length}
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'GET' && request.url.path.contains('/historico')) {
      return http.Response(
        jsonEncode({'data': historico ?? {'execucoes': []}}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'POST' && request.url.path.contains('/executar')) {
      return http.Response(
        jsonEncode({'mensagem': 'ok'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{}', 200, headers: {'content-type': 'application/json'});
  });
  return _RecordingCallerResult(NetworkCaller(client: client), calls);
}

void main() {
  testWidgets('renderiza N jobs vindos do backend', (tester) async {
    final rc = _recordingCaller();
    await tester.pumpWidget(_wrap(JobsScreen(networkCaller: rc.caller)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('job_row_scraper-cotacoes')), findsOneWidget);
    expect(
        find.byKey(const Key('job_row_alertas-vencimento')), findsOneWidget);
    expect(
        find.byKey(const Key('job_row_certificados-nfce')), findsOneWidget);
    expect(rc.calls, hasLength(1));
    expect(rc.calls.first, startsWith('GET'));
    expect(rc.calls.first, contains('/api/admin/jobs'));
  });

  testWidgets('executar sem forcar dispara POST direto, sem confirmacao',
      (tester) async {
    final rc = _recordingCaller();
    await tester.pumpWidget(_wrap(JobsScreen(networkCaller: rc.caller)));
    await tester.pumpAndSettle();

    await tester.tap(
        find.byKey(const Key('job_row_scraper-cotacoes_executar_button')));
    await tester.pumpAndSettle();

    expect(
        rc.calls.any((c) =>
            c.startsWith('POST') &&
            c.contains('/api/admin/jobs/scraper-cotacoes/executar') &&
            c.contains('forcar=false')),
        isTrue);
    expect(find.byKey(const Key('confirm_forcar_button')), findsNothing);
  });

  testWidgets(
      'executar com forcar=true exige confirmacao antes de disparar o POST',
      (tester) async {
    final rc = _recordingCaller();
    await tester.pumpWidget(_wrap(JobsScreen(networkCaller: rc.caller)));
    await tester.pumpAndSettle();

    // Ativa o switch "Forcar" da 1a linha.
    await tester.tap(find
        .byKey(const Key('job_row_scraper-cotacoes_forcar_switch')));
    await tester.pumpAndSettle();

    await tester.tap(
        find.byKey(const Key('job_row_scraper-cotacoes_executar_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Dialog de confirmacao aberto, chamada ainda nao disparada.
    expect(find.byKey(const Key('confirm_forcar_button')), findsOneWidget);
    expect(
        rc.calls.any((c) => c.contains('/executar')),
        isFalse,
    );

    await tester.tap(find.byKey(const Key('confirm_forcar_button')));
    await tester.pumpAndSettle();

    expect(
        rc.calls.any((c) =>
            c.startsWith('POST') &&
            c.contains('/api/admin/jobs/scraper-cotacoes/executar') &&
            c.contains('forcar=true')),
        isTrue);
  });

  testWidgets('cancelar o dialog de forcar nao dispara a chamada de rede',
      (tester) async {
    final rc = _recordingCaller();
    await tester.pumpWidget(_wrap(JobsScreen(networkCaller: rc.caller)));
    await tester.pumpAndSettle();

    await tester.tap(find
        .byKey(const Key('job_row_scraper-cotacoes_forcar_switch')));
    await tester.pumpAndSettle();

    await tester.tap(
        find.byKey(const Key('job_row_scraper-cotacoes_executar_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();

    expect(rc.calls.any((c) => c.contains('/executar')), isFalse);
  });

  testWidgets('botao Historico abre dialog e busca o historico do job',
      (tester) async {
    final rc = _recordingCaller(historico: {
      'execucoes': [
        {'inicio': '2026-08-27T03:00:00', 'sucesso': true}
      ]
    });
    await tester.pumpWidget(_wrap(JobsScreen(networkCaller: rc.caller)));
    await tester.pumpAndSettle();

    await tester.tap(
        find.byKey(const Key('job_row_scraper-cotacoes_historico_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('historico_dialog_content')), findsOneWidget);
    expect(
        rc.calls.any((c) =>
            c.startsWith('GET') &&
            c.contains('/api/admin/jobs/scraper-cotacoes/historico')),
        isTrue);
  });

  testWidgets('mostra erro e permite tentar novamente quando o GET falha',
      (tester) async {
    final calls = <String>[];
    var attempt = 0;
    final client = MockClient((request) async {
      calls.add('${request.method} ${request.url}');
      attempt++;
      if (attempt == 1) {
        return http.Response('erro interno', 500);
      }
      return http.Response(
        jsonEncode({'data': _jobsFixture}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final caller = NetworkCaller(client: client);

    await tester.pumpWidget(_wrap(JobsScreen(networkCaller: caller)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('jobs_screen_error')), findsOneWidget);

    await tester.tap(find.byKey(const Key('jobs_screen_retry_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('jobs_screen_error')), findsNothing);
    expect(find.byKey(const Key('job_row_scraper-cotacoes')), findsOneWidget);
  });
}
