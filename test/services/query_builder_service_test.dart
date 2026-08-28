import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/config/api_links.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';
import 'package:task_manager_admin_panel/services/query_builder_service.dart';

void main() {
  group('QueryBuilderService', () {
    test('listarSchemas desembrulha body.data.data em uma lista de mapas',
        () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), startsWith(ApiLinks.queryBuilderSchemas));
        return http.Response(
          jsonEncode({
            'data': {
              'data': [
                {'schema_name': 'public'},
                {'schema_name': 'financeiro'},
              ]
            },
            'response': {'error': false, 'message': 'ok', 'status': 200},
          }),
          200,
        );
      });
      final service =
          QueryBuilderService(networkCaller: NetworkCaller(client: client));

      final schemas = await service.listarSchemas();

      expect(schemas, [
        {'schema_name': 'public'},
        {'schema_name': 'financeiro'},
      ]);
    });

    test('listarTabelas desembrulha body.data.data em uma lista de mapas',
        () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), startsWith(ApiLinks.queryBuilderTabelas));
        return http.Response(
          jsonEncode({
            'data': {
              'data': [
                {'table_schema': 'public', 'table_name': 'login'},
              ]
            },
            'response': {'error': false, 'message': 'ok', 'status': 200},
          }),
          200,
        );
      });
      final service =
          QueryBuilderService(networkCaller: NetworkCaller(client: client));

      final tabelas = await service.listarTabelas();

      expect(tabelas, [
        {'table_schema': 'public', 'table_name': 'login'},
      ]);
    });

    test('listarColunas chama o endpoint com schema/tabela na URL', () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          startsWith(ApiLinks.queryBuilderColunas('public', 'login')),
        );
        return http.Response(
          jsonEncode({
            'data': {
              'data': [
                {'column_name': 'id', 'is_pk': true},
              ]
            },
            'response': {'error': false, 'message': 'ok', 'status': 200},
          }),
          200,
        );
      });
      final service =
          QueryBuilderService(networkCaller: NetworkCaller(client: client));

      final colunas = await service.listarColunas('public', 'login');

      expect(colunas, [
        {'column_name': 'id', 'is_pk': true},
      ]);
    });

    test('executar retorna o resultado direto de body.data em sucesso',
        () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), startsWith(ApiLinks.queryBuilderExecutar));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['sql'], 'SELECT * FROM login');
        return http.Response(
          jsonEncode({
            'data': {
              'colunas': [
                {'column_name': 'id'}
              ],
              'linhas': [
                [1]
              ],
              'totalLinhas': 1,
              'pagina': 1,
              'tamanhoPagina': 50,
              'totalPaginas': 1,
            },
            'response': {'error': false, 'message': 'ok', 'status': 200},
          }),
          200,
        );
      });
      final service =
          QueryBuilderService(networkCaller: NetworkCaller(client: client));

      final resultado = await service.executar('SELECT * FROM login');

      expect(resultado['erro'], isNull);
      expect(resultado['totalLinhas'], 1);
      expect(resultado['linhas'], [
        [1]
      ]);
    });

    test('executar retorna {erro: ...} quando o backend rejeita SQL de escrita',
        () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'data': {'erro': 'Apenas consultas SELECT/WITH são permitidas'},
            'response': {
              'error': true,
              'message': 'Apenas consultas SELECT/WITH são permitidas',
              'status': 400,
            },
          }),
          400,
        );
      });
      final service =
          QueryBuilderService(networkCaller: NetworkCaller(client: client));

      final resultado = await service.executar('DELETE FROM login');

      expect(resultado['erro'], 'Apenas consultas SELECT/WITH são permitidas');
    });

    test('executar retorna erro generico quando o backend responde 403 sem corpo',
        () async {
      final client = MockClient((request) async {
        return http.Response('', 403);
      });
      final service =
          QueryBuilderService(networkCaller: NetworkCaller(client: client));

      final resultado = await service.executar('SELECT 1');

      expect(resultado['erro'], contains('403'));
    });
  });
}
