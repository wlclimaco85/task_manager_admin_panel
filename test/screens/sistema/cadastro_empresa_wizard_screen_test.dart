import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/screens/sistema/cadastro_empresa_wizard_screen.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.darkTheme,
      home: child,
    );

/// [NetworkCaller] cujo client responde com sucesso a qualquer GET (listas
/// vazias de aplicativo/role) e devolve um `id` incremental para cada POST
/// — suficiente para o passo "Executar" completar sem falhar.
NetworkCaller _successCaller({List<String>? postPaths}) {
  var nextId = 1;
  final client = MockClient((request) async {
    if (request.method == 'GET') {
      return http.Response(
        jsonEncode({'data': <dynamic>[]}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    postPaths?.add('${request.method} ${request.url.path}');
    return http.Response(
      jsonEncode({'id': nextId++}),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  return NetworkCaller(client: client);
}

Future<void> _preencherEmpresaEAvancar(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('empresa_nome_field')),
    'Empresa Teste',
  );
  await tester.pump();
  await tester.ensureVisible(find.byKey(const Key('wizard_next_button')));
  await tester.tap(find.byKey(const Key('wizard_next_button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('navega pelos 7 passos do wizard', (tester) async {
    await tester.pumpWidget(_wrap(
      CadastroEmpresaWizardScreen(networkCaller: _successCaller()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Dados da Empresa'), findsOneWidget);

    // Passo 1 -> 2 exige nome da empresa preenchido (mesma validacao do
    // arquivo original).
    await tester.ensureVisible(find.byKey(const Key('wizard_next_button')));
    await tester.tap(find.byKey(const Key('wizard_next_button')));
    await tester.pumpAndSettle();
    expect(find.text('Dados da Empresa'), findsOneWidget,
        reason: 'nao deve avancar sem nome da empresa');

    await _preencherEmpresaEAvancar(tester);
    expect(find.text('2 Usuários (Admin + Financeiro)'), findsOneWidget);

    // Usuarios ja vem pre-preenchidos (defaults) -> avanca livre.
    await tester.ensureVisible(find.byKey(const Key('wizard_next_button')));
    await tester.tap(find.byKey(const Key('wizard_next_button')));
    await tester.pumpAndSettle();
    expect(find.text('5 Clientes'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('wizard_next_button')));
    await tester.tap(find.byKey(const Key('wizard_next_button')));
    await tester.pumpAndSettle();
    expect(find.text('5 Contas a Pagar + 5 a Receber'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('wizard_next_button')));
    await tester.tap(find.byKey(const Key('wizard_next_button')));
    await tester.pumpAndSettle();
    expect(find.text('Chamados + Chat'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('wizard_next_button')));
    await tester.tap(find.byKey(const Key('wizard_next_button')));
    await tester.pumpAndSettle();
    expect(find.text('5 Funcionários'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('wizard_next_button')));
    await tester.tap(find.byKey(const Key('wizard_next_button')));
    await tester.pumpAndSettle();
    expect(find.text('Resumo'), findsOneWidget);
    expect(find.byKey(const Key('wizard_execute_button')), findsOneWidget);

    // Volta ao passo 1 clicando no indicador.
    await tester.tap(find.byKey(const Key('wizard_step_0')));
    await tester.pumpAndSettle();
    expect(find.text('Dados da Empresa'), findsOneWidget);
  });

  testWidgets('passo Executar aciona o service e reflete o log na tela',
      (tester) async {
    final postPaths = <String>[];
    await tester.pumpWidget(_wrap(
      CadastroEmpresaWizardScreen(
        networkCaller: _successCaller(postPaths: postPaths),
      ),
    ));
    await tester.pumpAndSettle();

    await _preencherEmpresaEAvancar(tester);
    for (var i = 0; i < 5; i++) {
      await tester.ensureVisible(find.byKey(const Key('wizard_next_button')));
      await tester.tap(find.byKey(const Key('wizard_next_button')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Resumo'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('wizard_execute_button')));
    await tester.tap(find.byKey(const Key('wizard_execute_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wizard_done_indicator')), findsOneWidget);
    expect(find.byKey(const Key('wizard_log_list')), findsOneWidget);
    // 1 empresa + 2 usuarios + 5x(parceiro+login) + 5 pagar + 5 receber +
    // 1 nfe + 3 chamados + 1 chat + 5x(parceiro+login) = 38 POSTs.
    expect(postPaths.length, 38);
    expect(postPaths.any((p) => p.contains('/api/empresa')), isTrue);
  });

  testWidgets('falha na execucao mostra indicador de erro e permite tentar novamente',
      (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({'data': <dynamic>[]}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'DELETE') return http.Response('', 200);
      return http.Response('erro', 500);
    });

    await tester.pumpWidget(_wrap(
      CadastroEmpresaWizardScreen(networkCaller: NetworkCaller(client: client)),
    ));
    await tester.pumpAndSettle();

    await _preencherEmpresaEAvancar(tester);
    for (var i = 0; i < 5; i++) {
      await tester.ensureVisible(find.byKey(const Key('wizard_next_button')));
      await tester.tap(find.byKey(const Key('wizard_next_button')));
      await tester.pumpAndSettle();
    }

    await tester.ensureVisible(find.byKey(const Key('wizard_execute_button')));
    await tester.tap(find.byKey(const Key('wizard_execute_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wizard_failed_indicator')), findsOneWidget);
    expect(find.byKey(const Key('wizard_reset_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('wizard_reset_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wizard_execute_button')), findsOneWidget);
  });
}
