import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/query_builder_service.dart';

/// SIS-08 Query Builder — layout de 3 paineis: explorer de schema/tabela em
/// arvore a esquerda, editor SQL no centro, grid de resultados embaixo.
/// Adaptado de `task_manager_flutter/lib/windows/screens/
/// query_builder_window_screen.dart` (ver PLAN.md Fase 2, Task 12.2):
/// - `GridColors` (so existe no cliente) mapeado para `AppColors`/
///   `Theme.of(context)` (ver "Interfaces herdadas" do PLAN.md).
/// - Sem as abas "Nova/Salvar/Carregar query" nem o dialogo de edicao de
///   linha do original — fora do escopo desta fase (ApiLinks desta fase so
///   declara os 4 endpoints de schema/tabela/coluna/executar, nao
///   queries-salvas/atualizar).
/// - Botao "Executar" desabilitado quando o SQL nao comeca com
///   `SELECT`/`WITH` — validacao client-side redundante a do backend
///   (`QueryBuilderServiceImpl.SQL_SOMENTE_LEITURA`), feedback mais rapido
///   ao usuario, nao substitui a defesa server-side (Threat T-02-02).
class QueryBuilderScreen extends StatefulWidget {
  const QueryBuilderScreen({super.key, this.service});

  final QueryBuilderService? service;

  @override
  State<QueryBuilderScreen> createState() => _QueryBuilderScreenState();
}

class _QueryBuilderScreenState extends State<QueryBuilderScreen> {
  late final QueryBuilderService _service =
      widget.service ?? QueryBuilderService();

  final TextEditingController _sqlController = TextEditingController();

  bool _carregandoSchemas = false;
  bool _carregandoTabelas = false;
  bool _carregandoColunas = false;
  bool _executando = false;

  List<Map<String, dynamic>> _schemas = [];
  String? _schemaSelecionado;
  List<Map<String, dynamic>> _tabelas = [];
  String? _tabelaSelecionada;
  List<Map<String, dynamic>> _colunas = [];

  List<Map<String, dynamic>> _colunasResultado = [];
  List<List<dynamic>> _linhasResultado = [];
  String? _mensagemErro;
  int _totalRegistros = 0;

  static final RegExp _somenteLeitura =
      RegExp(r'^\s*(SELECT|WITH)\b', caseSensitive: false);

  bool get _podeExecutar =>
      !_executando && _somenteLeitura.hasMatch(_sqlController.text);

  @override
  void initState() {
    super.initState();
    _sqlController.addListener(() => setState(() {}));
    _carregarSchemas();
  }

  @override
  void dispose() {
    _sqlController.dispose();
    super.dispose();
  }

  Future<void> _carregarSchemas() async {
    setState(() => _carregandoSchemas = true);
    final schemas = await _service.listarSchemas();
    if (!mounted) return;
    setState(() {
      _schemas = schemas;
      _carregandoSchemas = false;
    });
  }

  Future<void> _carregarTabelas(String schema) async {
    setState(() {
      _schemaSelecionado = schema;
      _carregandoTabelas = true;
      _tabelas = [];
      _tabelaSelecionada = null;
      _colunas = [];
    });
    final tabelas = await _service.listarTabelas();
    if (!mounted) return;
    setState(() {
      _tabelas = tabelas
          .where((t) => (t['table_schema']?.toString() ?? '') == schema)
          .toList();
      _carregandoTabelas = false;
    });
  }

  Future<void> _carregarColunas(String tabela) async {
    final schema = _schemaSelecionado;
    if (schema == null) return;
    setState(() {
      _tabelaSelecionada = tabela;
      _carregandoColunas = true;
      _colunas = [];
    });
    final colunas = await _service.listarColunas(schema, tabela);
    if (!mounted) return;
    setState(() {
      _colunas = colunas;
      _carregandoColunas = false;
    });
  }

  Future<void> _executarQuery() async {
    if (!_podeExecutar) return;
    final sql = _sqlController.text.trim();

    setState(() {
      _executando = true;
      _mensagemErro = null;
      _colunasResultado = [];
      _linhasResultado = [];
    });

    final resultado = await _service.executar(sql);

    if (!mounted) return;

    final erro = resultado['erro']?.toString();
    if (erro != null && erro.isNotEmpty) {
      setState(() {
        _mensagemErro = erro;
        _executando = false;
      });
      return;
    }

    final colunas = resultado['colunas'];
    final linhas = resultado['linhas'];
    setState(() {
      _executando = false;
      _totalRegistros = (resultado['totalLinhas'] as num?)?.toInt() ?? 0;
      _colunasResultado = colunas is List
          ? colunas
              .map((c) => c is Map
                  ? Map<String, dynamic>.from(c)
                  : <String, dynamic>{'column_name': c.toString()})
              .toList()
          : [];
      _linhasResultado = linhas is List
          ? linhas.map((l) => l is List ? l : <dynamic>[]).toList()
          : [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;
    return Scaffold(
      appBar: AppBar(title: const Text('Query Builder')),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildExplorer(colors),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildEditor(colors),
                const Divider(height: 1),
                Expanded(child: _buildResultados(colors)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExplorer(AppColors colors) {
    return SizedBox(
      width: 260,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text('Explorer', style: Theme.of(context).textTheme.titleMedium),
          ),
          if (_carregandoSchemas)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: LinearProgressIndicator(),
            ),
          Expanded(
            child: ListView(
              children: [
                for (final schema in _schemas) _buildSchemaTile(schema, colors),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSchemaTile(Map<String, dynamic> schema, AppColors colors) {
    final nome = schema['schema_name']?.toString() ?? '?';
    final selecionado = nome == _schemaSelecionado;
    return ExpansionTile(
      key: ValueKey('schema-$nome'),
      leading: const Icon(Icons.schema),
      title: Text(nome),
      initiallyExpanded: selecionado,
      onExpansionChanged: (expandido) {
        if (expandido) _carregarTabelas(nome);
      },
      children: [
        if (selecionado && _carregandoTabelas)
          const Padding(
            padding: EdgeInsets.only(left: AppSpacing.xl),
            child: LinearProgressIndicator(),
          ),
        if (selecionado)
          for (final tabela in _tabelas) _buildTabelaTile(tabela, colors),
      ],
    );
  }

  Widget _buildTabelaTile(Map<String, dynamic> tabela, AppColors colors) {
    final nome = tabela['table_name']?.toString() ?? '?';
    final selecionada = nome == _tabelaSelecionada;
    return ExpansionTile(
      key: ValueKey('tabela-$nome'),
      leading: const Icon(Icons.table_chart_outlined, size: 18),
      title: Text(nome, style: const TextStyle(fontSize: 13)),
      onExpansionChanged: (expandido) {
        if (expandido) _carregarColunas(nome);
      },
      children: [
        if (selecionada && _carregandoColunas)
          const Padding(
            padding: EdgeInsets.only(left: AppSpacing.xl),
            child: LinearProgressIndicator(),
          ),
        if (selecionada)
          for (final coluna in _colunas)
            ListTile(
              dense: true,
              leading: Icon(
                coluna['is_pk'] == true ? Icons.vpn_key : Icons.arrow_right,
                size: 14,
                color: coluna['is_pk'] == true ? colors.warning : null,
              ),
              title: Text(
                coluna['column_name']?.toString() ?? '?',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              subtitle: Text(coluna['data_type']?.toString() ?? ''),
            ),
      ],
    );
  }

  Widget _buildEditor(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('query_builder_sql_field'),
            controller: _sqlController,
            maxLines: 6,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Digite sua consulta SQL aqui...\nEx: SELECT * FROM login',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              ElevatedButton.icon(
                key: const Key('query_builder_executar_button'),
                onPressed: _podeExecutar ? _executarQuery : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Executar'),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (!_somenteLeitura.hasMatch(_sqlController.text) &&
                  _sqlController.text.trim().isNotEmpty)
                Flexible(
                  child: Text(
                    'Apenas SELECT/WITH são permitidos',
                    style: TextStyle(color: colors.error, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const Spacer(),
              if (_totalRegistros > 0)
                Text('$_totalRegistros registro(s)'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultados(AppColors colors) {
    if (_executando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_mensagemErro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SelectableText(
            _mensagemErro!,
            style: TextStyle(color: colors.error),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_colunasResultado.isEmpty) {
      return const Center(child: Text('Nenhum resultado'));
    }
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            for (final col in _colunasResultado)
              DataColumn(label: Text(col['column_name']?.toString() ?? '?')),
          ],
          rows: [
            for (final linha in _linhasResultado)
              DataRow(
                cells: [
                  for (final valor in linha)
                    DataCell(Text(valor?.toString() ?? 'null')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
