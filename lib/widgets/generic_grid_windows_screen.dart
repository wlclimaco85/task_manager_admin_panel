import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:data_table_2/data_table_2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/grid_colors.dart';
import '../utils/grid_texts.dart';

import 'package:task_manager_admin_panel/utils/app_logger.dart';
import 'package:task_manager_admin_panel/models/tela_ajuda_model.dart';
import 'package:task_manager_admin_panel/services/tela_ajuda_service.dart';
import 'package:task_manager_admin_panel/config/api_links.dart';
import 'package:task_manager_admin_panel/services/auth_utility.dart';


import '../../../models/network_response.dart';
import '../../../utils/tenant_context.dart';
import '../../services/network_caller.dart';

// ==============================================
// ENUMS E CONFIGURAÇÕES
// ==============================================

// Enum para tipos de campo
enum FieldType {
  text,
  number,
  email,
  date,
  datetime,
  multiline,
  dropdown,
  boolean,
  file,
  password,
  phone,
  cpf,
  cnpj,
  cpfCnpj,
  cep,
  percentage,
  url,
  multiselect,
  currency,
}

// Configuração de arquivo
class FileConfig {
  final List<String> allowedExtensions;
  final bool allowMultiple;
  final int maxFileSize;
  final String fileFieldName;

  const FileConfig({
    this.allowedExtensions = const ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'],
    this.allowMultiple = false,
    this.maxFileSize = 5 * 1024 * 1024,
    this.fileFieldName = 'file',
  });
}

// Configuração avançada de campo
Future<String?> platformFileToDataUri(PlatformFile file) async {
  Uint8List? bytes = file.bytes;
  // dart:io File nao existe no Flutter Web — so tenta ler por path fora do Web.
  if (bytes == null && file.path != null && !kIsWeb) {
    bytes = await File(file.path!).readAsBytes();
  }
  if (bytes == null || bytes.isEmpty) return null;

  return 'data:${_mimeFromFileName(file.name)};base64,${base64Encode(bytes)}';
}

String _mimeFromFileName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'application/octet-stream';
}

// Fix (card #459): campos de relacionamento (@ManyToOne/@JoinColumn no
// backend) precisam ir como objeto {"id": N}, mas os dropdowns deste widget
// legado guardam so o id escalar (String/int). Alguns campos (ex.:
// aplicativo em WindowsLoginGridScreen.additionalFormData) ja chegam
// prontos como Map -- por isso a conversao so acontece quando o valor
// ainda e String/num (idempotente, nao mexe em quem ja e objeto).
const entityRelationshipFields = [
  'empresa', 'parceiro', 'aplicativo', 'fornecedor', 'cliente',
  'contaBancaria', 'setor', 'centroCusto', 'formaPagamento',
];

Map<String, dynamic> normalizeEntityRelationships(
    Map<String, dynamic> formData) {
  final updated = Map<String, dynamic>.from(formData);
  for (final field in entityRelationshipFields) {
    final value = updated[field];
    if (value is String && value.isNotEmpty) {
      updated[field] = {'id': int.tryParse(value) ?? value};
    } else if (value is num) {
      updated[field] = {'id': value.toInt()};
    }
  }
  return updated;
}

bool _hasUsableStorageId(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return false;
  final normalized = text.toLowerCase();
  return normalized != '0' && normalized != 'null' && normalized != 'false';
}

const _parceiroScopeKeys = ['parceiro', 'parceiroid', 'parcid', 'clienteid'];
const _empresaScopeKeys = ['empresa', 'empresaid', 'empid'];

/// `true` se `extraParams` (contexto de navegação — ex.: aba "Contas a
/// Pagar" dentro da tela de um Parceiro específico) traz explicitamente um
/// parceiro/parcId. Bug (card campo-parceiro-fornecedor-disabled-invertido):
/// a versão anterior lia `SharedPreferences.get('parceiroId'/'parcId')`, mas
/// NADA no app grava essas chaves — a leitura sempre retornava null,
/// deixando o campo "Fornecedor" travado para sempre e o campo "Parceiro"
/// dependente só do login (ver `effectiveHasParceiroContext`).
@visibleForTesting
bool hasParceiroContextInExtraParams(Map<String, dynamic>? extraParams) {
  if (extraParams == null) return false;
  for (final entry in extraParams.entries) {
    if (_parceiroScopeKeys.contains(entry.key.toLowerCase()) &&
        _hasUsableStorageId(entry.value)) {
      return true;
    }
  }
  return false;
}

/// `true` se `extraParams` escopa explicitamente por empresa (ex.: aba
/// "Contas a Pagar" dentro da tela de uma Empresa) SEM trazer parceiro —
/// nesse caso o contexto de parceiro NUNCA se aplica, mesmo que o login do
/// usuário logado seja de um parceiro (ex.: escritório contábil navegando
/// dentro de uma empresa cliente).
@visibleForTesting
bool hasExplicitEmpresaOnlyScope(Map<String, dynamic>? extraParams) {
  if (extraParams == null) return false;
  final hasEmpresaKey = extraParams.keys
      .any((k) => _empresaScopeKeys.contains(k.toLowerCase()));
  return hasEmpresaKey && !hasParceiroContextInExtraParams(extraParams);
}

/// Contexto efetivo de parceiro usado para travar "Parceiro" e liberar
/// "Fornecedor" (e vice-versa) nos formulários financeiros.
///
/// Prioridade:
/// 1. `extraParams` com parceiro/parceiroId/parcId explícito (drill-down a
///    partir da tela de um Parceiro específico) → SEMPRE contexto de parceiro.
/// 2. `extraParams` com empresa/empresaId explícito e SEM parceiro (drill-down
///    a partir da tela de uma Empresa) → NUNCA contexto de parceiro.
/// 3. Sem `extraParams` (acesso direto pelo menu principal, sem navegação
///    aninhada) → cai no próprio login (`false`).
@visibleForTesting
bool effectiveHasParceiroContext(
  Map<String, dynamic>? extraParams,
  bool tenantHasParceiro,
) {
  if (hasParceiroContextInExtraParams(extraParams)) return true;
  if (hasExplicitEmpresaOnlyScope(extraParams)) return false;
  return tenantHasParceiro;
}

bool _isParceiroLockField(FieldConfigWindows config) {
  final field = config.fieldName.toLowerCase();
  final label = config.label.toLowerCase();
  return field == 'parceiro' ||
      field == 'parceiroid' ||
      field == 'parceiro.id' ||
      field == 'parcid' ||
      label == 'parceiro';
}

bool _isFornecedorLockField(FieldConfigWindows config) {
  final field = config.fieldName.toLowerCase();
  final label = config.label.toLowerCase();
  return field == 'fornecedor' ||
      field == 'fornecedorid' ||
      field == 'fornecedor.id' ||
      label == 'fornecedor';
}

@visibleForTesting
bool isParceiroFieldDisabledByStorage(
  FieldConfigWindows config,
  bool hasParceiroIdOrParcId,
) =>
    _isParceiroLockField(config) && hasParceiroIdOrParcId;

/// Decide se um campo dropdown de "Parceiro" (ou variantes: fieldName
/// contendo "parceiro", ou "cliente") deve ser pré-preenchido com
/// [null] no INSERT — usado no bloco "TAREFA 1" de
/// [_GenericGridWindowsScreenState._openForm].
///
/// Bug de producao (card WdlEAxFK): antes usava `false`
/// bruto (so o login), nao o contexto EFETIVO ja calculado por
/// [effectiveHasParceiroContext] -- um Cliente abrindo uma tela em
/// drill-down de Empresa (extraParams so com empresa, regra 2 de
/// [effectiveHasParceiroContext]) ainda tinha o campo Parceiro
/// pre-preenchido com o proprio parceiro, mesmo o campo devendo ficar sem
/// contexto de parceiro nenhum ali.
@visibleForTesting
bool shouldPrefillParceiroField(
  FieldConfigWindows config,
  bool hasParceiroContext,
) {
  final fn = config.fieldName.toLowerCase();
  final isParceiroField =
      fn == 'parceiro' || fn.contains('parceiro') || fn == 'cliente';
  return isParceiroField && hasParceiroContext;
}

@visibleForTesting
bool isFornecedorFieldEnabledByStorage(
  FieldConfigWindows config,
  bool hasParceiroIdOrParcId,
) =>
    !_isFornecedorLockField(config) || hasParceiroIdOrParcId;

class FieldConfigWindows {
  final String label;
  final String fieldName;
  final bool isFilterable;
  final bool isInForm;

  /// H12: quando false, o campo não aparece como coluna na grid,
  /// mas continua disponível no formulário (diferente de isVisibleByDefault
  /// que só oculta por padrão e pode ser reativado pelo usuário).
  final bool isInGrid;
  final int flex;
  final int maxLines;
  final IconData? icon;
  final bool isSortable;
  final FieldType fieldType;
  final List<Map<String, dynamic>>? dropdownOptions;
  final Future<List<Map<String, dynamic>>> Function()? dropdownFutureBuilder;

  /// Para dropdown cascadeado: função que recebe o valor do campo pai e
  /// retorna a lista filtrada. Quando definido, ignora dropdownFutureBuilder.
  final Future<List<Map<String, dynamic>>> Function(String? param)?
      dropdownFutureBuilderWithParam;

  /// Nome do campo (fieldName) do qual este dropdown depende para cascade.
  final String? dependsOnField;
  final String dropdownValueField;
  final String dropdownDisplayField;
  final bool isRequired;
  final String? Function(String?)? validator;
  final String? displayFieldName;
  final bool isVisibleByDefault;
  final bool isFixed;
  final bool enabled;
  final dynamic defaultValue;
  final FileConfig? fileConfig;
  final dynamic dropdownSelectedValue;
  final Map<String, dynamic>? fieldSpecificConfig;

  /// Ordem explícita do campo no formulário. Quando definido, sobrepõe a ordem
  /// do servidor. Útil para campos Flutter-only (ex: dropdowns de substituição)
  /// que precisam aparecer em posição específica.
  final int? fieldOrder;

  /// Quando definido, o campo só aparece no form se o campo indicado por
  /// `visibleWhenField` tiver o valor igual a `visibleWhenValue`.
  /// Útil para campos que devem aparecer apenas quando um checkbox está marcado.
  final String? visibleWhenField;
  final dynamic visibleWhenValue;

  /// Controle granular de habilitação por modo do formulário.
  /// Quando null, usa o valor de [enabled].
  /// Útil para campos que devem ser somente-leitura no INSERT mas editáveis no EDIT
  /// (ex: status de um alvará).
  final bool? enabledOnInsert;
  final bool? enabledOnEdit;

  /// Busca remota paginada (server-side) — para dropdowns cujo universo de
  /// opções é grande demais para carregar de uma vez (ex: Parceiro). Quando
  /// definido, o dropdown NÃO faz o fetch único de [dropdownFutureBuilder]/
  /// [dropdownOptions]: abre um diálogo com busca debounced (reconsulta o
  /// backend a cada termo digitado) e paginação real via scroll (carrega
  /// mais páginas conforme o usuário rola a lista), em vez de filtrar
  /// localmente sobre um lote fixo já carregado.
  final Future<PaginaDropdown> Function({String? busca, required int pagina})?
      dropdownRemoteSearch;

  /// Resolve o rótulo exibido para o valor pré-selecionado (edição/valor
  /// travado) quando [dropdownRemoteSearch] está definido — o registro
  /// selecionado pode não estar na página atualmente carregada pelo
  /// dropdown remoto. Ignorado quando [dropdownRemoteSearch] é null.
  final Future<String?> Function(String id)? dropdownResolveLabel;

  const FieldConfigWindows({
    required this.label,
    required this.fieldName,
    this.isFilterable = true,
    this.isInForm = true,
    this.isInGrid = true,
    this.flex = 1,
    this.maxLines = 1,
    this.icon,
    this.isSortable = true,
    this.fieldType = FieldType.text,
    this.dropdownOptions,
    this.dropdownFutureBuilder,
    this.dropdownFutureBuilderWithParam,
    this.dependsOnField,
    this.dropdownValueField = 'value',
    this.dropdownDisplayField = 'label',
    this.isRequired = false,
    this.validator,
    this.displayFieldName,
    this.isVisibleByDefault = true,
    this.isFixed = false,
    this.enabled = true,
    this.defaultValue,
    this.fileConfig,
    this.dropdownSelectedValue,
    this.fieldSpecificConfig,
    this.fieldOrder,
    this.visibleWhenField,
    this.visibleWhenValue,
    this.enabledOnInsert,
    this.enabledOnEdit,
    this.dropdownRemoteSearch,
    this.dropdownResolveLabel,
  });
}

/// Página de resultados de um dropdown com busca remota paginada (ver
/// [FieldConfigWindows.dropdownRemoteSearch]).
class PaginaDropdown {
  final List<Map<String, dynamic>> items;
  final int total;

  /// Preenchido quando a busca falhou (erro de rede, status != 200, corpo
  /// invalido) -- diferencia "erro real" de "busca sem resultado", que antes
  /// pareciam a mesma coisa ("Nenhum resultado") na tela.
  final String? erro;

  const PaginaDropdown(this.items, this.total, {this.erro});
}

// Configuração de exportação
class ExportConfig {
  final bool enableCsvExport;
  final bool enablePdfExport;
  final String filenamePrefix;

  const ExportConfig({
    this.enableCsvExport = true,
    this.enablePdfExport = true,
    this.filenamePrefix = 'export',
  });
}

// Configuração de paginação
class PaginationConfig {
  final int defaultRowsPerPage;
  final List<int> availableRowsPerPage;
  final bool showItemsPerPageSelector;

  const PaginationConfig({
    this.defaultRowsPerPage = 25,
    this.availableRowsPerPage = const [10, 25, 50, 100],
    this.showItemsPerPageSelector = true,
  });
}

// Configuração de ação personalizada
class CustomAction<T> {
  final IconData icon;
  final String label;
  final void Function(BuildContext context, T item) onPressed;
  final bool Function(T item)? isVisible;

  /// Quando informado e > 0, exibe um badge numerico no canto do botao da acao
  /// (ex.: quantidade de anexos da conta). 0 ou null = sem badge.
  final int Function(T item)? badgeCount;

  const CustomAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isVisible,
    this.badgeCount,
  });
}

// ==============================================
// FORMATAÇÃO E VALIDAÇÃO
// ==============================================

// Formatters específicos para diferentes tipos de campo
class NumberInputFormatter extends TextInputFormatter {
  final int decimalDigits;

  NumberInputFormatter({this.decimalDigits = 2});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    final cleaned = newValue.text.replaceAll(RegExp(r'[^\d.]'), '');
    final parts = cleaned.split('.');

    if (parts.length > 2) return oldValue;
    if (parts.length == 2 && parts[1].length > decimalDigits) {
      return oldValue;
    }

    return newValue.copyWith(text: cleaned);
  }
}

class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    final cleaned = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.isEmpty) return newValue;

    final value = int.parse(cleaned) / 100;
    final formatted = 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cleaned = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    if (cleaned.length <= 11) {
      String formatted = cleaned;
      if (cleaned.length > 2) {
        formatted = '(${cleaned.substring(0, 2)}) ${cleaned.substring(2)}';
      }
      if (cleaned.length > 7) {
        formatted =
            '(${cleaned.substring(0, 2)}) ${cleaned.substring(2, 7)}-${cleaned.substring(7)}';
      }
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
    return oldValue;
  }
}

class CpfInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cleaned = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    if (cleaned.length <= 11) {
      String formatted = cleaned;
      if (cleaned.length > 3) {
        formatted = '${cleaned.substring(0, 3)}.${cleaned.substring(3)}';
      }
      if (cleaned.length > 6) {
        formatted =
            '${cleaned.substring(0, 3)}.${cleaned.substring(3, 6)}.${cleaned.substring(6)}';
      }
      if (cleaned.length > 9) {
        formatted =
            '${cleaned.substring(0, 3)}.${cleaned.substring(3, 6)}.${cleaned.substring(6, 9)}-${cleaned.substring(9)}';
      }
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
    return oldValue;
  }
}

class CnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cleaned = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    if (cleaned.length <= 14) {
      String formatted = cleaned;
      if (cleaned.length > 2) {
        formatted = '${cleaned.substring(0, 2)}.${cleaned.substring(2)}';
      }
      if (cleaned.length > 5) {
        formatted =
            '${cleaned.substring(0, 2)}.${cleaned.substring(2, 5)}.${cleaned.substring(5)}';
      }
      if (cleaned.length > 8) {
        formatted =
            '${cleaned.substring(0, 2)}.${cleaned.substring(2, 5)}.${cleaned.substring(5, 8)}/${cleaned.substring(8)}';
      }
      if (cleaned.length > 12) {
        formatted =
            '${cleaned.substring(0, 2)}.${cleaned.substring(2, 5)}.${cleaned.substring(5, 8)}/${cleaned.substring(8, 12)}-${cleaned.substring(12)}';
      }
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
    return oldValue;
  }
}

// Validações comuns
class FieldValidators {
  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) return null;
    final regex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return regex.hasMatch(value) ? null : 'Digite um email válido';
  }

  static String? validateRequired(String? value, String fieldName) {
    if (value == null || value.isEmpty) {
      return '$fieldName é obrigatório';
    }
    return null;
  }

  static String? validateMinLength(
    String? value,
    int minLength,
    String fieldName,
  ) {
    if (value == null || value.length < minLength) {
      return '$fieldName deve ter pelo menos $minLength caracteres';
    }
    return null;
  }

  static String? validatePhone(String? value) {
    if (value == null || value.isEmpty) return null;
    final cleaned = value.replaceAll(RegExp(r'[^\d]'), '');
    return cleaned.length >= 10 ? null : 'Digite um telefone válido';
  }

  static String? validateCpf(String? value) {
    if (value == null || value.isEmpty) return null;
    final cleaned = value.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.length != 11) return 'CPF deve ter 11 dígitos';
    return null;
  }

  static String? validateCnpj(String? value) {
    if (value == null || value.isEmpty) return null;
    final cleaned = value.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.length != 14) return 'CNPJ deve ter 14 dígitos';
    return null;
  }

  static String? validateNumber(String? value, {double? min, double? max}) {
    if (value == null || value.isEmpty) return null;
    final number = double.tryParse(value.replaceAll(',', '.'));
    if (number == null) return 'Digite um número válido';
    if (min != null && number < min) return 'Valor mínimo: $min';
    if (max != null && number > max) return 'Valor máximo: $max';
    return null;
  }
}

// ==============================================
// FÁBRICA DE CAMPOS (FIELD FACTORY)
// ==============================================

class FieldFactory {
  static Widget buildField({
    required FieldConfigWindows config,
    required TextEditingController controller,
    required BuildContext context,
    required Map<String, List<PlatformFile>> fileCache,
    required Map<String, List<Map<String, dynamic>>> dropdownCache,
    dynamic item,

    /// Mapa de todos os controllers do formulário — necessário para cascading.
    Map<String, TextEditingController>? allControllers,

    /// Fix (card #458): chamado apos selecionar/remover arquivo em campos
    /// FieldType.file, para forcar o rebuild do dialog (ver showDialog em
    /// _showFormDialog/StatefulBuilder).
    VoidCallback? onFileChanged,
  }) {
    if (item == null &&
        config.fieldType == FieldType.dropdown &&
        config.dropdownSelectedValue != null &&
        controller.text.isEmpty) {
      controller.text = config.dropdownSelectedValue.toString();
    }

    final fieldWidget = _buildSpecificField(
      config,
      controller,
      context,
      fileCache,
      dropdownCache,
      allControllers: allControllers,
      onFileChanged: onFileChanged,
    );

    // Boolean fields are always interactive — never absorb pointer
    final effectiveEnabled =
        config.enabled || config.fieldType == FieldType.boolean;

    return AbsorbPointer(
      absorbing: !effectiveEnabled,
      child: Opacity(opacity: effectiveEnabled ? 1.0 : 0.6, child: fieldWidget),
    );
  }

  static Widget _buildSpecificField(
    FieldConfigWindows config,
    TextEditingController controller,
    BuildContext context,
    Map<String, List<PlatformFile>> fileCache,
    Map<String, List<Map<String, dynamic>>> dropdownCache, {
    Map<String, TextEditingController>? allControllers,
    VoidCallback? onFileChanged,
  }) {
    switch (config.fieldType) {
      case FieldType.number:
        return _buildNumberField(config, controller);
      case FieldType.email:
        return _buildEmailField(config, controller);
      case FieldType.date:
        return _buildDateField(config, controller, context);
      case FieldType.password:
        return _buildPasswordField(config, controller);
      case FieldType.phone:
        return _buildPhoneField(config, controller);
      case FieldType.cpf:
        return _buildCpfField(config, controller);
      case FieldType.cnpj:
        return _buildCnpjField(config, controller);
      case FieldType.cpfCnpj:
        return _buildCpfCnpjField(config, controller);
      case FieldType.cep:
        return _buildCepField(config, controller, context);
      case FieldType.multiline:
        return _buildMultilineField(config, controller);
      case FieldType.dropdown:
        final dependsOnCtrl =
            config.dependsOnField != null && allControllers != null
                ? allControllers[config.dependsOnField]
                : null;
        return _buildDropdownField(config, controller, dropdownCache,
            dependsOnController: dependsOnCtrl);
      case FieldType.file:
        return _buildFileField(config, controller, fileCache, context,
            onFileChanged: onFileChanged);
      case FieldType.boolean:
        return _buildBooleanField(config, controller);
      case FieldType.currency:
        return _buildCurrencyField(config, controller);
      case FieldType.percentage:
        return _buildPercentageField(config, controller);
      case FieldType.url:
        return _buildUrlField(config, controller);
      case FieldType.multiselect:
        return _buildMultiselectField(
            config, controller, dropdownCache, context);
      default:
        return _buildTextField(config, controller);
    }
  }

  static Widget _buildNumberField(
    FieldConfigWindows config,
    TextEditingController controller,
  ) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: _buildInputDecoration(config),
      inputFormatters: [
        NumberInputFormatter(
          decimalDigits: config.fieldSpecificConfig?['decimalDigits'] ?? 2,
        ),
      ],
      validator: (value) {
        if (config.isRequired && (value == null || value.isEmpty)) {
          return '${config.label} é obrigatório';
        }
        if (value != null && value.isNotEmpty) {
          final number = double.tryParse(value.replaceAll(',', '.'));
          if (number == null) {
            return 'Digite um número válido';
          }
          if (config.fieldSpecificConfig?['minValue'] != null &&
              number < config.fieldSpecificConfig!['minValue']) {
            return 'Valor mínimo: ${config.fieldSpecificConfig!['minValue']}';
          }
          if (config.fieldSpecificConfig?['maxValue'] != null &&
              number > config.fieldSpecificConfig!['maxValue']) {
            return 'Valor máximo: ${config.fieldSpecificConfig!['maxValue']}';
          }
        }
        return config.validator?.call(value);
      },
    );
  }

  static Widget _buildEmailField(
    FieldConfigWindows config,
    TextEditingController controller,
  ) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.emailAddress,
      decoration: _buildInputDecoration(config),
      validator: (value) {
        if (config.isRequired && (value == null || value.isEmpty)) {
          return '${config.label} é obrigatório';
        }
        if (value != null && value.isNotEmpty && !_isValidEmail(value)) {
          return 'Digite um email válido';
        }
        return config.validator?.call(value);
      },
    );
  }

  static Widget _buildDateField(
    FieldConfigWindows config,
    TextEditingController controller,
    BuildContext context,
  ) {
    return TextFormField(
      controller: controller,
      decoration: _buildInputDecoration(config),
      readOnly: true,
      onTap: () => _selectDate(context, controller),
      validator: (value) {
        if (config.isRequired && (value == null || value.isEmpty)) {
          return '${config.label} é obrigatório';
        }
        return config.validator?.call(value);
      },
    );
  }

  static Widget _buildPasswordField(
    FieldConfigWindows config,
    TextEditingController controller,
  ) {
    return TextFormField(
      controller: controller,
      obscureText: true,
      decoration: _buildInputDecoration(config),
      validator: (value) {
        if (config.isRequired && (value == null || value.isEmpty)) {
          return '${config.label} é obrigatório';
        }
        if (value != null && value.isNotEmpty && value.length < 6) {
          return 'A senha deve ter pelo menos 6 caracteres';
        }
        return config.validator?.call(value);
      },
    );
  }

  static Widget _buildPhoneField(
    FieldConfigWindows config,
    TextEditingController controller,
  ) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.phone,
      decoration: _buildInputDecoration(config),
      inputFormatters: [PhoneInputFormatter()],
      validator: (value) {
        if (config.isRequired && (value == null || value.isEmpty)) {
          return '${config.label} é obrigatório';
        }
        if (value != null && value.isNotEmpty && !_isValidPhone(value)) {
          return 'Digite um telefone válido';
        }
        return config.validator?.call(value);
      },
    );
  }

  static Widget _buildCpfField(
    FieldConfigWindows config,
    TextEditingController controller,
  ) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: _buildInputDecoration(config),
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        CpfInputFormatter(),
      ],
      validator: (value) {
        if (config.isRequired && (value == null || value.isEmpty)) {
          return '${config.label} é obrigatório';
        }
        if (value != null && value.isNotEmpty && !_isValidCpf(value)) {
          return 'CPF inválido';
        }
        return config.validator?.call(value);
      },
    );
  }

  static Widget _buildCnpjField(
    FieldConfigWindows config,
    TextEditingController controller,
  ) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: _buildInputDecoration(config),
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        CnpjInputFormatter(),
      ],
      validator: (value) {
        if (config.isRequired && (value == null || value.isEmpty)) {
          return '${config.label} é obrigatório';
        }
        if (value != null && value.isNotEmpty && !_isValidCnpj(value)) {
          return 'CNPJ inválido';
        }
        return config.validator?.call(value);
      },
    );
  }

  static Widget _buildCpfCnpjField(
    FieldConfigWindows config,
    TextEditingController controller,
  ) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.text,
      decoration: _buildInputDecoration(config).copyWith(
        hintText: 'CPF ou CNPJ',
      ),
      validator: (value) {
        if (config.isRequired && (value == null || value.isEmpty)) {
          return '${config.label} é obrigatório';
        }
        return config.validator?.call(value);
      },
    );
  }

  static Widget _buildCepField(
    FieldConfigWindows config,
    TextEditingController controller,
    BuildContext context,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: _buildInputDecoration(config).copyWith(
              hintText: '00000-000',
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
            validator: (value) {
              if (config.isRequired && (value == null || value.isEmpty)) {
                return '${config.label} é obrigatório';
              }
              return config.validator?.call(value);
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: () => _buscarCep(context, controller),
            icon: const Icon(Icons.search, size: 18),
            label: const Text('Buscar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: GridColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
      ],
    );
  }

  static Future<void> _buscarCep(
    BuildContext context,
    TextEditingController cepController,
  ) async {
    final cep = cepController.text.replaceAll(RegExp(r'\D'), '');
    if (cep.length != 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CEP deve ter 8 dígitos', style: TextStyle(color: Colors.white)), backgroundColor: GridColors.error),
      );
      return;
    }
    try {
      final resp =
          await http.get(Uri.parse('https://viacep.com.br/ws/$cep/json/'));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['erro'] == true) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('CEP não encontrado', style: TextStyle(color: Colors.white)), backgroundColor: GridColors.warning),
            );
          }
          return;
        }
        _cepResultCallback?.call(data);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'CEP encontrado: ${data['logradouro'] ?? ''}, ${data['localidade'] ?? ''}', style: const TextStyle(color: Colors.white)),
                backgroundColor: GridColors.success),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao buscar CEP: $e', style: const TextStyle(color: Colors.white)), backgroundColor: GridColors.error),
        );
      }
    }
  }

  // Callback para preencher campos após busca de CEP
  static void Function(Map<String, dynamic>)? _cepResultCallback;

  static Widget _buildTextField(
    FieldConfigWindows config,
    TextEditingController controller,
  ) {
    // Detecta campos CPF/CNPJ pelo nome mesmo que o tipo seja text
    final fn = config.fieldName.toLowerCase();
    final isCpfCnpj = fn.contains('cpf') || fn.contains('cnpj');

    return TextFormField(
      controller: controller,
      decoration: _buildInputDecoration(config),
      maxLines: config.maxLines,
      keyboardType: isCpfCnpj ? TextInputType.number : null,
      inputFormatters:
          isCpfCnpj ? [FilteringTextInputFormatter.digitsOnly] : null,
      validator: config.validator,
    );
  }

  static Widget _buildMultilineField(
    FieldConfigWindows config,
    TextEditingController controller,
  ) {
    return TextFormField(
      controller: controller,
      decoration: _buildInputDecoration(config),
      maxLines: config.maxLines,
      validator: config.validator,
    );
  }

  static Widget _buildBooleanField(
    FieldConfigWindows config,
    TextEditingController controller,
  ) {
    return StatefulBuilder(
      builder: (context, setState) {
        final isChecked = controller.text.toLowerCase() == 'true';
        return CheckboxListTile(
          title: Text(config.label),
          value: isChecked,
          onChanged: (value) {
            controller.text = (value ?? false).toString();
            setState(() {});
          },
        );
      },
    );
  }

  static Widget _buildDropdownField(
    FieldConfigWindows config,
    TextEditingController controller,
    Map<String, List<Map<String, dynamic>>> dropdownCache, {
    TextEditingController? dependsOnController,
  }) {
    // Cascade: o widget gerencia o próprio fetch via dependsOnController
    if (config.dropdownFutureBuilderWithParam != null) {
      return _buildDropdownContent(
        config: config,
        controller: controller,
        options: const [],
        dependsOnController: dependsOnController,
      );
    }

    // Busca remota paginada: o widget gerencia o próprio fetch por página
    // dentro do diálogo — não carrega a lista inteira de uma vez.
    if (config.dropdownRemoteSearch != null) {
      return _buildDropdownContent(
        config: config,
        controller: controller,
        options: const [],
      );
    }

    final cacheKey = '${config.fieldName}_dropdown';

    if (dropdownCache.containsKey(cacheKey)) {
      return _buildDropdownContent(
        config: config,
        controller: controller,
        options: dropdownCache[cacheKey]!,
      );
    } else if (config.dropdownFutureBuilder != null) {
      return FutureBuilder<List<Map<String, dynamic>>>(
        future: config.dropdownFutureBuilder!(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const CircularProgressIndicator();
          } else if (snapshot.hasError) {
            return Text('Erro ao carregar opções: ${snapshot.error}');
          } else {
            final options = snapshot.data ?? [];
            dropdownCache[cacheKey] = options;
            return _buildDropdownContent(
              config: config,
              controller: controller,
              options: options,
            );
          }
        },
      );
    } else {
      return _buildDropdownContent(
        config: config,
        controller: controller,
        options: config.dropdownOptions ?? [],
      );
    }
  }

  static Widget _buildDropdownContent({
    required FieldConfigWindows config,
    required TextEditingController controller,
    required List<Map<String, dynamic>> options,
    TextEditingController? dependsOnController,
  }) {
    return _SearchableDropdownWindows(
      config: config,
      controller: controller,
      options: options,
      dependsOnController: dependsOnController,
    );
  }

  static Widget _buildFileField(
    FieldConfigWindows config,
    TextEditingController controller,
    Map<String, List<PlatformFile>> fileCache,
    BuildContext context, {
    VoidCallback? onFileChanged,
  }) {
    final fileConfig = config.fileConfig ?? const FileConfig();
    final currentFiles = fileCache[config.fieldName] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (currentFiles.isNotEmpty)
          ...currentFiles.map(
            (file) => ListTile(
              leading: const Icon(Icons.attach_file),
              title: Text(file.name),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: GridColors.error),
                onPressed: () {
                  fileCache[config.fieldName]?.remove(file);
                  controller.text = '';
                  onFileChanged?.call();
                },
              ),
            ),
          ),
        ElevatedButton.icon(
          onPressed: () =>
              _selectFiles(config, controller, fileCache, context, onFileChanged),
          icon: const Icon(Icons.attach_file),
          label: Text(
            currentFiles.isEmpty
                ? GridTexts.selectFile
                : GridTexts.addMoreFiles,
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: GridColors.primary,
            foregroundColor: GridColors.card,
          ),
        ),
        if (fileConfig.allowedExtensions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              'Extensões permitidas: ${fileConfig.allowedExtensions.join(', ')}',
              style: const TextStyle(
                fontSize: 12,
                color: GridColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }

  static Future<void> _selectFiles(
    FieldConfigWindows config,
    TextEditingController controller,
    Map<String, List<PlatformFile>> fileCache,
    BuildContext context, [
    VoidCallback? onFileChanged,
  ]) async {
    final fileConfig = config.fileConfig ?? const FileConfig();

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: fileConfig.allowedExtensions,
        allowMultiple: fileConfig.allowMultiple,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        fileCache[config.fieldName] = result.files;
        controller.text = result.files.map((f) => f.name).join(', ');
        onFileChanged?.call();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao selecionar arquivo: $e'),
          backgroundColor: GridColors.error,
        ),
      );
    }
  }

  static InputDecoration _buildInputDecoration(FieldConfigWindows config) {
    return InputDecoration(
      labelText: config.label + (config.isRequired ? ' *' : ''),
      labelStyle:
          const TextStyle(color: GridColors.textSecondary, fontSize: 13),
      isDense: true,
      filled: true,
      fillColor: GridColors.inputBackground,
      contentPadding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: GridColors.primary, width: 1.5),
        borderRadius: BorderRadius.circular(4),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: GridColors.inputBorder, width: 1.0),
        borderRadius: BorderRadius.circular(4),
      ),
      disabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: GridColors.divider, width: 1.0),
        borderRadius: BorderRadius.circular(4),
      ),
      prefixIcon: config.icon != null
          ? Icon(config.icon, size: 20, color: GridColors.primary)
          : null,
    );
  }

  static Future<void> _selectDate(
    BuildContext context,
    TextEditingController controller,
  ) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: GridColors.primary,
            onPrimary: Colors.white,
            onSurface: GridColors.secondary,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: GridColors.primary),
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      controller.text = DateFormat('yyyy-MM-dd').format(picked);
    }
  }

  // Métodos auxiliares
  static dynamic _getCurrentValue(
    FieldConfigWindows config,
    TextEditingController controller,
  ) {
    bool expectInteger = _isIntegerField(config);

    if (controller.text.isNotEmpty) {
      if (expectInteger) {
        return int.tryParse(controller.text);
      } else {
        return controller.text;
      }
    } else {
      return null;
    }
  }

  static bool _isIntegerField(FieldConfigWindows config) {
    return config.dropdownValueField == 'id' ||
        config.fieldName.toLowerCase().contains('id');
  }

  // Validações
  static bool _isValidEmail(String email) {
    final regex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return regex.hasMatch(email);
  }

  static bool _isValidPhone(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');
    return cleaned.length >= 10;
  }

  static bool _isValidCpf(String cpf) {
    final cleaned = cpf.replaceAll(RegExp(r'[^\d]'), '');
    return cleaned.length == 11;
  }

  static bool _isValidCnpj(String cnpj) {
    final cleaned = cnpj.replaceAll(RegExp(r'[^\d]'), '');
    return cleaned.length == 14;
  }

  static Widget _buildCurrencyField(
    FieldConfigWindows config,
    TextEditingController controller,
  ) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: _buildInputDecoration(config).copyWith(
        prefixIcon: const Icon(Icons.attach_money),
      ),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,\.]'))],
      validator: (value) {
        if (config.isRequired && (value == null || value.isEmpty)) {
          return '${config.label} é obrigatório';
        }
        return config.validator?.call(value);
      },
    );
  }

  static Widget _buildPercentageField(
    FieldConfigWindows config,
    TextEditingController controller,
  ) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: _buildInputDecoration(config).copyWith(
        suffixIcon: const Icon(Icons.percent),
      ),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,\.]'))],
      validator: (value) {
        if (config.isRequired && (value == null || value.isEmpty)) {
          return '${config.label} é obrigatório';
        }
        return config.validator?.call(value);
      },
    );
  }

  static Widget _buildUrlField(
    FieldConfigWindows config,
    TextEditingController controller,
  ) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.url,
      decoration: _buildInputDecoration(config).copyWith(
        prefixIcon: const Icon(Icons.link_outlined),
      ),
      validator: (value) {
        if (config.isRequired && (value == null || value.isEmpty)) {
          return '${config.label} é obrigatório';
        }
        return config.validator?.call(value);
      },
    );
  }

  static Widget _buildMultiselectField(
    FieldConfigWindows config,
    TextEditingController controller,
    Map<String, List<Map<String, dynamic>>> dropdownCache,
    BuildContext context,
  ) {
    final cacheKey = '${config.fieldName}_dropdown';
    final cached = dropdownCache[cacheKey];
    return _MultiSelectField(
      config: config,
      controller: controller,
      // Passa opções já carregadas (cache hit) ou null para o widget
      // buscar internamente via dropdownFutureBuilder (cache miss).
      // Nunca cria um novo Future aqui — evita reiniciar a cada rebuild.
      initialOptions: cached,
      dropdownFutureBuilder:
          cached == null ? config.dropdownFutureBuilder : null,
      dropdownOptions: cached == null && config.dropdownFutureBuilder == null
          ? (config.dropdownOptions ?? [])
          : null,
      onOptionsLoaded: (opts) => dropdownCache[cacheKey] = opts,
    );
  }

  static Widget _buildMultiselectContent(
    FieldConfigWindows config,
    TextEditingController controller,
    List<Map<String, dynamic>> options,
    Map<String, List<Map<String, dynamic>>> dropdownCache,
    BuildContext context,
  ) {
    return _MultiSelectField(
      config: config,
      controller: controller,
      initialOptions: options,
    );
  }
}

// ==============================================
// MULTISELECT FIELD (StatefulWidget reativo)
// ==============================================

class _MultiSelectField extends StatefulWidget {
  final FieldConfigWindows config;
  final TextEditingController controller;

  /// Opções já resolvidas (cache hit). Se null, o widget carrega via
  /// [dropdownFutureBuilder] ou usa [dropdownOptions] estático.
  final List<Map<String, dynamic>>? initialOptions;
  final Future<List<Map<String, dynamic>>> Function()? dropdownFutureBuilder;
  final List<Map<String, dynamic>>? dropdownOptions;

  /// Callback para propagar o resultado carregado de volta ao cache externo.
  final void Function(List<Map<String, dynamic>> opts)? onOptionsLoaded;

  const _MultiSelectField({
    required this.config,
    required this.controller,
    this.initialOptions,
    this.dropdownFutureBuilder,
    this.dropdownOptions,
    this.onOptionsLoaded,
  });

  @override
  State<_MultiSelectField> createState() => _MultiSelectFieldState();
}

class _MultiSelectFieldState extends State<_MultiSelectField> {
  late List<String> _selectedValues;
  List<Map<String, dynamic>> _options = [];
  bool _loadingOptions = false;

  String get _valueField => widget.config.dropdownValueField.isNotEmpty
      ? widget.config.dropdownValueField
      : 'value';
  String get _displayField => widget.config.dropdownDisplayField.isNotEmpty
      ? widget.config.dropdownDisplayField
      : 'label';

  @override
  void initState() {
    super.initState();
    _selectedValues = _parseController();
    widget.controller.addListener(_onControllerChanged);
    // Inicia carga de opções UMA ÚNICA VEZ — o Future fica cacheado no estado
    if (widget.initialOptions != null) {
      _options = widget.initialOptions!;
    } else if (widget.dropdownFutureBuilder != null) {
      _loadingOptions = true;
      widget.dropdownFutureBuilder!().then((opts) {
        if (mounted) {
          setState(() {
            _options = opts;
            _loadingOptions = false;
          });
          widget.onOptionsLoaded?.call(opts);
        }
      });
    } else {
      _options = widget.dropdownOptions ?? [];
    }
  }

  @override
  void didUpdateWidget(_MultiSelectField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Se o cache externo foi populado (initialOptions mudou de null para dados),
    // atualiza as opções locais sem nova requisição HTTP.
    if (widget.initialOptions != null && _options.isEmpty && !_loadingOptions) {
      setState(() => _options = widget.initialOptions!);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final parsed = _parseController();
    if (mounted && parsed.join(',') != _selectedValues.join(',')) {
      setState(() => _selectedValues = parsed);
    }
  }

  List<String> _parseController() {
    return widget.controller.text.isNotEmpty
        ? widget.controller.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : [];
  }

  String get _labels {
    return _options
        .where((o) => _selectedValues.contains(o[_valueField]?.toString()))
        .map((o) => o[_displayField]?.toString() ?? '')
        .where((l) => l.isNotEmpty)
        .join(', ');
  }

  Future<void> _openDialog() async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => _MultiSelectGridDialog(
        title: widget.config.label,
        options: _options,
        valueField: _valueField,
        displayField: _displayField,
        initialSelected: List.from(_selectedValues),
      ),
    );
    if (result != null) {
      setState(() => _selectedValues = result);
      widget.controller.text = result.join(', ');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingOptions) {
      return InputDecorator(
        decoration: FieldFactory._buildInputDecoration(widget.config).copyWith(
          suffixIcon: const SizedBox(
              width: 16,
              height: 16,
              child: Padding(
                  padding: EdgeInsets.all(14),
                  child: CircularProgressIndicator(strokeWidth: 2))),
        ),
        child: const Text('Carregando...',
            style: TextStyle(color: Colors.grey, fontSize: 14)),
      );
    }
    final labels = _labels;
    return InkWell(
      onTap: _openDialog,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: FieldFactory._buildInputDecoration(widget.config).copyWith(
          suffixIcon:
              const Icon(Icons.arrow_drop_down, color: GridColors.primary),
        ),
        child: Text(
          labels.isEmpty ? 'Selecione...' : labels,
          style: TextStyle(
            color: labels.isEmpty
                ? Colors.grey.shade500
                : GridColors.textSecondary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

// ==============================================
// MULTISELECT DIALOG (para FieldType.multiselect)
// ==============================================

class _MultiSelectGridDialog extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> options;
  final String valueField;
  final String displayField;
  final List<String> initialSelected;

  const _MultiSelectGridDialog({
    required this.title,
    required this.options,
    required this.valueField,
    required this.displayField,
    required this.initialSelected,
  });

  @override
  State<_MultiSelectGridDialog> createState() => _MultiSelectGridDialogState();
}

class _MultiSelectGridDialogState extends State<_MultiSelectGridDialog> {
  late List<String> _selected;
  late List<Map<String, dynamic>> _filtered;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.initialSelected);
    _filtered = widget.options;
    _ctrl.addListener(() {
      final q = _ctrl.text.toLowerCase();
      setState(() {
        _filtered = q.isEmpty
            ? widget.options
            : widget.options
                .where((o) =>
                    o[widget.displayField]
                        ?.toString()
                        .toLowerCase()
                        .contains(q) ??
                    false)
                .toList();
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool _isSelected(String val) => _selected.contains(val);

  void _toggle(String val) {
    setState(() {
      if (_isSelected(val)) {
        _selected.remove(val);
      } else {
        _selected.add(val);
      }
    });
  }

  void _selectAll() {
    setState(() {
      final allVals = _filtered
          .map((o) => o[widget.valueField]?.toString() ?? '')
          .where((v) => v.isNotEmpty)
          .toList();
      for (final v in allVals) {
        if (!_selected.contains(v)) _selected.add(v);
      }
    });
  }

  void _deselectAll() {
    setState(() {
      final filteredVals =
          _filtered.map((o) => o[widget.valueField]?.toString() ?? '').toSet();
      _selected.removeWhere((v) => filteredVals.contains(v));
    });
  }

  bool get _allFilteredSelected {
    if (_filtered.isEmpty) return false;
    return _filtered
        .every((o) => _isSelected(o[widget.valueField]?.toString() ?? ''));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: GridColors.dialogBackground,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520, maxWidth: 420),
        child: Column(children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: GridColors.primary,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              const Icon(Icons.checklist, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.title,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ),
              Text('${_selected.length} selecionado(s)',
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ]),
          ),
          // Busca
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Buscar...',
                prefixIcon: const Icon(Icons.search, color: GridColors.primary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: GridColors.inputBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: GridColors.primary, width: 1.5),
                ),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              ),
            ),
          ),
          const Divider(height: 1),
          // Barra Selecionar todos / Desmarcar todos
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _allFilteredSelected ? null : _selectAll,
                  icon: const Icon(Icons.select_all, size: 16),
                  label: Text(
                    _ctrl.text.isEmpty
                        ? 'Selecionar todos'
                        : 'Selecionar filtrados',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: GridColors.primary,
                    side: const BorderSide(color: GridColors.primary),
                    padding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _selected.isEmpty ? null : _deselectAll,
                  icon: const Icon(Icons.deselect, size: 16),
                  label: Text(
                    _ctrl.text.isEmpty
                        ? 'Desmarcar todos'
                        : 'Desmarcar filtrados',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: GridColors.textSecondary,
                    padding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: _filtered.length,
              itemBuilder: (ctx, i) {
                final opt = _filtered[i];
                final val = opt[widget.valueField]?.toString() ?? '';
                final label = opt[widget.displayField]?.toString() ?? val;
                final selected = _isSelected(val);
                return CheckboxListTile(
                  title: Text(label, style: const TextStyle(fontSize: 14)),
                  value: selected,
                  activeColor: GridColors.primary,
                  checkColor: Colors.white,
                  onChanged: (_) => _toggle(val),
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                    foregroundColor: GridColors.textSecondary),
                child: const Text('CANCELAR'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, _selected),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GridColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                child: const Text('CONFIRMAR'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ==============================================
// COMPONENTE PRINCIPAL GENERIC GRID SCREEN
// ==============================================

typedef FromJson<T> = T Function(Map<String, dynamic> json);
typedef ToJson<T> = Map<String, dynamic> Function(T item);
typedef SecurityCheck = bool Function(String permission);
typedef OnItemTap<T> = void Function(T item, BuildContext context);
typedef CustomActionBuilder<T> = List<CustomAction<T>> Function();

class GenericGridWindowsScreen<T> extends StatefulWidget {
  static List<Map<String, dynamic>> extractRows(dynamic body) {
    try {
      final parsed = (body is String) ? json.decode(body) : body;
      if (parsed is List) return List<Map<String, dynamic>>.from(parsed);
      if (parsed is Map && parsed.containsKey('data') && parsed['data'] is List) return List<Map<String, dynamic>>.from(parsed['data']);
      if (parsed is Map && parsed.containsKey('content') && parsed['content'] is List) return List<Map<String, dynamic>>.from(parsed['content']);
    } catch (_) {}
    return [];
  }
  final String title;
  final String fetchEndpoint;
  final String createEndpoint;
  final String updateEndpoint;
  final String deleteEndpoint;
  final FromJson<T>? fromJson;
  final ToJson<T>? toJson;
  final SecurityCheck? hasPermission;
  final Map<String, bool> buttonPermissions;
  final List<FieldConfigWindows> fieldConfigs;
  final String idFieldName;
  final String dateFieldName;
  final ExportConfig exportConfig;
  final PaginationConfig paginationConfig;
  final OnItemTap<T>? onItemTap;
  final CustomActionBuilder<T>? customActions;
  final bool enableSearch;
  final bool enableColumnReorder;
  final bool enableColumnResize;
  final Map<String, dynamic>? initialFilters;
  final String storageKey;
  final Widget Function(T item)? detailScreenBuilder;
  /// Quando true, a ação "Editar" do menu de ações abre o mesmo
  /// [detailScreenBuilder] usado por "Visualizar", em vez do popup de
  /// formulário genérico ([_openForm]). Default false para não alterar o
  /// comportamento das telas que já usam o popup.
  /// Ao voltar da tela, o grid é recarregado automaticamente — não é
  /// necessário nenhum callback de salvar na tela de destino, mas ela deve
  /// persistir de fato as alterações antes do usuário navegar de volta.
  final bool editUsesDetailScreen;
  final Map<String, dynamic>? extraParams;
  final Map<String, dynamic>? additionalFormData;
  /// Hook opcional para ajustar o formData final antes do envio (ex.: copiar
  /// um campo do form para outro campo fixo do payload). Aplicado após o
  /// merge de [additionalFormData]. Não afeta telas que não o utilizarem.
  final Map<String, dynamic> Function(Map<String, dynamic> formData)?
      transformFormData;
  final bool showAppBar;
  final List<Widget>? headerActions;
  final String? helpTelaNome;
  final void Function()? onAfterCreate;
  final void Function(Set<String> ids, List<Map<String, dynamic>> selectedData)?
      onSelectedRowsChanged;

  /// Busca dados extras ANTES de abrir o form de edição (item != null) e
  /// mescla no item carregado, no MESMO formato que os campos normais usam
  /// (ex.: multiselect espera List<Map> com 'id'). Útil para campos que não
  /// vêm na resposta padrão da entidade (ex.: módulos vinculados via tabela
  /// M:N separada) — evita hardcoded por nome de campo neste arquivo
  /// genérico; quem usa decide o que buscar.
  final Future<Map<String, dynamic>> Function(T item)? prefetchExtraFields;

  /// Chamado depois de salvar com sucesso (create OU update, diferente de
  /// onAfterCreate que só dispara no create) — recebe o formData enviado e o
  /// item original (null no create). Útil para persistir campos que o
  /// endpoint principal não aceita (ex.: vínculo M:N via outro endpoint).
  final Future<void> Function(Map<String, dynamic> formData, T? item)?
      onAfterSave;

  const GenericGridWindowsScreen({
    super.key,
    required this.title,
    required this.fetchEndpoint,
    required this.createEndpoint,
    required this.updateEndpoint,
    required this.deleteEndpoint,
    this.fromJson,
    this.toJson,
    this.hasPermission,
    required this.fieldConfigs,
    this.idFieldName = 'id',
    this.dateFieldName = 'createdAt',
    this.buttonPermissions = const {
      'create': true,
      'edit': true,
      'delete': true,
      'deleteMultiple': true,
      'export': true,
    },
    this.exportConfig = const ExportConfig(),
    this.paginationConfig = const PaginationConfig(),
    this.onItemTap,
    this.customActions,
    this.enableSearch = true,
    this.enableColumnReorder = false,
    this.enableColumnResize = false,
    this.initialFilters,
    this.storageKey = 'generic_grid_settings',
    this.detailScreenBuilder,
    this.editUsesDetailScreen = false,
    this.extraParams,
    this.additionalFormData,
    this.transformFormData,
    this.showAppBar = true,
    this.headerActions,
    this.helpTelaNome,
    this.onAfterCreate,
    this.onSelectedRowsChanged,
    this.prefetchExtraFields,
    this.onAfterSave,
  });

  @override
  State<GenericGridWindowsScreen<T>> createState() => _GenericGridWindowsScreenState<T>();
}

class _GenericGridWindowsScreenState<T> extends State<GenericGridWindowsScreen<T>> {
  List<T> items = [];
  List<T> filtered = [];
  Set<String> selectedRows = {};
  int rowsPerPage = 25;
  bool filtrosAbertos = false;
  bool isLoading = false;
  bool _isUpdating = false;
  bool _isDeleting = false;
  bool _isExporting = false;

  int _currentPage = 0;
  int _totalItems = 0;

  late PaginatorController _paginatorController;

  final Map<String, TextEditingController> _filterControllers = {};
  final TextEditingController _searchController = TextEditingController();
  final Map<String, List<Map<String, dynamic>>> _dropdownCache = {};
  final Map<String, List<PlatformFile>> _fileCache = {};
  // Para filtros do tipo dropdown: armazena o valor selecionado (para manter
  // consistência no DropdownButton) e o label para exibição nas tags de filtro.
  final Map<String, String?> _filterDropdownValues = {};
  final Map<String, String> _filterDropdownLabels = {};
  final ScrollController _tableScrollController = ScrollController();
  final Set<String> _lockedFilters = {};

  int? sortColumnIndex;
  bool sortAscending = true;
  final Map<String, bool> _columnVisibility = {};
  List<CustomAction<T>> _customActions = [];

  @override
  void initState() {
    super.initState();
    rowsPerPage = widget.paginationConfig.defaultRowsPerPage;
    _paginatorController = PaginatorController();

    for (final config in widget.fieldConfigs) {
      // H12: campos com isInGrid=false nunca ficam visíveis na grid
      _columnVisibility[config.fieldName] =
          config.isInGrid && config.isVisibleByDefault;
    }

    for (final config
        in widget.fieldConfigs.where((c) => c.isFilterable)) {
      _filterControllers[config.fieldName] = TextEditingController();
    }

    // Pré-carrega opções para campos dropdown/boolean filtráveis uma única vez
    for (final config in widget.fieldConfigs.where((c) =>
        c.isFilterable &&
        (c.fieldType == FieldType.dropdown ||
            c.fieldType == FieldType.boolean))) {
      final cacheKey = 'filter_${config.fieldName}';
      // Preferir as opções estáticas SÓ quando realmente existem. FKs do grid
      // dinâmico recebem dropdownOptions=[] (lista vazia, não-nula) e carregam
      // via dropdownFutureBuilder — por isso a lista vazia não pode "ganhar"
      // do futureBuilder, senão o filtro fica só com "Todos".
      final hasStaticOptions =
          config.dropdownOptions != null && config.dropdownOptions!.isNotEmpty;
      if (hasStaticOptions) {
        _dropdownCache[cacheKey] = config.dropdownOptions!;
      } else if (config.dropdownFutureBuilder != null) {
        config.dropdownFutureBuilder!().then((opts) {
          // Fix card #434: defesa contra duplicidade nas opcoes retornadas
          // pelo endpoint (dado duplicado no banco e/ou resposta com
          // registros repetidos) — dedupe por valueField antes de exibir,
          // independente da causa raiz no backend/dados.
          final deduped = <String, Map<String, dynamic>>{};
          for (final opt in opts) {
            final key = opt[config.dropdownValueField]?.toString();
            if (key != null) deduped[key] = opt;
          }
          if (mounted) {
            setState(() => _dropdownCache[cacheKey] = deduped.values.toList());
          }
        });
      } else if (config.dropdownOptions != null) {
        _dropdownCache[cacheKey] = config.dropdownOptions!;
      }
    }

    // Pré-carrega opções para campos dropdown do FORM (não apenas filtros).
    // Evita que o FutureBuilder dentro de _buildDropdownField recrie o Future
    // a cada rebuild do diálogo, causando dropdowns sempre vazios no web.
    for (final config in widget.fieldConfigs.where((c) =>
        c.isInForm &&
        !c.isFilterable &&
        c.fieldType == FieldType.dropdown &&
        c.dropdownFutureBuilderWithParam == null)) {
      final cacheKey = '${config.fieldName}_dropdown';
      if (_dropdownCache.containsKey(cacheKey)) continue;
      final hasStaticOptions =
          config.dropdownOptions != null && config.dropdownOptions!.isNotEmpty;
      if (hasStaticOptions) {
        _dropdownCache[cacheKey] = config.dropdownOptions!;
      } else if (config.dropdownFutureBuilder != null) {
        config.dropdownFutureBuilder!().then((opts) {
          if (mounted) setState(() => _dropdownCache[cacheKey] = opts);
        });
      }
    }

    _loadFilterPreferences().then((_) {
      // filtros iniciais explícitos do chamador têm prioridade sobre o salvo
      if (widget.initialFilters != null) {
        widget.initialFilters!.forEach((key, value) {
          if (_filterControllers.containsKey(key)) {
            _filterControllers[key]!.text = value.toString();
          }
        });
      }
      _applyTenantFilters();
      _loadColumnPreferences().then((_) {
        _loadItems(_currentPage, rowsPerPage);
      });
    });

    if (widget.customActions != null) {
      _customActions = widget.customActions!();
    }
  }

  void _applyTenantFilters() {
    final empresaId = TenantContext.empresaId;
    final parceiroId = null;
    final empresaNome = AuthUtility.userInfo?.login?.empresa?.nome ??
        AuthUtility.userInfo?.login?.empresa?.nome ?? '';
    final parceiroNome = '' ??
        '';

    const empresaKeys = {'empresa', 'empresaId', 'empresa.id', 'empId'};
    const parceiroKeys = {'parceiro', 'parceiroId', 'parceiro.id', 'parcId'};

    for (final config in widget.fieldConfigs.where((c) => c.isFilterable)) {
      final fn = config.fieldName;
      if (empresaId != null && empresaKeys.contains(fn)) {
        _filterControllers[fn]?.text = empresaId.toString();
        _filterDropdownValues[fn] = empresaId.toString();
        _filterDropdownLabels[fn] = empresaNome;
        _lockedFilters.add(fn);
      }
      if (parceiroId != null && parceiroId != 0 && parceiroKeys.contains(fn)) {
        _filterControllers[fn]?.text = parceiroId.toString();
        _filterDropdownValues[fn] = parceiroId.toString();
        _filterDropdownLabels[fn] = parceiroNome;
        _lockedFilters.add(fn);
      }
    }
  }

  Future<void> _loadColumnPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${widget.storageKey}_${widget.title}';

      for (final config in widget.fieldConfigs) {
        final savedValue = prefs.getBool('$key${config.fieldName}');
        if (savedValue != null) {
          _columnVisibility[config.fieldName] = savedValue;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        L.d('Erro ao carregar preferências: $e');
      }
    }
  }

  Future<void> _loadFilterPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${widget.storageKey}_${widget.title}_filter_';

      for (final entry in _filterControllers.entries) {
        final saved = prefs.getString('$key${entry.key}');
        if (saved != null && saved.isNotEmpty) entry.value.text = saved;
      }
    } catch (e) {
      if (kDebugMode) {
        L.d('Erro ao carregar filtros salvos: $e');
      }
    }
  }

  Future<void> _saveFilterPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${widget.storageKey}_${widget.title}_filter_';

      for (final entry in _filterControllers.entries) {
        final prefKey = '$key${entry.key}';
        if (entry.value.text.isEmpty) {
          await prefs.remove(prefKey);
        } else {
          await prefs.setString(prefKey, entry.value.text);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        L.d('Erro ao salvar filtros: $e');
      }
    }
  }

  @override
  void dispose() {
    _tableScrollController.dispose();
    _searchController.dispose();
    for (final c in _filterControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveColumnPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${widget.storageKey}_${widget.title}';

      for (final config in widget.fieldConfigs) {
        await prefs.setBool(
          '$key${config.fieldName}',
          _columnVisibility[config.fieldName] ?? config.isVisibleByDefault,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        L.d('Erro ao salvar preferências: $e');
      }
    }
  }

  String buildUrl(String baseUrl, Map<String, dynamic> params) {
    String url = baseUrl;

    // Verifica se a URL já contém parâmetros
    bool hasExistingParams = url.contains('?');

    // Adiciona os parâmetros à URL
    if (params.isNotEmpty) {
      url += hasExistingParams ? '&' : '?';

      // Converte os parâmetros para query string
      url += params.entries
          .map(
            (entry) =>
                '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value.toString())}',
          )
          .join('&');
    }

    return url;
  }

  Future<void> _downloadFile(int fileId, String fileName) async {
    try {
      final String authToken = '${AuthUtility.userInfo?.token}';

      final response = await http.get(
        Uri.parse(ApiLinks.downloadFile(fileId.toString())),
        headers: {'Authorization': 'Bearer $authToken'},
      );

      if (response.statusCode == 200) {
        await FileSaver.instance.saveFile(
          name: fileName,
          bytes: response.bodyBytes,
          fileExtension: fileName.split('.').last,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Download realizado com sucesso'),
            backgroundColor: GridColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Falha no download: ${response.statusCode}'),
            backgroundColor: GridColors.error,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro no download: $e'),
          backgroundColor: GridColors.error,
        ),
      );
    }
  }

  String construirUrl(String baseUrl, int pagina, int tamanhoPagina) {
    String url = baseUrl;
    bool jaTemParametros = url.contains('?');

    url += jaTemParametros ? '&' : '?';
    url += 'pagina=$pagina&tamanho=$tamanhoPagina';

    return url;
  }

  // No início do initState ou em um método de validação
  void _validatefieldConfigs() {
    for (final config in widget.fieldConfigs) {
      if (config.fieldType == FieldType.file) {
        // Validação silenciosa — sem prints em produção
      }
    }
  }

  dynamic _getDefaultValueForField(String fieldName) {
    // Analisa o nome do campo para determinar o tipo esperado
    final lowerFieldName = fieldName.toLowerCase();

    if (lowerFieldName.contains('id') ||
        lowerFieldName.contains('codigo') ||
        lowerFieldName.contains('numero')) {
      return 0;
    } else if (lowerFieldName.contains('data') ||
        lowerFieldName.contains('date')) {
      return '';
    } else if (lowerFieldName.contains('file') ||
        lowerFieldName.contains('anexo') ||
        lowerFieldName.contains('nome') ||
        lowerFieldName.contains('name')) {
      return ''; // Campos de texto relacionados a arquivo
    } else {
      return '';
    }
  }

  Future<void> _loadItems(int pagina, int tamanhoPagina) async {
    if (isLoading) return; // evita chamadas concorrentes
    setState(() => isLoading = true);

    try {
      String endpoint = construirUrl(
        widget.fetchEndpoint,
        pagina,
        tamanhoPagina,
      );
      String url = endpoint;

      // ── extraParams como query params (filtro por pai, ex: empresa=1) ──
      if (widget.extraParams != null && widget.extraParams!.isNotEmpty) {
        for (final entry in widget.extraParams!.entries) {
          final val = entry.value;
          if (val != null && val.toString().isNotEmpty) {
            url +=
                '&${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(val.toString())}';
          }
        }
      }

      if (sortColumnIndex != null &&
          sortColumnIndex! < widget.fieldConfigs.length &&
          widget.fieldConfigs[sortColumnIndex!].isSortable) {
        final config = widget.fieldConfigs[sortColumnIndex!];
        final direction = sortAscending ? 'ASC' : 'DESC';
        url += '&ordenarPor=${config.fieldName}&direcao=$direction';
      }

      for (final config
          in widget.fieldConfigs.where((c) => c.isFilterable)) {
        final filterValue = _filterControllers[config.fieldName]?.text;
        if (filterValue != null && filterValue.isNotEmpty) {
          url += '&${config.fieldName}=${Uri.encodeComponent(filterValue)}';
        }
      }

      if (_searchController.text.isNotEmpty) {
        url += '&busca=${Uri.encodeComponent(_searchController.text)}';
      }

      final NetworkResponse response = await NetworkCaller().getRequest(url);

      if (response.statusCode == 200 && response.body != null) {
        final responseData = response.body!['data'];
        final List<dynamic> data = responseData is Map
            ? responseData['dados'] ?? []
            : responseData ?? [];

        final processedData = data.map((json) {
          final itemMap = json is Map ? Map<String, dynamic>.from(json) : {};

          for (final config in widget.fieldConfigs.where(
            (c) => c.fieldType == FieldType.file,
          )) {
            final fileField = config.fieldName.split('.')[0];
            if (!itemMap.containsKey(fileField)) {
              itemMap[fileField] = {'id': 0, 'nome': ''};
            }
          }

          return itemMap;
        }).toList();

        setState(() {
          items = processedData.map((json) {
            Map<String, dynamic> jsonMap = Map<String, dynamic>.from(json);
            return widget.fromJson != null ? widget.fromJson!(jsonMap) : (jsonMap as T);
          }).toList();
          filtered = List.from(items);
          _totalItems = responseData is Map
              ? responseData['totalElements'] ?? 0
              : data.length;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Falha ao carregar dados: ${response.statusCode}'),
            backgroundColor: GridColors.error,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar dados: $e'),
          backgroundColor: GridColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _applyFilters() {
    _saveFilterPreferences();
    setState(() {
      _currentPage = 0;
    });
    _loadItems(_currentPage, rowsPerPage);
  }

  void _sort<U>(
    Comparable<U> Function(T c) getField,
    int columnIndex,
    bool asc,
  ) {
    setState(() {
      sortColumnIndex = columnIndex;
      sortAscending = asc;
    });
    _loadItems(_currentPage, rowsPerPage);
  }

  Future<void> _openForm({T? item}) async {
    final controllers = <String, TextEditingController>{};
    final itemMap = item != null
        ? Map<String, dynamic>.from((widget.toJson != null ? widget.toJson!(item) : item as Map<String, dynamic>))
        : <String, dynamic>{};
    final hasParceiroContext = effectiveHasParceiroContext(
      widget.extraParams,
      false,
    );

    // Busca dados extras (ex.: vínculos M:N que não vêm na entidade) ANTES de
    // montar os controllers, mesclando no itemMap no formato que os campos
    // normais já esperam — sem isso o form sempre abriria sem pré-seleção.
    if (item != null && widget.prefetchExtraFields != null) {
      try {
        final extra = await widget.prefetchExtraFields!(item);
        itemMap.addAll(extra);
      } catch (_) {
        // Falha no prefetch não deve bloquear a edição — o campo so fica vazio.
      }
    }
    if (!mounted) return;

    // Campos que devem ser pré-preenchidos e desabilitados (vêm de extraParams)
    // Ex: ao abrir form dentro da aba de empresa, empresa já vem selecionada
    final preFilledFields = <String>{};

    for (final config in widget.fieldConfigs.where((c) => c.isInForm)) {
      if (item == null && config.fieldName == widget.idFieldName) {
        continue;
      }

      String initialValue = '';
      if (item != null) {
        // Para dropdown/multiselect: usar acesso raw (sem _formatValue) para
        // obter o ID numérico, não o label de exibição. _getNestedValue chama
        // _formatValue que converte {'id':1,'nome':'Abraco...'} → "Abraco..."
        // fazendo o controller receber o label e o backend falhar ao parsear.
        final value = (config.fieldType == FieldType.dropdown ||
                config.fieldType == FieldType.multiselect)
            ? _getNestedRawValue(itemMap, config.fieldName)
            : _getNestedValue(itemMap, config.fieldName);
        if (value is Map) {
          initialValue =
              (value[config.dropdownValueField] ?? value['id'])?.toString() ??
                  '';
        } else if (value is List) {
          initialValue = value
              .map((e) {
                if (e is Map) {
                  return (e[config.dropdownValueField] ?? e['id'])
                          ?.toString() ??
                      '';
                }
                return e.toString();
              })
              .where((e) => e.isNotEmpty)
              .join(', ');
        } else {
          initialValue = value?.toString() ?? '';
        }
      } else {
        // INSERT: tenta pré-preencher com extraParams
        if (widget.extraParams != null) {
          final fn = config.fieldName.toLowerCase();
          for (final entry in widget.extraParams!.entries) {
            final key = entry.key.toLowerCase();
            // Match direto (ex: fieldName='empresa', param='empresa')
            // ou match sem sufixo Id (ex: fieldName='empresa', param='empId' → 'emp')
            if (key == fn ||
                key == '${fn}id' ||
                key == 'emp_id' && fn == 'empresa' ||
                key == 'empid' && fn == 'empresa' ||
                key == 'parcid' && fn == 'parceiro') {
              initialValue = entry.value.toString();
              preFilledFields.add(config.fieldName);
              break;
            }
          }
        }
        if (initialValue.isEmpty && config.defaultValue != null) {
          initialValue = config.defaultValue.toString();
        }

        // TAREFA 1: pré-preencher empresa e parceiro a partir do TenantContext
        // quando o campo ainda está vazio (não veio de extraParams nem defaultValue)
        if (initialValue.isEmpty &&
            config.fieldType == FieldType.dropdown &&
            config.dropdownValueField == 'id') {
          final fn = config.fieldName.toLowerCase();
          if ((fn == 'empresa' || fn.contains('empresa')) &&
              TenantContext.hasEmpresa) {
            initialValue = TenantContext.empresaId.toString();
            preFilledFields.add(config.fieldName);
          } else if (shouldPrefillParceiroField(config, hasParceiroContext)) {
            initialValue = null.toString();
            if (isParceiroFieldDisabledByStorage(
              config,
              hasParceiroContext,
            )) {
              preFilledFields.add(config.fieldName);
            }
          }
        }
      }

      controllers[config.fieldName] = TextEditingController(text: initialValue);

      if (config.fieldType == FieldType.password && item == null) {
        controllers['__confirm_${config.fieldName}'] = TextEditingController();
      }
    }

    // Fix (card #458): sem StatefulBuilder, o Dialog retornado por
    // _buildForm() e construido UMA UNICA VEZ quando o showDialog abre --
    // mutar _fileCache (campo da tela por tras do dialog) depois disso nao
    // reconstroi o dialog, entao o arquivo selecionado nunca aparecia na
    // tela mesmo com o picker retornando com sucesso. setDialogState()
    // e passado adiante ate _selectFiles() para forcar o rebuild do
    // dialog especificamente apos a selecao/remocao de arquivo.
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => _buildForm(
          ctx,
          item,
          controllers,
          preFilledFields,
          hasParceiroContext,
          setDialogState,
        ),
      ),
    );
  }

  Widget _buildForm(
    BuildContext context,
    T? item,
    Map<String, TextEditingController> controllers,
    Set<String> preFilledFields,
    bool hasParceiroContext,
    StateSetter setDialogState,
  ) {
    final preFilledFields0 = preFilledFields;

    // Configura callback do CEP para preencher campos de endereço
    FieldFactory._cepResultCallback = (data) {
      // Mapeamento ViaCEP → campos do form
      final mapping = <String, String>{
        'rua': data['logradouro']?.toString() ?? '',
        'bairro': data['bairro']?.toString() ?? '',
        'cidade': data['localidade']?.toString() ?? '',
        'estado': data['uf']?.toString() ?? '',
        'complemento': data['complemento']?.toString() ?? '',
      };
      for (final entry in mapping.entries) {
        if (controllers.containsKey(entry.key) && entry.value.isNotEmpty) {
          controllers[entry.key]!.text = entry.value;
        }
      }
    };

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        decoration: BoxDecoration(
          color: GridColors.dialogBackground,
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: GridColors.divider),
          boxShadow: const [
            BoxShadow(
              color: GridColors.shadow,
              blurRadius: 10.0,
              offset: Offset(0.0, 10.0),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: GridColors.primary,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(6),
                    topRight: Radius.circular(6),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.edit_note,
                        color: GridColors.textPrimary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item == null ? GridTexts.newItem : GridTexts.editItem,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: GridColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close,
                          color: GridColors.textPrimary, size: 18),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints.tightFor(width: 32, height: 32),
                      tooltip: 'Fechar',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              ...widget.fieldConfigs.where((config) {
                if (item == null && config.fieldName == widget.idFieldName) {
                  return false;
                }
                if (!config.isInForm) return false;
                // visibleWhen: só mostra o campo se o campo referenciado tiver o valor esperado
                if (config.visibleWhenField != null) {
                  final depCtrl = controllers[config.visibleWhenField!];
                  if (depCtrl == null) return false;
                  final depValue = depCtrl.text;
                  // Suporta bool (checkbox: 'true'/'false') e string
                  if (config.visibleWhenValue is bool) {
                    return depValue.toLowerCase() ==
                        (config.visibleWhenValue ? 'true' : 'false');
                  }
                  return depValue == config.visibleWhenValue?.toString();
                }
                return true;
              }).expand((config) {
                // Campo id no edit → sempre disabled
                final isIdField =
                    item != null && config.fieldName == widget.idFieldName;
                // Se o campo foi pré-preenchido via extraParams, desabilita
                final isPreFilled = preFilledFields0.contains(config.fieldName);

                // Calcula enabled efetivo considerando enabledOnInsert/enabledOnEdit
                final isEditMode = item != null;
                bool effectiveEnabled;
                if (isPreFilled || isIdField) {
                  effectiveEnabled = false;
                } else if (!isFornecedorFieldEnabledByStorage(
                  config,
                  hasParceiroContext,
                )) {
                  effectiveEnabled = false;
                } else if (!isEditMode && config.enabledOnInsert != null) {
                  effectiveEnabled = config.enabledOnInsert!;
                } else if (isEditMode && config.enabledOnEdit != null) {
                  effectiveEnabled = config.enabledOnEdit!;
                } else {
                  effectiveEnabled = config.enabled;
                }

                final effectiveConfig = effectiveEnabled == config.enabled
                    ? config
                    : FieldConfigWindows(
                        label: config.label,
                        fieldName: config.fieldName,
                        displayFieldName: config.displayFieldName,
                        fieldType: config.fieldType,
                        isInForm: config.isInForm,
                        isFilterable: config.isFilterable,
                        isRequired: config.isRequired,
                        isVisibleByDefault: config.isVisibleByDefault,
                        isFixed: config.isFixed,
                        enabled: effectiveEnabled,
                        dropdownFutureBuilder: config.dropdownFutureBuilder,
                        dropdownFutureBuilderWithParam:
                            config.dropdownFutureBuilderWithParam,
                        dependsOnField: config.dependsOnField,
                        dropdownOptions: config.dropdownOptions,
                        dropdownValueField: config.dropdownValueField,
                        dropdownDisplayField: config.dropdownDisplayField,
                        dropdownSelectedValue: config.dropdownSelectedValue,
                        defaultValue: config.defaultValue,
                        icon: config.icon,
                        flex: config.flex,
                        maxLines: config.maxLines,
                        isSortable: config.isSortable,
                        validator: config.validator,
                        visibleWhenField: config.visibleWhenField,
                        visibleWhenValue: config.visibleWhenValue,
                        enabledOnInsert: config.enabledOnInsert,
                        enabledOnEdit: config.enabledOnEdit,
                      );
                final mainField = Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18)
                      .copyWith(bottom: 12),
                  child: FieldFactory.buildField(
                    config: effectiveConfig,
                    controller: controllers[config.fieldName]!,
                    context: context,
                    fileCache: _fileCache,
                    dropdownCache: _dropdownCache,
                    item: item,
                    allControllers: controllers,
                    onFileChanged: () => setDialogState(() {}),
                  ),
                );

                // Adiciona campo "Confirmar Senha" logo após o campo senha no insert
                if (config.fieldType == FieldType.password &&
                    item == null &&
                    controllers.containsKey('__confirm_${config.fieldName}')) {
                  final confirmConfig = FieldConfigWindows(
                    label: 'Confirmar ${config.label}',
                    fieldName: '__confirm_${config.fieldName}',
                    fieldType: FieldType.password,
                    isRequired: config.isRequired,
                  );
                  return [
                    mainField,
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18)
                          .copyWith(bottom: 12),
                      child: FieldFactory.buildField(
                        config: confirmConfig,
                        controller:
                            controllers['__confirm_${config.fieldName}']!,
                        context: context,
                        fileCache: _fileCache,
                        dropdownCache: _dropdownCache,
                        item: item,
                      ),
                    ),
                  ];
                }

                return [mainField];
              }),
              const SizedBox(height: 10),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: Divider(height: 1, color: GridColors.divider),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: GridColors.textSecondary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    child: const Text("CANCELAR"),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _isUpdating
                        ? null
                        : () => _saveItem(item, controllers, context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GridColors.secondary,
                      foregroundColor: GridColors.card,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    child: _isUpdating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text("SALVAR"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveItem(
    T? item,
    Map<String, TextEditingController> controllers,
    BuildContext context,
  ) async {
    for (final config in widget.fieldConfigs.where(
      (c) => c.isInForm && c.isRequired,
    )) {
      // Não valida o campo ID no insert
      if (item == null && config.fieldName == widget.idFieldName) continue;

      if (controllers[config.fieldName]?.text.isEmpty == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${config.label} é obrigatório'),
            backgroundColor: GridColors.error,
          ),
        );
        return;
      }

      if (config.validator != null) {
        final error = config.validator!(controllers[config.fieldName]?.text);
        if (error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error), backgroundColor: GridColors.error),
          );
          return;
        }
      }
    }

    // Validações específicas por tipo de campo
    for (final config in widget.fieldConfigs.where((c) => c.isInForm)) {
      if (item == null && config.fieldName == widget.idFieldName) continue;
      final value = controllers[config.fieldName]?.text ?? '';

      // Email: validar formato
      if (config.fieldType == FieldType.email && value.isNotEmpty) {
        final emailRegex = RegExp(r'^[\w\.\-\+]+@[\w\-]+(\.[\w\-]+)+$');
        if (!emailRegex.hasMatch(value)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('${config.label}: formato de email inválido'),
                backgroundColor: GridColors.error),
          );
          return;
        }
      }

      // Senha: validar confirmação (só no insert)
      if (config.fieldType == FieldType.password && item == null) {
        final confirmKey = '__confirm_${config.fieldName}';
        final confirmValue = controllers[confirmKey]?.text ?? '';
        if (value != confirmValue) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('${config.label}: as senhas não coincidem'),
                backgroundColor: GridColors.error),
          );
          return;
        }
      }

      // CPF/CNPJ: só dígitos
      if ((config.fieldType == FieldType.cpf ||
              config.fieldType == FieldType.cnpj) &&
          value.isNotEmpty) {
        final onlyDigits = value.replaceAll(RegExp(r'\D'), '');
        if (onlyDigits.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('${config.label}: apenas números são permitidos'),
                backgroundColor: GridColors.error),
          );
          return;
        }
      }
    }

    setState(() => _isUpdating = true);

    final formData = <String, dynamic>{};

    for (final config in widget.fieldConfigs.where(
      (c) => c.fieldType == FieldType.file,
    )) {
      final files = _fileCache[config.fieldName];
      if (files != null && files.isNotEmpty) {
        formData[config.fieldName] = files;
      }
    }

    for (final config in widget.fieldConfigs.where(
      (c) => c.isInForm && c.fieldType != FieldType.file,
    )) {
      if (item == null && config.fieldName == widget.idFieldName) {
        continue;
      }

      final value = controllers[config.fieldName]!.text;

      // Multiselect fields: send as [{id: X}, {id: Y}] list of objects
      if (config.fieldType == FieldType.multiselect) {
        if (value.isNotEmpty) {
          final ids = value
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
          final listVal = ids.map((e) {
            final idVal = int.tryParse(e);
            return idVal != null ? {'id': idVal} : {'id': e};
          }).toList();
          formData[config.fieldName] = listVal;
        } else {
          formData[config.fieldName] = [];
        }
        continue;
      }

      // Dropdown fields: static enums send raw value; FK relations send {id: X} object
      if (config.fieldType == FieldType.dropdown && value.isNotEmpty) {
        // Static dropdown (no backend endpoint) → send raw value (e.g. status integer)
        if (config.dropdownFutureBuilder == null &&
            config.dropdownOptions != null &&
            config.dropdownOptions!.isNotEmpty) {
          if (config.fieldName.contains('.')) {
            final parts = config.fieldName.split('.');
            _setNestedValue(formData, parts, value);
          } else {
            formData[config.fieldName] = value;
          }
        } else if (config.dropdownValueField == 'id') {
          // FK dropdown (dropdownValueField='id') → send as {id: X} object
          final idVal = int.tryParse(value);
          final objVal = idVal != null ? {'id': idVal} : {'id': value};
          if (config.fieldName.contains('.')) {
            final parts = config.fieldName.split('.');
            _setNestedValue(formData, parts, objVal);
          } else {
            formData[config.fieldName] = objVal;
          }
        } else {
          // Enum dropdown (dropdownValueField='value') → send raw integer or string
          final intVal = int.tryParse(value);
          final rawVal = intVal ?? value;
          if (config.fieldName.contains('.')) {
            final parts = config.fieldName.split('.');
            _setNestedValue(formData, parts, rawVal);
          } else {
            formData[config.fieldName] = rawVal;
          }
        }
        continue;
      }

      // Dropdown vazio → não envia (null implícito no backend)
      if (config.fieldType == FieldType.dropdown && value.isEmpty) {
        continue;
      }

      if (config.fieldName.contains('.')) {
        final parts = config.fieldName.split('.');
        _setNestedValue(formData, parts, value);
      } else {
        formData[config.fieldName] = value;
      }
    }

    if (item != null) {
      final itemMap = (widget.toJson != null ? widget.toJson!(item) : item as Map<String, dynamic>);
      formData[widget.idFieldName] = _getNestedValue(
        itemMap,
        widget.idFieldName,
      );
    }

    final success = item == null
        ? await _createItem(formData)
        : await _updateItem(formData);

    if (success) {
      for (final config in widget.fieldConfigs.where(
        (c) => c.fieldType == FieldType.file,
      )) {
        _fileCache.remove(config.fieldName);
      }
      if (item == null && widget.onAfterCreate != null) {
        widget.onAfterCreate!();
      }
      if (widget.onAfterSave != null) {
        try {
          await widget.onAfterSave!(formData, item);
        } catch (_) {
          // Falha aqui não deve impedir o fechamento do form — o save
          // principal já teve sucesso; quem implementa onAfterSave decide
          // como avisar o usuário se precisar (ex.: snackbar próprio).
        }
      }
      if (!mounted) return;
      Navigator.pop(context);
      if (item == null) {
        // Ao criar, vai para primeira página com sort DESC para o novo item aparecer
        _currentPage = 0;
        sortColumnIndex = null;
        sortAscending = false;
      }
      _loadItems(_currentPage, rowsPerPage);
    }

    setState(() => _isUpdating = false);
  }

  /// Preenche, no formData já coletado do form, o valor fixo de payload
  /// (TelaField.defaultValue) de todo campo que ainda não tenha valor —
  /// tipicamente campos ocultos do form (isInForm=false) configurados no
  /// Editor de Telas. Suporta os templates `{{now+Nd}}` e `{{campo:xxx}}`.
  void _applyFieldDefaultValues(Map<String, dynamic> formData) {
    for (final c in widget.fieldConfigs) {
      if (c.defaultValue == null) continue;
      final atual = _getNestedRawValue(formData, c.fieldName);
      if (atual != null && atual.toString().isNotEmpty) continue;
      final resolvido = _resolveFieldDefaultTemplate(c.defaultValue, formData);
      _setNestedValue(formData, c.fieldName.split('.'), resolvido);
    }
  }

  dynamic _resolveFieldDefaultTemplate(
    dynamic value,
    Map<String, dynamic> formData,
  ) {
    if (value is! String) return value;
    final nowMatch = RegExp(r'^\{\{now\+(\d+)d\}\}$').firstMatch(value);
    if (nowMatch != null) {
      final dias = int.parse(nowMatch.group(1)!);
      return DateTime.now().add(Duration(days: dias)).toIso8601String();
    }
    final campoMatch = RegExp(r'^\{\{campo:([\w.]+)\}\}$').firstMatch(value);
    if (campoMatch != null) {
      return _getNestedRawValue(formData, campoMatch.group(1)!);
    }
    return value;
  }

  void _setNestedValue(
    Map<String, dynamic> map,
    List<String> parts,
    dynamic value,
  ) {
    if (parts.isEmpty) return;

    var current = map;
    for (int i = 0; i < parts.length - 1; i++) {
      final part = parts[i];
      if (!current.containsKey(part) ||
          current[part] is! Map<String, dynamic>) {
        current[part] = <String, dynamic>{};
      }
      current = current[part];
    }

    current[parts.last] = value;
  }

  Future<bool> _createItem(Map<String, dynamic> formData) async {
    if (!(widget.hasPermission == null || widget.hasPermission!('create')) ||
        !widget.buttonPermissions['create']!) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sem permissão para criar', style: TextStyle(color: Colors.white)), backgroundColor: GridColors.error));
      return false;
    }

    final Map<String, dynamic> enrichedFormData =
        Map.from(normalizeFormData(formData));

    _applyFieldDefaultValues(enrichedFormData);

    if (widget.additionalFormData != null) {
      enrichedFormData.addAll(widget.additionalFormData!);
    }

    if (widget.transformFormData != null) {
      final transformed =
          widget.transformFormData!(Map<String, dynamic>.from(enrichedFormData));
      enrichedFormData
        ..clear()
        ..addAll(transformed);
    }

    if (widget.extraParams != null) {
      enrichedFormData.addAll(widget.extraParams!);
    }

    final filesToUpload = <String, List<PlatformFile>>{};
    final keysToRemove = <String>[];

    for (final key in enrichedFormData.keys) {
      final value = enrichedFormData[key];
      if (value is List<PlatformFile>) {
        filesToUpload[key] = value;
        keysToRemove.add(key);
      }
    }

    for (final key in keysToRemove) {
      enrichedFormData.remove(key);
    }

    enrichedFormData.updateAll((key, value) {
      if (value is String && value.isNotEmpty) {
        try {
          final parsedDate = DateFormat("dd/MM/yyyy").parseStrict(value);
          return DateFormat("yyyy-MM-dd").format(parsedDate);
        } catch (e) {
          return value;
        }
      }
      return value;
    });

    final fotoFiles = filesToUpload.remove('foto');
    if (fotoFiles != null && fotoFiles.isNotEmpty) {
      final dataUri = await platformFileToDataUri(fotoFiles.first);
      if (dataUri != null) {
        enrichedFormData['foto'] = dataUri;
      }
    }

    if (filesToUpload.isNotEmpty) {
      final fileId = await _uploadFiles("", filesToUpload);
      enrichedFormData["file"] = {"id": fileId};
    }

    final response = await NetworkCaller().postRequest(
      widget.createEndpoint,
      normalizeEntityRelationships(enrichedFormData),
    );

    if (response.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Item criado com sucesso'),
          backgroundColor: GridColors.success,
        ),
      );
      return true;
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mensagemErroBackend(response, 'criar')),
          backgroundColor: GridColors.error,
        ),
      );
      return false;
    }
  }

  /// Extrai a mensagem de erro real retornada pelo backend (campo 'message'
  /// de ExceptionResponse/GlobalException, ex.: validacoes de negocio como
  /// CNPJ/CPF duplicado) em vez de so mostrar o status code, que nao explica
  /// o motivo da falha ao usuario.
  String _mensagemErroBackend(dynamic response, String acao) {
    final msg = response.body?['message'];
    if (msg is String && msg.trim().isNotEmpty) return msg;
    return 'Falha ao $acao item: ${response.statusCode}';
  }

  Future<int> _uploadFiles(
    String? itemId,
    Map<String, List<PlatformFile>> filesToUpload,
  ) async {
    final String authToken = '${AuthUtility.userInfo?.token}';
    if (itemId == null || filesToUpload.isEmpty) return 0;

    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(ApiLinks.uploadFile),
      );

      request.fields['itemId'] = itemId;

      for (final entry in filesToUpload.entries) {
        final String fieldName = entry.key;
        final List<PlatformFile> files = entry.value;

        for (final platformFile in files) {
          Uint8List fileBytes;

          if (platformFile.bytes != null) {
            fileBytes = platformFile.bytes!;
          } else if (platformFile.path != null) {
            File ioFile = File(platformFile.path!);
            fileBytes = await ioFile.readAsBytes();
          } else {
            continue;
          }

          request.files.add(
            http.MultipartFile.fromBytes(
              fieldName,
              fileBytes,
              filename: platformFile.name,
            ),
          );
        }
      }

      // Adicionar headers de autenticação
      if (authToken.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $authToken';
      }

      L.d('Enviando ${filesToUpload.length} arquivo(s) para o item $itemId');

      // Enviar a requisição
      final response = await request.send();

      // Verificar resposta
      if (response.statusCode == 200) {
        final responseBody = await response.stream.bytesToString();
        L.d('Upload realizado com sucesso: $responseBody');
        // Converter JSON para Map
        final decoded = jsonDecode(responseBody);

        // Retornar o fileId se existir
        return decoded['fileId'] ?? 0;
      } else {
        final errorBody = await response.stream.bytesToString();
        L.d('Erro no upload (${response.statusCode}): $errorBody');
      }
    } catch (e) {
      L.d('Exceção durante o upload: $e');
    }
    return 0;
  }

  Map<String, dynamic> normalizeFormData(Map<String, dynamic> formData) {
    final updated = Map<String, dynamic>.from(formData);

    if (updated.containsKey("status")) {
      final status = updated["status"];

      if (status is String) {
        if (status.toLowerCase() == "ativo") {
          updated["status"] = 0;
        } else if (status.toLowerCase() == "inativo") {
          updated["status"] = 1;
        } else {
          updated["status"] = 0;
        }
      } else if (status == null) {
        updated["status"] = 0;
      }
    } else {
      // Only inject status=0 if the entity actually has a status field configured
      final hasStatusField =
          widget.fieldConfigs.any((f) => f.fieldName == "status");
      if (hasStatusField) {
        updated["status"] = 0;
      }
    }

    return updated;
  }

  Future<bool> _updateItem(Map<String, dynamic> formData) async {
    if (!(widget.hasPermission == null || widget.hasPermission!('edit')) || !widget.buttonPermissions['edit']!) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem permissão para editar', style: TextStyle(color: Colors.white)), backgroundColor: GridColors.error),
      );
      return false;
    }
    final adjustedFormData =
        Map<String, dynamic>.from(normalizeFormData(formData));

    _applyFieldDefaultValues(adjustedFormData);

    if (widget.additionalFormData != null) {
      adjustedFormData.addAll(widget.additionalFormData!);
    }

    if (widget.transformFormData != null) {
      final transformed =
          widget.transformFormData!(Map<String, dynamic>.from(adjustedFormData));
      adjustedFormData
        ..clear()
        ..addAll(transformed);
    }

    final filesToUpload = <String, List<PlatformFile>>{};
    final keysToRemove = <String>[];
    for (final entry in adjustedFormData.entries) {
      final value = entry.value;
      if (value is List<PlatformFile>) {
        filesToUpload[entry.key] = value;
        keysToRemove.add(entry.key);
      }
    }
    for (final key in keysToRemove) {
      adjustedFormData.remove(key);
    }

    final fotoFiles = filesToUpload.remove('foto');
    if (fotoFiles != null && fotoFiles.isNotEmpty) {
      final dataUri = await platformFileToDataUri(fotoFiles.first);
      if (dataUri != null) {
        adjustedFormData['foto'] = dataUri;
      }
    }

    if (filesToUpload.isNotEmpty) {
      final fileId = await _uploadFiles(
        adjustedFormData[widget.idFieldName]?.toString(),
        filesToUpload,
      );
      adjustedFormData["file"] = {"id": fileId};
    }

    final response = await NetworkCaller().putRequest(
      widget.updateEndpoint.replaceAll(
        ':id',
        adjustedFormData[widget.idFieldName].toString(),
      ),
      normalizeEntityRelationships(adjustedFormData),
    );

    if (response.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Item atualizado com sucesso'),
          backgroundColor: GridColors.success,
        ),
      );
      return true;
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mensagemErroBackend(response, 'atualizar')),
          backgroundColor: GridColors.error,
        ),
      );
      return false;
    }
  }

  Future<void> _deleteItem(String id) async {
    if (!(widget.hasPermission == null || widget.hasPermission!('delete')) ||
        !widget.buttonPermissions['delete']!) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem permissão para excluir', style: TextStyle(color: Colors.white)), backgroundColor: GridColors.error),
      );
      return;
    }

    setState(() => _isDeleting = true);

    final response = await NetworkCaller().deleteRequest(
      widget.deleteEndpoint.replaceAll(':id', id),
    );

    setState(() => _isDeleting = false);

    if (response.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Item excluído com sucesso'),
          backgroundColor: GridColors.success,
        ),
      );
      _loadItems(_currentPage, rowsPerPage);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao excluir item: ${response.statusCode}'),
          backgroundColor: GridColors.error,
        ),
      );
    }
  }

  void _deleteSelected() {
    if (!(widget.hasPermission == null || widget.hasPermission!('deleteMultiple')) ||
        !widget.buttonPermissions['deleteMultiple']!) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sem permissão para excluir múltiplos itens', style: TextStyle(color: Colors.white)),
          backgroundColor: GridColors.error,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(GridTexts.confirmDelete),
        content: Text(
          'Deseja excluir ${selectedRows.length} item(s) selecionado(s)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(GridTexts.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              for (final id in selectedRows) {
                await _deleteItem(id);
              }
              setState(() => selectedRows.clear());
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: GridColors.error, foregroundColor: Colors.white),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportToCsv() async {
    if (!(widget.hasPermission == null || widget.hasPermission!('export')) ||
        !widget.buttonPermissions['export']!) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem permissão para exportar', style: TextStyle(color: Colors.white)), backgroundColor: GridColors.error),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final csvData = StringBuffer();

      final visibleFields = widget.fieldConfigs.where(
        (config) => _columnVisibility[config.fieldName] == true,
      );
      csvData.write(visibleFields.map((config) => config.label).join(','));
      csvData.write(',Data\n');

      for (final item in filtered) {
        final itemMap = (widget.toJson != null ? widget.toJson!(item) : item as Map<String, dynamic>);
        final row = visibleFields.map((config) {
          final value = _getNestedValue(
                itemMap,
                config.displayFieldName ?? config.fieldName,
              )?.toString() ??
              '';
          return value.contains(',') ? '"$value"' : value;
        }).join(',');

        final dateValue = _getNestedValue(itemMap, widget.dateFieldName);
        String date = 'N/A';
        if (dateValue != null) {
          try {
            final dateString = dateValue.toString();
            final dateTime = DateTime.parse(dateString).toLocal();
            date = DateFormat('dd/MM/yyyy HH:mm').format(dateTime);
          } catch (e) {
            date = 'Data inválida';
          }
        }

        csvData.write('$row,$date\n');
      }

      if (kDebugMode) {
        L.d(csvData.toString());
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dados exportados com sucesso'),
          backgroundColor: GridColors.success,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao exportar: $e'),
          backgroundColor: GridColors.error,
        ),
      );
    } finally {
      setState(() => _isExporting = false);
    }
  }

  Widget _buildLoadingOverlay() {
    final showBlockingOverlay = _isUpdating || _isDeleting || _isExporting;
    if (showBlockingOverlay) {
      return AnimatedOpacity(
        opacity: showBlockingOverlay ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          color: Colors.black.withValues(alpha: 0.35),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
              decoration: BoxDecoration(
                color: GridColors.primary,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    strokeWidth: 3,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Aguarde',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  static const int _maxAdvancedFilters = 16;

  String _normalizeFilterKey(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  bool _isTechnicalFilter(FieldConfigWindows config) {
    // Override explícito de dropdown/boolean com isFilterable=true NUNCA é técnico.
    // O desenvolvedor configurou esse campo intencionalmente como filtro visível.
    if (config.fieldType == FieldType.dropdown ||
        config.fieldType == FieldType.boolean) {
      return false;
    }

    final keys = [
      _normalizeFilterKey(config.fieldName),
      _normalizeFilterKey(config.label),
    ];

    if (config.fieldType == FieldType.file) return true;

    const hiddenKeys = {
      'id',
      'dhcreatedat',
      'dhupdatedat',
      'createdat',
      'updatedat',
      'created',
      'updated',
      'fileattachment',
      'fileattachmentid',
      'fileattachm',
      'anexo',
      'arquivo',
      'auditoria',
      'audit',
      'empresa',
      'empresaid',
      'clienteid',
      'tenantid',
      'aplicativo',
      'aplicativoid',
      'parceiros',
    };

    return keys.any((key) =>
        hiddenKeys.contains(key) ||
        key.contains('createdat') ||
        key.contains('updatedat') ||
        key.contains('fileattachment') ||
        key.contains('fileattachm'));
  }

  List<FieldConfigWindows> get _visibleFilterConfigs {
    final all = widget.fieldConfigs.where(
        (c) => c.isFilterable && !_isTechnicalFilter(c)).toList();
    // Prioriza campos dropdown/boolean (empresa, parceiro, status, etc.)
    // para aparecerem ANTES dos campos texto livres — evita que sejam
    // cortados pelo limite quando há muitos filtros de texto.
    all.sort((a, b) {
      final aIsDropdown =
          a.fieldType == FieldType.dropdown || a.fieldType == FieldType.boolean;
      final bIsDropdown =
          b.fieldType == FieldType.dropdown || b.fieldType == FieldType.boolean;
      if (aIsDropdown == bIsDropdown) return 0;
      return aIsDropdown ? -1 : 1; // dropdowns primeiro
    });
    return all.take(_maxAdvancedFilters).toList();
  }

  bool get _hasActiveFilterValues {
    if (_searchController.text.isNotEmpty) return true;
    return _visibleFilterConfigs.any(
      (config) => (_filterControllers[config.fieldName]?.text ?? '').isNotEmpty,
    );
  }

  void _clearVisibleFilters() {
    _searchController.clear();
    for (final config in _visibleFilterConfigs) {
      _filterControllers[config.fieldName]?.clear();
      _filterDropdownValues.remove(config.fieldName);
      _filterDropdownLabels.remove(config.fieldName);
    }
    _applyFilters();
  }

  Widget _buildFilters() {
    final advancedFilters = _visibleFilterConfigs;

    return Container(
      decoration: BoxDecoration(
        color: GridColors.filterBackground,
        border: Border.all(color: GridColors.divider),
        borderRadius: BorderRadius.circular(6),
      ),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Filtros',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const Spacer(),
                  if (_hasActiveFilterValues)
                    TextButton.icon(
                      onPressed: _clearVisibleFilters,
                      icon: const Icon(Icons.clear_all, size: 18),
                      label: const Text('Limpar'),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Fechar filtros',
                    onPressed: () => setState(() => filtrosAbertos = false),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (widget.enableSearch) ...[
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar em todos os campos',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _applyFilters();
                            },
                          )
                        : null,
                    isDense: true,
                    filled: true,
                    fillColor: GridColors.card,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: GridColors.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: GridColors.divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: GridColors.primary),
                    ),
                  ),
                  onChanged: (_) => _applyFilters(),
                ),
                const SizedBox(height: 14),
              ],
              if (advancedFilters.isNotEmpty) ...[
                const Text(
                  'Filtros principais',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final maxWidth = constraints.maxWidth;
                    final columns = maxWidth >= 1180
                        ? 4
                        : maxWidth >= 840
                            ? 3
                            : maxWidth >= 560
                                ? 2
                                : 1;
                    final calculatedWidth =
                        (maxWidth - ((columns - 1) * 12)) / columns;
                    final minWidth = maxWidth < 220 ? maxWidth : 220.0;
                    final fieldWidth =
                        calculatedWidth.clamp(minWidth, 340.0).toDouble();

                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final config in advancedFilters)
                          SizedBox(
                            width: fieldWidth,
                            child: _buildFilterWidget(config),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FILTRO: widget dispatch por tipo de campo
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFilterWidget(FieldConfigWindows config) {
    if (config.fieldType == FieldType.dropdown ||
        config.fieldType == FieldType.boolean) {
      return _buildFilterDropdown(config);
    }
    // Default: TextField de busca livre
    return TextField(
      controller: _filterControllers[config.fieldName],
      decoration: InputDecoration(
        labelText: config.label,
        hintText: 'Filtrar',
        prefixIcon: Icon(config.icon ?? Icons.search, size: 18),
        isDense: true,
        filled: true,
        fillColor: GridColors.card,
        suffixIcon:
            (_filterControllers[config.fieldName]?.text.isNotEmpty ?? false)
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      _filterControllers[config.fieldName]?.clear();
                      _applyFilters();
                    },
                  )
                : null,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: GridColors.divider)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: GridColors.divider)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: GridColors.primary)),
      ),
      onChanged: (_) {
        setState(() {});
        _applyFilters();
      },
    );
  }

  /// Dropdown de filtro com busca digitável (tipo [FieldType.dropdown]).
  /// Boolean mantém DropdownButton simples (só 2 opções).
  /// Dropdown abre diálogo com campo de busca, igual ao _MultiSelectField nos forms.
  Widget _buildFilterDropdown(FieldConfigWindows config) {
    final cacheKey = 'filter_${config.fieldName}';

    // ── boolean: DropdownButton simples com Sim/Não ───────────────────────────
    if (config.fieldType == FieldType.boolean) {
      const boolOptions = [
        {'value': 'true', 'label': 'Sim'},
        {'value': 'false', 'label': 'Não'},
      ];
      final currentValue = _filterControllers[config.fieldName]?.text;
      final hasValue = currentValue != null && currentValue.isNotEmpty;
      final validValue =
          hasValue && boolOptions.any((o) => o['value'] == currentValue)
              ? currentValue
              : null;
      return InputDecorator(
        decoration: InputDecoration(
          labelText: config.label,
          prefixIcon: Icon(config.icon ?? Icons.filter_alt_outlined, size: 18),
          isDense: true,
          filled: true,
          fillColor: GridColors.card,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: GridColors.divider)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: GridColors.divider)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: GridColors.primary)),
          suffixIcon: hasValue
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () {
                    setState(() {
                      _filterControllers[config.fieldName]?.clear();
                      _filterDropdownValues.remove(config.fieldName);
                      _filterDropdownLabels.remove(config.fieldName);
                    });
                    _applyFilters();
                  },
                )
              : null,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: validValue,
            isDense: true,
            isExpanded: true,
            hint: Text('Todos',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
            items: [
              DropdownMenuItem<String>(
                  value: '',
                  child: Text('Todos',
                      style: TextStyle(
                          fontSize: 14, color: Colors.grey.shade600))),
              ...boolOptions.map((opt) => DropdownMenuItem<String>(
                    value: opt['value']!,
                    child: Text(opt['label']!,
                        style: const TextStyle(fontSize: 14)),
                  )),
            ],
            onChanged: (val) {
              setState(() {
                if (val == null || val.isEmpty) {
                  _filterControllers[config.fieldName]?.clear();
                  _filterDropdownValues.remove(config.fieldName);
                  _filterDropdownLabels.remove(config.fieldName);
                } else {
                  _filterControllers[config.fieldName]!.text = val;
                  _filterDropdownValues[config.fieldName] = val;
                  _filterDropdownLabels[config.fieldName] =
                      boolOptions.firstWhere((o) => o['value'] == val,
                              orElse: () => {})['label'] ??
                          val;
                }
              });
              _applyFilters();
            },
          ),
        ),
      );
    }

    // ── dropdown: campo clicável que abre diálogo com busca ──────────────────
    final cached = _dropdownCache[cacheKey];
    if (cached == null) {
      // Ainda carregando — mostra progress
      return InputDecorator(
        decoration: InputDecoration(
          labelText: config.label,
          prefixIcon: Icon(config.icon ?? Icons.filter_alt_outlined, size: 18),
          isDense: true,
          filled: true,
          fillColor: GridColors.card,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: GridColors.divider)),
        ),
        child: const SizedBox(
            height: 18, child: LinearProgressIndicator(minHeight: 2)),
      );
    }

    final options = cached;
    final vf = config.dropdownValueField.isNotEmpty
        ? config.dropdownValueField
        : 'value';
    final df = config.dropdownDisplayField.isNotEmpty
        ? config.dropdownDisplayField
        : 'label';
    final currentLabel = _filterDropdownLabels[config.fieldName] ?? '';
    final hasValue = currentLabel.isNotEmpty;

    void clearFilter() {
      setState(() {
        _filterControllers[config.fieldName]?.clear();
        _filterDropdownValues.remove(config.fieldName);
        _filterDropdownLabels.remove(config.fieldName);
      });
      _applyFilters();
    }

    final isLocked = _lockedFilters.contains(config.fieldName);

    return GestureDetector(
      onTap: isLocked ? null : () async {
        final result = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (_) => _FilterSearchDialog(options: options, vf: vf, df: df),
        );
        if (result == null) return; // cancelado
        final val = result[vf]?.toString() ?? '';
        setState(() {
          if (val.isEmpty) {
            _filterControllers[config.fieldName]?.clear();
            _filterDropdownValues.remove(config.fieldName);
            _filterDropdownLabels.remove(config.fieldName);
          } else {
            _filterControllers[config.fieldName]!.text = val;
            _filterDropdownValues[config.fieldName] = val;
            _filterDropdownLabels[config.fieldName] =
                result[df]?.toString() ?? val;
          }
        });
        _applyFilters();
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: config.label,
          prefixIcon: Icon(config.icon ?? Icons.filter_alt_outlined, size: 18),
          isDense: true,
          filled: true,
          fillColor: GridColors.card,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: GridColors.divider)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: GridColors.divider)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: GridColors.primary)),
          suffixIcon: hasValue && !isLocked
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: clearFilter,
                )
              : isLocked
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.lock_outline,
                          size: 16, color: Colors.grey),
                    )
                  : const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.search,
                          size: 18, color: GridColors.inputBorder),
                    ),
        ),
        child: Text(
          hasValue ? currentLabel : 'Todos',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            color: isLocked ? Colors.grey.shade600 : (hasValue ? null : Colors.grey.shade500),
          ),
        ),
      ),
    );
  }

  /// Para filtros dropdown, exibe o label (nome) em vez do valor bruto (ID).
  String _getFilterDisplayValue(FieldConfigWindows config, String value) {
    if (config.fieldType == FieldType.dropdown ||
        config.fieldType == FieldType.boolean) {
      return _filterDropdownLabels[config.fieldName] ?? value;
    }
    return value;
  }

  Widget _buildActiveFilterTags() {
    final tags = <Widget>[];
    if (_searchController.text.isNotEmpty) {
      tags.add(_filterTag('Busca', _searchController.text, () {
        _searchController.clear();
        _applyFilters();
      }));
    }
    for (final config in _visibleFilterConfigs) {
      final v = _filterControllers[config.fieldName]?.text ?? '';
      if (v.isNotEmpty) {
        final displayValue = _getFilterDisplayValue(config, v);
        tags.add(_filterTag(config.label, displayValue, () {
          _filterControllers[config.fieldName]?.clear();
          _filterDropdownValues.remove(config.fieldName);
          _filterDropdownLabels.remove(config.fieldName);
          setState(() {});
          _applyFilters();
        }));
      }
    }
    if (tags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(spacing: 6, runSpacing: 4, children: tags),
    );
  }

  Widget _filterTag(String label, String value, VoidCallback onRemove) {
    return Chip(
      label: Text('$label: $value',
          style: const TextStyle(color: Colors.white, fontSize: 11)),
      deleteIcon: const Icon(Icons.close, size: 14, color: Colors.white),
      onDeleted: onRemove,
      backgroundColor: GridColors.primary,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Future<void> _showGridHelpDialog() async {
    final telaNome = widget.helpTelaNome ?? widget.title;
    TelaAjudaModel? ajuda;
    try {
      ajuda = await TelaAjudaService().buscarPorTela(telaNome);
    } catch (e) {
      L.e('Erro ao buscar ajuda da tela "$telaNome": $e');
    }

    if (!mounted) return;
    if (ajuda != null) {
      _showConfiguredHelpDialog(ajuda);
      return;
    }

    final visibleFields = widget.fieldConfigs.where((c) =>
            c.isVisibleByDefault &&
            c.label.trim().isNotEmpty &&
            !c.label.startsWith('_'))
        .map((c) => c.label.trim())
        .toSet()
        .take(10)
        .toList();
    final actions = <String>[
      'Consultar e acompanhar registros de ${widget.title}.',
      if (widget.enableSearch) 'Pesquisar registros pelo campo de busca.',
      if (widget.fieldConfigs.any((c) => c.isFilterable))
        'Usar filtros para refinar a lista.',
      if ((widget.hasPermission == null || widget.hasPermission!('create')) &&
          widget.buttonPermissions['create'] == true)
        'Criar novos registros pelo botao Novo.',
      if ((widget.hasPermission == null || widget.hasPermission!('edit')) &&
          widget.buttonPermissions['edit'] == true)
        'Editar registros existentes pelas acoes da linha.',
      if ((widget.hasPermission == null || widget.hasPermission!('delete')) &&
          widget.buttonPermissions['delete'] == true)
        'Excluir registros quando necessario.',
      if (widget.exportConfig.enableCsvExport &&
          (widget.hasPermission == null || widget.hasPermission!('export')) &&
          widget.buttonPermissions['export'] == true)
        'Exportar os dados visiveis para CSV.',
    ];

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.help_outline, color: GridColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text('Ajuda - ${widget.title}')),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _helpBlock('Para que serve', [_purposeForTitle()]),
                const SizedBox(height: 14),
                _helpBlock('O que voce pode fazer', actions),
                if (visibleFields.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _helpBlock('Principais informacoes', visibleFields),
                ],
                const SizedBox(height: 14),
                _helpBlock('Dicas rapidas', [
                  'Use Configurar colunas para mostrar ou ocultar campos.',
                  'Clique em Recarregar para buscar os dados mais recentes.',
                  'As informacoes respeitam o tenant, empresa e parceiro do usuario logado quando a tela usa esse contexto.',
                ]),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _showConfiguredHelpDialog(TelaAjudaModel ajuda) {
    final sections = <MapEntry<String, String?>>[
      MapEntry('Para que serve', ajuda.resumo),
      MapEntry('Como usar', ajuda.comoUsar),
      MapEntry('Campos importantes', ajuda.camposImportantes),
      MapEntry('Observacoes', ajuda.observacoes),
    ].where((entry) => entry.value?.trim().isNotEmpty == true).toList();

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.help_outline, color: GridColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ajuda.titulo.trim().isEmpty
                    ? 'Ajuda - ${widget.title}'
                    : ajuda.titulo,
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: sections.isEmpty
                  ? [
                      _helpBlock('Para que serve', [_purposeForTitle()])
                    ]
                  : sections
                      .expand(
                        (section) => [
                          _helpBlock(
                              section.key, _splitHelpText(section.value!)),
                          const SizedBox(height: 14),
                        ],
                      )
                      .toList()
                ..removeLast(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  List<String> _splitHelpText(String value) {
    final lines = value
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return lines.isEmpty ? [value.trim()] : lines;
  }

  String _purposeForTitle() {
    final title = widget.title.trim();
    final value = title.toLowerCase();
    if (value.contains('conta') && value.contains('pagar')) {
      return 'Controlar compromissos financeiros a pagar, vencimentos, baixas e acompanhamento do caixa.';
    }
    if (value.contains('conta') && value.contains('receber')) {
      return 'Controlar valores a receber, cobrancas, vencimentos, baixas e acompanhamento de clientes.';
    }
    if (value.contains('obrig')) {
      return 'Organizar obrigacoes fiscais, responsaveis, prazos, geracao de chamados e acompanhamento de envio.';
    }
    if (value.contains('parceiro') || value.contains('cliente')) {
      return 'Gerenciar clientes, parceiros e seus dados cadastrais usados nos fluxos do sistema.';
    }
    if (value.contains('empresa')) {
      return 'Gerenciar empresas e dados cadastrais usados por financeiro, fiscal, GED e demais modulos.';
    }
    if (value.contains('produto')) {
      return 'Gerenciar produtos, cadastros comerciais e informacoes usadas em vendas e documentos fiscais.';
    }
    if (value.contains('chamado') || value.contains('ticket')) {
      return 'Acompanhar solicitacoes, atendimentos, responsaveis, status e historico operacional.';
    }
    if (value.contains('nfe') || value.contains('nota')) {
      return 'Acompanhar documentos fiscais, emissao, entrada, saida, status e dados relacionados.';
    }
    return 'Consultar, cadastrar e manter os registros de $title dentro do fluxo operacional do sistema.';
  }

  Widget _helpBlock(String title, List<String> lines) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: GridColors.textSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        ...lines.map(
          (line) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('- '),
                Expanded(child: Text(line)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGridToolbar() {
    Widget buildRefreshButton() {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: GridColors.card,
          border: Border.all(color: GridColors.divider),
          borderRadius: BorderRadius.circular(6),
        ),
        child: IconButton(
          onPressed: () => _loadItems(_currentPage, rowsPerPage),
          icon: const Icon(Icons.refresh, size: 20),
          tooltip: 'Recarregar',
          color: GridColors.textSecondary,
          padding: EdgeInsets.zero,
        ),
      );
    }

    Widget buildPrimaryActions() {
      return Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          if ((widget.hasPermission == null || widget.hasPermission!('create')) &&
              widget.buttonPermissions['create']!)
            ElevatedButton.icon(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Novo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: GridColors.primary,
                foregroundColor: GridColors.card,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          if ((widget.hasPermission == null || widget.hasPermission!('deleteMultiple')) &&
              widget.buttonPermissions['deleteMultiple']!)
            OutlinedButton.icon(
              onPressed: selectedRows.isNotEmpty ? _deleteSelected : null,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(
                selectedRows.isEmpty
                    ? 'Excluir selecionados'
                    : 'Excluir (${selectedRows.length})',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: GridColors.error,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                side: const BorderSide(color: GridColors.divider),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ...?widget.headerActions,
        ],
      );
    }

    Widget buildUtilityActions() {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: _showGridHelpDialog,
            icon: const Icon(Icons.help_outline, size: 18),
            label: const Text('Ajuda'),
            style: OutlinedButton.styleFrom(
              foregroundColor: GridColors.secondary,
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              side: const BorderSide(color: GridColors.divider),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          buildRefreshButton(),
          OutlinedButton.icon(
            onPressed: () => setState(
              () => filtrosAbertos = !filtrosAbertos,
            ),
            icon: Icon(
              filtrosAbertos ? Icons.expand_less : Icons.tune,
              size: 18,
            ),
            label: Text(filtrosAbertos ? 'Ocultar filtros' : 'Filtros'),
            style: OutlinedButton.styleFrom(
              foregroundColor: GridColors.primary,
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              side: const BorderSide(color: GridColors.divider),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: GridColors.card,
        border: Border.all(color: GridColors.divider),
        borderRadius: BorderRadius.circular(6),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 720) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildPrimaryActions(),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: buildUtilityActions(),
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: buildPrimaryActions()),
              buildUtilityActions(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildColumnSettingsMenu() {
    return PopupMenuButton(
      icon: const Icon(Icons.settings),
      tooltip: 'Configurar colunas',
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'settings',
          child: Text('Configurar colunas visíveis'),
        ),
      ],
      onSelected: (value) {
        if (value == 'settings') {
          _showColumnSettingsDialog();
        }
      },
    );
  }

  void _showColumnSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Colunas visíveis'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: widget.fieldConfigs.map((config) {
                  return CheckboxListTile(
                    title: Text(config.label),
                    value: _columnVisibility[config.fieldName] ??
                        config.isVisibleByDefault,
                    onChanged: config.isFixed
                        ? null
                        : (value) {
                            setState(() {
                              _columnVisibility[config.fieldName] =
                                  value ?? false;
                            });
                          },
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(GridTexts.cancel),
              ),
              ElevatedButton(
                onPressed: () async {
                  await _saveColumnPreferences();
                  setState(() {});
                  Navigator.pop(ctx);
                  _applyFilters();
                },
                child: const Text('Aplicar'),
              ),
            ],
          );
        },
      ),
    );
  }

  List<DataColumn> _buildColumns() {
    final columns = <DataColumn>[];

    for (final config in widget.fieldConfigs.where(
      (c) => c.isInGrid && _columnVisibility[c.fieldName] == true,
    )) {
      columns.add(
        DataColumn(
          label: Text(config.label),
          onSort: config.isSortable
              ? (columnIndex, ascending) {
                  _sort<dynamic>(
                    (c) {
                      final value = _getNestedValue(
                        (widget.toJson != null ? widget.toJson!(c) : c as Map<String, dynamic>),
                        config.displayFieldName ?? config.fieldName,
                      );
                      return value is Comparable ? value : value.toString();
                    },
                    widget.fieldConfigs.indexOf(config),
                    ascending,
                  );
                }
              : null,
        ),
      );
    }

    columns.add(const DataColumn2(label: Text("Ações"), fixedWidth: 48));

    return columns;
  }

  Map<String, dynamic> _extractFileData(
    Map<String, dynamic> itemMap,
    FieldConfigWindows config,
  ) {
    try {
      final fileData =
          _getNestedValue(itemMap, config.fieldName.split('.')[0]) ?? {};

      if (fileData is Map) {
        return {
          'id': _getNestedValue(fileData, 'id') ?? 0,
          'nome': _getNestedValue(fileData, 'nome') ?? '',
          'fileName': _getNestedValue(fileData, 'fileName') ?? '',
          'fileType': _getNestedValue(fileData, 'fileType') ?? '',
        };
      }

      return {
        'id': _getObjectProperty(fileData, 'id') ?? 0,
        'nome': _getObjectProperty(fileData, 'nome') ??
            _getObjectProperty(fileData, 'fileName') ??
            '',
        'fileName': _getObjectProperty(fileData, 'fileName') ??
            _getObjectProperty(fileData, 'nome') ??
            '',
        'fileType': _getObjectProperty(fileData, 'fileType') ?? '',
      };
    } catch (e) {
      return {'id': 0, 'nome': '', 'fileName': '', 'fileType': ''};
    }
  }

  List<DataCell> _buildCells(T item, int index) {
    final itemMap = (widget.toJson != null ? widget.toJson!(item) : item as Map<String, dynamic>);
    final cells = <DataCell>[];

    for (final config in widget.fieldConfigs.where(
      (c) => c.isInGrid && _columnVisibility[c.fieldName] == true,
    )) {
      if (config.fieldType == FieldType.file) {
        final fileData = _extractFileData(itemMap, config);

        final int fileId = fileData['id'] is int
            ? fileData['id']
            : (fileData['id'] != null
                ? int.tryParse(fileData['id'].toString()) ?? 0
                : 0);

        final String fileName = fileData['nome']?.toString().isNotEmpty == true
            ? fileData['nome'].toString()
            : fileData['fileName']?.toString().isNotEmpty == true
                ? fileData['fileName'].toString()
                : _getNestedValue(
                      itemMap,
                      config.displayFieldName ?? 'file.nome',
                    )?.toString() ??
                    '';

        cells.add(
          DataCell(
            fileId > 0 && fileName.isNotEmpty
                ? InkWell(
                    onTap: () => _downloadFile(fileId, fileName),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.attach_file,
                          size: 16,
                          color: GridColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            fileName,
                            style: const TextStyle(
                              color: GridColors.primary,
                              decoration: TextDecoration.underline,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )
                : Text(
                    'Nenhum arquivo',
                    style: TextStyle(
                      color: GridColors.textSecondary.withValues(alpha: 0.5),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
          ),
        );
      } else {
        dynamic displayValue = _getNestedValue(
          itemMap,
          config.displayFieldName ?? config.fieldName,
        );

        // Resolve dropdown values to display labels (e.g. 0 -> "Ativo")
        if (displayValue != null &&
            config.fieldType == FieldType.dropdown &&
            config.dropdownOptions != null &&
            config.dropdownOptions!.isNotEmpty) {
          for (final option in config.dropdownOptions!) {
            final optionValue = option[config.dropdownValueField]?.toString();
            if (optionValue == displayValue.toString()) {
              displayValue = option[config.dropdownDisplayField];
              break;
            }
          }
        }

        // CARD #492: Quando dropdown usa dropdownFutureBuilder (dinamico),
        // displayValue pode ser um Map (ex: {id: 1, nome: "Acme"}).
        // Extrair a propriedade correta neste caso com validação defensiva.
        if (displayValue is Map &&
            config.fieldType == FieldType.dropdown &&
            config.dropdownDisplayField.isNotEmpty) {
          // CR-02: Verificar se chave existe antes de acessar
          final displayField = displayValue.containsKey(config.dropdownDisplayField)
              ? displayValue[config.dropdownDisplayField]
              : null;
          if (displayField != null) {
            displayValue = displayField;
          } else if (displayValue.containsKey('nome') && displayValue['nome'] != null) {
            displayValue = displayValue['nome'];
          } else if (displayValue.containsKey('name') && displayValue['name'] != null) {
            displayValue = displayValue['name'];
          } else if (displayValue.containsKey('label') && displayValue['label'] != null) {
            displayValue = displayValue['label'];
          } else {
            // CR-01: Log warning se nenhum field de display foi encontrado
            L.w('No display field found for dropdown. Map keys: ${displayValue.keys.join(", ")}');
            // Fallback seguro: se houver id, converter para string; senão usar placeholder
            displayValue = displayValue.containsKey('id') && displayValue['id'] != null
                ? displayValue['id'].toString()
                : '---';
          }
        }

        // Renderiza listas (ex: roles) como chips coloridos
        if (displayValue is List && displayValue.isNotEmpty) {
          final chips = displayValue.map((e) {
            String label = '';
            if (e is Map) {
              label = (e['description'] ??
                          e['nome'] ??
                          e['name'] ??
                          e['label'] ??
                          e['key'] ??
                          e['id'])
                      ?.toString() ??
                  '';
            } else {
              label = e.toString();
            }
            return Container(
              margin: const EdgeInsets.only(right: 3, bottom: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: GridColors.success,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }).toList();

          cells.add(DataCell(
            Tooltip(
              message: displayValue.map((e) {
                if (e is Map)
                  return (e['description'] ?? e['nome'] ?? e['name'] ?? e['id'])
                          ?.toString() ??
                      '';
                return e.toString();
              }).join(', '),
              child: Wrap(
                spacing: 2,
                runSpacing: 2,
                children: chips,
              ),
            ),
            onTap: widget.onItemTap != null
                ? () => widget.onItemTap!(item, context)
                : null,
          ));
        } else {
          cells.add(
            DataCell(
              Text(
                displayValue?.toString() ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: widget.onItemTap != null
                  ? () => widget.onItemTap!(item, context)
                  : null,
            ),
          );
        }
      }
    }

    // ── Coluna Ações: PopupMenuButton com todas as ações ──────────────────
    final List<PopupMenuEntry<String>> menuItems = [];

    if ((widget.hasPermission == null || widget.hasPermission!('edit')) && widget.buttonPermissions['edit']!) {
      menuItems.add(const PopupMenuItem(
          value: '__edit__',
          child: Row(children: [
            Icon(Icons.edit, size: 16),
            SizedBox(width: 8),
            Text('Editar', style: TextStyle(fontSize: 13))
          ])));
    }
    if (widget.detailScreenBuilder != null && (widget.hasPermission == null || widget.hasPermission!('view'))) {
      menuItems.add(const PopupMenuItem(
          value: '__view__',
          child: Row(children: [
            Icon(Icons.visibility, size: 16),
            SizedBox(width: 8),
            Text('Visualizar', style: TextStyle(fontSize: 13))
          ])));
    }
    if ((widget.hasPermission == null || widget.hasPermission!('delete')) && widget.buttonPermissions['delete']!) {
      menuItems.add(const PopupMenuDivider());
      menuItems.add(const PopupMenuItem(
          value: '__delete__',
          child: Row(children: [
            Icon(Icons.delete, size: 16, color: Colors.red),
            SizedBox(width: 8),
            Text('Excluir', style: TextStyle(fontSize: 13, color: Colors.red))
          ])));
    }
    for (final action
        in _customActions.where((a) => a.isVisible?.call(item) ?? true)) {
      final badge = action.badgeCount?.call(item) ?? 0;
      menuItems.add(PopupMenuItem(
          value: '__custom__${action.label}',
          child: Row(children: [
            Icon(action.icon, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(action.label, style: const TextStyle(fontSize: 13)),
            ),
            if (badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: GridColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: GridColors.primary,
                  ),
                ),
              ),
          ])));
    }

    cells.add(
      DataCell(
        menuItems.isEmpty
            ? const SizedBox(width: 32)
            : SizedBox(
                width: 32,
                child: PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_vert, size: 18),
                  itemBuilder: (_) => menuItems,
                  onSelected: (value) {
                    if (value == '__edit__') {
                      if (widget.editUsesDetailScreen &&
                          widget.detailScreenBuilder != null) {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    widget.detailScreenBuilder!(item)))
                            .then((_) {
                          if (mounted) _loadItems(_currentPage, rowsPerPage);
                        });
                      } else {
                        _openForm(item: item);
                      }
                    } else if (value == '__view__') {
                      // Bug de producao ("sai e volta, nao salvou nada"):
                      // diferente do ramo __edit__ acima, este nunca dava
                      // reload no grid ao voltar. A tela de detalhe
                      // (GenericDetailFormScreen) salva de verdade no
                      // backend (PUT confirmado 200), mas o item exibido
                      // na LISTA continuava o valor antigo em memoria --
                      // reabrir o mesmo registro (por "Visualizar" ou por
                      // "Editar" quando editUsesDetailScreen=false, unico
                      // caminho pra telas como Parceiro) reexibia o item
                      // desatualizado do grid, dando a impressao de que
                      // nada foi salvo.
                      Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      widget.detailScreenBuilder!(item)))
                          .then((_) {
                        if (mounted) _loadItems(_currentPage, rowsPerPage);
                      });
                    } else if (value == '__delete__') {
                      _deleteItem(_getNestedValue(itemMap, widget.idFieldName)
                          .toString());
                    } else if (value.startsWith('__custom__')) {
                      final label = value.substring('__custom__'.length);
                      final action =
                          _customActions.firstWhere((a) => a.label == label);
                      action.onPressed(context, item);
                    }
                  },
                ),
              ),
      ),
    );

    return cells;
  }

  dynamic _getNestedValue(dynamic map, String fieldName) {
    if (map == null) return null;
    if (map is! Map) return null;

    // Tenta acesso direto e variações de nome
    dynamic val = _tryGet(map, fieldName);

    if (val != null) {
      if (val is List) return val;
      if (val is Map) return _formatValue(val);
      return val;
    }

    // Se tem ponto, resolve path
    if (fieldName.contains('.')) {
      final parts = fieldName.split('.');
      // Tenta resolver o primeiro segmento
      dynamic parent = _tryGet(map, parts[0]);
      if (parent != null && parts.length > 1) {
        if (parent is Map) {
          final child = _tryGet(parent, parts[1]);
          if (child != null) return child;
          return _formatValue(parent);
        }
        if (parent is List) return parent;
      }
    }

    return null;
  }

  /// Como [_getNestedValue] mas sem chamar [_formatValue] — retorna o Map/List
  /// bruto. Usado em _openForm para campos dropdown/multiselect, onde precisamos
  /// do ID numérico, não do label de exibição.
  dynamic _getNestedRawValue(dynamic map, String fieldName) {
    if (map == null || map is! Map) return null;
    dynamic val = _tryGet(map, fieldName);
    if (val != null) return val; // retorna Map/List/primitive SEM formatação
    if (fieldName.contains('.')) {
      final parts = fieldName.split('.');
      dynamic parent = _tryGet(map, parts[0]);
      if (parent is Map && parts.length > 1) {
        return _tryGet(parent, parts[1]) ?? parent;
      }
      if (parent is List) return parent;
    }
    return null;
  }

  /// Tenta acessar um campo no map com varias variações de nome
  dynamic _tryGet(dynamic map, String key) {
    if (map is! Map) return null;
    // Direto
    if (map.containsKey(key)) return map[key];
    // camelCase
    final camel = _toCamel(key);
    if (map.containsKey(camel)) return map[camel];
    // snake_case
    final snake = _toSnake(key);
    if (map.containsKey(snake)) return map[snake];
    // Plural/singular
    if (map.containsKey('${key}s')) return map['${key}s'];
    if (key.endsWith('s') && map.containsKey(key.substring(0, key.length - 1)))
      return map[key.substring(0, key.length - 1)];
    // Remove sufixos comuns de tabelas FK (regime_tributario -> regime, file_attachment -> file)
    for (final suffix in [
      '_tributario',
      '_attachment',
      '_bancaria',
      '_pagamento',
      '_contratado',
      '_servico',
      '_parceiro'
    ]) {
      if (key.contains(suffix)) {
        final short = key.replaceAll(suffix, '');
        if (map.containsKey(short)) return map[short];
        final shortCamel = _toCamel(short);
        if (map.containsKey(shortCamel)) return map[shortCamel];
      }
    }
    // Tenta match parcial (ex: "regime_tributario" -> procura key que comeca com "regime")
    final prefix = key.split('_').first;
    if (prefix.length >= 3) {
      for (final k in map.keys) {
        if (k.toString().toLowerCase() == prefix.toLowerCase() && k != key)
          return map[k];
      }
    }
    return null;
  }

  /// Formata valor para exibicao na grid
  dynamic _formatValue(dynamic val) {
    if (val == null) return null;
    if (val is List) {
      return val.map((e) {
        if (e is Map)
          return e['key'] ??
              e['nome'] ??
              e['descricao'] ??
              e['label'] ??
              e['name'] ??
              e['id']?.toString() ??
              '';
        return e.toString();
      }).join(', ');
    }
    if (val is Map) {
      return val['nome'] ??
          val['descricao'] ??
          val['codigo'] ??
          val['key'] ??
          val['label'] ??
          val['name'] ??
          val['id']?.toString() ??
          '';
    }
    return val;
  }

  /// snake_case -> camelCase (ex: "tipo_login" -> "tipoLogin")
  String _toCamel(String s) {
    final parts = s.split('_');
    if (parts.length <= 1) return s;
    return parts.first +
        parts
            .skip(1)
            .map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1))
            .join();
  }

  /// camelCase -> snake_case (ex: "tipoLogin" -> "tipo_login")
  String _toSnake(String s) {
    return s.replaceAllMapped(
        RegExp(r'[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}');
  }

  /// Resolve path com ponto (ex: "empresa.nome" -> map["empresa"]["nome"])
  dynamic _resolveNestedPath(dynamic map, String fieldName) {
    final parts = fieldName.split('.');
    dynamic value = map;

    for (final part in parts) {
      if (value == null) return null;

      if (value is Map<dynamic, dynamic>) {
        final m = Map<String, dynamic>.from(value);
        value = m[part] ?? m[_toCamel(part)] ?? m[_toSnake(part)];
      } else if (value is Map<String, dynamic>) {
        value = value[part] ?? value[_toCamel(part)] ?? value[_toSnake(part)];
      } else if (value is List) {
        final index = int.tryParse(part);
        if (index != null && index >= 0 && index < value.length) {
          value = value[index];
        } else {
          return null;
        }
      } else {
        // Se já é um valor primitivo (String, int, double, bool), retorna direto
        if (value is String || value is num || value is bool) {
          return value;
        }
        // PARA OBJETOS DART: tenta métodos específicos sem reflexão
        value = _getObjectProperty(value, part);
        if (value == null) return null;
      }
    }

    return value;
  }

  dynamic _getObjectProperty(dynamic object, String propertyName) {
    if (object == null) return null;
    // Se já é primitivo, retorna direto
    if (object is String || object is num || object is bool) return object;

    // Tratamento específico para objetos de arquivo
    switch (propertyName.toLowerCase()) {
      case 'id':
        return object.id ??
            object.ID ??
            object.Id ??
            object.fileId ??
            object.fileID ??
            0;
      case 'nome':
      case 'filename':
      case 'name':
        return object.nome ??
            object.fileName ??
            object.filename ??
            object.name ??
            '';
      case 'filetype':
      case 'type':
        return object.fileType ?? object.type ?? object.contentType ?? '';
      case 'tamanho':
      case 'size':
        return object.tamanho ?? object.size ?? object.fileSize ?? 0;
      default:
        // Tenta converter para mapa via toJson() se existir
        try {
          if (object.toJson != null) {
            final jsonMap = object.toJson();
            if (jsonMap is Map && jsonMap.containsKey(propertyName)) {
              return jsonMap[propertyName];
            }
          }
        } catch (e) {
          // Ignora erro e retorna null
        }
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fixedColumnsCount = widget.fieldConfigs.where(
        (c) => _columnVisibility[c.fieldName] == true && c.isFixed).length;

    return Scaffold(
      backgroundColor: GridColors.background,
      appBar: widget.showAppBar
          ? AppBar(
              title: Text(widget.title),
              backgroundColor: GridColors.primary,
              foregroundColor: GridColors.card,
              actions: [
                IconButton(
                  icon: const Icon(Icons.help_outline),
                  onPressed: _showGridHelpDialog,
                  tooltip: 'Ajuda da tela',
                ),
                _buildColumnSettingsMenu(),
                if (widget.exportConfig.enableCsvExport &&
                    (widget.hasPermission == null || widget.hasPermission!('export')) &&
                    widget.buttonPermissions['export']!)
                  IconButton(
                    icon: _isExporting
                        ? const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          )
                        : const Icon(Icons.download),
                    onPressed: _isExporting ? null : _exportToCsv,
                    tooltip: "Exportar CSV",
                  ),
              ],
            )
          : null,
      body: Stack(
        children: [
          Column(
            children: [
              _buildGridToolbar(),
              if (filtrosAbertos) _buildFilters(),
              _buildActiveFilterTags(),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      margin: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: GridColors.card,
                        border: Border.all(color: GridColors.divider),
                      ),
                      child: PaginatedDataTable2(
                        columnSpacing: 10,
                        horizontalMargin: 8,
                        minWidth: 1200,
                        controller: _paginatorController,
                        scrollController: _tableScrollController,
                        wrapInCard: false,
                        fit: FlexFit.tight,
                        headingRowHeight: 32,
                        dataRowHeight: 32,
                        sortColumnIndex: sortColumnIndex,
                        sortAscending: sortAscending,
                        showFirstLastButtons: true,
                        renderEmptyRowsInTheEnd: false,
                        initialFirstRowIndex: _currentPage * rowsPerPage,
                        headingRowColor:
                            WidgetStateProperty.all(GridColors.gridHeader),
                        headingTextStyle: const TextStyle(
                          color: GridColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                        dataTextStyle: const TextStyle(
                          color: GridColors.textSecondary,
                          fontSize: 12,
                        ),
                        checkboxHorizontalMargin: 6,
                        dividerThickness: 0.8,
                        columns: _buildColumns(),
                        source: _GenericDataSource<T>(
                          items: filtered,
                          selectedRows: selectedRows,
                          cellBuilder: _buildCells,
                          totalItems: _totalItems,
                          isLoading: isLoading,
                          currentPage: _currentPage,
                          rowsPerPage: rowsPerPage,
                          rowIdBuilder: (item, _) {
                            final itemMap = (widget.toJson != null ? widget.toJson!(item) : item as Map<String, dynamic>);
                            return _getNestedValue(
                              itemMap,
                              widget.idFieldName,
                            ).toString();
                          },
                          onSelect: (index, selected) {
                            setState(() {
                              final itemMap = (widget.toJson != null ? widget.toJson!(filtered[index]) : filtered[index] as Map<String, dynamic>);
                              final id = _getNestedValue(
                                itemMap,
                                widget.idFieldName,
                              ).toString();
                              selected
                                  ? selectedRows.add(id)
                                  : selectedRows.remove(id);
                            });
                            // Build list of selected row data maps
                            final selectedData = <Map<String, dynamic>>[];
                            for (final item in filtered) {
                              final itemMap = (widget.toJson != null ? widget.toJson!(item) : item as Map<String, dynamic>);
                              final itemId = _getNestedValue(
                                itemMap,
                                widget.idFieldName,
                              ).toString();
                              if (selectedRows.contains(itemId)) {
                                selectedData.add(itemMap);
                              }
                            }
                            widget.onSelectedRowsChanged?.call(
                              Set.from(selectedRows),
                              selectedData,
                            );
                          },
                        ),
                        rowsPerPage: rowsPerPage,
                        availableRowsPerPage:
                            widget.paginationConfig.availableRowsPerPage,
                        onRowsPerPageChanged:
                            widget.paginationConfig.showItemsPerPageSelector
                                ? (value) {
                                    setState(() {
                                      rowsPerPage = value ??
                                          widget.paginationConfig
                                              .defaultRowsPerPage;
                                      _currentPage = 0;
                                    });
                                    _loadItems(_currentPage, rowsPerPage);
                                  }
                                : null,
                        onPageChanged: (pageIndex) {
                          // Ignora eventos de página disparados durante carregamento
                          if (isLoading) return;
                          final numeroPagina =
                              rowsPerPage > 0 ? pageIndex ~/ rowsPerPage : 0;
                          // Ignora se já estamos nessa página
                          if (numeroPagina == _currentPage) return;
                          setState(() {
                            _currentPage = numeroPagina;
                          });
                          _loadItems(_currentPage, rowsPerPage);
                        },
                        fixedLeftColumns: widget.fieldConfigs.where(
                          (c) =>
                              _columnVisibility[c.fieldName] == true &&
                              c.isFixed,
                        ).length,
                        empty: Center(
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            child: const Text(
                              "Nenhum item encontrado",
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ), // fecha Container
                    // Overlay de loading durante paginação
                    if (isLoading)
                      Positioned.fill(
                        child: Container(
                          color: Colors.white.withValues(alpha: 0.7),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: GridColors.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ), // fecha Stack
              ), // fecha Expanded
            ],
          ),
          _buildLoadingOverlay(),
        ],
      ),
    );
  }
}

class _GenericDataSource<T> extends DataTableSource {
  final List<T> items;
  final Set<String> selectedRows;
  final List<DataCell> Function(T item, int index) cellBuilder;
  final String Function(T item, int index) rowIdBuilder;
  final void Function(int index, bool selected) onSelect;
  final int totalItems;
  final bool isLoading;
  final int currentPage;
  final int rowsPerPage;

  _GenericDataSource({
    required this.items,
    required this.selectedRows,
    required this.cellBuilder,
    required this.rowIdBuilder,
    required this.onSelect,
    required this.totalItems,
    this.isLoading = false,
    this.currentPage = 0,
    this.rowsPerPage = 25,
  });

  @override
  DataRow? getRow(int index) {
    // index é absoluto — converte para índice relativo dentro de items (página atual)
    final pageOffset = currentPage * rowsPerPage;
    final localIndex = index - pageOffset;
    if (localIndex < 0 || localIndex >= items.length) return null;
    final item = items[localIndex];
    final itemId = rowIdBuilder(item, localIndex);
    final isSelected = selectedRows.contains(itemId);

    return DataRow(
      selected: isSelected,
      color: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected))
          return GridColors.selectedRow;
        if (states.contains(WidgetState.hovered)) return GridColors.hover;
        return localIndex.isEven ? GridColors.rowEven : GridColors.rowOdd;
      }),
      onSelectChanged: (selected) => onSelect(localIndex, selected ?? false),
      cells: cellBuilder(item, localIndex),
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => totalItems > 0 ? totalItems : items.length;

  @override
  int get selectedRowCount => selectedRows.length;
}

// ─── Searchable Dropdown (Windows/Web framework) ─────────────────────────────
// Replaces DropdownButtonFormField with a tap-to-open dialog that has a
// search field — works for any list size.

class _SearchableDropdownWindows extends StatefulWidget {
  final FieldConfigWindows config;
  final TextEditingController controller;
  final List<Map<String, dynamic>> options;

  /// Quando definido (cascade), o widget observa este controller e re-busca
  /// as opções usando [config.dropdownFutureBuilderWithParam] toda vez que o
  /// valor do campo pai mudar.
  final TextEditingController? dependsOnController;

  const _SearchableDropdownWindows({
    required this.config,
    required this.controller,
    required this.options,
    this.dependsOnController,
  });

  @override
  State<_SearchableDropdownWindows> createState() =>
      _SearchableDropdownWindowsState();
}

class _SearchableDropdownWindowsState
    extends State<_SearchableDropdownWindows> {
  String? _selectedLabel;
  List<Map<String, dynamic>> _resolvedOptions = [];
  bool _loadingCascade = false;
  String? _lastDependsOnValue;

  @override
  void initState() {
    super.initState();
    _resolvedOptions = widget.options;

    if (widget.dependsOnController != null &&
        widget.config.dropdownFutureBuilderWithParam != null) {
      // Modo cascade: busca inicial + listener
      _lastDependsOnValue = widget.dependsOnController!.text;
      _fetchCascade(_lastDependsOnValue);
      widget.dependsOnController!.addListener(_onDependencyChanged);
    } else if (widget.config.dropdownRemoteSearch != null) {
      _resolveRemoteLabelIfNeeded();
    } else {
      _resolvedOptions = widget.options;
      _resolveLabel();
    }
  }

  /// Resolve o rótulo exibido para um valor já selecionado quando o dropdown
  /// usa busca remota (não há lista local para procurar) — ex: tela de
  /// edição de Conta a Pagar/Receber com Fornecedor/Parceiro já preenchido.
  Future<void> _resolveRemoteLabelIfNeeded() async {
    final val = widget.controller.text.isNotEmpty
        ? widget.controller.text
        : widget.config.dropdownSelectedValue?.toString();
    if (val == null || val.isEmpty) return;
    if (widget.controller.text.isEmpty) widget.controller.text = val;
    final resolver = widget.config.dropdownResolveLabel;
    if (resolver == null) return;
    final label = await resolver(val);
    if (mounted && label != null) {
      setState(() => _selectedLabel = label);
    }
  }

  @override
  void dispose() {
    widget.dependsOnController?.removeListener(_onDependencyChanged);
    super.dispose();
  }

  void _onDependencyChanged() {
    final newVal = widget.dependsOnController!.text;
    if (newVal == _lastDependsOnValue) return;
    _lastDependsOnValue = newVal;
    // Limpa seleção atual quando o pai muda
    if (mounted) {
      setState(() {
        widget.controller.text = '';
        _selectedLabel = null;
        _resolvedOptions = [];
      });
    }
    _fetchCascade(newVal);
  }

  Future<void> _fetchCascade(String? param) async {
    if (!mounted) return;
    setState(() => _loadingCascade = true);
    try {
      final opts = await widget.config.dropdownFutureBuilderWithParam!(
          param == null || param.isEmpty ? null : param);
      if (mounted) {
        setState(() {
          _resolvedOptions = opts;
          _loadingCascade = false;
        });
        _resolveLabel();
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCascade = false);
    }
  }

  void _resolveLabel() {
    final val = widget.controller.text.isNotEmpty
        ? widget.controller.text
        : widget.config.dropdownSelectedValue?.toString();
    if (val == null || val.isEmpty) return;
    for (final o in _resolvedOptions) {
      final ov = o[widget.config.dropdownValueField]?.toString();
      if (ov == val) {
        _selectedLabel = o[widget.config.dropdownDisplayField]?.toString();
        break;
      }
    }
    // Pre-fill controller if empty
    if (widget.controller.text.isEmpty && val.isNotEmpty) {
      widget.controller.text = val;
    }
  }

  Future<void> _openSearch() async {
    if (!widget.config.enabled) return;
    final remoteSearch = widget.config.dropdownRemoteSearch;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => remoteSearch != null
          ? RemoteDropdownSearchDialog(
              title: widget.config.label,
              valueField: widget.config.dropdownValueField,
              displayField: widget.config.dropdownDisplayField,
              currentValue: widget.controller.text,
              loadPage: remoteSearch,
            )
          : _DropdownSearchDialog(
              title: widget.config.label,
              options: _resolvedOptions,
              valueField: widget.config.dropdownValueField,
              displayField: widget.config.dropdownDisplayField,
              currentValue: widget.controller.text,
            ),
    );
    if (result != null) {
      setState(() {
        widget.controller.text =
            result[widget.config.dropdownValueField]?.toString() ?? '';
        _selectedLabel = result[widget.config.dropdownDisplayField]?.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Cascade loading indicator
    if (_loadingCascade) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(color: GridColors.primary),
      );
    }

    final label = widget.config.label + (widget.config.isRequired ? ' *' : '');
    final displayText = _selectedLabel ?? widget.controller.text;
    final isEmpty = displayText.isEmpty;
    final isDisabled = !widget.config.enabled;

    return FormField<String>(
      initialValue: widget.controller.text,
      validator: (v) {
        if (widget.config.validator != null) {
          return widget.config.validator!(widget.controller.text);
        }
        return null;
      },
      builder: (state) => InkWell(
        onTap: isDisabled ? null : _openSearch,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(fontSize: 13),
            filled: true,
            fillColor: isDisabled ? const Color(0xFFF5F5F5) : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: GridColors.primary, width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: GridColors.primary, width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: GridColors.divider),
            ),
            suffixIcon: isDisabled
                ? const Icon(Icons.lock_outline, size: 16, color: Colors.grey)
                : const Icon(Icons.search, size: 18, color: GridColors.primary),
            errorText: state.errorText,
          ),
          child: Text(
            isEmpty ? 'Selecione' : displayText,
            style: TextStyle(
              fontSize: 13,
              color: isEmpty
                  ? Colors.grey
                  : isDisabled
                      ? Colors.grey
                      : const Color(0xFF212121),
              overflow: TextOverflow.ellipsis,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

// ─── Dialog de busca remota (server-side + scroll pagination) ────────────────
//
// Bug de producao corrigido aqui: o dropdown de Parceiro/Fornecedor em Contas
// a Pagar/Receber carregava so o 1o lote de 25 registros (GET /api/parceiro
// sem parametros de busca/paginacao) e filtrava so client-side sobre esse
// lote pequeno — termos que so batiam em registros fora da 1a pagina nunca
// apareciam. Este dialog reconsulta o backend a cada termo digitado
// (debounce) e carrega mais paginas conforme o usuario rola a lista, ate
// esgotar os resultados reais.
class RemoteDropdownSearchDialog extends StatefulWidget {
  final String title;
  final String valueField;
  final String displayField;
  final String? currentValue;
  final Future<PaginaDropdown> Function({String? busca, required int pagina})
      loadPage;

  const RemoteDropdownSearchDialog({
    super.key,
    required this.title,
    required this.valueField,
    required this.displayField,
    required this.loadPage,
    this.currentValue,
  });

  @override
  State<RemoteDropdownSearchDialog> createState() =>
      RemoteDropdownSearchDialogState();
}

class RemoteDropdownSearchDialogState
    extends State<RemoteDropdownSearchDialog> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _debounce;
  final List<Map<String, dynamic>> _items = [];
  int _pagina = 0;
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String _termoAtual = '';
  int _requestToken = 0;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _carregarPrimeiraPagina();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loading || _loadingMore) return;
    if (_items.length >= _total) return;
    if (!_scrollCtrl.hasClients) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 80) {
      _carregarProximaPagina();
    }
  }

  Future<void> _carregarPrimeiraPagina() async {
    final token = ++_requestToken;
    setState(() => _loading = true);
    final pagina = await widget.loadPage(
      busca: _termoAtual.isEmpty ? null : _termoAtual,
      pagina: 0,
    );
    if (!mounted || token != _requestToken) return;
    setState(() {
      _items
        ..clear()
        ..addAll(pagina.items);
      _total = pagina.total;
      _pagina = 0;
      _loading = false;
      _erro = pagina.erro;
    });
  }

  Future<void> _carregarProximaPagina() async {
    // Incrementa (não só lê) o token — mesma defesa de _carregarPrimeiraPagina.
    // Hoje o único chamador é _onScroll, já protegido por _loading/_loadingMore,
    // mas sem incrementar aqui um futuro segundo chamador (ex.: botão "carregar
    // mais" manual) poderia invalidar-se mutuamente de forma incorreta.
    final token = ++_requestToken;
    setState(() => _loadingMore = true);
    final proximaPagina = _pagina + 1;
    final pagina = await widget.loadPage(
      busca: _termoAtual.isEmpty ? null : _termoAtual,
      pagina: proximaPagina,
    );
    if (!mounted || token != _requestToken) return;
    setState(() {
      _items.addAll(pagina.items);
      _total = pagina.total;
      _pagina = proximaPagina;
      _loadingMore = false;
      _erro = pagina.erro;
    });
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _termoAtual = q.trim();
      _carregarPrimeiraPagina();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
        child: Column(
          children: [
            Container(
              decoration: const BoxDecoration(
                color: GridColors.primary,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Buscar ${widget.title.toLowerCase()}...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchCtrl.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: GridColors.primary),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: GridColors.primary, width: 2),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    _loading ? 'Buscando...' : '$_total resultado(s)',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop(<String, dynamic>{}),
                    child: const Text(GridTexts.clearSelection,
                        style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _erro ?? 'Nenhum resultado',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _erro != null
                                    ? GridColors.error
                                    : Colors.grey,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollCtrl,
                          itemCount: _items.length + (_loadingMore ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i >= _items.length) {
                              return const Padding(
                                padding: EdgeInsets.all(12),
                                child: Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                ),
                              );
                            }
                            final o = _items[i];
                            final val = o[widget.valueField]?.toString();
                            final label =
                                o[widget.displayField]?.toString() ??
                                    val ??
                                    '';
                            final isSelected = val == widget.currentValue;
                            return ListTile(
                              dense: true,
                              selected: isSelected,
                              selectedTileColor:
                                  GridColors.primary.withValues(alpha: 0.08),
                              leading: isSelected
                                  ? const Icon(Icons.check_circle,
                                      color: GridColors.primary, size: 18)
                                  : const Icon(Icons.radio_button_unchecked,
                                      color: Colors.grey, size: 18),
                              title: Text(label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? GridColors.primary
                                        : const Color(0xFF212121),
                                  )),
                              onTap: () => Navigator.of(context).pop(o),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Dialog de busca ─────────────────────────────────────────────────────────

class _DropdownSearchDialog extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> options;
  final String valueField;
  final String displayField;
  final String? currentValue;

  const _DropdownSearchDialog({
    required this.title,
    required this.options,
    required this.valueField,
    required this.displayField,
    this.currentValue,
  });

  @override
  State<_DropdownSearchDialog> createState() => _DropdownSearchDialogState();
}

class _DropdownSearchDialogState extends State<_DropdownSearchDialog> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.options;
  }

  void _onSearch(String q) {
    final query = q.toLowerCase().trim();
    setState(() {
      _filtered = query.isEmpty
          ? widget.options
          : widget.options
              .where((o) => (o[widget.displayField]?.toString() ?? '')
                  .toLowerCase()
                  .contains(query))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
        child: Column(
          children: [
            // Header
            Container(
              decoration: const BoxDecoration(
                color: GridColors.primary,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Search field
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: _onSearch,
                decoration: InputDecoration(
                  hintText: 'Buscar ${widget.title.toLowerCase()}...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchCtrl.clear();
                            _onSearch('');
                          },
                        )
                      : null,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: GridColors.primary),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: GridColors.primary, width: 2),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            // Option count
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    '${_filtered.length} resultado(s)',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const Spacer(),
                  // Clear selection
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop(<String, dynamic>{}),
                    child: const Text(GridTexts.clearSelection,
                        style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // List
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(
                      child: Text('Nenhum resultado',
                          style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) {
                        final o = _filtered[i];
                        final val = o[widget.valueField]?.toString();
                        final label =
                            o[widget.displayField]?.toString() ?? val ?? '';
                        final isSelected = val == widget.currentValue;
                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          selectedTileColor:
                              GridColors.primary.withValues(alpha: 0.08),
                          leading: isSelected
                              ? const Icon(Icons.check_circle,
                                  color: GridColors.primary, size: 18)
                              : const Icon(Icons.radio_button_unchecked,
                                  color: Colors.grey, size: 18),
                          title: Text(label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? GridColors.primary
                                    : const Color(0xFF212121),
                              )),
                          onTap: () => Navigator.of(context).pop(o),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Diálogo de busca usado pelo _buildFilterDropdown para dropdowns dinâmicos.
// Abre uma lista filtrada conforme o usuário digita, igual ao _MultiSelectField.
// ─────────────────────────────────────────────────────────────────────────────
class _FilterSearchDialog extends StatefulWidget {
  final List<Map<String, dynamic>> options;
  final String vf; // campo de valor (ex: 'value' ou 'id')
  final String df; // campo de display (ex: 'label' ou 'nome')

  const _FilterSearchDialog({
    required this.options,
    required this.vf,
    required this.df,
  });

  @override
  State<_FilterSearchDialog> createState() => _FilterSearchDialogState();
}

class _FilterSearchDialogState extends State<_FilterSearchDialog> {
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.options
        : widget.options
            .where((o) => (o[widget.df]?.toString() ?? '')
                .toLowerCase()
                .contains(_query.toLowerCase()))
            .toList();

    return Dialog(
      backgroundColor: GridColors.dialogBackground,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: SizedBox(
        width: 360, // largura fixa e compacta — não estica na tela toda
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Campo de busca
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Buscar...',
                  prefixIcon: const Icon(Icons.search,
                      size: 18, color: GridColors.inputBorder),
                  isDense: true,
                  filled: true,
                  fillColor: GridColors.card,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: GridColors.divider)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: GridColors.divider)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: GridColors.secondary)),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const Divider(height: 1, color: GridColors.divider),
            // Lista de opções
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: const Icon(Icons.clear_all,
                        size: 18, color: GridColors.textSecondary),
                    title: const Text('Todos',
                        style: TextStyle(
                            fontSize: 13, color: GridColors.textSecondary)),
                    onTap: () =>
                        Navigator.pop(context, {widget.vf: '', widget.df: ''}),
                  ),
                  const Divider(height: 1, color: GridColors.divider),
                  ...filtered.map((opt) {
                    final lbl = opt[widget.df]?.toString() ??
                        opt[widget.vf]?.toString() ??
                        '';
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      title: Text(lbl,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                      onTap: () => Navigator.pop(context, opt),
                    );
                  }),
                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text('Nenhum resultado',
                            style: TextStyle(
                                fontSize: 12, color: GridColors.textSecondary)),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: GridColors.divider),
            // Botão cancelar
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar',
                      style: TextStyle(
                          color: GridColors.textSecondary, fontSize: 13)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
