import 'package:flutter/material.dart';
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
  });

  final String title;
  final List<FieldConfig> fields;
  final String createUrl;

  /// Quando nao-nulo, o formulario esta em modo edicao (PUT nesta URL).
  /// Quando nulo, e criacao (POST em [createUrl]).
  final String? updateUrl;
  final Map<String, dynamic>? initialValues;
  final NetworkCaller? networkCaller;

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

  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    for (final field in widget.fields) {
      final initial = widget.initialValues?[field.key];
      if (field.type == FieldType.boolean) {
        _boolValues[field.key] = initial == true;
      } else {
        _controllers[field.key] =
            TextEditingController(text: initial?.toString() ?? '');
      }
    }
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

    final data = _collectFormData();
    final response = widget.isEditing
        ? await _caller.putRequest(widget.updateUrl!, data)
        : await _caller.postRequest(widget.createUrl, data);

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
}
