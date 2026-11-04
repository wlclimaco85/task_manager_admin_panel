import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/screens/sistema/modulo_tela_grid_screen.dart';

void main() {
  for (final width in [360.0, 1200.0]) {
    testWidgets('telas por modulo sem overflow e pagina 2 em largura $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final paginas = <String?>[];
      final client = MockClient((request) async {
        if (request.url.path.endsWith('modulos-resumo')) {
          return http.Response('[]', 200);
        }
        paginas.add(request.url.queryParameters['pagina']);
        final pagina = request.url.queryParameters['pagina'] ?? '0';
        return http.Response(
            jsonEncode({
              'data': {
                'dados': [
                  {
                    'id': 1,
                    'moduloId': 1,
                    'moduloNome': 'Fiscal',
                    'telaNome': 'tela_pagina_$pagina',
                    'ativo': true
                  }
                ],
                'totalElements': 26,
                'totalPages': 2,
              }
            }),
            200);
      });
      addTearDown(client.close);
      await http.runWithClient(() async {
        await tester
            .pumpWidget(const MaterialApp(home: WebModuloTelaGridScreen()));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }, () => client);
      expect(find.text('tela_pagina_0'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(paginas, ['0', '1']);
      expect(find.text('tela_pagina_1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
