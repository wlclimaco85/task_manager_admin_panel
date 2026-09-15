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
            'data': [
              {'id': 1, 'nome': 'Financeiro', 'descricao': 'Modulo financeiro'},
              {'id': 2, 'nome': 'Estoque', 'descricao': 'Modulo estoque'},
            ],
          });
        }
        if (url.contains('/api/parceiro-modulo')) {
          return jsonResponse([
            {'moduloId': 1, 'valor': 10.0, 'diaVencimento': 5},
          ]);
        }
        if (url.contains('/api/parceiro')) {
          return jsonResponse([
            {'id': parceiroId, 'nome': 'Fazenda Boa Vista'},
          ]);
        }
        return http.Response('Not Found', 404);
      });

      final caller = NetworkCaller(client: client);

      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        home: ModuloAtribuicaoScreen(networkCaller: caller),
      ));
      await tester.pumpAndSettle();

      await carregarParceiro(tester);

      expect(find.text('Encontrado: Fazenda Boa Vista'), findsOneWidget);
      expect(find.byKey(const Key('modulo_atribuicao_checkbox_1')), findsOneWidget);
      expect(find.byKey(const Key('modulo_atribuicao_checkbox_2')), findsOneWidget);

      final checkboxFinanceiro = tester.widget<Checkbox>(
        find.byKey(const Key('modulo_atribuicao_checkbox_1')),
      );
      final checkboxEstoque = tester.widget<Checkbox>(
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
            'data': [
              {'id': 1, 'nome': 'Financeiro', 'descricao': 'Modulo financeiro'},
            ],
          });
        }
        if (url.contains('/api/parceiro-modulo')) {
          return jsonResponse(<Map<String, dynamic>>[]);
        }
        if (url.contains('/api/parceiro')) {
          return jsonResponse([
            {'id': parceiroId, 'nome': 'Fazenda Boa Vista'},
          ]);
        }
        return http.Response('Not Found', 404);
      });

      final caller = NetworkCaller(client: client);

      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        home: ModuloAtribuicaoScreen(networkCaller: caller),
      ));
      await tester.pumpAndSettle();

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
            'data': [
              {'id': 1, 'nome': 'Financeiro', 'descricao': 'Modulo financeiro'},
              {'id': 2, 'nome': 'Estoque', 'descricao': 'Modulo estoque'},
            ],
          });
        }
        if (url.contains('/api/parceiro-modulo')) {
          return jsonResponse([
            {'moduloId': 1, 'valor': 10.0, 'diaVencimento': 5},
          ]);
        }
        if (url.contains('/api/parceiro')) {
          return jsonResponse([
            {'id': parceiroId, 'nome': 'Fazenda Boa Vista'},
          ]);
        }
        return http.Response('Not Found', 404);
      });

      final caller = NetworkCaller(client: client);

      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        home: ModuloAtribuicaoScreen(networkCaller: caller),
      ));
      await tester.pumpAndSettle();

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

    testWidgets(
        'calcula subtotal comercial: 1 a 3 modulos somam e mais de 3 modulos fixa em 129,90 com 1 mes gratis',
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
            'data': [
              {'id': 1, 'nome': 'Financeiro', 'descricao': 'Mod Financeiro', 'valor': 49.90},
              {'id': 2, 'nome': 'Estoque', 'descricao': 'Mod Estoque', 'valor': 49.90},
              {'id': 3, 'nome': 'Fiscal', 'descricao': 'Mod Fiscal', 'valor': 49.90},
              {'id': 4, 'nome': 'Vendas', 'descricao': 'Mod Vendas', 'valor': 49.90},
            ],
          });
        }
        if (url.contains('/api/parceiro-modulo')) {
          return jsonResponse(<Map<String, dynamic>>[]);
        }
        if (url.contains('/api/parceiro')) {
          return jsonResponse([
            {'id': parceiroId, 'nome': 'Fazenda Boa Vista'},
          ]);
        }
        return http.Response('Not Found', 404);
      });

      final caller = NetworkCaller(client: client);

      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        home: ModuloAtribuicaoScreen(networkCaller: caller),
      ));
      await tester.pumpAndSettle();

      await carregarParceiro(tester);

      // Badge de 1º Mês Grátis presente
      expect(find.text('1º Mês Grátis de Avaliação!'), findsOneWidget);

      // Inicialmente 0 modulos -> R$ 0,00/mês
      expect(find.text('R\$ 0,00/mês'), findsOneWidget);

      // Marca 1 modulo (49,90)
      await tester.tap(find.byKey(const Key('modulo_atribuicao_checkbox_1')));
      await tester.pumpAndSettle();
      expect(find.text('R\$ 49,90/mês'), findsOneWidget);

      // Marca 2º modulo (+49,90 = 99,80)
      await tester.tap(find.byKey(const Key('modulo_atribuicao_checkbox_2')));
      await tester.pumpAndSettle();
      expect(find.text('R\$ 99,80/mês'), findsOneWidget);

      // Marca 3º modulo (+49,90 = 149,70)
      await tester.tap(find.byKey(const Key('modulo_atribuicao_checkbox_3')));
      await tester.pumpAndSettle();
      expect(find.text('R\$ 149,70/mês'), findsOneWidget);

      // Marca 4º modulo (> 3 modulos): regra comercial aplica valor fixo de R$ 129,90/mês
      await tester.tap(find.byKey(const Key('modulo_atribuicao_checkbox_4')));
      await tester.pumpAndSettle();
      expect(find.text('R\$ 129,90/mês'), findsOneWidget);
      expect(
        find.text('Pacote Ilimitado (> 3 módulos): valor especial fixo de R\$ 129,90/mês!'),
        findsOneWidget,
      );
    });

    testWidgets('clicar em Conceder Licenca abre o LicencaWizardDialog com progresso',
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
            'data': [
              {'id': 1, 'nome': 'Financeiro', 'descricao': 'Mod Financeiro'},
            ],
          });
        }
        if (url.contains('/api/parceiro-modulo')) {
          return jsonResponse([
            {'moduloId': 1, 'valor': 10.0, 'diaVencimento': 5},
          ]);
        }
        if (url.contains(ApiLinks.allRoles)) {
          return jsonResponse([
            {'id': 10, 'role': 'ROLE_FINANCEIRO'},
          ]);
        }
        if (url.contains('/api/logins')) {
          return jsonResponse([
            {'id': 101, 'nome': 'Joao Silva', 'login': 'joao'},
          ]);
        }
        if (url.contains('/api/parceiro')) {
          return jsonResponse([
            {'id': parceiroId, 'nome': 'Fazenda Boa Vista'},
          ]);
        }
        return http.Response('Not Found', 404);
      });

      final caller = NetworkCaller(client: client);

      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        home: ModuloAtribuicaoScreen(networkCaller: caller),
      ));
      await tester.pumpAndSettle();

      await carregarParceiro(tester);

      // Clica no botão Conceder Licença
      await tester.tap(find.byKey(const Key('modulo_atribuicao_conceder_licenca_btn')));
      await tester.pumpAndSettle();

      // Verifica se o diálogo do Wizard abriu
      expect(find.text('Concessão de Licença & Acessos'), findsOneWidget);
      expect(find.text('1. Role de Acesso'), findsOneWidget);
      expect(find.text('2. Usuários'), findsOneWidget);
      expect(find.text('3. Finalizar'), findsOneWidget);
    });
  });
}
