import 'package:flutter/material.dart';

import '../services/acao_java_service.dart';
import '../services/modulo_java_service.dart';
import '../utils/app_logger.dart';

/// Dicionário de Dados (plataforma low-code): por tela/tabela, as abas **Ações** (botões que chamam uma
/// rotina Java, com parâmetros de popup) e **Eventos** (rotinas Java em insert/update/delete).
/// As abas Campos e Ligações entram em etapa seguinte. Somente MASTER (o servidor também exige).
class DicionarioDadosView extends StatefulWidget {
  final AcaoJavaService? acoes;
  final ModuloJavaService? modulos;

  const DicionarioDadosView({super.key, this.acoes, this.modulos});

  @override
  State<DicionarioDadosView> createState() => _DicionarioDadosViewState();
}

class _DicionarioDadosViewState extends State<DicionarioDadosView> {
  late final AcaoJavaService _acoesSvc = widget.acoes ?? AcaoJavaService();
  late final ModuloJavaService _modulosSvc = widget.modulos ?? ModuloJavaService();

  final _tela = TextEditingController();
  final _tabela = TextEditingController();

  List<AcaoJava> _acoes = const [];
  List<EventoJava> _eventos = const [];
  List<ModuloJava> _modulos = const [];
  bool _carregandoAcoes = false;
  bool _carregandoEventos = false;
  String? _erroAcoes;
  String? _erroEventos;
  bool _acoesCarregadas = false;
  bool _eventosCarregados = false;

  @override
  void dispose() {
    _tela.dispose();
    _tabela.dispose();
    super.dispose();
  }

  void _aviso(String t, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t), backgroundColor: erro ? Colors.red.shade700 : null));
  }

  Future<void> _garantirModulos() async {
    if (_modulos.isNotEmpty) return;
    try {
      _modulos = await _modulosSvc.listar();
    } catch (e) {
      AppLogger.i.warn('DicionarioDadosView: módulos indisponíveis: $e');
      _aviso('$e', erro: true);
    }
  }

  Future<void> _carregarAcoes() async {
    final tela = _tela.text.trim();
    if (tela.isEmpty) {
      _aviso('Informe o nome da tela.', erro: true);
      return;
    }
    setState(() {
      _carregandoAcoes = true;
      _erroAcoes = null;
    });
    try {
      final lista = await _acoesSvc.listarTodas(tela);
      if (mounted) setState(() { _acoes = lista; _acoesCarregadas = true; });
    } catch (e) {
      AppLogger.i.warn('DicionarioDadosView: erro ao listar ações: $e');
      if (mounted) setState(() => _erroAcoes = '$e');
    }
    if (mounted) setState(() => _carregandoAcoes = false);
  }

  Future<void> _carregarEventos() async {
    final tabela = _tabela.text.trim();
    if (tabela.isEmpty) {
      _aviso('Informe o nome da tabela.', erro: true);
      return;
    }
    setState(() {
      _carregandoEventos = true;
      _erroEventos = null;
    });
    try {
      final lista = await _acoesSvc.listarEventos(tabela);
      if (mounted) setState(() { _eventos = lista; _eventosCarregados = true; });
    } catch (e) {
      AppLogger.i.warn('DicionarioDadosView: erro ao listar eventos: $e');
      if (mounted) setState(() => _erroEventos = '$e');
    }
    if (mounted) setState(() => _carregandoEventos = false);
  }

  Future<void> _editarAcao([AcaoJava? atual]) async {
    await _garantirModulos();
    if (!mounted) return;
    final editada = await showDialog<AcaoJava>(
      context: context,
      builder: (_) => _AcaoDialog(
        telaNome: _tela.text.trim(),
        atual: atual,
        modulos: _modulos,
        servico: _acoesSvc,
      ),
    );
    if (editada == null) return;
    try {
      await _acoesSvc.salvarAcao(editada);
      _aviso('Ação salva.');
      await _carregarAcoes();
    } catch (e) {
      AppLogger.i.warn('DicionarioDadosView: erro ao salvar ação: $e');
      _aviso('$e', erro: true);
    }
  }

  Future<void> _excluirAcao(AcaoJava a) async {
    if (!await _confirmar('Excluir a ação "${a.label}"?')) return;
    try {
      await _acoesSvc.excluirAcao(a.id!);
      await _carregarAcoes();
    } catch (e) {
      AppLogger.i.warn('DicionarioDadosView: erro ao excluir ação: $e');
      _aviso('$e', erro: true);
    }
  }

  Future<void> _editarEvento([EventoJava? atual]) async {
    await _garantirModulos();
    if (!mounted) return;
    final editado = await showDialog<EventoJava>(
      context: context,
      builder: (_) => _EventoDialog(
        tabelaNome: _tabela.text.trim(),
        atual: atual,
        modulos: _modulos,
        servico: _acoesSvc,
      ),
    );
    if (editado == null) return;
    try {
      await _acoesSvc.salvarEvento(editado);
      _aviso('Evento salvo.');
      await _carregarEventos();
    } catch (e) {
      AppLogger.i.warn('DicionarioDadosView: erro ao salvar evento: $e');
      _aviso('$e', erro: true);
    }
  }

  Future<void> _excluirEvento(EventoJava e) async {
    if (!await _confirmar('Excluir o evento "${e.descricao}"?')) return;
    try {
      await _acoesSvc.excluirEvento(e.id!);
      await _carregarEventos();
    } catch (ex) {
      AppLogger.i.warn('DicionarioDadosView: erro ao excluir evento: $ex');
      _aviso('$ex', erro: true);
    }
  }

  Future<bool> _confirmar(String texto) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar'),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Excluir')),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Dicionário de Dados',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
        ),
        const TabBar(tabs: [Tab(text: 'Ações'), Tab(text: 'Eventos')]),
        Expanded(
          child: TabBarView(children: [_abaAcoes(), _abaEventos()]),
        ),
      ]),
    );
  }

  Widget _filtro(TextEditingController c, String rotulo, String dica, VoidCallback onCarregar, bool carregando) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: c,
            decoration: InputDecoration(labelText: rotulo, hintText: dica),
            onSubmitted: (_) => onCarregar(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: carregando ? null : onCarregar,
          icon: const Icon(Icons.search),
          label: const Text('Carregar'),
        ),
      ]),
    );
  }

  Widget _abaAcoes() {
    return Column(children: [
      _filtro(_tela, 'Tela (nome usado nas grids)', 'ex.: produto', _carregarAcoes, _carregandoAcoes),
      if (_acoesCarregadas)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
                onPressed: () => _editarAcao(),
                icon: const Icon(Icons.add),
                label: const Text('Nova ação')),
          ),
        ),
      Expanded(
        child: _carregandoAcoes
            ? const Center(child: CircularProgressIndicator())
            : _erroAcoes != null
                ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_erroAcoes!)))
                : !_acoesCarregadas
                    ? const Center(child: Text('Informe a tela e toque em Carregar.'))
                    : _acoes.isEmpty
                        ? const Center(child: Text('Nenhuma ação cadastrada para esta tela.'))
                        : ListView.separated(
                            itemCount: _acoes.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final a = _acoes[i];
                              return ListTile(
                                minVerticalPadding: 10,
                                leading: const Icon(Icons.bolt),
                                title: Text(a.label),
                                subtitle: Text('${a.classe}\n${a.params.length} parâmetro(s) · tabela ${a.tabelaNome ?? '-'}'),
                                isThreeLine: true,
                                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                  if (!a.ativo) const Chip(label: Text('Inativa')),
                                  IconButton(tooltip: 'Editar', onPressed: () => _editarAcao(a), icon: const Icon(Icons.edit_outlined)),
                                  IconButton(tooltip: 'Excluir', onPressed: () => _excluirAcao(a), icon: const Icon(Icons.delete_outline)),
                                ]),
                              );
                            }),
      ),
    ]);
  }

  Widget _abaEventos() {
    return Column(children: [
      _filtro(_tabela, 'Tabela (nome no banco)', 'ex.: produto', _carregarEventos, _carregandoEventos),
      if (_eventosCarregados)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
                onPressed: () => _editarEvento(),
                icon: const Icon(Icons.add),
                label: const Text('Novo evento')),
          ),
        ),
      Expanded(
        child: _carregandoEventos
            ? const Center(child: CircularProgressIndicator())
            : _erroEventos != null
                ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_erroEventos!)))
                : !_eventosCarregados
                    ? const Center(child: Text('Informe a tabela e toque em Carregar.'))
                    : _eventos.isEmpty
                        ? const Center(child: Text('Nenhum evento cadastrado para esta tabela.'))
                        : ListView.separated(
                            itemCount: _eventos.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final e = _eventos[i];
                              return ListTile(
                                minVerticalPadding: 10,
                                leading: CircleAvatar(child: Text('${e.numEvento ?? ''}')),
                                title: Text(e.descricao),
                                subtitle: Text('${e.momento} ${e.operacao} · ${e.classe}'),
                                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                  if (!e.ativo) const Chip(label: Text('Inativo')),
                                  IconButton(tooltip: 'Editar', onPressed: () => _editarEvento(e), icon: const Icon(Icons.edit_outlined)),
                                  IconButton(tooltip: 'Excluir', onPressed: () => _excluirEvento(e), icon: const Icon(Icons.delete_outline)),
                                ]),
                              );
                            }),
      ),
    ]);
  }
}

/// Escolha de Módulo + Classe (filtrada por ACAO ou EVENTO) usada pelos dois formulários.
class _ModuloClasse extends StatefulWidget {
  final List<ModuloJava> modulos;
  final AcaoJavaService servico;
  final String tipo; // ACAO | EVENTO
  final int? moduloId;
  final String classe;
  final void Function(int? moduloId, String classe) onChanged;

  const _ModuloClasse({
    required this.modulos,
    required this.servico,
    required this.tipo,
    required this.moduloId,
    required this.classe,
    required this.onChanged,
  });

  @override
  State<_ModuloClasse> createState() => _ModuloClasseState();
}

class _ModuloClasseState extends State<_ModuloClasse> {
  List<String> _classes = const [];
  bool _carregando = false;
  String? _erro;
  int? _moduloId;
  String _classe = '';

  @override
  void initState() {
    super.initState();
    _moduloId = widget.moduloId;
    _classe = widget.classe;
    if (_moduloId != null) _carregarClasses(_moduloId!);
  }

  Future<void> _carregarClasses(int moduloId) async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final todas = await widget.servico.listarClasses(moduloId);
      if (!mounted) return;
      setState(() => _classes = todas.where((c) => c.tipo == widget.tipo).map((c) => c.nome).toSet().toList());
    } catch (e) {
      AppLogger.i.warn('DicionarioDadosView: classes indisponíveis: $e');
      if (mounted) setState(() => _erro = '$e');
    }
    if (mounted) setState(() => _carregando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DropdownButtonFormField<int>(
        initialValue: widget.modulos.any((m) => m.id == _moduloId) ? _moduloId : null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Módulo Java *'),
        items: [
          for (final m in widget.modulos)
            DropdownMenuItem(value: m.id, child: Text('${m.id} - ${m.descricao}', overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) {
          setState(() {
            _moduloId = v;
            _classe = '';
            _classes = const [];
          });
          widget.onChanged(v, '');
          if (v != null) _carregarClasses(v);
        },
        validator: (v) => v == null ? 'Escolha o módulo' : null,
      ),
      if (_carregando) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
      if (_erro != null) Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      DropdownButtonFormField<String>(
        initialValue: _classes.contains(_classe) ? _classe : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Classe Java *',
          helperText: _moduloId != null && !_carregando && _classes.isEmpty
              ? 'Nenhuma classe ${widget.tipo == 'ACAO' ? 'AcaoRotinaJava' : 'EventoJava'} nos jars deste módulo.'
              : null,
        ),
        items: [for (final c in _classes) DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))],
        onChanged: (v) {
          setState(() => _classe = v ?? '');
          widget.onChanged(_moduloId, v ?? '');
        },
        validator: (v) => (v == null || v.isEmpty) ? 'Escolha a classe' : null,
      ),
    ]);
  }
}

class _AcaoDialog extends StatefulWidget {
  final String telaNome;
  final AcaoJava? atual;
  final List<ModuloJava> modulos;
  final AcaoJavaService servico;

  const _AcaoDialog({required this.telaNome, required this.atual, required this.modulos, required this.servico});

  @override
  State<_AcaoDialog> createState() => _AcaoDialogState();
}

class _AcaoDialogState extends State<_AcaoDialog> {
  static const _tipos = ['TEXTO', 'INTEIRO', 'DECIMAL', 'LOGICO', 'DATA', 'LISTA'];
  final _form = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.atual?.label ?? '');
  late final _confirm = TextEditingController(text: widget.atual?.confirmMessage ?? '');
  late final _tabela = TextEditingController(text: widget.atual?.tabelaNome ?? widget.telaNome);
  late final _idColuna = TextEditingController(text: widget.atual?.idColuna ?? 'id');
  late final _ordem = TextEditingController(text: '${widget.atual?.ordem ?? 0}');
  late bool _exige = widget.atual?.exigeSelecao ?? true;
  late bool _ativo = widget.atual?.ativo ?? true;
  late int? _moduloId = widget.atual?.moduloJavaId;
  late String _classe = widget.atual?.classe ?? '';
  late final List<_ParamEdit> _params = [
    for (final p in widget.atual?.params ?? const <AcaoJavaParam>[]) _ParamEdit.de(p),
  ];

  @override
  void dispose() {
    for (final c in [_label, _confirm, _tabela, _idColuna, _ordem]) {
      c.dispose();
    }
    for (final p in _params) {
      p.dispose();
    }
    super.dispose();
  }

  void _salvar() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      AcaoJava(
        id: widget.atual?.id,
        telaNome: widget.telaNome,
        label: _label.text.trim(),
        icon: widget.atual?.icon ?? 'bolt',
        confirmMessage: _confirm.text.trim().isEmpty ? null : _confirm.text.trim(),
        moduloJavaId: _moduloId,
        classe: _classe,
        tabelaNome: _tabela.text.trim().isEmpty ? null : _tabela.text.trim(),
        idColuna: _idColuna.text.trim().isEmpty ? 'id' : _idColuna.text.trim(),
        exigeSelecao: _exige,
        ativo: _ativo,
        ordem: int.tryParse(_ordem.text.trim()) ?? 0,
        params: [for (final p in _params) p.paraParam()],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.atual == null ? 'Nova ação' : 'Editar ação'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(labelText: 'Descrição (texto do botão) *'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe a descrição' : null,
              ),
              _ModuloClasse(
                modulos: widget.modulos,
                servico: widget.servico,
                tipo: 'ACAO',
                moduloId: _moduloId,
                classe: _classe,
                onChanged: (m, c) {
                  _moduloId = m;
                  _classe = c;
                },
              ),
              TextFormField(controller: _tabela, decoration: const InputDecoration(labelText: 'Tabela dos registros selecionados')),
              TextFormField(controller: _idColuna, decoration: const InputDecoration(labelText: 'Coluna de id')),
              TextFormField(controller: _confirm, decoration: const InputDecoration(labelText: 'Mensagem de confirmação')),
              TextFormField(controller: _ordem, decoration: const InputDecoration(labelText: 'Ordem'), keyboardType: TextInputType.number),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Exige registros selecionados'),
                  value: _exige,
                  onChanged: (v) => setState(() => _exige = v)),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ativa'),
                  value: _ativo,
                  onChanged: (v) => setState(() => _ativo = v)),
              const Divider(),
              Row(children: [
                const Expanded(child: Text('Parâmetros do popup', style: TextStyle(fontWeight: FontWeight.w600))),
                TextButton.icon(
                    onPressed: () => setState(() => _params.add(_ParamEdit.vazio())),
                    icon: const Icon(Icons.add),
                    label: const Text('Parâmetro')),
              ]),
              for (var i = 0; i < _params.length; i++) _paramForm(i),
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

  Widget _paramForm(int i) {
    final p = _params[i];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: p.descricao,
                decoration: const InputDecoration(labelText: 'Descrição *'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe' : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: p.nome,
                decoration: const InputDecoration(labelText: 'Nome *'),
                validator: (v) => RegExp(r'^[a-z][a-z0-9_]{0,59}$').hasMatch((v ?? '').trim().toLowerCase())
                    ? null
                    : 'Use letras, números e _',
              ),
            ),
            IconButton(
                tooltip: 'Remover',
                onPressed: () => setState(() => _params.removeAt(i).dispose()),
                icon: const Icon(Icons.delete_outline)),
          ]),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: p.tipo,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: [for (final t in _tipos) DropdownMenuItem(value: t, child: Text(t))],
                onChanged: (v) => setState(() => p.tipo = v ?? 'TEXTO'),
              ),
            ),
            const SizedBox(width: 8),
            if (p.tipo == 'LISTA')
              Expanded(
                child: TextFormField(
                  controller: p.opcoes,
                  decoration: const InputDecoration(labelText: 'Opções (separe com ;)'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe as opções' : null,
                ),
              ),
          ]),
          Row(children: [
            Expanded(
                child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Obrigatório'),
                    value: p.obrigatorio,
                    onChanged: (v) => setState(() => p.obrigatorio = v ?? false))),
            Expanded(
                child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sugerir último valor'),
                    value: p.sugerirUltimo,
                    onChanged: (v) => setState(() => p.sugerirUltimo = v ?? false))),
          ]),
        ]),
      ),
    );
  }
}

class _ParamEdit {
  final TextEditingController descricao;
  final TextEditingController nome;
  final TextEditingController opcoes;
  String tipo;
  bool obrigatorio;
  bool sugerirUltimo;

  _ParamEdit(this.descricao, this.nome, this.opcoes, this.tipo, this.obrigatorio, this.sugerirUltimo);

  factory _ParamEdit.vazio() =>
      _ParamEdit(TextEditingController(), TextEditingController(), TextEditingController(), 'TEXTO', false, false);

  factory _ParamEdit.de(AcaoJavaParam p) => _ParamEdit(
      TextEditingController(text: p.descricao),
      TextEditingController(text: p.nome),
      TextEditingController(text: p.opcoes ?? ''),
      p.tipo,
      p.obrigatorio,
      p.sugerirUltimo);

  AcaoJavaParam paraParam() => AcaoJavaParam(
        descricao: descricao.text.trim(),
        nome: nome.text.trim().toLowerCase(),
        tipo: tipo,
        obrigatorio: obrigatorio,
        sugerirUltimo: sugerirUltimo,
        opcoes: tipo == 'LISTA' ? opcoes.text.trim() : null,
      );

  void dispose() {
    descricao.dispose();
    nome.dispose();
    opcoes.dispose();
  }
}

class _EventoDialog extends StatefulWidget {
  final String tabelaNome;
  final EventoJava? atual;
  final List<ModuloJava> modulos;
  final AcaoJavaService servico;

  const _EventoDialog({required this.tabelaNome, required this.atual, required this.modulos, required this.servico});

  @override
  State<_EventoDialog> createState() => _EventoDialogState();
}

class _EventoDialogState extends State<_EventoDialog> {
  final _form = GlobalKey<FormState>();
  late final _descricao = TextEditingController(text: widget.atual?.descricao ?? '');
  late final _ordem = TextEditingController(text: '${widget.atual?.ordem ?? 0}');
  late String _momento = widget.atual?.momento ?? 'ANTES';
  late String _operacao = widget.atual?.operacao ?? 'INSERT';
  late bool _ativo = widget.atual?.ativo ?? true;
  late bool _aborta = widget.atual?.abortaEmErro ?? true;
  late int? _moduloId = widget.atual?.moduloJavaId;
  late String _classe = widget.atual?.classe ?? '';

  @override
  void dispose() {
    _descricao.dispose();
    _ordem.dispose();
    super.dispose();
  }

  void _salvar() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      EventoJava(
        id: widget.atual?.id,
        tabelaNome: widget.tabelaNome,
        numEvento: widget.atual?.numEvento,
        descricao: _descricao.text.trim(),
        momento: _momento,
        operacao: _operacao,
        moduloJavaId: _moduloId,
        classe: _classe,
        ativo: _ativo,
        ordem: int.tryParse(_ordem.text.trim()) ?? 0,
        abortaEmErro: _aborta,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.atual == null ? 'Novo evento' : 'Editar evento'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextFormField(
                controller: _descricao,
                decoration: const InputDecoration(labelText: 'Descrição *'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe a descrição' : null,
              ),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _momento,
                    decoration: const InputDecoration(labelText: 'Momento'),
                    items: const [
                      DropdownMenuItem(value: 'ANTES', child: Text('Antes')),
                      DropdownMenuItem(value: 'DEPOIS', child: Text('Depois')),
                    ],
                    onChanged: (v) => setState(() => _momento = v ?? 'ANTES'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _operacao,
                    decoration: const InputDecoration(labelText: 'Operação'),
                    items: const [
                      DropdownMenuItem(value: 'INSERT', child: Text('Inserir')),
                      DropdownMenuItem(value: 'UPDATE', child: Text('Atualizar')),
                      DropdownMenuItem(value: 'DELETE', child: Text('Excluir')),
                    ],
                    onChanged: (v) => setState(() => _operacao = v ?? 'INSERT'),
                  ),
                ),
              ]),
              _ModuloClasse(
                modulos: widget.modulos,
                servico: widget.servico,
                tipo: 'EVENTO',
                moduloId: _moduloId,
                classe: _classe,
                onChanged: (m, c) {
                  _moduloId = m;
                  _classe = c;
                },
              ),
              TextFormField(controller: _ordem, decoration: const InputDecoration(labelText: 'Ordem'), keyboardType: TextInputType.number),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ativo'),
                  value: _ativo,
                  onChanged: (v) => setState(() => _ativo = v)),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Abortar a operação se o evento falhar'),
                  subtitle: const Text('Eventos "Antes" sempre abortam.'),
                  value: _aborta,
                  onChanged: (v) => setState(() => _aborta = v)),
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
}
