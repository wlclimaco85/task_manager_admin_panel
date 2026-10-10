import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/widgets/generic_grid_windows_screen.dart';

void main() {
  group('resolverEndpointComId', () {
    test('substitui o placeholder :id quando presente', () {
      expect(resolverEndpointComId('http://x/api/modulos/:id', '7'),
          'http://x/api/modulos/7');
    });

    test('acrescenta /id quando o endpoint e a colecao (sem :id)', () {
      expect(resolverEndpointComId('http://x/api/licencas', '7'),
          'http://x/api/licencas/7');
    });

    test('nao duplica a barra final', () {
      expect(resolverEndpointComId('http://x/api/licencas/', '7'),
          'http://x/api/licencas/7');
    });

    test('preserva a query string ao acrescentar o id', () {
      expect(resolverEndpointComId('http://x/api/licencas?empId=3', '7'),
          'http://x/api/licencas/7?empId=3');
    });
  });
}
