import 'dart:convert';

import 'package:flutter/material.dart';
import '../../config/api_links.dart';
import '../../core/theme/app_theme.dart';
import '../../services/network_caller.dart';

/// SIS-05 Editor de Telas — editor de campos de uma tela (2 paineis):
/// esquerda lista os campos em [ReorderableListView] (drag dispara
/// `PUT ApiLinks.reorderTelaFields`), direita edita as propriedades do
/// campo selecionado (secoes Identificacao/Tipo/Visibilidade/
/// Comportamento/Payload, salvando via `PUT ApiLinks.updateTelaField`).
///
/// Porta o comportamento de `_FieldEditorScreen`/`_FieldPropertiesPanel` de
/// `task_manager_flutter/lib/web/screens/tela_editor_screen.dart`, adaptado
/// ao design system proprio do admin panel — ver PLAN.md Task 09.2.
///
/// NOTA (achado desta execucao, nao um debito de codigo): o backend
/// (`TelaController`, `AppAcademia`) hoje so expoe `GET /api/telas` e
/// `GET /api/telas/{nome}` — os endpoints `PUT /api/telas/{telaId}/fields/
/// reorder` e `PUT /api/telas/{telaId}/fields/{fieldId}` referenciados por
/// `ApiLinks` (Wave 1, Task 01.2) ainda nao existem no backend. Esta tela
/// implementa o contrato ja definido pelo `ApiLinks`; falha de rede
/// (404/erro) e tratada e exibida ao usuario, nao trava a UI. Reportar ao
/// dono do backend antes de considerar a Fase 2 pronta ponta-a-ponta.
class TelaFieldEditorScreen extends StatefulWidget {
  const TelaFieldEditorScreen({
    super.key,
    required this.telaId,
    required this.telaNome,
    required this.telaTitulo,
    this.networkCaller,
  });

  final dynamic telaId;
  final String telaNome;
  final String telaTitulo;
  final NetworkCaller? networkCaller;

  @override
  State<TelaFieldEditorScreen> createState() => TelaFieldEditorScreenState();
}

class TelaFieldEditorScreenState extends State<TelaFieldEditorScreen> {
  late final NetworkCaller _caller = widget.networkCaller ?? NetworkCaller();

  bool get _ownsCaller => widget.networkCaller == null;

  List<Map<String, dynamic>> _fields = [];
  bool _loading = true;
  String? _errorMessage;
  Map<String, dynamic>? _selectedField;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    if (_ownsCaller) _caller.close();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final response = await _caller.getRequest(ApiLinks.telaByNome(widget.telaNome));
    if (!mounted) return;

    if (!response.isSuccess) {
      setState(() {
        _loading = false;
        _errorMessage =
            'Nao foi possivel carregar os campos da tela (codigo ${response.statusCode}).';
      });
      return;
    }

    final rawFields = response.body?['fields'] as List? ?? [];
    final fields = rawFields
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList()
      ..sort((a, b) =>
          ((a['fieldOrder'] as num?) ?? 0).compareTo((b['fieldOrder'] as num?) ?? 0));

    setState(() {
      _fields = fields;
      _loading = false;
    });
  }

  Future<void> _reordenar(int oldIndex, int newIndex) async {
    setState(() {
      final item = _fields.removeAt(oldIndex);
      _fields.insert(newIndex, item);
      for (var i = 0; i < _fields.length; i++) {
        _fields[i] = {..._fields[i], 'fieldOrder': i + 1};
      }
    });

    final orders = _fields
        .asMap()
        .entries
        .map((e) => {'id': e.value['id'], 'fieldOrder': e.key + 1})
        .toList();

    // NetworkCaller.putRequest exige body Map<String,dynamic> (contrato
    // compartilhado com o resto do app) — o array de ordens vai dentro da
    // chave `fields`, unica adaptacao necessaria para caber no wrapper
    // existente (nao ha PUT com body de lista crua na infra atual e este
    // plano nao pode alterar network_caller.dart). Ver nota de classe sobre
    // o endpoint de backend ainda nao existir.
    final response = await _caller.putRequest(
      ApiLinks.reorderTelaFields(widget.telaId.toString()),
      {'fields': orders},
    );
    if (!mounted) return;

    if (!response.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Falha ao salvar nova ordem (codigo ${response.statusCode}).'),
        ),
      );
    }
  }

  Future<void> _salvarCampo(Map<String, dynamic> field) async {
    final fieldId = field['id'];
    if (fieldId == null) return;

    setState(() => _saving = true);
    final response = await _caller.putRequest(
      ApiLinks.updateTelaField(widget.telaId.toString(), fieldId.toString()),
      field,
    );
    if (!mounted) return;

    setState(() => _saving = false);

    if (response.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Campo salvo!')),
      );
      await _carregar();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar (codigo ${response.statusCode}).')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Editar: ${widget.telaTitulo}')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(key: Key('field_editor_loading')))
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_errorMessage!, key: const Key('field_editor_error_text')),
                      const SizedBox(height: AppSpacing.sm),
                      ElevatedButton(
                          onPressed: _carregar,
                          child: const Text('Tentar novamente')),
                    ],
                  ),
                )
              : Row(
                  children: [
                    SizedBox(
                      width: 300,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Row(
                              children: [
                                const Icon(Icons.list, size: 16),
                                const SizedBox(width: AppSpacing.sm),
                                Text('${_fields.length} campos'),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ReorderableListView.builder(
                              key: const Key('field_editor_reorderable_list'),
                              itemCount: _fields.length,
                              onReorderItem: _reordenar,
                              itemBuilder: (_, i) {
                                final f = _fields[i];
                                final isSelected = _selectedField?['id'] == f['id'];
                                return _FieldListItem(
                                  key: ValueKey(f['id'] ?? i),
                                  field: f,
                                  isSelected: isSelected,
                                  onTap: () =>
                                      setState(() => _selectedField = Map.from(f)),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _selectedField == null
                          ? const Center(
                              child: Text(
                                'Selecione um campo para editar',
                                key: Key('field_editor_no_selection'),
                              ),
                            )
                          : _FieldPropertiesPanel(
                              key: ValueKey(_selectedField!['id']),
                              field: _selectedField!,
                              saving: _saving,
                              onChanged: (updated) =>
                                  setState(() => _selectedField = updated),
                              onSave: () => _salvarCampo(_selectedField!),
                            ),
                    ),
                  ],
                ),
    );
  }
}

class _FieldListItem extends StatelessWidget {
  const _FieldListItem({
    super.key,
    required this.field,
    required this.isSelected,
    required this.onTap,
  });

  final Map<String, dynamic> field;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final type = field['fieldType']?.toString() ?? 'text';
    final enabled = field['enabled'] != false;
    final inForm = field['isInForm'] != false;
    return ListTile(
      key: Key('field_editor_item_${field['id']}'),
      selected: isSelected,
      onTap: onTap,
      leading: Icon(_typeIcon(type), size: 18),
      title: Text(field['label']?.toString() ?? field['fieldName']?.toString() ?? ''),
      subtitle: Text(field['fieldName']?.toString() ?? ''),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!inForm) const Icon(Icons.visibility_off, size: 14),
          if (!enabled) const Icon(Icons.lock, size: 14),
          if (field['isRequired'] == true) const Icon(Icons.star, size: 12),
        ],
      ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'dropdown':
        return Icons.arrow_drop_down_circle;
      case 'multiselect':
        return Icons.checklist;
      case 'boolean':
        return Icons.toggle_on;
      case 'date':
        return Icons.calendar_today;
      case 'number':
        return Icons.numbers;
      case 'email':
        return Icons.email;
      case 'password':
        return Icons.lock;
      case 'phone':
        return Icons.phone;
      case 'currency':
        return Icons.attach_money;
      case 'multiline':
        return Icons.notes;
      case 'file':
        return Icons.attach_file;
      default:
        return Icons.text_fields;
    }
  }
}

class _FieldPropertiesPanel extends StatefulWidget {
  const _FieldPropertiesPanel({
    super.key,
    required this.field,
    required this.saving,
    required this.onChanged,
    required this.onSave,
  });

  final Map<String, dynamic> field;
  final bool saving;
  final void Function(Map<String, dynamic>) onChanged;
  final VoidCallback onSave;

  @override
  State<_FieldPropertiesPanel> createState() => _FieldPropertiesPanelState();
}

class _FieldPropertiesPanelState extends State<_FieldPropertiesPanel> {
  late Map<String, dynamic> _f;
  late TextEditingController _labelCtrl;
  late TextEditingController _fieldNameCtrl;
  late TextEditingController _displayFieldCtrl;
  late TextEditingController _dropdownEndpointCtrl;
  late TextEditingController _maxLinesCtrl;
  late TextEditingController _fieldOrderCtrl;
  late TextEditingController _maskCtrl;
  late TextEditingController _defaultValueCtrl;

  static const _fieldTypes = [
    'text', 'number', 'email', 'date', 'multiline', 'dropdown',
    'multiselect', 'boolean', 'file', 'password', 'phone', 'cpf',
    'cnpj', 'currency', 'percentage', 'url',
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(_FieldPropertiesPanel old) {
    super.didUpdateWidget(old);
    if (old.field['id'] != widget.field['id']) _init();
  }

  void _init() {
    _f = Map.from(widget.field);
    _labelCtrl = TextEditingController(text: _f['label']?.toString() ?? '');
    _fieldNameCtrl = TextEditingController(text: _f['fieldName']?.toString() ?? '');
    _displayFieldCtrl =
        TextEditingController(text: _f['displayFieldName']?.toString() ?? '');
    _dropdownEndpointCtrl =
        TextEditingController(text: _f['dropdownEndpoint']?.toString() ?? '');
    _maxLinesCtrl = TextEditingController(text: _f['maxLines']?.toString() ?? '1');
    _fieldOrderCtrl = TextEditingController(text: _f['fieldOrder']?.toString() ?? '0');
    _maskCtrl = TextEditingController(text: _f['mask']?.toString() ?? '');
    final dv = _f['defaultValue'];
    _defaultValueCtrl = TextEditingController(
      text: dv == null ? '' : (dv is String ? dv : jsonEncode(dv)),
    );
  }

  void _update(String key, dynamic value) {
    setState(() => _f[key] = value);
    widget.onChanged(_f);
  }

  /// Converte o texto digitado em "Valor Fixo (Payload)" para o tipo mais
  /// adequado: JSON (objeto/lista) se comecar com `{`/`[`, bool, num, ou
  /// String literal (inclui os templates `{{now+Nd}}` / `{{campo:xxx}}`).
  /// Portado verbatim de `tela_editor_screen.dart` (cliente) — nao
  /// reinventar (ver PLAN.md Task 09.2).
  void _updateDefaultValue(String text) {
    if (text.isEmpty) {
      _update('defaultValue', null);
      return;
    }
    if (text.startsWith('{{') || (!text.startsWith('{') && !text.startsWith('['))) {
      if (text == 'true' || text == 'false') {
        _update('defaultValue', text == 'true');
        return;
      }
      final asNum = num.tryParse(text);
      if (asNum != null) {
        _update('defaultValue', asNum);
        return;
      }
      _update('defaultValue', text);
      return;
    }
    try {
      _update('defaultValue', jsonDecode(text));
    } catch (_) {
      _update('defaultValue', text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.settings, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Propriedades: ${_f['fieldName'] ?? ''}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ElevatedButton.icon(
                key: const Key('field_editor_save_button'),
                onPressed: widget.saving ? null : widget.onSave,
                icon: widget.saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save, size: 16),
                label: Text(widget.saving ? 'Salvando...' : 'Salvar'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          _section('Identificação'),
          _textField('Label (exibição)', _labelCtrl, (v) => _update('label', v)),
          _textField(
              'Field Name (código)', _fieldNameCtrl, (v) => _update('fieldName', v)),
          _textField('Display Field Name', _displayFieldCtrl,
              (v) => _update('displayFieldName', v)),
          _numberField('Ordem no Form', _fieldOrderCtrl,
              (v) => _update('fieldOrder', int.tryParse(v) ?? 0)),

          _section('Tipo do Campo'),
          _dropdown('Tipo', _f['fieldType']?.toString() ?? 'text', _fieldTypes,
              (v) => _update('fieldType', v)),
          if (_f['fieldType'] == 'multiline')
            _numberField('Máx. Linhas', _maxLinesCtrl,
                (v) => _update('maxLines', int.tryParse(v) ?? 1)),
          if (_f['fieldType'] == 'dropdown' || _f['fieldType'] == 'multiselect')
            _textField('Endpoint Dropdown', _dropdownEndpointCtrl,
                (v) => _update('dropdownEndpoint', v)),
          _textField('Máscara (ex: ##/##/####)', _maskCtrl, (v) => _update('mask', v)),

          _section('Visibilidade'),
          _switch('Visível no Form', _f['isInForm'] != false,
              (v) => _update('isInForm', v)),
          _switch('Visível na Grid', _f['isVisibleByDefault'] != false,
              (v) => _update('isVisibleByDefault', v)),
          _switch('Filtrável', _f['isFilterable'] != false,
              (v) => _update('isFilterable', v)),
          _switch('Ordenável', _f['isSortable'] != false,
              (v) => _update('isSortable', v)),
          _switch('Mostrar no Insert', _f['showInInsert'] != false,
              (v) => _update('showInInsert', v)),
          _switch('Mostrar no Update', _f['showInUpdate'] != false,
              (v) => _update('showInUpdate', v)),

          _section('Comportamento'),
          _switch('Obrigatório', _f['isRequired'] == true,
              (v) => _update('isRequired', v)),
          _switch('Habilitado (editável)', _f['enabled'] != false,
              (v) => _update('enabled', v)),
          _switch('Fixo (não ocultar)', _f['isFixed'] == true,
              (v) => _update('isFixed', v)),
          _switch('Multi-select', _f['multiSelect'] == true,
              (v) => _update('multiSelect', v)),

          _section('Payload'),
          _textField('Valor Fixo (Payload)', _defaultValueCtrl, _updateDefaultValue,
              key: const Key('field_editor_default_value_field')),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              'Enviado no salvar mesmo com o campo oculto do form '
              '(Visível no Form = desligado). Aceita texto, número, true/false, '
              'JSON ({"id": 1}) ou os templates {{now+Nd}} e {{campo:xxx}}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
        child: Text(title, style: Theme.of(context).textTheme.labelLarge),
      );

  Widget _textField(String label, TextEditingController ctrl, void Function(String) onChanged,
          {Key? key}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: TextFormField(
          key: key,
          controller: ctrl,
          onChanged: onChanged,
          decoration: InputDecoration(labelText: label),
        ),
      );

  Widget _numberField(String label, TextEditingController ctrl, void Function(String) onChanged) =>
      _textField(label, ctrl, onChanged);

  Widget _dropdown(
          String label, String value, List<String> options, void Function(String?) onChanged) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: DropdownButtonFormField<String>(
          key: const Key('field_editor_type_dropdown'),
          initialValue: options.contains(value) ? value : options.first,
          decoration: InputDecoration(labelText: label),
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: onChanged,
        ),
      );

  Widget _switch(String label, bool value, void Function(bool) onChanged) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: SwitchListTile(
          key: Key('field_editor_switch_$label'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: value,
          onChanged: onChanged,
        ),
      );
}
