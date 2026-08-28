import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/models/role_permission_catalog.dart';

RolePermissao _permissao({
  int roleId = 1,
  String telaNome = 'nfeEntrada',
  bool podeVer = false,
  bool podeInserir = false,
  bool podeEditar = false,
  bool podeDeletar = false,
  bool podeBaixar = false,
}) {
  return RolePermissao(
    id: 0,
    roleId: roleId,
    roleKey: '',
    roleDescription: '',
    telaNome: telaNome,
    podeVer: podeVer,
    podeInserir: podeInserir,
    podeEditar: podeEditar,
    podeDeletar: podeDeletar,
    podeBaixar: podeBaixar,
  );
}

void main() {
  group('RolePermissionCatalog.groups', () {
    test('monta 1 grupo por tela distinta, ordenado por label', () {
      final grupos = RolePermissionCatalog.groups(['centro_custo', 'aplicativo']);

      expect(grupos, hasLength(2));
      expect(grupos[0].label, 'Aplicativo');
      expect(grupos[1].label, 'Centro Custo');
      expect(grupos[0].entries, hasLength(1));
      expect(grupos[0].entries.single.telaNome, 'aplicativo');
    });

    test('deduplica telas equivalentes por normalizacao', () {
      final grupos = RolePermissionCatalog.groups(['nfeEntrada', 'nfe_entrada']);

      expect(grupos, hasLength(1));
    });

    test('filtra por query no label/telaNome', () {
      final grupos = RolePermissionCatalog.groups(
        ['aplicativo', 'centro_custo'],
        query: 'centro',
      );

      expect(grupos, hasLength(1));
      expect(grupos.single.entries.single.telaNome, 'centro_custo');
    });

    test('ignora nomes de tela vazios', () {
      final grupos = RolePermissionCatalog.groups(['', 'aplicativo']);

      expect(grupos, hasLength(1));
    });
  });

  group('rolePermissionGroupCheckboxValue', () {
    test('retorna true quando todas as 5 permissoes da tela estao marcadas', () {
      final grupo = RolePermissionCatalog.groups(['aplicativo']).single;
      final permissao = _permissao(
        telaNome: 'aplicativo',
        podeVer: true,
        podeInserir: true,
        podeEditar: true,
        podeDeletar: true,
        podeBaixar: true,
      );

      final value = rolePermissionGroupCheckboxValue(
        grupo: grupo,
        permissaoDe: (_) => permissao,
      );

      expect(value, isTrue);
    });

    test('retorna false quando nenhuma permissao esta marcada', () {
      final grupo = RolePermissionCatalog.groups(['aplicativo']).single;
      final permissao = _permissao(telaNome: 'aplicativo');

      final value = rolePermissionGroupCheckboxValue(
        grupo: grupo,
        permissaoDe: (_) => permissao,
      );

      expect(value, isFalse);
    });

    test('retorna null (indeterminado) quando parcialmente marcado', () {
      final grupo = RolePermissionCatalog.groups(['aplicativo']).single;
      final permissao = _permissao(telaNome: 'aplicativo', podeVer: true);

      final value = rolePermissionGroupCheckboxValue(
        grupo: grupo,
        permissaoDe: (_) => permissao,
      );

      expect(value, isNull);
    });
  });

  group('buildRolePermissionGroupBatch', () {
    test('monta lista de 1 item por tela do grupo com os 5 campos', () {
      final grupo = RolePermissionCatalog.groups(['aplicativo']).single;

      final batch = buildRolePermissionGroupBatch(roleId: 7, grupo: grupo, marcar: true);

      expect(batch, hasLength(1));
      expect(batch.single['roleId'], 7);
      expect(batch.single['telaNome'], 'aplicativo');
      for (final campo in rolePermissionFields) {
        expect(batch.single[campo], true);
      }
    });
  });

  group('rolePermissionWithAllFields', () {
    test('retorna copia com todos os 5 campos ajustados', () {
      final original = _permissao(telaNome: 'aplicativo', podeVer: true);

      final atualizado = rolePermissionWithAllFields(original, valor: false);

      expect(atualizado.podeVer, isFalse);
      expect(atualizado.podeInserir, isFalse);
      expect(atualizado.podeEditar, isFalse);
      expect(atualizado.podeDeletar, isFalse);
      expect(atualizado.podeBaixar, isFalse);
    });
  });
}
