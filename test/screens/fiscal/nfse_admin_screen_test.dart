import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/screens/fiscal/nfse_admin_screen.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';

void main() {
  testWidgets('lista NFS-e do dono e confirma rascunho pelo endpoint real',
      (tester) async {
    var confirmou = false;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/api/modulo-atribuicao/nfse')) {
        return http.Response(
          jsonEncode([
            {
              'id': 77,
              'parceiro': 'Cliente Fiscal',
              'empresa': 'Contabilidade Central',
              'status': 'RASCUNHO',
              'valor_servicos': 129.90,
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'POST' &&
          request.url.path.endsWith('/api/nfse/77/confirmar')) {
        confirmou = true;
        return http.Response(
          jsonEncode({'id': 77, 'status': 'CONFIRMADA'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('Not Found', 404);
    });

    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: NfseAdminScreen(networkCaller: NetworkCaller(client: client)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Cliente Fiscal'), findsOneWidget);
    expect(find.text('RASCUNHO'), findsOneWidget);
    await tester.tap(find.byKey(const Key('nfse_admin_confirmar_77')));
    await tester.pumpAndSettle();

    expect(confirmou, isTrue);
    expect(find.text('NFS-e confirmada.'), findsOneWidget);
  });
}
