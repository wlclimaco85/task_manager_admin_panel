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

/// CNPJ pertence a uma EMPRESA (id 10) que ja tem 1 usuario e 1 role proprios.
FakeBackend _backend({List<Map<String, dynamic>> usuarios = const []}) {
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
  api.json(
      'GET /api/admin/trial/resolver-cnpj',
      jsonEncode({
        'tipoAlvo': 'EMPRESA',
        'empresaId': 10,
        'empresaNome': 'Padaria do Ze LTDA',
        'usuarios': usuarios,
        'roles': [
          {'id': 5, 'key': 'ROLE_FISCAL', 'description': 'Fiscal da Padaria'}
        ],
      }));
  api.json('GET /api/empresa-modulo', jsonEncode([]));
  api.json('POST /api/empresa-modulo', '{}');
  api.json('POST /api/logins', jsonEncode({'data': {'id': 900}}));
  api.json('POST /api/login/900/roles/5', '{}');
  api.json('POST /api/login/1/roles/5', '{}');
  api.json('PUT /api/admin/trial/solicitacoes/7/status', '{}');
  api.json('DELETE /api/login/900', '{}');
  return api;
}

Future<void> _abrir(WidgetTester tester, FakeBackend api) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: TrialSolicitacoesScreen(networkCaller: NetworkCaller(client: api.client)),
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
  testWidgets('Aprovar localiza a empresa pelo CNPJ, vincula modulos nela e cancelar desfaz (continua PENDENTE)',
      (tester) async {
    final api = _backend();
    await _abrir(tester, api);

    await tester.tap(find.byKey(const Key('trial_aprovar_7')));
    await _assentar(tester);

    expect(find.text('Concessão de Licença & Acessos'), findsOneWidget);
    expect(find.text('Padaria do Ze LTDA'), findsWidgets);
    expect(find.textContaining('NFC-e, Financeiro'), findsOneWidget);
    expect(api.vezes('GET /api/admin/trial/resolver-cnpj'), 1);
    expect(api.vezes('POST /api/empresa-modulo'), 1);
    // nada de cadastrar parceiro sob a empresa de quem esta logado
    expect(api.vezes('POST /api/parceiro/insert'), 0);
    // roles/usuarios vem da resolucao do CNPJ, nao da lista global do sistema
    expect(api.vezes('GET /api/role'), 0);
    expect(api.vezes('GET /api/logins'), 0);

    await tester.tap(find.byKey(const Key('licenca_wizard_fechar_btn')));
    await _assentar(tester);

    expect(api.vezes('PUT /api/admin/trial/solicitacoes/7/status'), 0);
    // compensacao: restaura o conjunto anterior (vazio) de modulos da empresa
    expect(api.vezes('POST /api/empresa-modulo'), 2);
    expect(find.textContaining('continua PENDENTE'), findsOneWidget);
  });

  testWidgets('Aprovar: cria usuario NA empresa do CNPJ, atribui a role e so entao marca APROVADO',
      (tester) async {
    final api = _backend();
    await _abrir(tester, api);

    await tester.tap(find.byKey(const Key('trial_aprovar_7')));
    await _assentar(tester);

    await tester.tap(find.byKey(const Key('licenca_wizard_proximo_btn')));
    await _assentar(tester);
    await tester.tap(find.byKey(const Key('licenca_wizard_criar_usuario_vazio_btn')));
    await _assentar(tester);
    expect(find.widgetWithText(TextFormField, 'ze@padaria.com'), findsOneWidget);
    await tester.tap(find.byKey(const Key('licenca_wizard_novo_usuario_salvar')));
    await _assentar(tester);

    final criar = api.chamadas.indexOf('POST /api/logins');
    final payload = jsonDecode(api.corpos[criar]) as Map<String, dynamic>;
    expect(payload['email'], 'ze@padaria.com');
    expect(payload['empresa'], {'id': 10});
    expect(payload.containsKey('parceiro'), isFalse);

    await tester.tap(find.byKey(const Key('licenca_wizard_proximo_btn')));
    await _assentar(tester);
    await tester.tap(find.byKey(const Key('licenca_wizard_finalizar_btn')));
    await _assentar(tester);

    expect(api.vezes('POST /api/login/900/roles/5'), 1);
    final put = api.chamadas.indexOf('PUT /api/admin/trial/solicitacoes/7/status');
    expect(put, greaterThan(api.chamadas.indexOf('POST /api/login/900/roles/5')));
    expect(jsonDecode(api.corpos[put])['status'], 'APROVADO');
  });

  testWidgets('Aprovar com usuario ja existente na empresa do CNPJ: lista so os dela e atribui a role a ele',
      (tester) async {
    final api = _backend(usuarios: [
      {'id': 1, 'nome': 'Ze da Padaria', 'email': 'ze@padaria.com'}
    ]);
    await _abrir(tester, api);

    await tester.tap(find.byKey(const Key('trial_aprovar_7')));
    await _assentar(tester);
    await tester.tap(find.byKey(const Key('licenca_wizard_proximo_btn')));
    await _assentar(tester);
    expect(find.text('Ze da Padaria'), findsOneWidget);
    await tester.tap(find.byKey(const Key('licenca_wizard_proximo_btn')));
    await _assentar(tester);
    await tester.tap(find.byKey(const Key('licenca_wizard_finalizar_btn')));
    await _assentar(tester);

    expect(api.vezes('POST /api/login/1/roles/5'), 1);
    expect(api.vezes('POST /api/logins'), 0);
  });

  testWidgets('CNPJ que nao e de nenhuma empresa/parceiro: avisa e nao cria nada', (tester) async {
    final api = _backend();
    api.json('GET /api/admin/trial/resolver-cnpj', jsonEncode({'tipoAlvo': 'NAO_ENCONTRADO'}));
    await _abrir(tester, api);

    await tester.tap(find.byKey(const Key('trial_aprovar_7')));
    await _assentar(tester);

    expect(find.textContaining('nao pertence a nenhuma empresa'), findsOneWidget);
    expect(find.text('Concessão de Licença & Acessos'), findsNothing);
    expect(api.vezes('POST /api/empresa-modulo'), 0);
    expect(api.vezes('POST /api/parceiro/insert'), 0);
    expect(api.vezes('PUT /api/admin/trial/solicitacoes/7/status'), 0);
  });

  testWidgets('Aprovar com modulo sem correspondencia avisa e cancelar nao consulta nem vincula nada',
      (tester) async {
    final api = _backend();
    api.json('GET /api/admin/trial/solicitacoes',
        jsonEncode({'data': [{..._solicitacao, 'modulos': '["NFC-e","Modulo Fantasma"]'}]}));
    await _abrir(tester, api);

    await tester.tap(find.byKey(const Key('trial_aprovar_7')));
    await _assentar(tester);

    expect(find.textContaining('Modulo Fantasma'), findsWidgets);
    await tester.tap(find.byKey(const Key('trial_modulos_cancelar_btn')));
    await _assentar(tester);

    expect(api.vezes('GET /api/admin/trial/resolver-cnpj'), 0);
    expect(api.vezes('POST /api/empresa-modulo'), 0);
    expect(api.vezes('PUT /api/admin/trial/solicitacoes/7/status'), 0);
  });
}
