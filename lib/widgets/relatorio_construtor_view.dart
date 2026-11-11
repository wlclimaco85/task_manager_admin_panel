import 'package:flutter/material.dart';

import '../services/dashboard_personalizado_service.dart' show DashFiltro;
import '../services/relatorio_personalizado_service.dart';
import '../utils/app_logger.dart';
import 'dashboard_componente_view.dart';
import 'relatorio_designer_view.dart';
import 'package:file_saver/file_saver.dart';

const _formatos = ['TEXTO', 'NUMERO', 'MOEDA', 'PERCENTUAL', 'DATA'];
const _tiposFiltro = ['TEXTO', 'INTEIRO', 'DECIMAL', 'DATA', 'LOGICO'];

/// Construtor de Relatórios PDF (plataforma low-code, F7, modo simples): o MASTER escreve o SQL (SELECT com
/// :empresaId), declara os filtros e ajusta o layout (orientação, rótulos, formatos, totais e agrupamento).
/// "Testar" mostra a prévia e "Carregar colunas" preenche a configuração a partir do SQL. Somente MASTER.
class RelatorioConstrutorView extends StatefulWidget {
  final RelatorioPersonalizadoService? servico;

  /// Entrega o PDF da previa ao usuario (padrao: FileSaver; injetavel para teste).
  final Future<void> Function(PdfRelatorio pdf)? salvar;

  const RelatorioConstrutorView({super.key, this.servico, this.salvar});

  @override
  State<RelatorioConstrutorView> createState() => _RelatorioConstrutorViewState();
}

class _RelatorioConstrutorViewState extends State<RelatorioConstrutorView> {
  late final RelatorioPersonalizadoService _svc = widget.servico ?? RelatorioPersonalizadoService();
  List<RelatorioPersonalizado> _lista = const [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  void _aviso(String t, {bool erro = false}) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(t), backgroundColor: erro ? Colors.red.shade700 : null));
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final l = await _svc.todos();
      if (mounted) setState(() => _lista = l);
    } catch (e) {
      AppLogger.i.warn('RelatorioConstrutorView: erro ao listar: $e');
      if (mounted) setState(() => _erro = '$e');
    }
    if (mounted) setState(() => _carregando = false);
  }

  Future<void> _editar([RelatorioPersonalizado? atual]) async {
    RelatorioPersonalizado? base = atual;
    if (atual?.id != null) {
      try {
        base = await _svc.buscarComSql(atual!.id!);
      } catch (e) {
        AppLogger.i.warn('RelatorioConstrutorView: erro ao abrir para edicao: $e');
        _aviso('$e', erro: true);
        return;
      }
    }
    if (!mounted) return;
    final editado = await showDialog<RelatorioPersonalizado>(
      context: context,
      builder: (_) => _RelatorioDialog(atual: base, servico: _svc, salvar: widget.salvar),
    );
    if (editado == null) return;
    try {
      await _svc.salvar(editado);
      _aviso('Relatório salvo.');
      await _carregar();
    } catch (e) {
      AppLogger.i.warn('RelatorioConstrutorView: erro ao salvar: $e');
      _aviso('$e', erro: true);
    }
  }

  Future<void> _excluir(RelatorioPersonalizado r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir relatório'),
        content: Text('Excluir "${r.titulo}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _svc.excluir(r.id!);
      await _carregar();
    } catch (e) {
      AppLogger.i.warn('RelatorioConstrutorView: erro ao excluir: $e');
      _aviso('$e', erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Expanded(child: Text('Construtor de Relatórios', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          IconButton(tooltip: 'Atualizar', onPressed: _carregar, icon: const Icon(Icons.refresh)),
          FilledButton.icon(onPressed: () => _editar(), icon: const Icon(Icons.add), label: const Text('Novo relatório')),
        ]),
      ),
      Expanded(
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
                ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_erro!)))
                : _lista.isEmpty
                    ? const Center(child: Text('Nenhum relatório criado ainda.'))
                    : ListView.separated(
                        itemCount: _lista.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final r = _lista[i];
                          return ListTile(
                            minVerticalPadding: 10,
                            leading: const Icon(Icons.picture_as_pdf_outlined),
                            title: Text(r.titulo),
                            subtitle: Text('${r.grupo ?? 'Sem grupo'}${r.ativo ? '' : ' · inativo'}'),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(tooltip: 'Editar', onPressed: () => _editar(r), icon: const Icon(Icons.edit_outlined)),
                              IconButton(tooltip: 'Excluir', onPressed: () => _excluir(r), icon: const Icon(Icons.delete_outline)),
                            ]),
                          );
                        }),
      ),
    ]);
  }
}

class _ColEdit {
  final String nome;
  final TextEditingController rotulo;
  String formato;
  bool total;

  _ColEdit(this.nome, this.rotulo, this.formato, this.total);

  factory _ColEdit.de(RelColuna c) => _ColEdit(c.nome, TextEditingController(text: c.rotulo), c.formato, c.total);

  void dispose() => rotulo.dispose();
}

class _FiltroEdit {
  final TextEditingController nome;
  final TextEditingController descricao;
  final TextEditingController padrao;
  String tipo;

  _FiltroEdit(this.nome, this.descricao, this.padrao, this.tipo);

  factory _FiltroEdit.vazio() => _FiltroEdit(TextEditingController(), TextEditingController(), TextEditingController(), 'TEXTO');

  factory _FiltroEdit.de(DashFiltro f) => _FiltroEdit(TextEditingController(text: f.nome),
      TextEditingController(text: f.descricao), TextEditingController(text: f.padrao ?? ''), f.tipo);

  void dispose() {
    nome.dispose();
    descricao.dispose();
    padrao.dispose();
  }
}

class _RelatorioDialog extends StatefulWidget {
  final RelatorioPersonalizado? atual;
  final RelatorioPersonalizadoService servico;
  final Future<void> Function(PdfRelatorio pdf)? salvar;

  const _RelatorioDialog({required this.atual, required this.servico, this.salvar});

  @override
  State<_RelatorioDialog> createState() => _RelatorioDialogState();
}

class _RelatorioDialogState extends State<_RelatorioDialog> {
  final _form = GlobalKey<FormState>();
  late final _titulo = TextEditingController(text: widget.atual?.titulo ?? '');
  late final _grupo = TextEditingController(text: widget.atual?.grupo ?? '');
  late final _descricao = TextEditingController(text: widget.atual?.descricao ?? '');
  late final _sql = TextEditingController(text: widget.atual?.sql ?? '');
  late final _subtitulo = TextEditingController(text: widget.atual?.config.subtitulo ?? '');
  late final _rodape = TextEditingController(text: widget.atual?.config.rodape ?? '');
  late bool _ativo = widget.atual?.ativo ?? true;
  late String _orientacao = widget.atual?.config.orientacao ?? 'RETRATO';
  late String? _agruparPor = widget.atual?.config.agruparPor;
  late final List<_ColEdit> _colunas = [for (final c in widget.atual?.config.colunas ?? const <RelColuna>[]) _ColEdit.de(c)];
  late final List<_FiltroEdit> _filtros = [for (final f in widget.atual?.filtros ?? const <DashFiltro>[]) _FiltroEdit.de(f)];
  late String _modo = widget.atual?.config.modo ?? 'SIMPLES';
  late RelLayout? _layout = widget.atual?.config.layout;
  ResultadoDashLocal? _previa;
  String? _erroPrevia;
  bool _testando = false;

  @override
  void dispose() {
    for (final c in [_titulo, _grupo, _descricao, _sql, _subtitulo, _rodape]) {
      c.dispose();
    }
    for (final c in _colunas) {
      c.dispose();
    }
    for (final f in _filtros) {
      f.dispose();
    }
    super.dispose();
  }

  String _hoje() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> _valoresDeTeste() {
    final m = <String, dynamic>{};
    for (final f in _filtros) {
      final nome = f.nome.text.trim();
      final p = f.padrao.text.trim();
      if (nome.isEmpty) continue;
      if (f.tipo == 'DATA') {
        m[nome] = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(p) ? p : _hoje();
      } else if (f.tipo == 'INTEIRO' || f.tipo == 'DECIMAL') {
        m[nome] = p.isEmpty ? '0' : p;
      } else if (f.tipo == 'LOGICO') {
        m[nome] = p.isEmpty ? 'false' : p;
      } else {
        m[nome] = p;
      }
    }
    return m;
  }

  Future<void> _testar() async {
    setState(() {
      _testando = true;
      _erroPrevia = null;
      _previa = null;
    });
    try {
      final r = await widget.servico.testarSql(_sql.text.trim(), _valoresDeTeste());
      if (mounted) setState(() => _previa = ResultadoDashLocal(r.colunas, r.linhas));
    } catch (e) {
      AppLogger.i.warn('RelatorioConstrutorView: SQL recusado/falhou no teste: $e');
      if (mounted) setState(() => _erroPrevia = '$e');
    }
    if (mounted) setState(() => _testando = false);
  }

  /// Preenche a configuracao de colunas com as do SQL (mantem o que ja foi ajustado para colunas de mesmo nome).
  void _carregarColunas() {
    final p = _previa;
    if (p == null) return;
    final antigos = {for (final c in _colunas) c.nome.toLowerCase(): c};
    final novos = <_ColEdit>[];
    for (final nome in p.colunas) {
      final a = antigos.remove(nome.toLowerCase());
      novos.add(a ?? _ColEdit(nome, TextEditingController(text: _rotuloSugerido(nome)), 'TEXTO', false));
    }
    for (final sobra in antigos.values) {
      sobra.dispose();
    }
    setState(() {
      _colunas
        ..clear()
        ..addAll(novos);
      if (_agruparPor != null && !p.colunas.any((c) => c.toLowerCase() == _agruparPor!.toLowerCase())) _agruparPor = null;
    });
  }

  String _rotuloSugerido(String nome) {
    final s = nome.replaceAll('_', ' ');
    return s.isEmpty ? nome : s[0].toUpperCase() + s.substring(1);
  }

  List<String> _nomesDeColunas() {
    if (_previa != null) return _previa!.colunas;
    return [for (final c in _colunas) c.nome];
  }

  List<RelColuna> _configColunas() => [
        for (final c in _colunas)
          RelColuna(nome: c.nome, rotulo: c.rotulo.text.trim().isEmpty ? c.nome : c.rotulo.text.trim(), formato: c.formato, total: c.total),
      ];

  Future<void> _salvarPrevia(PdfRelatorio pdf) async {
    if (widget.salvar != null) {
      await widget.salvar!(pdf);
      return;
    }
    await FileSaver.instance.saveFile(name: 'previa_relatorio', bytes: pdf.bytes, fileExtension: 'pdf', mimeType: MimeType.pdf);
  }

  Future<void> _previaPdf(RelLayout layout) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final pdf = await widget.servico.previaPdf(
        _titulo.text.trim(),
        _sql.text.trim(),
        _valoresDeTeste(),
        RelConfig(orientacao: _orientacao, modo: 'AVANCADO', layout: layout, colunas: _configColunas()),
      );
      await _salvarPrevia(pdf);
      messenger.showSnackBar(const SnackBar(content: Text('Prévia gerada.')));
    } catch (e) {
      AppLogger.i.warn('RelatorioConstrutorView: previa PDF falhou: $e');
      messenger.showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade700));
    }
  }

  Future<void> _abrirDesigner() async {
    final colunas = _nomesDeColunas();
    if (colunas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Use Testar e Carregar colunas antes de abrir o designer.')));
      return;
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar(); // o aviso nao pode cobrir os botoes do designer
    final resultado = await showDialog<RelLayout>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(title: const Text('Designer do relatório')),
          body: RelatorioDesignerView(
            layout: _layout ?? layoutInicial(_titulo.text.trim(), _configColunas().isEmpty ? [for (final c in colunas) RelColuna(nome: c, rotulo: c)] : _configColunas(), _orientacao),
            colunas: colunas,
            orientacao: _orientacao,
            titulo: _titulo.text.trim(),
            configColunas: _configColunas(),
            onAplicar: (l) => Navigator.pop(ctx, l),
            onCancelar: () => Navigator.pop(ctx),
            onPrevia: _previaPdf,
          ),
        ),
      ),
    );
    if (resultado != null && mounted) setState(() => _layout = resultado);
  }

  List<RelColuna> _colunasConfig() => [
        for (final c in _colunas)
          RelColuna(nome: c.nome, rotulo: c.rotulo.text.trim().isEmpty ? c.nome : c.rotulo.text.trim(), formato: c.formato, total: c.total),
      ];

  void _salvar() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      RelatorioPersonalizado(
        id: widget.atual?.id,
        titulo: _titulo.text.trim(),
        grupo: _grupo.text.trim().isEmpty ? null : _grupo.text.trim(),
        descricao: _descricao.text.trim().isEmpty ? null : _descricao.text.trim(),
        ativo: _ativo,
        sql: _sql.text.trim(),
        filtros: [
          for (final f in _filtros)
            DashFiltro(
                nome: f.nome.text.trim(),
                descricao: f.descricao.text.trim(),
                tipo: f.tipo,
                padrao: f.padrao.text.trim().isEmpty ? null : f.padrao.text.trim()),
        ],
        config: RelConfig(
          orientacao: _orientacao,
          subtitulo: _subtitulo.text.trim().isEmpty ? null : _subtitulo.text.trim(),
          rodape: _rodape.text.trim().isEmpty ? null : _rodape.text.trim(),
          agruparPor: _agruparPor,
          modo: _modo,
          layout: _modo == 'AVANCADO' ? (_layout ?? layoutInicial(_titulo.text.trim(), _colunasConfig(), _orientacao)) : null,
          colunas: _colunasConfig(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.atual == null ? 'Novo relatório' : 'Editar relatório'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextFormField(
                controller: _titulo,
                maxLength: 150,
                decoration: const InputDecoration(labelText: 'Título *'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o título' : null,
              ),
              Wrap(spacing: 12, runSpacing: 4, children: [
                SizedBox(width: 220, child: TextFormField(controller: _grupo, decoration: const InputDecoration(labelText: 'Grupo'))),
                SizedBox(width: 320, child: TextFormField(controller: _descricao, decoration: const InputDecoration(labelText: 'Descrição'))),
              ]),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Ativo'), value: _ativo, onChanged: (v) => setState(() => _ativo = v)),
              const Divider(),
              Row(children: [
                const Expanded(child: Text('Filtros (parâmetros :nome do SQL)', style: TextStyle(fontWeight: FontWeight.w600))),
                TextButton.icon(onPressed: () => setState(() => _filtros.add(_FiltroEdit.vazio())), icon: const Icon(Icons.add), label: const Text('Filtro')),
              ]),
              for (var i = 0; i < _filtros.length; i++) _filtroForm(i),
              const Divider(),
              const Text('Consulta', style: TextStyle(fontWeight: FontWeight.w600)),
              const Text('SQL SELECT usando :empresaId (ex.: WHERE empresa_id = :empresaId). Use ORDER BY para a ordem do relatório.',
                  style: TextStyle(fontSize: 12)),
              TextFormField(
                controller: _sql,
                minLines: 4,
                maxLines: 10,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(labelText: 'SQL (SELECT) *', alignLabelWithHint: true),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o SQL' : null,
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: _testando ? null : _testar,
                  icon: _testando ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow),
                  label: const Text('Testar'),
                ),
                OutlinedButton.icon(
                  onPressed: _previa == null ? null : _carregarColunas,
                  icon: const Icon(Icons.view_column_outlined),
                  label: const Text('Carregar colunas'),
                ),
              ]),
              if (_erroPrevia != null)
                Padding(padding: const EdgeInsets.only(top: 6), child: Text(_erroPrevia!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              if (_previa != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: SingleChildScrollView(
                    child: ComponenteDashboardViewLinhas(colunas: _previa!.colunas, linhas: _previa!.linhas),
                  ),
                ),
              const Divider(),
              const Text('Layout do PDF', style: TextStyle(fontWeight: FontWeight.w600)),
              Wrap(spacing: 12, runSpacing: 4, children: [
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _orientacao,
                    decoration: const InputDecoration(labelText: 'Orientação'),
                    items: const [
                      DropdownMenuItem(value: 'RETRATO', child: Text('Retrato')),
                      DropdownMenuItem(value: 'PAISAGEM', child: Text('Paisagem')),
                    ],
                    onChanged: (v) => setState(() => _orientacao = v ?? 'RETRATO'),
                  ),
                ),
                SizedBox(width: 280, child: TextFormField(controller: _subtitulo, decoration: const InputDecoration(labelText: 'Subtítulo'))),
                SizedBox(width: 280, child: TextFormField(controller: _rodape, decoration: const InputDecoration(labelText: 'Rodapé'))),
              ]),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'SIMPLES', label: Text('Simples'), icon: Icon(Icons.table_rows_outlined)),
                  ButtonSegment(value: 'AVANCADO', label: Text('Avançado (designer)'), icon: Icon(Icons.dashboard_customize_outlined)),
                ],
                selected: {_modo},
                onSelectionChanged: (v) => setState(() => _modo = v.first),
              ),
              if (_modo == 'AVANCADO')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    FilledButton.tonalIcon(onPressed: _abrirDesigner, icon: const Icon(Icons.edit_note), label: const Text('Abrir designer')),
                    const SizedBox(width: 8),
                    Text(_layout == null ? 'Sem layout ainda' : 'Layout definido', style: const TextStyle(fontSize: 12)),
                  ]),
                ),
              if (_colunas.isNotEmpty) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: _colunas.any((c) => c.nome == _agruparPor) ? _agruparPor : null,
                  decoration: const InputDecoration(labelText: 'Agrupar por (opcional; o SQL deve ordenar por esta coluna)'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Sem agrupamento')),
                    for (final c in _colunas) DropdownMenuItem<String?>(value: c.nome, child: Text(c.nome)),
                  ],
                  onChanged: (v) => setState(() => _agruparPor = v),
                ),
                for (final c in _colunas) _colunaForm(c),
              ] else
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Use Testar e Carregar colunas para configurar rótulos, formatos e totais. Sem configuração, o PDF usa os nomes das colunas.',
                      style: TextStyle(fontSize: 12)),
                ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _salvar, child: const Text('Salvar')),
      ],
    );
  }

  Widget _colunaForm(_ColEdit c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(width: 130, child: Text(c.nome, overflow: TextOverflow.ellipsis)),
        SizedBox(width: 200, child: TextFormField(controller: c.rotulo, decoration: const InputDecoration(labelText: 'Rótulo', isDense: true))),
        SizedBox(
          width: 140,
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: c.formato,
            decoration: const InputDecoration(labelText: 'Formato', isDense: true),
            items: [for (final f in _formatos) DropdownMenuItem(value: f, child: Text(f))],
            onChanged: (v) => setState(() => c.formato = v ?? 'TEXTO'),
          ),
        ),
        FilterChip(label: const Text('Somar'), selected: c.total, onSelected: (v) => setState(() => c.total = v)),
      ]),
    );
  }

  Widget _filtroForm(int i) {
    final f = _filtros[i];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 150,
            child: TextFormField(
              controller: f.nome,
              decoration: const InputDecoration(labelText: 'Nome *'),
              validator: (v) => RegExp(r'^[a-z][a-zA-Z0-9_]{0,39}$').hasMatch((v ?? '').trim()) ? null : 'Letra minúscula; letras, números e _',
            ),
          ),
          SizedBox(
            width: 170,
            child: TextFormField(
              controller: f.descricao,
              decoration: const InputDecoration(labelText: 'Descrição *'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe' : null,
            ),
          ),
          SizedBox(
            width: 130,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: f.tipo,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: [for (final t in _tiposFiltro) DropdownMenuItem(value: t, child: Text(t))],
              onChanged: (v) => setState(() => f.tipo = v ?? 'TEXTO'),
            ),
          ),
          SizedBox(
              width: 150,
              child: TextFormField(controller: f.padrao, decoration: InputDecoration(labelText: 'Padrão', helperText: f.tipo == 'DATA' ? 'HOJE, INICIO_MES, INICIO_ANO' : null))),
          IconButton(tooltip: 'Remover filtro', onPressed: () => setState(() => _filtros.removeAt(i).dispose()), icon: const Icon(Icons.delete_outline)),
        ]),
      ),
    );
  }
}

/// Colunas e linhas da previa do SQL.
class ResultadoDashLocal {
  final List<String> colunas;
  final List<List<dynamic>> linhas;

  const ResultadoDashLocal(this.colunas, this.linhas);
}

/// Tabela simples da previa (usa o mesmo formato numerico dos dashboards).
class ComponenteDashboardViewLinhas extends StatelessWidget {
  final List<String> colunas;
  final List<List<dynamic>> linhas;

  const ComponenteDashboardViewLinhas({super.key, required this.colunas, required this.linhas});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [for (final c in colunas) DataColumn(label: Text(c))],
        rows: [
          for (final l in linhas)
            DataRow(cells: [for (final v in l) DataCell(Text(v is num ? formatarNumero(v) : (v?.toString() ?? '-')))]),
        ],
      ),
    );
  }
}
