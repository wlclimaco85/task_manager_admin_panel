import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/models/cadastro_empresa_models.dart';
import 'package:task_manager_admin_panel/services/cadastro_empresa_service.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';

/// Constroi 10 `ContaData` (posicoes 0-4 = pagar, 5-9 = receber), mesma
/// convencao posicional usada por `CadastroEmpresaService.execute`.
List<ContaData> _contas() => [
      for (int i = 0; i < 5; i++)
        ContaData(descricao: 'Conta Pagar ${i + 1}', valor: 100),
      for (int i = 0; i < 5; i++)
        ContaData(descricao: 'Conta Receber ${i + 1}', valor: 100),
    ];

const _empresa = EmpresaData(nome: 'Empresa Teste', email: 'e@teste.com');

final _usuarios = const [
  UsuarioData(nome: 'Admin Principal', email: 'admin@e.com', senha: 'x', tipo: 'ADMIN'),
  UsuarioData(nome: 'Financeiro', email: 'fin@e.com', senha: 'x', tipo: 'FINANCEIRO'),
];

List<ClienteData> _clientes() => List.generate(
      5,
      (i) => ClienteData(nome: 'Cliente ${i + 1}', email: 'cliente${i + 1}@e.com'),
    );

final _chamados = const [
  ChamadoData(titulo: 'Chamado 1'),
  ChamadoData(titulo: 'Chamado 2'),
  ChamadoData(titulo: 'Chamado 3'),
];

List<FuncionarioData> _funcionarios() => List.generate(
      5,
      (i) => FuncionarioData(nome: 'Funcionario ${i + 1}', email: 'func${i + 1}@e.com'),
    );

void main() {
  group('CadastroEmpresaService.execute — fluxo completo com sucesso', () {
    test('cria 38 entidades (1+2+10+10+1+3+1+10) e nao dispara rollback',
        () async {
      var nextId = 100;
      final postRequests = <http.Request>[];
      final deleteRequests = <http.Request>[];

      final client = MockClient((request) async {
        if (request.method == 'DELETE') {
          deleteRequests.add(request);
          return http.Response('', 200);
        }
        postRequests.add(request);
        final id = nextId++;
        return http.Response(
          jsonEncode({'id': id}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service =
          CadastroEmpresaService(networkCaller: NetworkCaller(client: client));

      await service.execute(
        empresa: _empresa,
        usuarios: _usuarios,
        clientes: _clientes(),
        contas: _contas(),
        chamados: _chamados,
        funcionarios: _funcionarios(),
      );

      expect(postRequests.length, 38);
      expect(deleteRequests, isEmpty);
    });

    test('payload de conta a receber usa chave cliente, nao parceiro',
        () async {
      var nextId = 100;
      final postRequests = <http.Request>[];

      final client = MockClient((request) async {
        if (request.method == 'DELETE') return http.Response('', 200);
        postRequests.add(request);
        final id = nextId++;
        return http.Response(
          jsonEncode({'id': id}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service =
          CadastroEmpresaService(networkCaller: NetworkCaller(client: client));

      await service.execute(
        empresa: _empresa,
        usuarios: _usuarios,
        clientes: _clientes(),
        contas: _contas(),
        chamados: _chamados,
        funcionarios: _funcionarios(),
      );

      final contaReceberReq = postRequests.firstWhere(
          (r) => r.url.path.contains('/api/conta_receber'));
      final body = jsonDecode(contaReceberReq.body) as Map<String, dynamic>;
      expect(body.containsKey('cliente'), isTrue);
      expect(body.containsKey('parceiro'), isFalse);

      final contaPagarReq = postRequests.firstWhere(
          (r) => r.url.path.contains('/api/conta_pagar'));
      final pagarBody = jsonDecode(contaPagarReq.body) as Map<String, dynamic>;
      expect(pagarBody.containsKey('parceiro'), isTrue);
      expect(pagarBody.containsKey('cliente'), isFalse);
    });

    test('extrai id de resposta aninhada (data.id)', () async {
      final client = MockClient((request) async {
        if (request.method == 'DELETE') return http.Response('', 200);
        return http.Response(
          jsonEncode({
            'data': {'id': 777}
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service =
          CadastroEmpresaService(networkCaller: NetworkCaller(client: client));

      // Nao deve lancar CadastroException — todo id resolvido via data.id.
      await service.execute(
        empresa: _empresa,
        usuarios: _usuarios,
        clientes: _clientes(),
        contas: _contas(),
        chamados: _chamados,
        funcionarios: _funcionarios(),
      );
    });
  });

  group('CadastroEmpresaService.execute — falha e rollback', () {
    test(
        'falha na 3a conta a pagar lanca CadastroException e reverte em ordem LIFO',
        () async {
      var nextId = 100;
      var contaPagarCount = 0;
      final deleteRequests = <http.Request>[];

      final client = MockClient((request) async {
        if (request.method == 'DELETE') {
          deleteRequests.add(request);
          return http.Response('', 200);
        }
        if (request.url.path.contains('/api/conta_pagar')) {
          contaPagarCount++;
          if (contaPagarCount == 3) {
            return http.Response('erro interno', 500);
          }
        }
        final id = nextId++;
        return http.Response(
          jsonEncode({'id': id}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service =
          CadastroEmpresaService(networkCaller: NetworkCaller(client: client));

      await expectLater(
        () => service.execute(
          empresa: _empresa,
          usuarios: _usuarios,
          clientes: _clientes(),
          contas: _contas(),
          chamados: _chamados,
          funcionarios: _funcionarios(),
        ),
        throwsA(isA<CadastroException>()),
      );

      // Criadas antes da falha: 1 empresa + 2 usuarios + 5x(parceiro+login)
      // + 2 contas a pagar = 15.
      expect(deleteRequests.length, 15);
      // Ultima entidade criada (2a conta a pagar) e a primeira removida.
      expect(deleteRequests.first.url.path, contains('/api/conta_pagar/'));
      // Primeira entidade criada (empresa) e a ultima removida.
      expect(deleteRequests.last.url.path, contains('/api/empresa/'));
    });

    test('rollback nao interrompe em falha de remocao individual', () async {
      var nextId = 100;
      var deleteCount = 0;
      final deleteRequests = <http.Request>[];

      final client = MockClient((request) async {
        if (request.method == 'DELETE') {
          deleteCount++;
          deleteRequests.add(request);
          if (deleteCount == 1) {
            return http.Response('erro', 500);
          }
          return http.Response('', 200);
        }
        if (request.url.path.contains('/api/login')) {
          return http.Response('erro', 500);
        }
        final id = nextId++;
        return http.Response(
          jsonEncode({'id': id}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service =
          CadastroEmpresaService(networkCaller: NetworkCaller(client: client));

      await expectLater(
        () => service.execute(
          empresa: _empresa,
          usuarios: _usuarios,
          clientes: _clientes(),
          contas: _contas(),
          chamados: _chamados,
          funcionarios: _funcionarios(),
        ),
        throwsA(isA<CadastroException>()),
      );

      // Falha ocorre no 1o usuario (login) apos empresa criada: 1 entidade
      // para reverter (empresa), mesmo com a 1a remocao falhando.
      expect(deleteRequests.length, 1);
    });
  });
}
