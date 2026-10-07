import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';
import 'package:task_manager_admin_panel/services/trial_aprovacao_service.dart';

import '../helpers/fake_backend.dart';

const _catalogo = [
  {'id': 1, 'nome': 'NFC-e'},
  {'id': 2, 'nome': 'Financeiro'},
  {'id': 3, 'nome': 'Departamento Pessoal'},
];

List<Map<String, dynamic>> _catalogoMapas() =>
    _catalogo.map((m) => Map<String, dynamic>.from(m)).toList();

Map<String, dynamic> _solicitacao({String modulos = '["NFC-e","Financeiro"]'}) => {
      'id': 7,
      'nome': 'Padaria do Ze',
      'email': 'ze@padaria.com',
      'cnpj': '12.345.678/0001-90',
      'localizacao': 'Sao Paulo - SP',
      'modulos': modulos,
    };

void main() {
  group('mapeamento de modulos', () {
    test('parseModulosNomes le JSON array, lista e texto separado por virgula', () {
      expect(TrialAprovacaoService.parseModulosNomes('["NFC-e","Financeiro"]'),
          ['NFC-e', 'Financeiro']);
      expect(TrialAprovacaoService.parseModulosNomes(['A', 'a ', 'B']), ['A', 'B']);
      expect(TrialAprovacaoService.parseModulosNomes('NFC-e, Financeiro'),
          ['NFC-e', 'Financeiro']);
      expect(TrialAprovacaoService.parseModulosNomes(null), isEmpty);
      expect(TrialAprovacaoService.parseModulosNomes('[]'), isEmpty);
    });

    test('mapearModulos ignora acento/caixa/pontuacao e informa os nao encontrados', () {
      final mapa = TrialAprovacaoService.mapearModulos(
        ['NFCe', 'financeiro', 'Departamento Pessoal', 'Modulo Inexistente'],
        _catalogoMapas(),
      );
      expect(mapa.ids, [1, 2, 3]);
      expect(mapa.naoEncontrados, ['Modulo Inexistente']);
      expect(mapa.temCorrespondencia, isTrue);
    });

    test('catalogo vazio => sem correspondencia, tudo em naoEncontrados', () {
      final mapa = TrialAprovacaoService.mapearModulos(['NFC-e'], const []);
      expect(mapa.temCorrespondencia, isFalse);
      expect(mapa.naoEncontrados, ['NFC-e']);
    });

    test('cancelar o popup (false/null) mantem PENDENTE; so true aprova', () {
      expect(TrialAprovacaoService.deveMarcarAprovado(true), isTrue);
      expect(TrialAprovacaoService.deveMarcarAprovado(false), isFalse);
      expect(TrialAprovacaoService.deveMarcarAprovado(null), isFalse);
    });

    test('documentoDaSolicitacao prefere CNPJ e devolve so digitos', () {
      expect(TrialAprovacaoService.documentoDaSolicitacao(_solicitacao()),
          '12345678000190');
      expect(
          TrialAprovacaoService.documentoDaSolicitacao({'cpf': '123.456.789-09'}),
          '12345678909');
    });
  });

  group('prepararCliente / desfazer', () {
    late FakeBackend api;
    late TrialAprovacaoService service;

    setUp(() {
      api = FakeBackend();
      service = TrialAprovacaoService(
        caller: NetworkCaller(client: api.client),
        empresaIdProvider: () => 1,
      );
      api.json('GET /api/modulo-servico', jsonEncode({'data': _catalogo}));
    });

    ModulosMapeados mapa() => TrialAprovacaoService.mapearModulos(
        ['NFC-e', 'Financeiro'], _catalogoMapas());

    test('cliente novo: cria parceiro sob a empresa logada e vincula os modulos', () async {
      api.json('GET /api/parceiro', jsonEncode({'data': {'dados': []}}));
      api.json('POST /api/parceiro/insert', jsonEncode({'data': {'id': 416}}));
      api.json('POST /api/parceiro-modulo', jsonEncode({'modulosVinculados': 2}));

      final cliente = await service.prepararCliente(_solicitacao(), mapa());

      expect(cliente.parceiroId, 416);
      expect(cliente.parceiroCriado, isTrue);
      expect(cliente.modulosNomes, ['NFC-e', 'Financeiro']);

      final i = api.chamadas.indexOf('POST /api/parceiro/insert');
      final payload = jsonDecode(api.corpos[i]) as Map<String, dynamic>;
      expect(payload['nome'], 'Padaria do Ze');
      expect(payload['cpf'], '12345678000190');
      expect(payload['empresa'], {'id': 1});
      expect(payload['cidade'], 'Sao Paulo');
      expect(payload['estado'], 'SP');

      final v = api.chamadas.indexOf('POST /api/parceiro-modulo');
      expect(jsonDecode(api.corpos[v]), {'parceiroId': 416, 'moduloIds': [1, 2]});
    });

    test('cliente ja existente (mesmo CNPJ): reaproveita, nao cria e preserva modulos/valor',
        () async {
      api.json(
          'GET /api/parceiro',
          jsonEncode({
            'data': {
              'dados': [
                {'id': 55, 'nome': 'Padaria do Ze LTDA', 'cpf': '12.345.678/0001-90'}
              ]
            }
          }));
      api.json(
          'GET /api/parceiro-modulo',
          jsonEncode([
            {'id': 3, 'nome': 'Departamento Pessoal', 'valor': 49.9, 'dia_vencimento': 10}
          ]));
      api.json('POST /api/parceiro-modulo', '{}');
      api.json('PUT /api/parceiro-modulo/3', '{}');

      final cliente = await service.prepararCliente(_solicitacao(), mapa());

      expect(cliente.parceiroId, 55);
      expect(cliente.parceiroCriado, isFalse);
      expect(api.vezes('POST /api/parceiro/insert'), 0);
      final v = api.chamadas.indexOf('POST /api/parceiro-modulo');
      expect((jsonDecode(api.corpos[v])['moduloIds'] as List).toSet(), {1, 2, 3});
      // valor e vencimento do modulo antigo foram reaplicados (o POST zera)
      final p = api.chamadas.indexOf('PUT /api/parceiro-modulo/3');
      expect(jsonDecode(api.corpos[p]),
          {'parceiroId': 55, 'valor': 49.9, 'diaVencimento': 10});
      expect(cliente.modulosNomes,
          containsAll(['Departamento Pessoal', 'NFC-e', 'Financeiro']));
    });

    test('falha ao vincular modulos desfaz o parceiro recem-criado e relanca', () async {
      api.json('GET /api/parceiro', jsonEncode({'data': {'dados': []}}));
      api.json('POST /api/parceiro/insert', jsonEncode({'data': {'id': 416}}));
      api.json('POST /api/parceiro-modulo', '{}', status: 500);
      api.json('DELETE /api/parceiro/416', '{}');

      await expectLater(
        service.prepararCliente(_solicitacao(), mapa()),
        throwsA(isA<TrialAprovacaoException>()),
      );
      expect(api.vezes('DELETE /api/parceiro/416'), 1);
    });

    test('desfazer de cliente criado: remove logins, desvincula modulos e apaga o parceiro',
        () async {
      api.json('GET /api/parceiro', jsonEncode({'data': {'dados': []}}));
      api.json('POST /api/parceiro/insert', jsonEncode({'data': {'id': 416}}));
      api.json('POST /api/parceiro-modulo', '{}');
      api.json('DELETE /api/login/900', '{}');
      api.json('DELETE /api/parceiro/416', '{}');

      final cliente = await service.prepararCliente(_solicitacao(), mapa());
      cliente.loginsCriados.add(900);
      api.limpar();

      final ok = await service.desfazer(cliente);

      expect(ok, isTrue);
      expect(api.chamadas, [
        'DELETE /api/login/900',
        'POST /api/parceiro-modulo',
        'DELETE /api/parceiro/416',
      ]);
      expect(jsonDecode(api.corpos[1]), {'parceiroId': 416, 'moduloIds': []});
    });

    test('desfazer de cliente reaproveitado restaura os modulos anteriores e NAO apaga o parceiro',
        () async {
      api.json(
          'GET /api/parceiro',
          jsonEncode({
            'data': {
              'dados': [
                {'id': 55, 'nome': 'Padaria', 'cpf': '12345678000190'}
              ]
            }
          }));
      api.json(
          'GET /api/parceiro-modulo',
          jsonEncode([
            {'id': 3, 'nome': 'Departamento Pessoal'}
          ]));
      api.json('POST /api/parceiro-modulo', '{}');

      final cliente = await service.prepararCliente(_solicitacao(), mapa());
      api.limpar();
      final ok = await service.desfazer(cliente);

      expect(ok, isTrue);
      expect(api.vezes('DELETE /api/parceiro/55'), 0);
      expect(jsonDecode(api.corpos.single), {'parceiroId': 55, 'moduloIds': [3]});
    });

    test('sem modulo correspondente no catalogo: erro claro e nada e criado', () async {
      final vazio = TrialAprovacaoService.mapearModulos(['X'], const []);
      await expectLater(
        service.prepararCliente(_solicitacao(), vazio),
        throwsA(isA<TrialAprovacaoException>()),
      );
      expect(api.vezes('POST /api/parceiro/insert'), 0);
    });

    test('401 vira mensagem de sessao expirada (nao "nao encontrado")', () async {
      api.json('GET /api/modulo-servico', '{}', status: 401);
      await expectLater(
        service.carregarCatalogo(),
        throwsA(isA<TrialAprovacaoException>()
            .having((e) => e.mensagem, 'mensagem', contains('sessao expirada'))),
      );
    });
  });
}
