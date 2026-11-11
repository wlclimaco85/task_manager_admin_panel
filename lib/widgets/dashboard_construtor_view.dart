import 'package:flutter/material.dart';

import '../services/dashboard_personalizado_service.dart';
import '../utils/app_logger.dart';
import 'dashboard_componente_view.dart';

/// Construtor de Dashboards (plataforma low-code, F6): cria e edita dashboards (filtros + componentes com SQL
/// somente-leitura). O SQL precisa filtrar pela empresa com :empresaId (o servidor preenche e valida); o botão
/// "Testar" mostra uma prévia de até 50 linhas. Somente MASTER (o servidor também exige).
class DashboardConstrutorView extends StatefulWidget {
  final DashboardPersonalizadoService? servico;

  const DashboardConstrutorView({super.key, this.servico});

  @override
  State<DashboardConstrutorView> createState() => _DashboardConstrutorViewState();
}

class _DashboardConstrutorViewState extends State<DashboardConstrutorView> {
  late final DashboardPersonalizadoService _svc = widget.servico ?? DashboardPersonalizadoService();
  List<DashboardPersonalizado> _lista = const [];
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
      AppLogger.i.warn('DashboardConstrutorView: erro ao listar: $e');
      if (mounted) setState(() => _erro = '$e');
    }
    if (mounted) setState(() => _carregando = false);
  }

  Future<void> _editar([DashboardPersonalizado? atual]) async {
    DashboardPersonalizado? base = atual;
    if (atual?.id != null) {
      try {
        base = await _svc.buscarComSql(atual!.id!);
      } catch (e) {
        AppLogger.i.warn('DashboardConstrutorView: erro ao abrir para edicao: $e');
        _aviso('$e', erro: true);
        return;
      }
    }
    if (!mounted) return;
    final editado = await showDialog<DashboardPersonalizado>(
      context: context,
      builder: (_) => _DashboardDialog(atual: base, servico: _svc),
    );
    if (editado == null) return;
    try {
      await _svc.salvar(editado);
      _aviso('Dashboard salvo.');
      await _carregar();
    } catch (e) {
      AppLogger.i.warn('DashboardConstrutorView: erro ao salvar: $e');
      _aviso('$e', erro: true);
    }
  }

  Future<void> _excluir(DashboardPersonalizado d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir dashboard'),
        content: Text('Excluir "${d.titulo}" e todos os seus componentes?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _svc.excluir(d.id!);
      await _carregar();
    } catch (e) {
      AppLogger.i.warn('DashboardConstrutorView: erro ao excluir: $e');
      _aviso('$e', erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Expanded(
              child: Text('Construtor de Dashboards', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          IconButton(tooltip: 'Atualizar', onPressed: _carregar, icon: const Icon(Icons.refresh)),
          FilledButton.icon(onPressed: () => _editar(), icon: const Icon(Icons.add), label: const Text('Novo dashboard')),
        ]),
      ),
      Expanded(
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
                ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_erro!)))
                : _lista.isEmpty
                    ? const Center(child: Text('Nenhum dashboard criado ainda.'))
                    : ListView.separated(
                        itemCount: _lista.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final d = _lista[i];
                          return ListTile(
                            minVerticalPadding: 10,
                            leading: const Icon(Icons.insights_outlined),
                            title: Text(d.titulo),
                            subtitle: Text('${d.grupo ?? 'Sem grupo'}${d.ativo ? '' : ' · inativo'}'),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(tooltip: 'Editar', onPressed: () => _editar(d), icon: const Icon(Icons.edit_outlined)),
                              IconButton(tooltip: 'Excluir', onPressed: () => _excluir(d), icon: const Icon(Icons.delete_outline)),
                            ]),
                          );
                        }),
      ),
    ]);
  }
}

const _tiposComponente = {
  'KPI': 'Valor (KPI)',
  'TABELA': 'Tabela',
  'LINHA': 'Linha',
  'BARRAS': 'Barras',
  'COLUNAS': 'Colunas',
  'PIZZA': 'Pizza',
  'DONUT': 'Donut',
};
const _tiposFiltro = ['TEXTO', 'INTEIRO', 'DECIMAL', 'DATA', 'LOGICO'];

class _CompEdit {
  final TextEditingController titulo;
  final TextEditingController sql;
  String tipo;
  int largura;
  ResultadoDash? previa;
  String? erroPrevia;
  bool testando = false;

  _CompEdit(this.titulo, this.sql, this.tipo, this.largura);

  factory _CompEdit.vazio() => _CompEdit(TextEditingController(), TextEditingController(), 'TABELA', 1);

  factory _CompEdit.de(DashComponente c) =>
      _CompEdit(TextEditingController(text: c.titulo), TextEditingController(text: c.sql ?? ''), c.tipo, c.largura);

  void dispose() {
    titulo.dispose();
    sql.dispose();
  }
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

class _DashboardDialog extends StatefulWidget {
  final DashboardPersonalizado? atual;
  final DashboardPersonalizadoService servico;

  const _DashboardDialog({required this.atual, required this.servico});

  @override
  State<_DashboardDialog> createState() => _DashboardDialogState();
}

class _DashboardDialogState extends State<_DashboardDialog> {
  final _form = GlobalKey<FormState>();
  late final _titulo = TextEditingController(text: widget.atual?.titulo ?? '');
  late final _grupo = TextEditingController(text: widget.atual?.grupo ?? '');
  late final _descricao = TextEditingController(text: widget.atual?.descricao ?? '');
  late bool _ativo = widget.atual?.ativo ?? true;
  late final List<_CompEdit> _comps = [for (final c in widget.atual?.componentes ?? const <DashComponente>[]) _CompEdit.de(c)];
  late final List<_FiltroEdit> _filtros = [for (final f in widget.atual?.filtros ?? const <DashFiltro>[]) _FiltroEdit.de(f)];

  @override
  void dispose() {
    for (final c in [_titulo, _grupo, _descricao]) {
      c.dispose();
    }
    for (final c in _comps) {
      c.dispose();
    }
    for (final f in _filtros) {
      f.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _valoresDeTeste() {
    // Valores de teste: o padrao do filtro (datas simbolicas viram vazio e o servidor resolve).
    final m = <String, dynamic>{};
    for (final f in _filtros) {
      final p = f.padrao.text.trim();
      final nome = f.nome.text.trim();
      if (nome.isEmpty) continue;
      if (f.tipo == 'DATA') {
        if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(p)) m[nome] = p;
        else m[nome] = _hoje();
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

  String _hoje() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _testar(_CompEdit c) async {
    setState(() {
      c.testando = true;
      c.erroPrevia = null;
      c.previa = null;
    });
    try {
      final r = await widget.servico.testarSql(c.sql.text.trim(), _valoresDeTeste());
      if (mounted) setState(() => c.previa = r);
    } catch (e) {
      AppLogger.i.warn('DashboardConstrutorView: SQL recusado/falhou no teste: $e');
      if (mounted) setState(() => c.erroPrevia = '$e');
    }
    if (mounted) setState(() => c.testando = false);
  }

  void _salvar() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      DashboardPersonalizado(
        id: widget.atual?.id,
        titulo: _titulo.text.trim(),
        grupo: _grupo.text.trim().isEmpty ? null : _grupo.text.trim(),
        descricao: _descricao.text.trim().isEmpty ? null : _descricao.text.trim(),
        ativo: _ativo,
        filtros: [
          for (final f in _filtros)
            DashFiltro(
                nome: f.nome.text.trim(),
                descricao: f.descricao.text.trim(),
                tipo: f.tipo,
                padrao: f.padrao.text.trim().isEmpty ? null : f.padrao.text.trim()),
        ],
        componentes: [
          for (var i = 0; i < _comps.length; i++)
            DashComponente(tipo: _comps[i].tipo, titulo: _comps[i].titulo.text.trim(), sql: _comps[i].sql.text.trim(), ordem: i, largura: _comps[i].largura),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.atual == null ? 'Novo dashboard' : 'Editar dashboard'),
      content: SizedBox(
        width: 720,
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
              Row(children: [
                Expanded(child: TextFormField(controller: _grupo, decoration: const InputDecoration(labelText: 'Grupo'))),
                const SizedBox(width: 8),
                Expanded(child: TextFormField(controller: _descricao, decoration: const InputDecoration(labelText: 'Descrição'))),
              ]),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Ativo'), value: _ativo, onChanged: (v) => setState(() => _ativo = v)),
              const Divider(),
              Row(children: [
                const Expanded(child: Text('Filtros (parâmetros :nome do SQL)', style: TextStyle(fontWeight: FontWeight.w600))),
                TextButton.icon(onPressed: () => setState(() => _filtros.add(_FiltroEdit.vazio())), icon: const Icon(Icons.add), label: const Text('Filtro')),
              ]),
              for (var i = 0; i < _filtros.length; i++) _filtroForm(i),
              const Divider(),
              Row(children: [
                const Expanded(child: Text('Componentes', style: TextStyle(fontWeight: FontWeight.w600))),
                TextButton.icon(onPressed: () => setState(() => _comps.add(_CompEdit.vazio())), icon: const Icon(Icons.add), label: const Text('Componente')),
              ]),
              const Text(
                'Gráficos: 1ª coluna = rótulo; demais colunas numéricas = séries. Valor (KPI): 1ª linha e 1ª coluna. '
                'O SQL deve ser SELECT e usar :empresaId (ex.: WHERE empresa_id = :empresaId).',
                style: TextStyle(fontSize: 12),
              ),
              for (var i = 0; i < _comps.length; i++) _compForm(i),
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
          SizedBox(width: 150, child: TextFormField(controller: f.padrao, decoration: InputDecoration(labelText: 'Padrão', helperText: f.tipo == 'DATA' ? 'HOJE, INICIO_MES, INICIO_ANO' : null))),
          IconButton(tooltip: 'Remover filtro', onPressed: () => setState(() => _filtros.removeAt(i).dispose()), icon: const Icon(Icons.delete_outline)),
        ]),
      ),
    );
  }

  Widget _compForm(int i) {
    final c = _comps[i];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 240,
              child: TextFormField(
                controller: c.titulo,
                decoration: const InputDecoration(labelText: 'Título do componente *'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe' : null,
              ),
            ),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: c.tipo,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: [for (final e in _tiposComponente.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => c.tipo = v ?? 'TABELA'),
              ),
            ),
            DropdownButton<int>(
              value: c.largura,
              items: const [DropdownMenuItem(value: 1, child: Text('Meia')), DropdownMenuItem(value: 2, child: Text('Cheia'))],
              onChanged: (v) => setState(() => c.largura = v ?? 1),
            ),
            IconButton(tooltip: 'Remover componente', onPressed: () => setState(() => _comps.removeAt(i).dispose()), icon: const Icon(Icons.delete_outline)),
          ]),
          TextFormField(
            controller: c.sql,
            minLines: 3,
            maxLines: 8,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(labelText: 'SQL (SELECT) *', alignLabelWithHint: true),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o SQL' : null,
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: c.testando ? null : () => _testar(c),
              icon: c.testando ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow),
              label: const Text('Testar'),
            ),
          ),
          if (c.erroPrevia != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(c.erroPrevia!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (c.previa != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(child: ComponenteDashboardView(resultado: ResultadoDash(
                  tipo: c.tipo, titulo: 'Prévia (${c.previa!.linhas.length} linha(s))', colunas: c.previa!.colunas, linhas: c.previa!.linhas))),
            ),
        ]),
      ),
    );
  }
}
