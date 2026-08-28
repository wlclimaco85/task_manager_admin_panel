import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_manager_admin_panel/models/login_model.dart';
import 'package:task_manager_admin_panel/services/auth_utility.dart';

String _buildJwt({required int expiresInSeconds}) {
  final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'none'})));
  final exp =
      DateTime.now().add(Duration(seconds: expiresInSeconds)).millisecondsSinceEpoch ~/
          1000;
  final payload = base64Url.encode(utf8.encode(jsonEncode({'exp': exp})));
  return '$header.$payload.signature';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthUtility.userInfo = null;
  });

  group('isJwtExpired', () {
    test('retorna false para token com exp no futuro', () {
      final token = _buildJwt(expiresInSeconds: 3600);
      expect(isJwtExpired(token), isFalse);
    });

    test('retorna true para token com exp no passado', () {
      final token = _buildJwt(expiresInSeconds: -3600);
      expect(isJwtExpired(token), isTrue);
    });

    test('retorna true para token malformado', () {
      expect(isJwtExpired('token-invalido'), isTrue);
    });

    test('retorna false quando o payload nao tem claim exp', () {
      final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'none'})));
      final payload = base64Url.encode(utf8.encode(jsonEncode({'sub': '1'})));
      expect(isJwtExpired('$header.$payload.sig'), isFalse);
    });
  });

  group('AuthUtility.isLoggedIn', () {
    test('false quando nao ha usuario carregado', () {
      expect(AuthUtility.isLoggedIn, isFalse);
    });

    test('true quando ha token', () {
      AuthUtility.userInfo = const LoginModel(token: 'abc123');
      expect(AuthUtility.isLoggedIn, isTrue);
    });

    test('true quando ha login.id mesmo sem token', () {
      AuthUtility.userInfo =
          const LoginModel(login: LoginInfo(id: 7));
      expect(AuthUtility.isLoggedIn, isTrue);
    });
  });

  group('AuthUtility persistencia de sessao', () {
    test('setUserInfo -> getUserInfo recupera os mesmos dados', () async {
      final model = LoginModel(
        token: _buildJwt(expiresInSeconds: 3600),
        login: const LoginInfo(id: 1, email: 'dono@appacademia.com'),
      );

      await AuthUtility.setUserInfo(model);
      final recovered = await AuthUtility.getUserInfo();

      expect(recovered?.token, model.token);
      expect(recovered?.login?.id, 1);
      expect(recovered?.login?.email, 'dono@appacademia.com');
    });

    test('clearUserInfo remove a sessao persistida', () async {
      final model = LoginModel(token: _buildJwt(expiresInSeconds: 3600));
      await AuthUtility.setUserInfo(model);

      await AuthUtility.clearUserInfo();

      expect(AuthUtility.userInfo, isNull);
      expect(await AuthUtility.getUserInfo(), isNull);
    });

    test('isUserLoggedIn retorna false e limpa sessao com token expirado',
        () async {
      final expired = LoginModel(
        token: _buildJwt(expiresInSeconds: -10),
        login: const LoginInfo(id: 1),
      );
      await AuthUtility.setUserInfo(expired);

      final result = await AuthUtility.isUserLoggedIn();

      expect(result, isFalse);
      expect(AuthUtility.userInfo, isNull);
    });

    test('isUserLoggedIn retorna true com token valido', () async {
      final valid = LoginModel(
        token: _buildJwt(expiresInSeconds: 3600),
        login: const LoginInfo(id: 1),
      );
      await AuthUtility.setUserInfo(valid);

      expect(await AuthUtility.isUserLoggedIn(), isTrue);
    });

    test('isUserLoggedIn retorna false sem sessao armazenada', () async {
      expect(await AuthUtility.isUserLoggedIn(), isFalse);
    });
  });
}
