import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/services/importacao_cadastros_service.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';

/// Testes de `ImportacaoCadastrosService` (Task 08a.1, PLAN.md Fase 2).
/// `NetworkCaller` mockado via `http.testing.MockClient` (sem dependencia
/// de codegen do mockito) — cenarios create/update/erro-continua, conforme
/// declarado no `Verify` do plano.
void main() {
  group('ImportacaoCadastrosService.importar — tipo funcionarios (login+funcionario)', () {
    test('linha cujo e-mail ja existe em /api/logins gera PUT, nao POST', () async {
      final requests = <http.Request>[];
      final mockClient = MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET' && request.url.path.endsWith('/api/logins')) {
          return http.Response(
              jsonEncode({
                'data': [
                  {'id': 10, 'email': 'joao@teste.com'}
                ]
              }),
              200);
        }
        if (request.method == 'PUT' && request.url.path.endsWith('/api/logins/10')) {
          return http.Response(jsonEncode({'id': 10}), 200);
        }
        if (request.method == 'GET' && request.url.path.endsWith('/api/funcionario')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (request.method == 'POST' && request.url.path.endsWith('/api/funcionario')) {
          return http.Response(jsonEncode({'id': 55}), 200);
        }
        return http.Response('nao mapeado: ${request.method} ${request.url}', 404);
      });

      final service =
          ImportacaoCadastrosService(networkCaller: NetworkCaller(client: mockClient));

      final resultado = await service.importar(
        tipo: ImportacaoCadastroTipo.funcionarios,
        rows: const [
          {'nome': 'Joao Silva', 'email': 'joao@teste.com', 'cpf': '12345678900'},
        ],
        empresaIdSelecionada: '3',
        atualizar: true,
      );

      expect(resultado.sucesso, 1);
      expect(resultado.erros, 0);
      expect(resultado.total, 1);

      final putLogin = requests
          .where((r) => r.method == 'PUT' && r.url.path.endsWith('/api/logins/10'));
      expect(putLogin.length, 1, reason: 'deveria dar PUT no login existente');

      final postLogin = requests
          .where((r) => r.method == 'POST' && r.url.path.endsWith('/api/logins'));
      expect(postLogin, isEmpty, reason: 'nao deveria criar login novo (ja existe)');
    });

    test('linha nova (sem dedup encontrado) gera POST, nao PUT', () async {
      final requests = <http.Request>[];
      final mockClient = MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET' && request.url.path.endsWith('/api/logins')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (request.method == 'POST' && request.url.path.endsWith('/api/logins')) {
          return http.Response(jsonEncode({'id': 20}), 200);
        }
        if (request.method == 'GET' && request.url.path.endsWith('/api/funcionario')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (request.method == 'POST' && request.url.path.endsWith('/api/funcionario')) {
          return http.Response(jsonEncode({'id': 77}), 200);
        }
        return http.Response('nao mapeado: ${request.method} ${request.url}', 404);
      });

      final service =
          ImportacaoCadastrosService(networkCaller: NetworkCaller(client: mockClient));

      final resultado = await service.importar(
        tipo: ImportacaoCadastroTipo.funcionarios,
        rows: const [
          {'nome': 'Maria Souza', 'email': 'maria@teste.com', 'cpf': '98765432100'},
        ],
        empresaIdSelecionada: '3',
        atualizar: true,
      );

      expect(resultado.sucesso, 1);
      expect(resultado.erros, 0);

      final postLogin = requests
          .where((r) => r.method == 'POST' && r.url.path.endsWith('/api/logins'));
      expect(postLogin.length, 1, reason: 'deveria criar login novo (sem dedup)');

      final putLogin = requests.where((r) => r.method == 'PUT');
      expect(putLogin, isEmpty, reason: 'nao deveria dar PUT em nada (nao existe ainda)');
    });

    test('falha em uma linha nao interrompe as seguintes (log de erro por linha)', () async {
      final mockClient = MockClient((request) async {
        if (request.method == 'GET' && request.url.path.endsWith('/api/logins')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (request.method == 'POST' && request.url.path.endsWith('/api/logins')) {
          return http.Response(jsonEncode({'id': 30}), 200);
        }
        if (request.method == 'GET' && request.url.path.endsWith('/api/funcionario')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (request.method == 'POST' && request.url.path.endsWith('/api/funcionario')) {
          return http.Response(jsonEncode({'id': 99}), 200);
        }
        return http.Response('nao mapeado: ${request.method} ${request.url}', 404);
      });

      final service =
          ImportacaoCadastrosService(networkCaller: NetworkCaller(client: mockClient));

      final progresso = <int>[];
      final resultado = await service.importar(
        tipo: ImportacaoCadastroTipo.funcionarios,
        rows: const [
          // linha 1: falta CPF -> deve gerar erro e NAO deve interromper.
          {'nome': 'Sem CPF', 'email': 'semcpf@teste.com', 'cpf': ''},
          // linha 2: valida -> deve gerar sucesso mesmo apos erro anterior.
          {'nome': 'Pedro Alves', 'email': 'pedro@teste.com', 'cpf': '11122233344'},
        ],
        empresaIdSelecionada: '3',
        atualizar: true,
        onProgress: (linhaAtual, total, entry) => progresso.add(linhaAtual),
      );

      expect(resultado.total, 2);
      expect(resultado.erros, 1);
      expect(resultado.sucesso, 1);
      expect(resultado.detalhes[0].status, 'erro');
      expect(resultado.detalhes[1].status, 'sucesso');
      expect(progresso, [1, 2]);
    });
  });

  group('ImportacaoCadastrosService — regressao WR-03 (falha de rede no dedup)', () {
    test(
        'GET de dedup falhando (500) marca a linha como erro, NAO cria duplicata via POST',
        () async {
      final requests = <http.Request>[];
      final mockClient = MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET' && request.url.path.endsWith('/api/logins')) {
          // Simula falha transitoria na consulta de dedup -- antes do fix,
          // isso era engolido e tratado como "nao existe", seguindo para
          // POST (duplicata silenciosa).
          return http.Response('erro interno', 500);
        }
        if (request.method == 'POST' && request.url.path.endsWith('/api/logins')) {
          return http.Response(jsonEncode({'id': 999}), 200);
        }
        return http.Response('nao mapeado: ${request.method} ${request.url}', 404);
      });

      final service =
          ImportacaoCadastrosService(networkCaller: NetworkCaller(client: mockClient));

      final resultado = await service.importar(
        tipo: ImportacaoCadastroTipo.funcionarios,
        rows: const [
          {'nome': 'Joao Silva', 'email': 'joao@teste.com', 'cpf': '12345678900'},
        ],
        empresaIdSelecionada: '3',
        atualizar: true,
      );

      expect(resultado.erros, 1, reason: 'falha na consulta de dedup deve virar erro na linha');
      expect(resultado.sucesso, 0);
      expect(resultado.detalhes[0].status, 'erro');

      final postLogin = requests
          .where((r) => r.method == 'POST' && r.url.path.endsWith('/api/logins'));
      expect(postLogin, isEmpty,
          reason: 'NAO deveria criar duplicata via POST quando o dedup falhou de consultar');
    });
  });

  group('ImportacaoCadastrosService.importar — tipo empresa (dedup por CNPJ)', () {
    test('CNPJ existente gera PUT em vez de POST', () async {
      final requests = <http.Request>[];
      final mockClient = MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET' && request.url.path.endsWith('/api/empresa')) {
          return http.Response(
              jsonEncode({
                'data': {
                  'dados': [
                    {'id': 5, 'nome': 'Academia X', 'cnpj': '11222333000181'}
                  ]
                }
              }),
              200);
        }
        if (request.method == 'PUT' && request.url.path.endsWith('/api/empresa/update/5')) {
          return http.Response(jsonEncode({'id': 5}), 200);
        }
        return http.Response('nao mapeado: ${request.method} ${request.url}', 404);
      });

      final service =
          ImportacaoCadastrosService(networkCaller: NetworkCaller(client: mockClient));

      final resultado = await service.importar(
        tipo: ImportacaoCadastroTipo.empresa,
        rows: const [
          {'nome': 'Academia X', 'cnpj': '11.222.333/0001-81'},
        ],
        atualizar: true,
      );

      expect(resultado.sucesso, 1);
      expect(resultado.erros, 0);
      final put = requests
          .where((r) => r.method == 'PUT' && r.url.path.endsWith('/api/empresa/update/5'));
      expect(put.length, 1);
      final post =
          requests.where((r) => r.method == 'POST' && r.url.path.endsWith('/api/empresa'));
      expect(post, isEmpty);
    });
  });
}
