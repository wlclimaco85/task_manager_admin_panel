import 'package:flutter/material.dart';
import '../../config/api_links.dart';
import '../../core/theme/app_theme.dart';
import '../../services/network_caller.dart';
import 'tela_field_editor_screen.dart';

/// SIS-05 Editor de Telas — grid de telas (`GET ApiLinks.allTelas`) com busca
/// client-side por nome/titulo, card por tela mostrando a contagem de
/// campos, e navegacao para [TelaFieldEditorScreen] ao clicar em "Editar".
///
/// Bespoke (nao reusa [GenericGridScreen]): a acao "Editar" abre um editor
/// de estrutura (campos/colunas da tela), nao um form CRUD de valores de
/// registro — ver RESEARCH.md Item 5 e PLAN.md Task 09.1 desta fase. Porta
/// o comportamento de `task_manager_flutter/lib/web/screens/
/// tela_editor_screen.dart` (`TelaEditorScreen`), adaptado ao design system
/// proprio do admin panel (sem cores hardcoded do cliente).
class TelaEditorScreen extends StatefulWidget {
  const TelaEditorScreen({super.key, this.networkCaller});

  /// Injetavel para testes; quando `null`, a tela cria e fecha sua propria
  /// instancia (mesmo padrao de [GenericGridScreen]).
  final NetworkCaller? networkCaller;

  @override
  State<TelaEditorScreen> createState() => TelaEditorScreenState();
}

class TelaEditorScreenState extends State<TelaEditorScreen> {
  late final NetworkCaller _caller = widget.networkCaller ?? NetworkCaller();

  bool get _ownsCaller => widget.networkCaller == null;

  List<Map<String, dynamic>> _telas = [];
  bool _loading = true;
  String? _errorMessage;
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (_ownsCaller) _caller.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final response = await _caller.getRequest(ApiLinks.allTelas);
    if (!mounted) return;

    if (!response.isSuccess) {
      setState(() {
        _loading = false;
        _errorMessage =
            'Nao foi possivel carregar as telas (codigo ${response.statusCode}).';
      });
      return;
    }

    // Parser tolerante a 3 formatos (mesma logica de GenericGridScreen._load
    // / Task 01.1): `data` lista direta, `data.dados`/`data.content`
    // (paginado), ou `dados` na raiz sem wrapper `data`.
    dynamic data = response.body?['data'] ?? response.body?['dados'] ?? [];
    if (data is Map) {
      data = data['dados'] ?? data['content'] ?? [];
    }
    final telas = (data is List)
        ? data
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    setState(() {
      _telas = telas;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _filtradas {
    if (_searchTerm.isEmpty) return _telas;
    final term = _searchTerm.toLowerCase();
    return _telas.where((t) {
      final nome = t['nome']?.toString().toLowerCase() ?? '';
      final titulo = t['titulo']?.toString().toLowerCase() ?? '';
      return nome.contains(term) || titulo.contains(term);
    }).toList();
  }

  void _abrirEditor(Map<String, dynamic> tela) {
    final id = tela['id'];
    if (id == null) return;
    final nome = tela['nome']?.toString() ?? '';
    final titulo = tela['titulo']?.toString() ?? nome;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TelaFieldEditorScreen(
        telaId: id,
        telaNome: nome,
        telaTitulo: titulo,
        networkCaller: _caller,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editor de Telas'),
        actions: [
          IconButton(
            key: const Key('tela_editor_refresh_button'),
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('tela_editor_search_field'),
              decoration: const InputDecoration(
                labelText: 'Buscar tela',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _searchTerm = v),
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
          child: CircularProgressIndicator(key: Key('tela_editor_loading')));
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!, key: const Key('tela_editor_error_text')),
            const SizedBox(height: AppSpacing.sm),
            ElevatedButton(
                onPressed: _load, child: const Text('Tentar novamente')),
          ],
        ),
      );
    }

    final telas = _filtradas;
    if (telas.isEmpty) {
      return const Center(
        child: Text('Nenhuma tela encontrada.',
            key: Key('tela_editor_empty_state')),
      );
    }

    return ListView.separated(
      key: const Key('tela_editor_list'),
      itemCount: telas.length,
      separatorBuilder: (_, index) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, i) {
        final tela = telas[i];
        final fieldsCount = (tela['fields'] as List?)?.length ?? 0;
        final titulo =
            tela['titulo']?.toString() ?? tela['nome']?.toString() ?? '';
        final nome = tela['nome']?.toString() ?? '';
        return Card(
          key: Key('tela_editor_card_${tela['id']}'),
          child: ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: Text(titulo),
            subtitle: Text(nome),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Chip(label: Text('$fieldsCount campos')),
                const SizedBox(width: AppSpacing.sm),
                ElevatedButton.icon(
                  key: Key('tela_editor_edit_button_${tela['id']}'),
                  onPressed: () => _abrirEditor(tela),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Editar'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
