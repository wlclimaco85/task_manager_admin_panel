/// Tipos de campo suportados pelo GenericDetailFormScreen. Subconjunto
/// enxuto do FieldType do app cliente — cresce sob demanda conforme os
/// modulos das proximas fases precisarem (nao preventivamente).
enum FieldType {
  text,
  number,
  email,
  boolean,
  multiline,
}

/// Configuracao declarativa de um campo de formulario, usada tanto pelo
/// GenericDetailFormScreen (renderizar o input certo) quanto para exibir a
/// coluna correspondente no GenericGridScreen.
class FieldConfig {
  const FieldConfig({
    required this.key,
    required this.label,
    this.type = FieldType.text,
    this.required = false,
    this.showInGrid = true,
    this.validator,
  });

  /// Nome do campo no JSON do backend.
  final String key;

  /// Rotulo exibido na UI (grid header e label do form).
  final String label;

  final FieldType type;
  final bool required;

  /// Se `false`, o campo aparece no formulario mas nao vira coluna no grid.
  final bool showInGrid;

  /// Validador extra, alem da obrigatoriedade padrao de [required].
  final String? Function(String? value)? validator;
}
