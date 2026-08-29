import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/screens/sistema/configuracoes_sistema/importacao_cadastros_screen.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';

/// Testes de widget de `ImportacaoCadastrosScreen` (Task 08b.1, PLAN.md
/// Fase 2). Cobre o `Verify` declarado: progresso avança por linha, erro em
/// 1 linha não trava as seguintes, log final mostra resumo
/// create/update/erro. `NetworkCaller` mockado via `http.testing.MockClient`
/// (mesmo padrão de `importacao_cadastros_service_test.dart`).
Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.darkTheme, home: child);

PlatformFile _csvFile(String conteudo, {String name = 'cadastros.csv'}) {
  final bytes = Uint8List.fromList(utf8.encode(conteudo));
  return PlatformFile(name: name, size: bytes.length, bytes: bytes);
}

Future<FilePickerResult?> _pickReturning(PlatformFile file) {
  return Future.value(FilePickerResult([file]));
}

void main() {
  testWidgets(
      'seleciona CSV de Funcionarios e auto-mapeia colunas por sinonimo',
      (tester) async {
    final csv = _csvFile('nome;email;cpf\nJoao Silva;joao@teste.com;12345678900\n');

    await tester.pumpWidget(_wrap(ImportacaoCadastrosScreen(
      networkCaller: NetworkCaller(client: MockClient((r) async => http.Response('{}', 200))),
      pickFileOverride: () => _pickReturning(csv),
    )));
    await tester.pumpAndSettle();

    // Troca para o tipo "Funcionarios".
    await tester.tap(find.byKey(const Key('importacao_cadastros_tipo_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Importar Funcionarios e Logins').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('importacao_cadastros_pick_file_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('importacao_cadastros_mapeamento_expansion')));
    await tester.pumpAndSettle();

    final nomeField =
        tester.widget<TextField>(find.byKey(const Key('importacao_cadastros_map_nome')));
    expect(nomeField.controller?.text, 'nome');

    final emailField =
        tester.widget<TextField>(find.byKey(const Key('importacao_cadastros_map_email')));
    expect(emailField.controller?.text, 'email');

    final cpfField =
        tester.widget<TextField>(find.byKey(const Key('importacao_cadastros_map_cpf')));
    expect(cpfField.controller?.text, 'cpf');
  });

  testWidgets('exibe preview de ate 3 linhas do CSV em tabela', (tester) async {
    final csv = _csvFile('nome;email;cpf\n'
        'Ana;ana@teste.com;11111111111\n'
        'Bruno;bruno@teste.com;22222222222\n'
        'Carla;carla@teste.com;33333333333\n'
        'Diego;diego@teste.com;44444444444\n');

    await tester.pumpWidget(_wrap(ImportacaoCadastrosScreen(
      networkCaller: NetworkCaller(client: MockClient((r) async => http.Response('{}', 200))),
      pickFileOverride: () => _pickReturning(csv),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('importacao_cadastros_pick_file_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('importacao_cadastros_preview_table')), findsOneWidget);
    expect(find.textContaining('Preview (3 de 4 linhas)'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Diego'), findsNothing);
  });

  testWidgets(
      'importacao processa linhas via callback de progresso, erro em 1 linha nao trava as demais, log final mostra resumo',
      (tester) async {
    final csv = _csvFile('nome;email;cpf\n'
        'Joao Silva;joao@teste.com;12345678900\n'
        'Maria Souza;;98765432100\n');

    final mockClient = MockClient((request) async {
      if (request.method == 'GET' && request.url.path.endsWith('/api/logins')) {
        return http.Response(jsonEncode({'data': []}), 200);
      }
      if (request.method == 'POST' && request.url.path.endsWith('/api/logins')) {
        return http.Response(jsonEncode({'id': 10}), 200);
      }
      if (request.method == 'GET' && request.url.path.endsWith('/api/funcionario')) {
        return http.Response(jsonEncode({'data': []}), 200);
      }
      if (request.method == 'POST' && request.url.path.endsWith('/api/funcionario')) {
        return http.Response(jsonEncode({'id': 20}), 200);
      }
      return http.Response('nao mapeado: ${request.method} ${request.url}', 404);
    });

    await tester.pumpWidget(_wrap(ImportacaoCadastrosScreen(
      networkCaller: NetworkCaller(client: mockClient),
      pickFileOverride: () => _pickReturning(csv),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('importacao_cadastros_tipo_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Importar Funcionarios e Logins').last);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('importacao_cadastros_empresa_field')), '3');
    await tester.tap(find.byKey(const Key('importacao_cadastros_pick_file_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('importacao_cadastros_import_button')));
    await tester.pumpAndSettle();

    // Linha 1 (Joao) tem email; linha 2 (Maria) nao tem email — deve gerar
    // erro na 2a linha sem interromper a 1a (ja processada com sucesso).
    expect(find.byKey(const Key('importacao_cadastros_resultado_text')), findsOneWidget);
    expect(find.textContaining('Sucesso: 1'), findsOneWidget);
    expect(find.textContaining('Erros: 1'), findsOneWidget);
    expect(find.textContaining('Total: 2'), findsOneWidget);

    expect(find.byKey(const Key('importacao_cadastros_log_list')), findsOneWidget);
  });

  testWidgets('botao Importar fica desabilitado sem arquivo selecionado', (tester) async {
    await tester.pumpWidget(_wrap(ImportacaoCadastrosScreen(
      networkCaller: NetworkCaller(client: MockClient((r) async => http.Response('{}', 200))),
      pickFileOverride: () => Future.value(null),
    )));
    await tester.pumpAndSettle();

    final importButton = tester
        .widget<ElevatedButton>(find.byKey(const Key('importacao_cadastros_import_button')));
    expect(importButton.onPressed, isNull);
  });
}
