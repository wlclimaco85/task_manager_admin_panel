import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/utils/role_permissao_normalizacao.dart';

void main() {
  group('toBackendTelaNome', () {
    test('converte snake_case para camelCase', () {
      expect(toBackendTelaNome('nfe_entrada'), 'nfeEntrada');
    });

    test('mantem nomes ja simples/camelCase inalterados', () {
      expect(toBackendTelaNome('chat'), 'chat');
      expect(toBackendTelaNome('nfeEntrada'), 'nfeEntrada');
    });

    test('converte multiplos underscores', () {
      expect(toBackendTelaNome('centro_custo_geral'), 'centroCustoGeral');
    });
  });

  group('normalizeTelaNome', () {
    test('normaliza para o mesmo valor independente de convencao', () {
      expect(normalizeTelaNome('Nfe_Entrada'), normalizeTelaNome('nfeentrada'));
      expect(normalizeTelaNome('nfeEntrada'), normalizeTelaNome('nfe_entrada'.toLowerCase()));
    });

    test('lowercase + remove underscore', () {
      expect(normalizeTelaNome('Centro_Custo'), 'centrocusto');
    });
  });
}
