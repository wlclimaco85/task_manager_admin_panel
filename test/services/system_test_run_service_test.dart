import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/services/system_test_run_service.dart';

void main() {
  test('inicia fase 1 em homologacao e interpreta progresso', () async {
    late http.Request captured;
    final service = SystemTestRunService(client: MockClient((request) async {
      captured = request;
      return http.Response(
          jsonEncode({
            'runId': 'run-1',
            'marker': 'E2E-1',
            'environment': 'HOMOLOGACAO',
            'status': 'RUNNING',
            'progressPercent': 37,
            'totalOperations': 100,
            'completedOperations': 37,
            'successCount': 37,
            'failureCount': 0,
            'cleanedCount': 0,
            'residueCount': 0,
          }),
          202);
    }));

    final run = await service.start('token-real', const ['FASE_1']);

    expect(captured.method, 'POST');
    expect(captured.headers['authorization'], 'Bearer token-real');
    expect(jsonDecode(captured.body), {
      'environment': 'HOMOLOGACAO',
      'groups': ['FASE_1']
    });
    expect(run.progressPercent, 37);
    expect(run.isActive, isTrue);
  });

  test('propaga status e corpo quando backend rejeita execucao', () async {
    final service = SystemTestRunService(
        client: MockClient((_) async =>
            http.Response('{"message":"Somente homologacao"}', 400)));

    expect(
        () => service.start('token', const ['FASE_1']),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('400'))));
  });

  test('retoma a execucao ativa devolvida com 409', () async {
    final service = SystemTestRunService(
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'runId': 'run-active',
              'marker': 'E2E-ACTIVE',
              'environment': 'HOMOLOGACAO',
              'status': 'RUNNING',
              'progressPercent': 42,
            }),
            409)));

    final run = await service.start('token', const ['FASE_1']);

    expect(run.runId, 'run-active');
    expect(run.progressPercent, 42);
    expect(run.isActive, isTrue);
  });

  test('envia grupo agregado da fase 2 sem alterar o ambiente', () async {
    late http.Request captured;
    final service = SystemTestRunService(client: MockClient((request) async {
      captured = request;
      return http.Response(
          jsonEncode({
            'runId': 'run-2',
            'marker': 'E2E-2',
            'environment': 'HOMOLOGACAO',
            'status': 'PENDING',
          }),
          202);
    }));

    await service.start('token', const ['FASE_2']);

    expect(jsonDecode(captured.body), {
      'environment': 'HOMOLOGACAO',
      'groups': ['FASE_2']
    });
  });
}
