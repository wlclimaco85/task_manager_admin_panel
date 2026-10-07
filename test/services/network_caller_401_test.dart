import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';

/// 401 do JwtAuthorizationFilter (token expirado/revogado/sessao encerrada)
/// antes so' aparecia como "(401)" nas telas; agora dispara o handler global
/// (que leva ao login), exceto nas rotas publicas de autenticacao.
void main() {
  tearDown(() => NetworkCaller.globalOnUnauthorized = null);

  test('401 em rota protegida dispara o handler global', () async {
    var chamadas = 0;
    NetworkCaller.globalOnUnauthorized = () => chamadas++;
    final caller = NetworkCaller(
        client: MockClient((_) async => http.Response('{}', 401)));

    final r = await caller.getRequest('https://exemplo.test/api/modulo-atribuicao/resumo');

    expect(r.statusCode, 401);
    expect(r.isSuccess, isFalse);
    expect(chamadas, 1);
  });

  test('401 no login (rota publica) NAO dispara o handler', () async {
    var chamadas = 0;
    NetworkCaller.globalOnUnauthorized = () => chamadas++;
    final caller = NetworkCaller(
        client: MockClient((_) async => http.Response('{}', 401)));

    await caller.postRequest('https://exemplo.test/rest/auth/login', {'email': 'a'});

    expect(chamadas, 0);
  });

  test('onUnauthorized do proprio caller tem prioridade sobre o global', () async {
    var global = 0, local = 0;
    NetworkCaller.globalOnUnauthorized = () => global++;
    final caller = NetworkCaller(
        client: MockClient((_) async => http.Response('{}', 401)),
        onUnauthorized: () => local++);

    await caller.getRequest('https://exemplo.test/api/x');

    expect(local, 1);
    expect(global, 0);
  });

  test('200 nao dispara o handler', () async {
    var chamadas = 0;
    NetworkCaller.globalOnUnauthorized = () => chamadas++;
    final caller =
        NetworkCaller(client: MockClient((_) async => http.Response('{}', 200)));
    await caller.getRequest('https://exemplo.test/api/x');
    expect(chamadas, 0);
  });
}
