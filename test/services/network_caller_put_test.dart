import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';

/// Bug real (2026-10-07): aprovar/rejeitar trial dava "Falha ao atualizar status"
/// porque o PUT ia com empresa/aplicativo (objetos) junto de {"status": ...} e o
/// endpoint le o corpo como mapa simples.
void main() {
  test('putRequest com enriquecerCorpo=false envia o corpo exatamente como informado',
      () async {
    String? corpoEnviado;
    String? metodo;
    final client = MockClient((http.Request req) async {
      corpoEnviado = req.body;
      metodo = req.method;
      return http.Response('{"status":"APROVADO"}', 200);
    });
    final caller = NetworkCaller(client: client);

    final resposta = await caller.putRequest(
      'https://exemplo.test/api/admin/trial/solicitacoes/7/status',
      {'status': 'APROVADO'},
      enriquecerCorpo: false,
    );

    expect(resposta.isSuccess, isTrue);
    expect(metodo, 'PUT');
    expect(jsonDecode(corpoEnviado!), {'status': 'APROVADO'});
  });

  test('putRequest sem o parametro mantem o comportamento padrao (corpo enviado como JSON)',
      () async {
    String? corpoEnviado;
    final client = MockClient((http.Request req) async {
      corpoEnviado = req.body;
      return http.Response('{}', 200);
    });
    final caller = NetworkCaller(client: client);

    await caller.putRequest('https://exemplo.test/api/x', {'status': 'A'});

    final decodificado = jsonDecode(corpoEnviado!) as Map<String, dynamic>;
    expect(decodificado['status'], 'A');
  });
}
