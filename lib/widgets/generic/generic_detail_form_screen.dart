import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../services/network_caller.dart';
import 'field_config.dart';

/// Formulario generico de criacao/edicao, dirigido por [FieldConfig].
/// Base reutilizavel para os modulos das proximas fases — ver RESEARCH.md
/// da Fase 1 para o racional de manter este par (grid+form) enxuto e
/// crescer sob demanda em vez de portar o widget legado de ~2000 linhas do
/// app cliente de uma vez.
class GenericDetailFormScreen extends StatefulWidget {
  const GenericDetailFormScreen({
    super.key,
    required this.title,
    required this.fields,
    required this.createUrl,
    this.updateUrl,
    this.initialValues,
    this.networkCaller,
    this.transformPayload,
  });

  final String title;
  final List<FieldConfig> fields;
  final String createUrl;

  /// Quando nao-nulo, o formulario esta em modo edicao (PUT nesta URL).
  /// Quando nulo, e criacao (POST em [createUrl]).
  final String? updateUrl;
  final Map<String, dynamic>? initialValues;
  final NetworkCaller? networkCaller;

  /// Aplicado ao payload logo apos `_collectFormData()`, antes do
  /// POST/PUT — permite adaptar o payload por endpoint (ex. aninhar FKs
  /// planas em `{id:...}`, ou payload assimetrico por verbo, ver
  /// `_transformChamadoPayload` na Fase 3 Task 05.1). Quando `null`, o
  /// payload coletado segue sem alteracao.
  final Map<String, dynamic> Function(Map<String, dynamic> raw, bool isEditing)?
      transformPayload;

  bool get isEditing => updateUrl != null;

  @override
  State<GenericDetailFormScreen> createState() =>
      GenericDetailFormScreenState();
}

class GenericDetailFormScreenState extends State<GenericDetailFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final NetworkCaller _caller = widget.networkCaller ?? NetworkCaller();
  bool get _ownsCaller => widget.networkCaller == null;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _boolValues = {};
  final Map<String, DateTime?> _dateValues = {};
  final Map<String, dynamic> _dropdownValues = {};
  final Map<String, List<DropdownOption>> _loadedOptions = {};
  final Set<String> _loadingOptionKeys = {};

  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    for (final field in widget.fields) {
      final initial = widget.initialValues?[field.key];
      if (field.type == FieldType.boolean) {
        _boolValues[field.key] = initial == true;
      } else if (field.type == FieldType.date) {
        _dateValues[field.key] = DateTime.tryParse(initial?.toString() ?? '');
      } else if (field.type == FieldType.dropdown) {
        _dropdownValues[field.key] =
            initial is Map ? initial['id'] : initial;
        final loader = field.optionsLoader;
        if (loader != null) {
          _loadOptions(field.key, loader);
        }
      } else {
        _controllers[field.key] =
            TextEditingController(text: initial?.toString() ?? '');
      }
    }
  }

  Future<void> _loadOptions(
    String key,
    Future<List<DropdownOption>> Function(NetworkCaller) loader,
  ) async {
    setState(() => _loadingOptionKeys.add(key));
    final options = await loader(_caller);
    if (!mounted) return;
    setState(() {
      _loadedOptions[key] = options;
      _loadingOptionKeys.remove(key);
    });
  }

  @override
  void dispose() {
    if (_ownsCaller) _caller.close();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _collectFormData() {
    final data = <String, dynamic>{};
    for (final field in widget.fields) {
      if (field.type == FieldType.boolean) {
        data[field.key] = _boolValues[field.key] ?? false;
      } else if (field.type == FieldType.number) {
        final text = _controllers[field.key]!.text.trim();
        data[field.key] = text.isEmpty ? null : num.tryParse(text);
      } else if (field.type == FieldType.date) {
        final date = _dateValues[field.key];
        if (date == null) {
          data[field.key] = null;
        } else {
          final formatted = DateFormat('yyyy-MM-dd').format(date);
          data[field.key] = field.dateTime ? '${formatted}T00:00:00' : formatted;
        }
      } else if (field.type == FieldType.dropdown) {
        data[field.key] = _dropdownValues[field.key];
      } else {
        data[field.key] = _controllers[field.key]!.text.trim();
      }
    }
    return data;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    final collected = _collectFormData();
    final payload =
        widget.transformPayload?.call(collected, widget.isEditing) ??
            collected;
    final response = widget.isEditing
        ? await _caller.putRequest(widget.updateUrl!, payload)
        : await _caller.postRequest(widget.createUrl, payload);

    if (!mounted) return;

    setState(() => _saving = false);

    if (response.isSuccess) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _errorMessage =
          'Nao foi possivel salvar (codigo ${response.statusCode}).');
    }
  }

  String? _validate(FieldConfig field, String? value) {
    if (field.required && (value == null || value.trim().isEmpty)) {
      return '${field.label} e obrigatorio.';
    }
    return field.validator?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing
            ? 'Editar ${widget.title}'
            : 'Novo(a) ${widget.title}'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            for (final field in widget.fields) ...[
              _buildField(field),
              const SizedBox(height: AppSpacing.md),
            ],
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  _errorMessage!,
                  key: const Key('form_error_text'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ElevatedButton(
              key: const Key('form_submit_button'),
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(FieldConfig field) {
    if (field.type == FieldType.boolean) {
      return SwitchListTile(
        key: Key('form_field_${field.key}'),
        title: Text(field.label),
        value: _boolValues[field.key] ?? false,
        onChanged: (v) => setState(() => _boolValues[field.key] = v),
      );
    }

    if (field.type == FieldType.date) {
      return _buildDateField(field);
    }

    if (field.type == FieldType.dropdown) {
      return _buildDropdownField(field);
    }

    return TextFormField(
      key: Key('form_field_${field.key}'),
      controller: _controllers[field.key],
      maxLines: field.type == FieldType.multiline ? 4 : 1,
      keyboardType: field.type == FieldType.number
          ? TextInputType.number
          : field.type == FieldType.email
              ? TextInputType.emailAddress
              : TextInputType.text,
      decoration: InputDecoration(
        labelText: field.required ? '${field.label} *' : field.label,
      ),
      validator: (value) => _validate(field, value),
    );
  }

  Widget _buildDateField(FieldConfig field) {
    final date = _dateValues[field.key];
    final text = date == null ? 'Selecionar data' : DateFormat('dd/MM/yyyy').format(date);
    return InkWell(
      key: Key('form_field_${field.key}'),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(1900),
          lastDate: DateTime(2100),
        );
        if (picked != null) {
          setState(() => _dateValues[field.key] = picked);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: field.required ? '${field.label} *' : field.label,
        ),
        child: Text(text),
      ),
    );
  }

  Widget _buildDropdownField(FieldConfig field) {
    if (_loadingOptionKeys.contains(field.key)) {
      return Padding(
        key: Key('form_field_${field.key}'),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(field.required ? '${field.label} *' : field.label),
            const SizedBox(height: AppSpacing.sm),
            const LinearProgressIndicator(),
          ],
        ),
      );
    }

    final options = field.options ?? _loadedOptions[field.key] ?? [];
    return DropdownButtonFormField<dynamic>(
      key: Key('form_field_${field.key}'),
      initialValue: _dropdownValues[field.key],
      decoration: InputDecoration(
        labelText: field.required ? '${field.label} *' : field.label,
      ),
      items: [
        if (!field.required)
          const DropdownMenuItem<dynamic>(value: null, child: Text('Nenhum')),
        ...options.map(
          (o) => DropdownMenuItem<dynamic>(value: o.value, child: Text(o.label)),
        ),
      ],
      onChanged: (value) => setState(() => _dropdownValues[field.key] = value),
      validator: (value) {
        if (field.required && value == null) {
          return '${field.label} e obrigatorio.';
        }
        return null;
      },
    );
  }
}
