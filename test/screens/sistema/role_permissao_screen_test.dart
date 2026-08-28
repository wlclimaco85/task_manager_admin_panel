import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/config/api_links.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/screens/sistema/role_permissao_screen.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.darkTheme, home: child);

http.Response _json(Map<String, dynamic> body, {int statusCode = 200}) => http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json'},
    );

void main() {
  group('RolePermissaoScreen', () {
    testWidgets('carrega roles/permissoes e monta a matriz', (tester) async {
      final putRequests = <http.Request>[];
      final client = MockClient((request) async {
        if (request.method == 'GET' && request.url.toString().contains('/role-permissao/all')) {
          return _json({
            'data': {
              'dados': [
                {
                  'id': 1,
                  'roleId': 1,
                  'roleKey': 'admin',
                  'roleDescription': 'Admin',
                  'telaNome': 'aplicativo',
                  'podeVer': true,
                  'podeInserir': false,
                  'podeEditar': false,
                  'podeDeletar': false,
                  'podeBaixar': false,
                },
              ],
            },
          });
        }
        if (request.method == 'GET' && request.url.toString().contains('/api/role')) {
          return _json({
            'data': {
              'dados': [
                {'id': 1, 'description': 'Admin'},
              ],
            },
          });
        }
        if (request.method == 'PUT') {
          putRequests.add(request);
          return _json({'id': 1});
        }
        return http.Response('not found', 404);
      });

      final caller = NetworkCaller(client: client);

      await tester.pumpWidget(_wrap(RolePermissaoScreen(networkCaller: caller)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('permissoes_role_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('permissoes_tabela')), findsOneWidget);
      expect(find.text('Aplicativo'), findsWidgets);
    });

    testWidgets('toggle individual chama PUT com telaNome correto', (tester) async {
      final putRequests = <http.Request>[];
      final client = MockClient((request) async {
        if (request.method == 'GET' && request.url.toString().contains('/role-permissao/all')) {
          return _json({
            'data': {
              'dados': [
                {
                  'id': 1,
                  'roleId': 1,
                  'roleKey': 'admin',
                  'roleDescription': 'Admin',
                  'telaNome': 'aplicativo',
                  'podeVer': false,
                  'podeInserir': false,
                  'podeEditar': false,
                  'podeDeletar': false,
                  'podeBaixar': false,
                },
              ],
            },
          });
        }
        if (request.method == 'GET' && request.url.toString().contains('/api/role')) {
          return _json({
            'data': {
              'dados': [
                {'id': 1, 'description': 'Admin'},
              ],
            },
          });
        }
        if (request.method == 'PUT') {
          putRequests.add(request);
          return _json({'id': 1});
        }
        return http.Response('not found', 404);
      });

      final caller = NetworkCaller(client: client);

      await tester.pumpWidget(_wrap(RolePermissaoScreen(networkCaller: caller)));
      await tester.pumpAndSettle();

      // Primeiro checkbox de dados da tabela (coluna "Ver" da linha "aplicativo").
      final checkboxes = find.byType(Checkbox);
      // O 1o Checkbox e o de "grupo" (tristate); o 2o em diante sao as
      // colunas Ver/Inserir/Editar/Deletar/Baixar da unica tela carregada.
      await tester.tap(checkboxes.at(1));
      await tester.pumpAndSettle();

      expect(putRequests, hasLength(1));
      final expectedUrl =
          ApiLinks.updateRolePermissao('1', Uri.encodeComponent('aplicativo'));
      // TenantContext.applyToUrl() sempre reconstroi a URL com
      // queryParameters (mesmo vazios quando o usuario nao esta logado),
      // resultando em um "?" residual -- comportamento do utilitario
      // compartilhado, nao deste plano.
      expect(putRequests.single.url.toString(), startsWith(expectedUrl));
      final sentBody = jsonDecode(putRequests.single.body) as Map<String, dynamic>;
      expect(sentBody['podeVer'], true);
    });

    testWidgets('checkbox de grupo chama POST batch com os 5 campos', (tester) async {
      final networkClient = MockClient((request) async {
        if (request.method == 'GET' && request.url.toString().contains('/role-permissao/all')) {
          return _json({
            'data': {
              'dados': [
                {
                  'id': 1,
                  'roleId': 1,
                  'roleKey': 'admin',
                  'roleDescription': 'Admin',
                  'telaNome': 'aplicativo',
                  'podeVer': false,
                  'podeInserir': false,
                  'podeEditar': false,
                  'podeDeletar': false,
                  'podeBaixar': false,
                },
              ],
            },
          });
        }
        if (request.method == 'GET' && request.url.toString().contains('/api/role')) {
          return _json({
            'data': {
              'dados': [
                {'id': 1, 'description': 'Admin'},
              ],
            },
          });
        }
        return http.Response('not found', 404);
      });

      final postRequests = <http.Request>[];
      final batchClient = MockClient((request) async {
        postRequests.add(request);
        return _json({'ok': true});
      });

      final caller = NetworkCaller(client: networkClient);

      await tester.pumpWidget(_wrap(RolePermissaoScreen(
        networkCaller: caller,
        httpClient: batchClient,
      )));
      await tester.pumpAndSettle();

      final grupoCheckbox = find.byKey(const Key('permissoes_grupo_checkbox_aplicativo'));
      expect(grupoCheckbox, findsOneWidget);

      await tester.tap(grupoCheckbox);
      await tester.pumpAndSettle();

      expect(postRequests, hasLength(1));
      expect(postRequests.single.url.toString(), ApiLinks.batchRolePermissao);
      final payload = jsonDecode(postRequests.single.body) as List<dynamic>;
      expect(payload, hasLength(1));
      final item = payload.single as Map<String, dynamic>;
      expect(item['roleId'], 1);
      expect(item['telaNome'], 'aplicativo');
      expect(item['podeVer'], true);
      expect(item['podeInserir'], true);
      expect(item['podeEditar'], true);
      expect(item['podeDeletar'], true);
      expect(item['podeBaixar'], true);
    });

    testWidgets('busca filtra a tabela por termo', (tester) async {
      final client = MockClient((request) async {
        if (request.method == 'GET' && request.url.toString().contains('/role-permissao/all')) {
          return _json({
            'data': {
              'dados': [
                {
                  'id': 1,
                  'roleId': 1,
                  'roleKey': 'admin',
                  'roleDescription': 'Admin',
                  'telaNome': 'aplicativo',
                  'podeVer': false,
                  'podeInserir': false,
                  'podeEditar': false,
                  'podeDeletar': false,
                  'podeBaixar': false,
                },
                {
                  'id': 2,
                  'roleId': 1,
                  'roleKey': 'admin',
                  'roleDescription': 'Admin',
                  'telaNome': 'centro_custo',
                  'podeVer': false,
                  'podeInserir': false,
                  'podeEditar': false,
                  'podeDeletar': false,
                  'podeBaixar': false,
                },
              ],
            },
          });
        }
        if (request.method == 'GET' && request.url.toString().contains('/api/role')) {
          return _json({
            'data': {
              'dados': [
                {'id': 1, 'description': 'Admin'},
              ],
            },
          });
        }
        return http.Response('not found', 404);
      });

      final caller = NetworkCaller(client: client);

      await tester.pumpWidget(_wrap(RolePermissaoScreen(networkCaller: caller)));
      await tester.pumpAndSettle();

      expect(find.text('Aplicativo'), findsWidgets);
      expect(find.text('Centro Custo'), findsWidgets);

      await tester.enterText(
          find.byKey(const Key('permissoes_busca_field')), 'centro');
      await tester.pumpAndSettle();

      expect(find.text('Centro Custo'), findsWidgets);
      expect(find.text('Aplicativo'), findsNothing);
    });
  });
}
