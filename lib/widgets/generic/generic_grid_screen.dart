import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/network_caller.dart';
import 'field_config.dart';
import 'generic_detail_form_screen.dart';

/// Grid generico e reutilizavel, base para os modulos das Fases 2-5
/// (migracao do menu "Sistema", Contatos, Ordem de Servico, Modulos
/// contratados etc). Busca a lista no backend via [NetworkCaller], exibe em
/// tabela paginavel localmente, e abre [GenericDetailFormScreen] para
/// criar/editar cada registro.
///
/// Escopo da Fase 1: suficiente para provar o padrao grid+form+detail
/// ponta-a-ponta contra o backend real. Recursos do widget legado do
/// cliente (busca remota debounced, upload de arquivo, dropdown
/// relacionado etc.) entram incrementalmente nas fases seguintes, quando
/// algum modulo realmente precisar — ver RESEARCH.md da Fase 1.
class GenericGridScreen extends StatefulWidget {
  const GenericGridScreen({
    super.key,
    required this.title,
    required this.listUrl,
    required this.createUrl,
    required this.updateUrl,
    required this.deleteUrl,
    required this.fields,
    this.networkCaller,
    this.rowsPerPage = 10,
  });

  final String title;
  final String listUrl;
  final String createUrl;
  final String Function(String id) updateUrl;
  final String Function(String id) deleteUrl;
  final List<FieldConfig> fields;
  final NetworkCaller? networkCaller;
  final int rowsPerPage;

  @override
  State<GenericGridScreen> createState() => GenericGridScreenState();
}

class GenericGridScreenState extends State<GenericGridScreen> {
  late final NetworkCaller _caller = widget.networkCaller ?? NetworkCaller();

  List<Map<String, dynamic>> _allRows = [];
  List<Map<String, dynamic>> _filteredRows = [];
  bool _loading = true;
  String? _errorMessage;
  String _searchTerm = '';
  int _page = 0;

  List<FieldConfig> get _gridFields =>
      widget.fields.where((f) => f.showInGrid).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final response = await _caller.getRequest(widget.listUrl);

    if (!mounted) return;

    if (!response.isSuccess) {
      setState(() {
        _loading = false;
        _errorMessage =
            'Nao foi possivel carregar os dados (codigo ${response.statusCode}).';
      });
      return;
    }

    final data = response.body?['data'] ?? response.body?['dados'] ?? [];
    final rows = (data is List)
        ? data
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    setState(() {
      _allRows = rows;
      _applyFilter();
      _loading = false;
    });
  }

  void _applyFilter() {
    if (_searchTerm.isEmpty) {
      _filteredRows = _allRows;
    } else {
      final term = _searchTerm.toLowerCase();
      _filteredRows = _allRows.where((row) {
        return _gridFields.any((field) {
          final value = row[field.key]?.toString().toLowerCase() ?? '';
          return value.contains(term);
        });
      }).toList();
    }
    _page = 0;
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchTerm = value;
      _applyFilter();
    });
  }

  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GenericDetailFormScreen(
          title: widget.title,
          fields: widget.fields,
          initialValues: existing,
          createUrl: widget.createUrl,
          updateUrl: existing != null && existing['id'] != null
              ? widget.updateUrl(existing['id'].toString())
              : null,
          networkCaller: _caller,
        ),
      ),
    );
    if (saved == true) {
      await _load();
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar exclusao'),
        content: const Text('Deseja realmente excluir este registro?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final response = await _caller.deleteRequest(widget.deleteUrl(id));
    if (!mounted) return;

    if (response.isSuccess) {
      await _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Falha ao excluir (codigo ${response.statusCode}).')),
      );
    }
  }

  List<Map<String, dynamic>> get _pageRows {
    final start = _page * widget.rowsPerPage;
    if (start >= _filteredRows.length) return [];
    final end = (start + widget.rowsPerPage).clamp(0, _filteredRows.length);
    return _filteredRows.sublist(start, end);
  }

  int get _pageCount =>
      (_filteredRows.length / widget.rowsPerPage).ceil().clamp(1, 999999);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            key: const Key('grid_refresh_button'),
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('grid_add_button'),
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('grid_search_field'),
              decoration: const InputDecoration(
                labelText: 'Buscar',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(key: Key('grid_loading')));
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!, key: const Key('grid_error_text')),
            const SizedBox(height: AppSpacing.sm),
            ElevatedButton(onPressed: _load, child: const Text('Tentar novamente')),
          ],
        ),
      );
    }

    if (_filteredRows.isEmpty) {
      return const Center(
        child: Text('Nenhum registro encontrado.', key: Key('grid_empty_state')),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                key: const Key('grid_data_table'),
                columns: [
                  ..._gridFields.map((f) => DataColumn(label: Text(f.label))),
                  const DataColumn(label: Text('Acoes')),
                ],
                rows: _pageRows
                    .map((row) => DataRow(cells: [
                          ..._gridFields.map(
                            (f) => DataCell(Text(row[f.key]?.toString() ?? '')),
                          ),
                          DataCell(Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                onPressed: () => _openForm(existing: row),
                                tooltip: 'Editar',
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18),
                                onPressed: () => _delete(row),
                                tooltip: 'Excluir',
                              ),
                            ],
                          )),
                        ]))
                    .toList(),
              ),
            ),
          ),
        ),
        if (_pageCount > 1)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _page > 0 ? () => setState(() => _page--) : null,
                ),
                Text('Pagina ${_page + 1} de $_pageCount'),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _page < _pageCount - 1
                      ? () => setState(() => _page++)
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
