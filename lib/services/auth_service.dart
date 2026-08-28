import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_links.dart';
import '../models/login_model.dart';
import 'auth_utility.dart';

/// Resultado de uma tentativa de login.
class LoginResult {
  final bool success;
  final String? errorMessage;
  final LoginModel? model;

  const LoginResult.ok(this.model)
      : success = true,
        errorMessage = null;

  const LoginResult.error(this.errorMessage)
      : success = false,
        model = null;
}

/// Servico de autenticacao do Painel do Dono. Chama o MESMO endpoint de
/// login do backend usado pelo app cliente (`ApiLinks.login`).
class AuthService {
  AuthService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<LoginResult> login({
    required String email,
    required String senha,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse(ApiLinks.login),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'senha': senha}),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return LoginResult.error(
          _friendlyErrorFor(response.statusCode, response.body),
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final model = LoginModel.fromJson(json);

      if (model.token == null || model.token!.isEmpty) {
        return const LoginResult.error(
          'Login efetuado, mas o backend nao retornou um token valido.',
        );
      }

      await AuthUtility.setUserInfo(model);
      return LoginResult.ok(model);
    } on FormatException {
      return const LoginResult.error(
          'Resposta invalida do servidor. Tente novamente.');
    } catch (_) {
      // Nao expor detalhe interno da excecao (SocketException, TLS, DNS
      // etc.) na UI — achado de code-review: mensagem crua vazava detalhe
      // de conexao para o usuario final.
      return const LoginResult.error(
          'Nao foi possivel conectar ao servidor. Verifique sua conexao e tente novamente.');
    }
  }

  Future<void> logout() => AuthUtility.clearUserInfo();

  String _friendlyErrorFor(int statusCode, String body) {
    if (statusCode == 401 || statusCode == 403) {
      return 'E-mail ou senha invalidos.';
    }
    if (statusCode >= 500) {
      return 'Servidor indisponivel no momento. Tente novamente em instantes.';
    }
    return 'Nao foi possivel entrar (codigo $statusCode).';
  }
}
