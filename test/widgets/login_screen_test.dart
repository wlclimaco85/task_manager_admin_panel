import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/models/login_model.dart';
import 'package:task_manager_admin_panel/screens/login_screen.dart';
import 'package:task_manager_admin_panel/services/auth_service.dart';

class _StubAuthService implements AuthService {
  _StubAuthService(this._result);

  final LoginResult _result;
  int callCount = 0;
  String? lastEmail;
  String? lastSenha;

  @override
  Future<LoginResult> login({required String email, required String senha}) async {
    callCount++;
    lastEmail = email;
    lastSenha = senha;
    return _result;
  }

  @override
  Future<void> logout() async {}
}

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.darkTheme, home: child);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('mostra erros de validacao quando os campos estao vazios',
      (tester) async {
    await tester.pumpWidget(_wrap(const LoginScreen()));

    await tester.tap(find.byKey(const Key('login_submit_button')));
    await tester.pump();

    expect(find.text('Informe o e-mail.'), findsOneWidget);
    expect(find.text('Informe a senha.'), findsOneWidget);
  });

  testWidgets('exibe mensagem de erro quando o login falha', (tester) async {
    final stub = _StubAuthService(const LoginResult.error('E-mail ou senha invalidos.'));

    await tester.pumpWidget(_wrap(LoginScreen(authService: stub)));

    await tester.enterText(
        find.byKey(const Key('login_email_field')), 'dono@appacademia.com');
    await tester.enterText(find.byKey(const Key('login_senha_field')), 'senha123');
    await tester.tap(find.byKey(const Key('login_submit_button')));
    await tester.pumpAndSettle();

    expect(stub.callCount, 1);
    expect(stub.lastEmail, 'dono@appacademia.com');
    expect(find.byKey(const Key('login_error_text')), findsOneWidget);
    expect(find.text('E-mail ou senha invalidos.'), findsOneWidget);
  });

  testWidgets('nao chama o servico quando o formulario e invalido',
      (tester) async {
    final stub = _StubAuthService(
      const LoginResult.ok(LoginModel(token: 'abc')),
    );

    await tester.pumpWidget(_wrap(LoginScreen(authService: stub)));
    await tester.enterText(
        find.byKey(const Key('login_email_field')), 'email-invalido');
    await tester.tap(find.byKey(const Key('login_submit_button')));
    await tester.pump();

    expect(stub.callCount, 0);
    expect(find.text('E-mail invalido.'), findsOneWidget);
  });
}
