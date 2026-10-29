import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/models/login_model.dart';
import 'package:task_manager_admin_panel/services/auth_utility.dart';
import 'package:task_manager_admin_panel/utils/tenant_context.dart';

void main() {
  tearDown(() => AuthUtility.userInfo = null);

  LoginModel login(String tipo) => LoginModel(
        token: 't',
        login: LoginInfo(
          id: 1,
          email: 'x@y.com',
          tipoLogin: tipo,
          empresa: const EmpresaRef(id: 1, nome: 'Tech Solutions'),
        ),
      );

  test('dono nao tem empId injetado na listagem de empresas', () {
    AuthUtility.userInfo = login('MASTER');

    final url = TenantContext.applyToUrl('https://api.x/api/empresa');

    expect(Uri.parse(url).queryParameters.containsKey('empId'), isFalse);
  });

  test('dono continua com empId nas demais listagens', () {
    AuthUtility.userInfo = login('MASTER');

    final url = TenantContext.applyToUrl('https://api.x/api/parceiro');

    expect(Uri.parse(url).queryParameters['empId'], '1');
  });

  test('quem nao e dono continua com empId na listagem de empresas', () {
    AuthUtility.userInfo = login('APP_ABRACO');

    final url = TenantContext.applyToUrl('https://api.x/api/empresa');

    expect(Uri.parse(url).queryParameters['empId'], '1');
  });
}
