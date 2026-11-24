import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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

const _rotaResolver = 'GET /api/admin/trial/resolver-cnpj';

String _resolucaoEmpresa() => jsonEncode({
      'tipoAlvo': 'EMPRESA',
      'empresaId': 10,
      'empresaNome': 'Padaria do Ze LTDA',
      'usuarios': [
        {'id': 1, 'nome': 'Ze', 'email': 'ze@padaria.com'}
      ],
      'roles': [
        {'id': 5, 'key': 'ROLE_FISCAL', 'description': 'Fiscal'}
      ],
    });

String _resolucaoParceiro() => jsonEncode({
      'tipoAlvo': 'PARCEIRO',
      'empresaId': 5,
      'empresaNome': 'Escritorio',
      'parceiroId': 55,
      'parceiroNome': 'Padaria do Ze LTDA',
      'usuarios': [],
      'roles': [],
    });

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

  group('prepararCliente / desfazer (escopo resolvido pelo CNPJ da solicitacao)', () {
    late FakeBackend api;
    late TrialAprovacaoService service;

    setUp(() {
      api = FakeBackend();
      service = TrialAprovacaoService(caller: NetworkCaller(client: api.client));
      api.json('GET /api/modulo-servico', jsonEncode({'data': _catalogo}));
    });

    ModulosMapeados mapa() => TrialAprovacaoService.mapearModulos(
        ['NFC-e', 'Financeiro'], _catalogoMapas());

    test('CNPJ envia so os digitos ao backend e nada usa a empresa de quem esta logado',
        () async {
      String? cnpjEnviado;
      api.on(_rotaResolver, (req) {
        cnpjEnviado = req.url.queryParameters['cnpj'];
        return http.Response(_resolucaoEmpresa(), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });
      api.json('GET /api/empresa-modulo', jsonEncode([]));
      api.json('POST /api/empresa-modulo', '{}');

      await service.prepararCliente(_solicitacao(), mapa());

      expect(cnpjEnviado, '12345678000190');
      expect(api.vezes('POST /api/parceiro/insert'), 0);
    });

    test('CNPJ de EMPRESA: vincula modulos na empresa, traz usuarios e roles dela', () async {
      api.json(_rotaResolver, _resolucaoEmpresa());
      api.json('GET /api/empresa-modulo', jsonEncode([]));
      api.json('POST /api/empresa-modulo', '{}');

      final cliente = await service.prepararCliente(_solicitacao(), mapa());

      expect(cliente.ehParceiro, isFalse);
      expect(cliente.alvoId, 10);
      expect(cliente.alvoNome, 'Padaria do Ze LTDA');
      expect(cliente.resolucao.usuarios.single['email'], 'ze@padaria.com');
      expect(cliente.resolucao.roles.single['key'], 'ROLE_FISCAL');
      expect(cliente.modulosNomes, ['NFC-e', 'Financeiro']);
      final v = api.chamadas.indexOf('POST /api/empresa-modulo');
      expect(jsonDecode(api.corpos[v]), {'empresaId': 10, 'moduloIds': [1, 2]});
      expect(api.vezes('POST /api/parceiro-modulo'), 0);
    });

    test('CNPJ de PARCEIRO: vincula no parceiro e preserva modulos/valor anteriores',
        () async {
      api.json(_rotaResolver, _resolucaoParceiro());
      api.json(
          'GET /api/parceiro-modulo',
          jsonEncode([
            {'id': 3, 'nome': 'Departamento Pessoal', 'valor': 49.9, 'dia_vencimento': 10}
          ]));
      api.json('POST /api/parceiro-modulo', '{}');
      api.json('PUT /api/parceiro-modulo/3', '{}');

      final cliente = await service.prepararCliente(_solicitacao(), mapa());

      expect(cliente.ehParceiro, isTrue);
      expect(cliente.alvoId, 55);
      expect(cliente.resolucao.empresaId, 5);
      final v = api.chamadas.indexOf('POST /api/parceiro-modulo');
      expect((jsonDecode(api.corpos[v])['moduloIds'] as List).toSet(), {1, 2, 3});
      final p = api.chamadas.indexOf('PUT /api/parceiro-modulo/3');
      expect(jsonDecode(api.corpos[p]),
          {'parceiroId': 55, 'valor': 49.9, 'diaVencimento': 10});
      expect(cliente.modulosNomes,
          containsAll(['Departamento Pessoal', 'NFC-e', 'Financeiro']));
    });

    test('CNPJ que nao e empresa nem parceiro: erro claro, nada e criado nem vinculado',
        () async {
      api.json(_rotaResolver, jsonEncode({'tipoAlvo': 'NAO_ENCONTRADO'}));

      await expectLater(
        service.prepararCliente(_solicitacao(), mapa()),
        throwsA(isA<TrialAprovacaoException>()
            .having((e) => e.mensagem, 'mensagem', contains('nao pertence'))),
      );
      expect(api.vezes('POST /api/parceiro/insert'), 0);
      expect(api.vezes('POST /api/parceiro-modulo'), 0);
      expect(api.vezes('POST /api/empresa-modulo'), 0);
    });

    test('solicitacao sem CNPJ/CPF: erro claro e nem consulta o backend', () async {
      await expectLater(
        service.prepararCliente({'id': 7, 'nome': 'X'}, mapa()),
        throwsA(isA<TrialAprovacaoException>()),
      );
      expect(api.vezes(_rotaResolver), 0);
    });

    test('backend recusa o CNPJ (400): mostra a mensagem do servidor', () async {
      api.json(_rotaResolver, jsonEncode({'erro': 'Informe um CPF ou CNPJ valido.'}),
          status: 400);
      await expectLater(
        service.prepararCliente(_solicitacao(), mapa()),
        throwsA(isA<TrialAprovacaoException>()
            .having((e) => e.mensagem, 'mensagem', contains('CPF ou CNPJ valido'))),
      );
    });

    test('falha ao vincular modulos tenta restaurar o estado anterior e relanca', () async {
      api.json(_rotaResolver, _resolucaoEmpresa());
      api.json('GET /api/empresa-modulo', jsonEncode([]));
      api.json('POST /api/empresa-modulo', '{}', status: 500);

      await expectLater(
        service.prepararCliente(_solicitacao(), mapa()),
        throwsA(isA<TrialAprovacaoException>()),
      );
      // 1a chamada = vinculo que falhou; 2a = compensacao (restaura conjunto anterior vazio)
      expect(api.vezes('POST /api/empresa-modulo'), 2);
    });

    test('desfazer: remove logins criados e restaura modulos anteriores, sem apagar o cliente',
        () async {
      api.json(_rotaResolver, _resolucaoParceiro());
      api.json(
          'GET /api/parceiro-modulo',
          jsonEncode([
            {'id': 3, 'nome': 'Departamento Pessoal'}
          ]));
      api.json('POST /api/parceiro-modulo', '{}');
      api.json('DELETE /api/login/900', '{}');

      final cliente = await service.prepararCliente(_solicitacao(), mapa());
      cliente.loginsCriados.add(900);
      api.limpar();

      final ok = await service.desfazer(cliente);

      expect(ok, isTrue);
      expect(api.chamadas, ['DELETE /api/login/900', 'POST /api/parceiro-modulo']);
      expect(jsonDecode(api.corpos[1]), {'parceiroId': 55, 'moduloIds': [3]});
      expect(api.vezes('DELETE /api/parceiro/55'), 0);
    });

    test('sem modulo correspondente no catalogo: erro claro e nada e consultado', () async {
      final vazio = TrialAprovacaoService.mapearModulos(['X'], const []);
      await expectLater(
        service.prepararCliente(_solicitacao(), vazio),
        throwsA(isA<TrialAprovacaoException>()),
      );
      expect(api.vezes(_rotaResolver), 0);
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
