import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/config/api_links.dart';
import 'package:task_manager_admin_panel/screens/modulos/modulo_atribuicao_screen.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';

void main() {
  const parceiroId = 42;

  http.Response jsonResponse(dynamic body, {int status = 200}) {
    return http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
  }

  Future<void> carregarParceiro(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('modulo_atribuicao_id_field')),
      parceiroId.toString(),
    );
    await tester.tap(find.byKey(const Key('modulo_atribuicao_carregar_btn')));
    await tester.pumpAndSettle();
  }

  group('ModuloAtribuicaoScreen', () {
    testWidgets(
        'carregar parceiro valido mostra catalogo com itens pre-marcados conforme parceiro-modulo',
        (tester) async {
      final client = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('/api/parceiro/$parceiroId')) {
          return jsonResponse({
            'data': {'id': parceiroId, 'nome': 'Fazenda Boa Vista'},
          });
        }
        if (url.contains(ApiLinks.allModulosServico.split('?').first)) {
          return jsonResponse({
            'data': {
              'dados': [
                {'id': 1, 'nome': 'Financeiro', 'descricao': 'Modulo financeiro'},
                {'id': 2, 'nome': 'Estoque', 'descricao': 'Modulo estoque'},
              ],
              'totalElements': 2,
            },
          });
        }
        if (url.contains('/api/parceiro-modulo')) {
          return jsonResponse([
            {'moduloId': 1, 'valor': 10.0, 'diaVencimento': 5},
          ]);
        }
        return http.Response('Not Found', 404);
      });

      final caller = NetworkCaller(client: client);

      await tester.pumpWidget(MaterialApp(
        home: ModuloAtribuicaoScreen(),
      ));
      await tester.pump();

      await carregarParceiro(tester);

      expect(find.text('Encontrado: Fazenda Boa Vista'), findsOneWidget);
      expect(find.byKey(const Key('modulo_atribuicao_checkbox_1')), findsOneWidget);
      expect(find.byKey(const Key('modulo_atribuicao_checkbox_2')), findsOneWidget);

      final checkboxFinanceiro = tester.widget<CheckboxListTile>(
        find.byKey(const Key('modulo_atribuicao_checkbox_1')),
      );
      final checkboxEstoque = tester.widget<CheckboxListTile>(
        find.byKey(const Key('modulo_atribuicao_checkbox_2')),
      );

      expect(checkboxFinanceiro.value, isTrue);
      expect(checkboxEstoque.value, isFalse);
    });

    testWidgets('salvar sem confirmar o dialog nao dispara o POST',
        (tester) async {
      var postDisparado = false;
      final client = MockClient((request) async {
        final url = request.url.toString();
        if (request.method == 'POST') {
          postDisparado = true;
          return jsonResponse({'data': {}});
        }
        if (url.contains('/api/parceiro/$parceiroId')) {
          return jsonResponse({
            'data': {'id': parceiroId, 'nome': 'Fazenda Boa Vista'},
          });
        }
        if (url.contains(ApiLinks.allModulosServico.split('?').first)) {
          return jsonResponse({
            'data': {
              'dados': [
                {'id': 1, 'nome': 'Financeiro', 'descricao': 'Modulo financeiro'},
              ],
              'totalElements': 1,
            },
          });
        }
        if (url.contains('/api/parceiro-modulo')) {
          return jsonResponse(<Map<String, dynamic>>[]);
        }
        return http.Response('Not Found', 404);
      });

      final caller = NetworkCaller(client: client);

      await tester.pumpWidget(MaterialApp(
        home: ModuloAtribuicaoScreen(),
      ));
      await tester.pump();

      await carregarParceiro(tester);

      await tester.tap(find.byKey(const Key('modulo_atribuicao_salvar_btn')));
      await tester.pumpAndSettle();

      // Dialog de confirmacao aberto — cancelar em vez de confirmar.
      expect(find.byKey(const Key('modulo_atribuicao_confirmar_btn')), findsOneWidget);
      await tester.tap(find.byKey(const Key('modulo_atribuicao_cancelar_btn')));
      await tester.pumpAndSettle();

      expect(postDisparado, isFalse);
    });

    testWidgets('confirmar o dialog dispara POST com o moduloIds esperado',
        (tester) async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        final url = request.url.toString();
        if (request.method == 'POST') {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return jsonResponse({'data': {}});
        }
        if (url.contains('/api/parceiro/$parceiroId')) {
          return jsonResponse({
            'data': {'id': parceiroId, 'nome': 'Fazenda Boa Vista'},
          });
        }
        if (url.contains(ApiLinks.allModulosServico.split('?').first)) {
          return jsonResponse({
            'data': {
              'dados': [
                {'id': 1, 'nome': 'Financeiro', 'descricao': 'Modulo financeiro'},
                {'id': 2, 'nome': 'Estoque', 'descricao': 'Modulo estoque'},
              ],
              'totalElements': 2,
            },
          });
        }
        if (url.contains('/api/parceiro-modulo')) {
          return jsonResponse([
            {'moduloId': 1, 'valor': 10.0, 'diaVencimento': 5},
          ]);
        }
        return http.Response('Not Found', 404);
      });

      final caller = NetworkCaller(client: client);

      await tester.pumpWidget(MaterialApp(
        home: ModuloAtribuicaoScreen(),
      ));
      await tester.pump();

      await carregarParceiro(tester);

      // Marca o modulo 2 (Estoque), que veio desmarcado.
      await tester.tap(find.byKey(const Key('modulo_atribuicao_checkbox_2')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('modulo_atribuicao_salvar_btn')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('modulo_atribuicao_confirmar_btn')));
      await tester.pumpAndSettle();

      expect(capturedBody, isNotNull);
      expect(capturedBody!['parceiroId'], parceiroId);
      expect(
        Set<int>.from(capturedBody!['moduloIds'] as List),
        {1, 2},
      );
    });
  });
}
