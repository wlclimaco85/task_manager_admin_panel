import '../utils/role_permissao_normalizacao.dart';

/// Modelo de uma permissao de role por tela (matriz SIS-06). Portado
/// verbatim de `task_manager_flutter/lib/models/role_permissao_model.dart`
/// (mesmos campos/serializacao) -- ver PLAN.md da Fase 2, Task 10.1.
class RolePermissao {
  final int id;
  final int roleId;
  final String roleKey;
  final String roleDescription;
  final String telaNome;
  final bool podeVer;
  final bool podeInserir;
  final bool podeEditar;
  final bool podeDeletar;
  final bool podeBaixar;

  RolePermissao({
    required this.id,
    required this.roleId,
    required this.roleKey,
    required this.roleDescription,
    required this.telaNome,
    required this.podeVer,
    required this.podeInserir,
    required this.podeEditar,
    required this.podeDeletar,
    required this.podeBaixar,
  });

  factory RolePermissao.fromJson(Map<String, dynamic> json) {
    return RolePermissao(
      id: json['id'] ?? 0,
      roleId: json['roleId'] ?? 0,
      roleKey: json['roleKey'] ?? '',
      roleDescription: json['roleDescription'] ?? '',
      telaNome: json['telaNome'] ?? '',
      podeVer: json['podeVer'] ?? false,
      podeInserir: json['podeInserir'] ?? false,
      podeEditar: json['podeEditar'] ?? false,
      podeDeletar: json['podeDeletar'] ?? false,
      podeBaixar: json['podeBaixar'] ?? false,
    );
  }

  RolePermissao copyWith({
    bool? podeVer,
    bool? podeInserir,
    bool? podeEditar,
    bool? podeDeletar,
    bool? podeBaixar,
  }) {
    return RolePermissao(
      id: id,
      roleId: roleId,
      roleKey: roleKey,
      roleDescription: roleDescription,
      telaNome: telaNome,
      podeVer: podeVer ?? this.podeVer,
      podeInserir: podeInserir ?? this.podeInserir,
      podeEditar: podeEditar ?? this.podeEditar,
      podeDeletar: podeDeletar ?? this.podeDeletar,
      podeBaixar: podeBaixar ?? this.podeBaixar,
    );
  }
}

/// Uma linha (tela) da matriz de Permissoes.
class RolePermissionMenuEntry {
  final String groupId;
  final String groupLabel;
  final String menuItemId;
  final String label;
  final String telaNome;

  const RolePermissionMenuEntry({
    required this.groupId,
    required this.groupLabel,
    required this.menuItemId,
    required this.label,
    required this.telaNome,
  });

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return label.toLowerCase().contains(normalized) ||
        groupLabel.toLowerCase().contains(normalized) ||
        menuItemId.toLowerCase().contains(normalized) ||
        telaNome.toLowerCase().contains(normalized);
  }
}

/// Um grupo de telas da matriz de Permissoes (unidade do checkbox "grupo").
class RolePermissionGroup {
  final String id;
  final String label;
  final List<RolePermissionMenuEntry> entries;

  const RolePermissionGroup({
    required this.id,
    required this.label,
    required this.entries,
  });
}

/// Catalogo de telas exibidas na matriz de Permissoes (SIS-06).
///
/// ADAPTACAO (Fase 2, Task 10.1): o arquivo original do cliente
/// (`task_manager_flutter/lib/utils/role_permission_catalog.dart`) monta os
/// grupos a partir de `MenuConfig.groups` -- a arvore de menu completa do
/// app cliente (`menu_config.dart`, ~600 linhas) mais `PermissionService`,
/// nenhum dos dois presente no admin panel e fora do escopo desta fase
/// (arquivos deste plano: `role_permissao_normalizacao.dart`,
/// `role_permission_catalog.dart`, `role_permissao_screen.dart`, ver
/// PLAN.md). A matriz de Permissoes gerencia acesso as telas de TODO o
/// sistema (nao so aos 8 itens do menu "Sistema" deste app), entao a fonte
/// de verdade correta aqui e o proprio conjunto de `telaNome` que ja existe
/// em `role_permissao` (retornado por `GET /api/role-permissao/all`) -- cada
/// tela vira seu proprio grupo de 1 entrada. O checkbox de "grupo" (portado
/// de `buildRolePermissionGroupBatch`) continua funcional: marca/desmarca as
/// 5 permissoes daquela tela via `POST .../batch`. Nenhuma logica de
/// normalizacao de nome foi alterada -- so a fonte da lista de telas.
class RolePermissionCatalog {
  RolePermissionCatalog._();

  /// Monta os grupos (1 tela = 1 grupo) a partir dos nomes de tela
  /// distintos em [telaNomes], ordenados por label, filtrados por [query]
  /// (ver [RolePermissionMenuEntry.matches]).
  static List<RolePermissionGroup> groups(
    Iterable<String> telaNomes, {
    String query = '',
  }) {
    final vistos = <String>{};
    final entradas = <RolePermissionMenuEntry>[];

    for (final telaNome in telaNomes) {
      if (telaNome.isEmpty) continue;
      final chave = normalizeTelaNome(telaNome);
      if (chave.isEmpty || !vistos.add(chave)) continue;
      final label = _humanizeTelaNome(telaNome);
      entradas.add(RolePermissionMenuEntry(
        groupId: chave,
        groupLabel: label,
        menuItemId: telaNome,
        label: label,
        telaNome: telaNome,
      ));
    }

    entradas.sort((a, b) => a.label.compareTo(b.label));

    return entradas
        .where((e) => e.matches(query))
        .map((e) => RolePermissionGroup(id: e.groupId, label: e.groupLabel, entries: [e]))
        .toList();
  }

  /// Converte um `telaNome` (camelCase ou snake_case) para um label legivel.
  /// Exemplo: `'nfeEntrada'` -> `'Nfe Entrada'`, `'centro_custo'` -> `'Centro Custo'`.
  static String _humanizeTelaNome(String telaNome) {
    final comEspacos = telaNome
        .replaceAllMapped(
            RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .replaceAll('_', ' ')
        .trim();
    if (comEspacos.isEmpty) return telaNome;
    return comEspacos
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}

/// Campos booleanos de uma permissao, na ordem exibida na matriz.
const List<String> rolePermissionFields = [
  'podeVer',
  'podeInserir',
  'podeEditar',
  'podeDeletar',
  'podeBaixar',
];

/// Le o valor de um campo de [RolePermissao] pelo nome. Portado verbatim de
/// `task_manager_flutter/lib/utils/role_permission_group_selection.dart`.
bool rolePermissionFieldValue(RolePermissao permissao, String campo) {
  return switch (campo) {
    'podeVer' => permissao.podeVer,
    'podeInserir' => permissao.podeInserir,
    'podeEditar' => permissao.podeEditar,
    'podeDeletar' => permissao.podeDeletar,
    'podeBaixar' => permissao.podeBaixar,
    _ => false,
  };
}

/// Valor do checkbox "tristate" de um grupo: `true` se todas as
/// permissoes de todas as telas do grupo estao marcadas, `false` se
/// nenhuma, `null` (indeterminado) se parcial. Portado verbatim.
bool? rolePermissionGroupCheckboxValue({
  required RolePermissionGroup grupo,
  required RolePermissao Function(RolePermissionMenuEntry tela) permissaoDe,
}) {
  if (grupo.entries.isEmpty) return false;

  var total = 0;
  var marcados = 0;

  for (final tela in grupo.entries) {
    final permissao = permissaoDe(tela);
    for (final campo in rolePermissionFields) {
      total++;
      if (rolePermissionFieldValue(permissao, campo)) {
        marcados++;
      }
    }
  }

  if (marcados == 0) return false;
  if (marcados == total) return true;
  return null;
}

/// Monta o payload de `POST /api/role-permissao/batch` para marcar ou
/// desmarcar as 5 permissoes de todas as telas do grupo de uma vez.
/// Portado verbatim -- o backend (`RolePermissaoController.batch`) espera
/// uma LISTA JSON na raiz do body (`List<Map<String,Object>>`), nao um
/// objeto envolvendo a lista.
List<Map<String, Object>> buildRolePermissionGroupBatch({
  required int roleId,
  required RolePermissionGroup grupo,
  required bool marcar,
}) {
  return grupo.entries
      .map(
        (tela) => <String, Object>{
          'roleId': roleId,
          'telaNome': tela.telaNome,
          for (final campo in rolePermissionFields) campo: marcar,
        },
      )
      .toList();
}

/// Retorna uma copia de [permissao] com todos os 5 campos ajustados para
/// [valor] -- usado para atualizar o estado local apos um `_salvarGrupo`
/// bem-sucedido. Portado verbatim.
RolePermissao rolePermissionWithAllFields(
  RolePermissao permissao, {
  required bool valor,
}) {
  return permissao.copyWith(
    podeVer: valor,
    podeInserir: valor,
    podeEditar: valor,
    podeDeletar: valor,
    podeBaixar: valor,
  );
}
