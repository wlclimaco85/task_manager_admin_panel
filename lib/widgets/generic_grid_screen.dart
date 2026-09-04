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
import '../../../services/auth_utility.dart';
import '../../../models/network_response.dart';
import '../../../config/api_links.dart';
import '../../services/network_caller.dart';
import 'searchable_dropdown.dart';

import 'package:task_manager_admin_panel/utils/app_logger.dart';
import 'package:task_manager_admin_panel/models/tela_ajuda_model.dart';
import 'package:task_manager_admin_panel/services/tela_ajuda_service.dart';
// ==============================================
// ENUMS E CONFIGURAÇÕES
// ==============================================

// Enum para tipos de campo
enum FieldType {
  text,
  number,
  email,
  date,
  multiline,
  dropdown,
  boolean,
  file,
  password,
  phone,
  cpf,
  cnpj,
  currency,
  percentage,
  url,
  multiselect,
}

// Fix (card #459): campos de relacionamento (@ManyToOne/@JoinColumn no
// backend) precisam ir como objeto {"id": N}, mas os dropdowns deste widget
// legado guardam so o id escalar (String/int). A conversao so acontece
// quando o valor ainda e String/num (idempotente, nao mexe em quem ja
// chega pronto como objeto).
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
class FieldConfig {
  final String label;
  final String fieldName;
  final bool isFilterable;
  final bool isInForm;
  final int flex;
  final int maxLines;
  final IconData? icon;
  final bool isSortable;
  final FieldType fieldType;
  final List<Map<String, dynamic>>? dropdownOptions;
  final Future<List<Map<String, dynamic>>> Function()? dropdownFutureBuilder;
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

  const FieldConfig({
    required this.label,
    required this.fieldName,
    this.isFilterable = true,
    this.isInForm = true,
    this.flex = 1,
    this.maxLines = 1,
    this.icon,
    this.isSortable = true,
    this.fieldType = FieldType.text,
    this.dropdownOptions,
    this.dropdownFutureBuilder,
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
  });
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

  const CustomAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isVisible,
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
    required FieldConfig config,
    required TextEditingController controller,
    required BuildContext context,
    required Map<String, List<PlatformFile>> fileCache,
    required Map<String, List<Map<String, dynamic>>> dropdownCache,
    dynamic item,

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
      onFileChanged: onFileChanged,
    );

    return AbsorbPointer(
      absorbing: !config.enabled,
      child: Opacity(opacity: config.enabled ? 1.0 : 0.6, child: fieldWidget),
    );
  }

  static Widget _buildSpecificField(
    FieldConfig config,
    TextEditingController controller,
    BuildContext context,
    Map<String, List<PlatformFile>> fileCache,
    Map<String, List<Map<String, dynamic>>> dropdownCache, {
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
      case FieldType.multiline:
        return _buildMultilineField(config, controller);
      case FieldType.dropdown:
        return _buildDropdownField(config, controller, dropdownCache);
      case FieldType.file:
        return _buildFileField(config, controller, fileCache, context,
            onFileChanged: onFileChanged);
      case FieldType.boolean:
        return _buildBooleanField(config, controller);
      default:
        return _buildTextField(config, controller);
    }
  }

  static Widget _buildNumberField(
    FieldConfig config,
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
    FieldConfig config,
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
    FieldConfig config,
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
    FieldConfig config,
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
    FieldConfig config,
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
    FieldConfig config,
    TextEditingController controller,
  ) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: _buildInputDecoration(config),
      inputFormatters: [CpfInputFormatter()],
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
    FieldConfig config,
    TextEditingController controller,
  ) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: _buildInputDecoration(config),
      inputFormatters: [CnpjInputFormatter()],
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

  static Widget _buildTextField(
    FieldConfig config,
    TextEditingController controller,
  ) {
    return TextFormField(
      controller: controller,
      decoration: _buildInputDecoration(config),
      maxLines: config.maxLines,
      validator: config.validator,
    );
  }

  static Widget _buildMultilineField(
    FieldConfig config,
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
    FieldConfig config,
    TextEditingController controller,
  ) {
    return CheckboxListTile(
      title: Text(config.label),
      value: controller.text.toLowerCase() == 'true',
      onChanged: (value) {
        controller.text = value.toString();
      },
    );
  }

  static Widget _buildDropdownField(
    FieldConfig config,
    TextEditingController controller,
    Map<String, List<Map<String, dynamic>>> dropdownCache,
  ) {
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
    required FieldConfig config,
    required TextEditingController controller,
    required List<Map<String, dynamic>> options,
  }) {
    bool expectInteger = _isIntegerField(config);
    dynamic currentValue = _getCurrentValue(config, controller);

    final uniqueOptions = options
        .fold<Map<dynamic, Map<String, dynamic>>>({}, (map, item) {
          dynamic key = item[config.dropdownValueField];
          if (key != null && !map.containsKey(key)) {
            map[key] = item;
          }
          return map;
        })
        .values
        .toList();

    bool valueExists = uniqueOptions.any(
      (option) => option[config.dropdownValueField] == currentValue,
    );

    if (!valueExists && config.dropdownSelectedValue != null) {
      currentValue = config.dropdownSelectedValue;
    } else if (!valueExists) {
      currentValue = null;
    }

    return SearchableDropdownField(
      label: config.label,
      value: currentValue?.toString(),
      items: uniqueOptions,
      valueField: config.dropdownValueField,
      displayField: config.dropdownDisplayField,
      enabled: config.enabled,
      isRequired: config.isRequired,
      nullable: !config.isRequired,
      nullLabel: GridTexts.clearSelection,
      validator: config.validator,
      onChanged: (v) => controller.text = v ?? '',
    );
  }

  static Widget _buildFileField(
    FieldConfig config,
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
    FieldConfig config,
    TextEditingController controller,
    Map<String, List<PlatformFile>> fileCache,
    BuildContext context, [
    VoidCallback? onFileChanged,
  ]) async {
    final fileConfig = config.fileConfig ?? const FileConfig();

    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: fileConfig.allowedExtensions,
        allowMultiple: fileConfig.allowMultiple,
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

  static InputDecoration _buildInputDecoration(FieldConfig config) {
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
    );

    if (picked != null) {
      controller.text = DateFormat('yyyy-MM-dd').format(picked);
    }
  }

  // Métodos auxiliares
  static dynamic _getCurrentValue(
    FieldConfig config,
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

  static bool _isIntegerField(FieldConfig config) {
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
}

// ==============================================
// COMPONENTE PRINCIPAL GENERIC GRID SCREEN
// ==============================================

typedef FromJson<T> = T Function(Map<String, dynamic> json);
typedef ToJson<T> = Map<String, dynamic> Function(T item);
typedef SecurityCheck = bool Function(String permission);
typedef OnItemTap<T> = void Function(T item, BuildContext context);
typedef CustomActionBuilder<T> = List<CustomAction<T>> Function();

class GenericGridScreen<T> extends StatefulWidget {
  final String title;
  final String fetchEndpoint;
  final String createEndpoint;
  final String updateEndpoint;
  final String deleteEndpoint;
  final FromJson<T> fromJson;
  final ToJson<T> toJson;
  final SecurityCheck hasPermission;
  final Map<String, bool> buttonPermissions;
  final List<FieldConfig> fieldConfigs;
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
  final Map<String, dynamic>? extraParams;
  final String? helpTelaNome;
  final List<Widget>? headerActions;

  const GenericGridScreen({
    super.key,
    required this.title,
    required this.fetchEndpoint,
    required this.createEndpoint,
    required this.updateEndpoint,
    required this.deleteEndpoint,
    required this.fromJson,
    required this.toJson,
    required this.hasPermission,
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
    this.extraParams,
    this.helpTelaNome,
    this.headerActions,
  });

  @override
  State<GenericGridScreen<T>> createState() => _GenericGridScreenState<T>();
}

class _GenericGridScreenState<T> extends State<GenericGridScreen<T>> {
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
      _columnVisibility[config.fieldName] = config.isVisibleByDefault;
    }

    for (final config in widget.fieldConfigs.where((c) => c.isFilterable)) {
      _filterControllers[config.fieldName] = TextEditingController();
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
      _loadColumnPreferences().then((_) {
        _loadItems(_currentPage, rowsPerPage);
      });
    });

    if (widget.customActions != null) {
      _customActions = widget.customActions!();
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

  Future<void> _loadColumnPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Inclui o título para não colidir entre telas diferentes que usam o
      // mesmo storageKey padrão (bug: antes usava só widget.storageKey).
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
        Uri.parse(ApiLinks.downloadFile(fileId)),
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
  void _validateFieldConfigs() {
    for (final config in widget.fieldConfigs) {
      if (config.fieldType == FieldType.file) {
        L.d('Configuração File: ${config.fieldName}');
        L.d('Display Field: ${config.displayFieldName}');

        // Valida se a estrutura está correta
        if (!config.fieldName.contains('.')) {
          L.d('AVISO: Campo file deve ser aninhado (ex: "file.id")');
        }
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

      if (sortColumnIndex != null &&
          sortColumnIndex! < widget.fieldConfigs.length &&
          widget.fieldConfigs[sortColumnIndex!].isSortable) {
        final config = widget.fieldConfigs[sortColumnIndex!];
        final direction = sortAscending ? 'ASC' : 'DESC';
        url += '&ordenarPor=${config.fieldName}&direcao=$direction';
      }

      for (final config in widget.fieldConfigs.where((c) => c.isFilterable)) {
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
            return widget.fromJson(jsonMap);
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
      setState(() => isLoading = false);
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

  void _openForm({T? item}) {
    final controllers = <String, TextEditingController>{};
    final itemMap = item != null ? widget.toJson(item) : {};

    for (final config in widget.fieldConfigs.where((c) => c.isInForm)) {
      if (item == null && config.fieldName == widget.idFieldName) {
        continue;
      }

      String initialValue = '';
      if (item != null) {
        final value = _getNestedValue(itemMap, config.fieldName);
        if (value is Map) {
          initialValue = value[config.dropdownValueField]?.toString() ?? '';
        } else {
          initialValue = value?.toString() ?? '';
        }
      } else if (config.defaultValue != null) {
        initialValue = config.defaultValue.toString();
      }

      controllers[config.fieldName] = TextEditingController(text: initialValue);
    }

    // Fix (card #458): sem StatefulBuilder, o Dialog retornado por
    // _buildForm() e construido UMA UNICA VEZ quando o showDialog abre --
    // mutar fileCache (campo da tela por tras do dialog) depois disso nao
    // reconstroi o dialog, entao o arquivo selecionado nunca aparecia na
    // tela mesmo com o picker retornando com sucesso. setDialogState()
    // e passado adiante ate _selectFiles() para forcar o rebuild do
    // dialog especificamente apos a selecao/remocao de arquivo.
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) =>
            _buildForm(ctx, item, controllers, setDialogState),
      ),
    );
  }

  Widget _buildForm(
    BuildContext context,
    T? item,
    Map<String, TextEditingController> controllers,
    StateSetter setDialogState,
  ) {
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
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    ...widget.fieldConfigs.where((config) {
                      if (item == null &&
                          config.fieldName == widget.idFieldName) {
                        return false;
                      }
                      return config.isInForm;
                    }).map((config) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: FieldFactory.buildField(
                          config: config,
                          controller: controllers[config.fieldName]!,
                          context: context,
                          fileCache: _fileCache,
                          dropdownCache: _dropdownCache,
                          item: item,
                          onFileChanged: () => setDialogState(() {}),
                        ),
                      );
                    }),
                    const SizedBox(height: 10),
                    const Divider(height: 1, color: GridColors.divider),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            foregroundColor: GridColors.textSecondary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
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
                                    valueColor:
                                        AlwaysStoppedAnimation(Colors.white),
                                  ),
                                )
                              : const Text("SALVAR"),
                        ),
                      ],
                    ),
                  ],
                ),
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

      if (config.fieldName.contains('.')) {
        final parts = config.fieldName.split('.');
        _setNestedValue(formData, parts, value);
      } else {
        formData[config.fieldName] = value;
      }
    }

    if (item != null) {
      final itemMap = widget.toJson(item);
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
      Navigator.pop(context);
      _loadItems(_currentPage, rowsPerPage);
    }

    setState(() => _isUpdating = false);
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
    if (!widget.hasPermission('create') ||
        !widget.buttonPermissions['create']!) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sem permissão para criar')));
      return false;
    }

    final Map<String, dynamic> enrichedFormData = Map.from(formData);

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

    int fileId = 0;
    if (filesToUpload.isNotEmpty) {
      fileId = await _uploadFiles("", filesToUpload);
      enrichedFormData["file"] = {"id": fileId};
    }

    L.d(enrichedFormData);

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
          content: Text('Falha ao criar item: ${response.statusCode}'),
          backgroundColor: GridColors.error,
        ),
      );
      return false;
    }
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
      updated["status"] = 0;
    }

    return updated;
  }

  Future<bool> _updateItem(Map<String, dynamic> formData) async {
    if (!widget.hasPermission('edit') || !widget.buttonPermissions['edit']!) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem permissão para editar')),
      );
      return false;
    }
    final adjustedFormData = normalizeFormData(formData);

    final response = await NetworkCaller().postRequest(
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
          content: Text('Falha ao atualizar item: ${response.statusCode}'),
          backgroundColor: GridColors.error,
        ),
      );
      return false;
    }
  }

  Future<void> _deleteItem(String id) async {
    if (!widget.hasPermission('delete') ||
        !widget.buttonPermissions['delete']!) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem permissão para excluir')),
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
    if (!widget.hasPermission('deleteMultiple') ||
        !widget.buttonPermissions['deleteMultiple']!) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sem permissão para excluir múltiplos itens'),
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
    if (!widget.hasPermission('export') ||
        !widget.buttonPermissions['export']!) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem permissão para exportar')),
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
        final itemMap = widget.toJson(item);
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
    // Loading da grade cobre filtros/paginacao; este overlay fica so para acoes bloqueantes.
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

  static const int _maxAdvancedFilters = 10;

  String _normalizeFilterKey(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  bool _isTechnicalFilter(FieldConfig config) {
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

  List<FieldConfig> get _visibleFilterConfigs => widget.fieldConfigs
      .where((config) => config.isFilterable && !_isTechnicalFilter(config))
      .take(_maxAdvancedFilters)
      .toList();

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
                            child: TextField(
                              controller: _filterControllers[config.fieldName],
                              decoration: InputDecoration(
                                labelText: config.label,
                                hintText: 'Filtrar',
                                prefixIcon:
                                    Icon(config.icon ?? Icons.search, size: 18),
                                isDense: true,
                                filled: true,
                                fillColor: GridColors.card,
                                suffixIcon: (_filterControllers[
                                                config.fieldName]
                                            ?.text
                                            .isNotEmpty ??
                                        false)
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 16),
                                        onPressed: () {
                                          _filterControllers[config.fieldName]
                                              ?.clear();
                                          _applyFilters();
                                        },
                                      )
                                    : null,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(
                                    color: GridColors.divider,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(
                                    color: GridColors.divider,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(
                                    color: GridColors.primary,
                                  ),
                                ),
                              ),
                              onChanged: (_) {
                                setState(() {});
                                _applyFilters();
                              },
                            ),
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

  /// Tags vermelhas de filtros ativos — visíveis mesmo com painel fechado
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
        tags.add(_filterTag(config.label, v, () {
          _filterControllers[config.fieldName]?.clear();
          _applyFilters();
        }));
      }
    }

    if (tags.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: tags,
      ),
    );
  }

  Widget _filterTag(String label, String value, VoidCallback onRemove) {
    return Chip(
      label: Text(
        '$label: $value',
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
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

    final visibleFields = widget.fieldConfigs
        .where((c) =>
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
      if (widget.hasPermission('create') &&
          widget.buttonPermissions['create'] == true)
        'Criar novos registros pelo botao Novo.',
      if (widget.hasPermission('edit') &&
          widget.buttonPermissions['edit'] == true)
        'Editar registros existentes pelas acoes da linha.',
      if (widget.hasPermission('delete') &&
          widget.buttonPermissions['delete'] == true)
        'Excluir registros quando necessario.',
      if (widget.exportConfig.enableCsvExport &&
          widget.hasPermission('export') &&
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
          if (widget.hasPermission('create') &&
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
          if (widget.hasPermission('deleteMultiple') &&
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
                if (widget.headerActions != null) ...[
                  ...widget.headerActions!,
                  const SizedBox(height: 8),
                ],
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
              if (widget.headerActions != null) ...[
                ...widget.headerActions!,
                const SizedBox(width: 12),
              ],
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
      (c) => _columnVisibility[c.fieldName] == true,
    )) {
      columns.add(
        DataColumn(
          label: Text(config.label),
          onSort: config.isSortable
              ? (columnIndex, ascending) {
                  _sort<dynamic>(
                    (c) {
                      final value = _getNestedValue(
                        widget.toJson(c),
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

    columns.add(const DataColumn(label: Text("Ações")));

    return columns;
  }

  Map<String, dynamic> _extractFileData(
    Map<String, dynamic> itemMap,
    FieldConfig config,
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
    final itemMap = widget.toJson(item);
    final cells = <DataCell>[];

    for (final config in widget.fieldConfigs.where(
      (c) => _columnVisibility[c.fieldName] == true,
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
        final displayValue = _getNestedValue(
          itemMap,
          config.displayFieldName ?? config.fieldName,
        );

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

    cells.add(
      DataCell(
        Row(
          children: [
            if (widget.detailScreenBuilder != null &&
                widget.hasPermission('view'))
              IconButton(
                icon: const Icon(Icons.visibility, size: 20),
                onPressed: () {
                  // Bug de producao ("sai e volta, nao salvou nada"): a
                  // tela de detalhe salva de verdade no backend, mas sem
                  // recarregar o grid ao voltar o item exibido na lista
                  // continua o valor antigo em memoria -- reabrir o mesmo
                  // registro reexibia o dado desatualizado.
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => widget.detailScreenBuilder!(item),
                    ),
                  ).then((_) {
                    if (mounted) _loadItems(_currentPage, rowsPerPage);
                  });
                },
              ),
            if (widget.hasPermission('edit') &&
                widget.buttonPermissions['edit']!)
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: () => _openForm(item: item),
              ),
            if (widget.hasPermission('delete') &&
                widget.buttonPermissions['delete']!)
              IconButton(
                icon: const Icon(Icons.delete, size: 20),
                onPressed: () => _deleteItem(
                  _getNestedValue(itemMap, widget.idFieldName).toString(),
                ),
              ),
            ..._customActions
                .where((action) => action.isVisible?.call(item) ?? true)
                .map(
                  (action) => IconButton(
                    icon: Icon(action.icon, size: 20),
                    onPressed: () => action.onPressed(context, item),
                    tooltip: action.label,
                  ),
                ),
          ],
        ),
      ),
    );

    return cells;
  }

  dynamic _getNestedValue(dynamic map, String fieldName) {
    if (map == null) return null;

    // Se não tem ponto, é acesso direto
    if (!fieldName.contains('.')) {
      return map is Map ? map[fieldName] : null;
    }

    final parts = fieldName.split('.');
    dynamic value = map;

    for (final part in parts) {
      if (value == null) return null;

      if (value is Map<dynamic, dynamic>) {
        value = Map<String, dynamic>.from(value)[part];
      } else if (value is Map<String, dynamic>) {
        value = value[part];
      } else if (value is List) {
        final index = int.tryParse(part);
        if (index != null && index >= 0 && index < value.length) {
          value = value[index];
        } else {
          return null;
        }
      } else {
        // PARA OBJETOS DART: tenta métodos específicos sem reflexão
        value = _getObjectProperty(value, part);
        if (value == null) return null;
      }
    }

    return value;
  }

  dynamic _getObjectProperty(dynamic object, String propertyName) {
    if (object == null) return null;

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
    final fixedColumnsCount = widget.fieldConfigs
        .where((c) => _columnVisibility[c.fieldName] == true && c.isFixed)
        .length;

    return Scaffold(
      backgroundColor: GridColors.background,
      appBar: AppBar(
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
              widget.hasPermission('export') &&
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
      ),
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
                        minWidth: 800,
                        wrapInCard: false,
                        headingRowHeight: 32,
                        dataRowHeight: 32,
                        controller: _paginatorController,
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
                          isLoading: isLoading,
                          totalItems: _totalItems,
                          currentPage: _currentPage,
                          rowsPerPage: rowsPerPage,
                          rowIdBuilder: (item, _) {
                            final itemMap = widget.toJson(item);
                            return _getNestedValue(
                              itemMap,
                              widget.idFieldName,
                            ).toString();
                          },
                          onSelect: (index, selected) {
                            setState(() {
                              final itemMap = widget.toJson(filtered[index]);
                              final id = _getNestedValue(
                                itemMap,
                                widget.idFieldName,
                              ).toString();
                              selected
                                  ? selectedRows.add(id)
                                  : selectedRows.remove(id);
                            });
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
                          // pageIndex é o offset (primeira linha da página)
                          // backend espera número da página (base 0)
                          final numeroPagina =
                              rowsPerPage > 0 ? pageIndex ~/ rowsPerPage : 0;
                          // Ignora se já estamos nessa página
                          if (numeroPagina == _currentPage) return;
                          setState(() {
                            _currentPage = numeroPagina;
                          });
                          _loadItems(_currentPage, rowsPerPage);
                        },
                        fixedLeftColumns: widget.fieldConfigs
                            .where(
                              (c) =>
                                  _columnVisibility[c.fieldName] == true &&
                                  c.isFixed,
                            )
                            .length,
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
    this.totalItems = 0,
    this.isLoading = false,
    this.currentPage = 0,
    this.rowsPerPage = 25,
  });

  @override
  DataRow? getRow(int index) {
    // index é absoluto (ex: página 2 com 25 itens/pág → index começa em 25)
    // converte para índice relativo dentro de items (que só tem a página atual)
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
