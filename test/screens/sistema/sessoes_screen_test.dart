import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/screens/sistema/sessoes_screen.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';

/// Bug de producao (2026-09-11): sessoes zumbis (JWT valido por 10h sem
/// revogacao server-side) causavam erro 429 toda manha. Tela App do Dono
/// > Sistema > Sessoes permite matar sessao manualmente.
void main() {
  http.Response jsonResponse(dynamic body, {int status = 200}) {
    return http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
  }

  Widget wrap(NetworkCaller caller) => MaterialApp(
        home: SessoesScreen(networkCaller: caller),
      );

  testWidgets('renderiza lista de sessoes ativas e ociosas', (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path.contains('/api/sessoes')) {
        return jsonResponse([
          {
            'loginId': 1,
            'nome': 'Fulano',
            'email': 'fulano@teste.com',
            'empresaNome': 'Empresa A',
            'ultimoAcesso': '2026-09-11T08:00:00',
            'sessaoInvalidadaEm': null,
            'ativa': true,
            'ociosa': false,
          },
          {
            'loginId': 2,
            'nome': 'Ciclana',
            'email': 'ciclana@teste.com',
            'empresaNome': 'Empresa B',
            'ultimoAcesso': '2026-09-11T06:00:00',
            'sessaoInvalidadaEm': null,
            'ativa': true,
            'ociosa': true,
          },
        ]);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(wrap(NetworkCaller(client: client)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Fulano'), findsOneWidget);
    expect(find.textContaining('Ciclana'), findsOneWidget);
    expect(find.textContaining('OCIOSA'), findsOneWidget);
    expect(find.text('Matar sessão'), findsNWidgets(2));
  });

  testWidgets('matar sessao chama o endpoint e recarrega a lista', (tester) async {
    var chamouMatar = false;
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path.contains('/api/sessoes')) {
        return jsonResponse([
          {
            'loginId': 5,
            'nome': 'Alguem',
            'email': 'alguem@teste.com',
            'empresaNome': 'Empresa C',
            'ultimoAcesso': '2026-09-11T08:00:00',
            'ativa': true,
            'ociosa': false,
          },
        ]);
      }
      if (request.method == 'POST' && request.url.path.contains('/matar')) {
        chamouMatar = true;
        return jsonResponse({'sucesso': true, 'loginId': 5});
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(wrap(NetworkCaller(client: client)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Matar sessão'));
    await tester.pumpAndSettle();

    // Confirma o dialog
    await tester.tap(find.widgetWithText(FilledButton, 'Matar sessão'));
    await tester.pumpAndSettle();

    expect(chamouMatar, isTrue);
  });

  testWidgets('erro ao carregar mostra mensagem e botao de tentar novamente', (tester) async {
    final client = MockClient((request) async {
      return http.Response('erro', 500);
    });

    await tester.pumpWidget(wrap(NetworkCaller(client: client)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Não foi possível carregar'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
  });
}
