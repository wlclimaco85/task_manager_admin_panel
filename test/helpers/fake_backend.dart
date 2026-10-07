import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/config/api_links.dart';

/// Backend falso: registra cada chamada ("METODO caminho") e responde conforme
/// rotas registradas. Rota ausente -> 404 (como o backend real).
class FakeBackend {
  FakeBackend();

  final List<String> chamadas = [];
  final List<String> corpos = [];
  final Map<String, http.Response Function(http.Request)> _rotas = {};

  /// [rota] = "METODO /caminho" (sem query).
  void on(String rota, http.Response Function(http.Request req) resposta) {
    _rotas[rota] = resposta;
  }

  void json(String rota, String corpo, {int status = 200}) =>
      on(rota, (_) => http.Response(corpo, status,
          headers: {'content-type': 'application/json; charset=utf-8'}));

  MockClient get client => MockClient((req) async {
        final base = Uri.parse(ApiLinks.baseUrl).path;
        final chave = '${req.method} ${req.url.path.replaceFirst(base, '')}';
        chamadas.add(chave);
        corpos.add(req.body);
        final handler = _rotas[chave];
        if (handler == null) return http.Response('{}', 404);
        return handler(req);
      });

  int vezes(String chave) => chamadas.where((c) => c == chave).length;

  void limpar() {
    chamadas.clear();
    corpos.clear();
  }
}
