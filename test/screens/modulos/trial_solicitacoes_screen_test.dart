import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/screens/modulos/trial_solicitacoes_screen.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';

import '../../helpers/fake_backend.dart';

const _solicitacao = {
  'id': 7,
  'nome': 'Padaria do Ze',
  'email': 'ze@padaria.com',
  'cnpj': '12345678000190',
  'localizacao': 'Sao Paulo - SP',
  'modulos': '["NFC-e","Financeiro"]',
  'valorTotal': 99.8,
  'status': 'PENDENTE',
};

FakeBackend _backend({List<Map<String, dynamic>> logins = const []}) {
  final api = FakeBackend();
  api.json('GET /api/admin/trial/solicitacoes', jsonEncode({'data': [_solicitacao]}));
  api.json(
      'GET /api/modulo-servico',
      jsonEncode({
        'data': [
          {'id': 1, 'nome': 'NFC-e'},
          {'id': 2, 'nome': 'Financeiro'},
        ]
      }));
  api.json('GET /api/parceiro', jsonEncode({'data': {'dados': []}}));
  api.json('POST /api/parceiro/insert', jsonEncode({'data': {'id': 416}}));
  api.json('POST /api/parceiro-modulo', '{}');
  api.json('GET /api/role', jsonEncode({'data': {'dados': [{'id': 5, 'description': 'Financeiro'}]}}));
  api.json('GET /api/logins', jsonEncode({'data': {'dados': logins}}));
  api.json('POST /api/logins', jsonEncode({'data': {'id': 900}}));
  api.json('POST /api/login/900/roles/5', '{}');
  api.json('PUT /api/admin/trial/solicitacoes/7/status', '{}');
  api.json('DELETE /api/parceiro/416', '{}');
  api.json('DELETE /api/login/900', '{}');
  return api;
}

Future<void> _abrir(WidgetTester tester, FakeBackend api) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: TrialSolicitacoesScreen(
      networkCaller: NetworkCaller(client: api.client),
      empresaIdProvider: () => 1,
    ),
  ));
  await _assentar(tester);
}

/// O botao Aprovar mostra um spinner (animacao infinita) enquanto o fluxo roda;
/// pumpAndSettle nunca assentaria, entao bombeia quadros por tempo fixo.
Future<void> _assentar(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('Aprovar cria o cliente, abre o popup de licenca e cancelar desfaz tudo (continua PENDENTE)',
      (tester) async {
    final api = _backend();
    await _abrir(tester, api);

    await tester.tap(find.byKey(const Key('trial_aprovar_7')));
    await _assentar(tester);

    // Popup identico ao de Atribuicao de Modulos, ja com o cliente e os modulos
    expect(find.text('Concessão de Licença & Acessos'), findsOneWidget);
    expect(find.text('Padaria do Ze'), findsWidgets);
    expect(find.textContaining('NFC-e, Financeiro'), findsOneWidget);
    expect(api.vezes('POST /api/parceiro/insert'), 1);
    expect(api.vezes('POST /api/parceiro-modulo'), 1);

    await tester.tap(find.byKey(const Key('licenca_wizard_fechar_btn')));
    await _assentar(tester);

    expect(api.vezes('PUT /api/admin/trial/solicitacoes/7/status'), 0);
    expect(api.vezes('DELETE /api/parceiro/416'), 1);
    expect(find.textContaining('continua PENDENTE'), findsOneWidget);
  });

  testWidgets('Aprovar: cria usuario com o e-mail da solicitacao, atribui a role e so entao marca APROVADO',
      (tester) async {
    final api = _backend();
    await _abrir(tester, api);

    await tester.tap(find.byKey(const Key('trial_aprovar_7')));
    await _assentar(tester);

    await tester.tap(find.byKey(const Key('licenca_wizard_proximo_btn')));
    await _assentar(tester);
    // Etapa 2: sem usuarios -> criar usuario (dialogo ja vem com o e-mail da solicitacao)
    await tester.tap(find.byKey(const Key('licenca_wizard_criar_usuario_vazio_btn')));
    await _assentar(tester);
    expect(find.widgetWithText(TextFormField, 'ze@padaria.com'), findsOneWidget);
    await tester.tap(find.byKey(const Key('licenca_wizard_novo_usuario_salvar')));
    await _assentar(tester);

    final criar = api.chamadas.indexOf('POST /api/logins');
    final payload = jsonDecode(api.corpos[criar]) as Map<String, dynamic>;
    expect(payload['email'], 'ze@padaria.com');
    expect(payload['parceiro'], {'id': 416});
    expect(payload['empresa'], {'id': 1});

    await tester.tap(find.byKey(const Key('licenca_wizard_proximo_btn')));
    await _assentar(tester);
    await tester.tap(find.byKey(const Key('licenca_wizard_finalizar_btn')));
    await _assentar(tester);

    expect(api.vezes('POST /api/login/900/roles/5'), 1);
    final put = api.chamadas.indexOf('PUT /api/admin/trial/solicitacoes/7/status');
    expect(put, greaterThan(api.chamadas.indexOf('POST /api/login/900/roles/5')));
    expect(jsonDecode(api.corpos[put])['status'], 'APROVADO');
    expect(api.vezes('DELETE /api/parceiro/416'), 0);
  });

  testWidgets('Aprovar com modulo sem correspondencia avisa e cancelar nao cria nada', (tester) async {
    final api = _backend();
    api.json('GET /api/admin/trial/solicitacoes',
        jsonEncode({'data': [{..._solicitacao, 'modulos': '["NFC-e","Modulo Fantasma"]'}]}));
    await _abrir(tester, api);

    await tester.tap(find.byKey(const Key('trial_aprovar_7')));
    await _assentar(tester);

    expect(find.textContaining('Modulo Fantasma'), findsWidgets);
    await tester.tap(find.byKey(const Key('trial_modulos_cancelar_btn')));
    await _assentar(tester);

    expect(api.vezes('POST /api/parceiro/insert'), 0);
    expect(api.vezes('PUT /api/admin/trial/solicitacoes/7/status'), 0);
  });
}
