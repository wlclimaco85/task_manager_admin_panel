import '../../services/network_caller.dart';

/// Tipos de campo suportados pelo GenericDetailFormScreen. Subconjunto
/// enxuto do FieldType do app cliente — cresce sob demanda conforme os
/// modulos das proximas fases precisarem (nao preventivamente).
enum FieldType {
  text,
  number,
  email,
  boolean,
  multiline,
  date,
  dropdown,
}

/// Opcao de um campo [FieldType.dropdown]. `value` e o valor bruto enviado
/// ao backend (mesmo tipo do JSON, ex. String de enum ou int de FK);
/// `label` e o texto exibido ao usuario.
class DropdownOption {
  const DropdownOption({required this.value, required this.label});

  final dynamic value;
  final String label;
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
    this.dateTime = false,
    this.options,
    this.optionsLoader,
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

  /// So relevante para [FieldType.date]. `true` = backend espera
  /// `LocalDateTime` (serializado com sufixo `T00:00:00`); `false` (default)
  /// = backend espera `LocalDate` (`yyyy-MM-dd`).
  final bool dateTime;

  /// So relevante para [FieldType.dropdown]. Opcoes fixas e sincronas (ex.
  /// status/prioridade de um enum). Nunca preenchido ao mesmo tempo que
  /// [optionsLoader] no mesmo campo.
  final List<DropdownOption>? options;

  /// So relevante para [FieldType.dropdown]. Carregamento assincrono de
  /// opcoes (ex. FK remota de Aplicativo/Parceiro/Empresa/Setor), disparado
  /// 1x no `initState` do form, recebendo o [NetworkCaller] ja existente do
  /// form chamador (nunca cria um `NetworkCaller` proprio). Nunca preenchido
  /// ao mesmo tempo que [options] no mesmo campo.
  final Future<List<DropdownOption>> Function(NetworkCaller)? optionsLoader;
}
