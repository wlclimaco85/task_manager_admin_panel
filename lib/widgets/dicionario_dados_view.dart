import 'package:flutter/material.dart';

import '../services/acao_java_service.dart';
import '../services/dicionario_campo_service.dart';
import '../services/modulo_java_service.dart';
import '../utils/app_logger.dart';

/// Dicionário de Dados (plataforma low-code), por tela/tabela, com 4 abas:
/// **Campos** (só o rótulo muda; tipo e nome são fixos e o campo nunca é excluído; dá para incluir campo em tela
/// da própria empresa), **Ligações** (FK: o campo vira lista de busca), **Ações** (botões que chamam uma rotina
/// Java, com parâmetros de popup) e **Eventos** (rotinas Java em insert/update/delete).
/// Somente MASTER (o servidor também exige).
class DicionarioDadosView extends StatefulWidget {
  final AcaoJavaService? acoes;
  final ModuloJavaService? modulos;
  final DicionarioCampoService? campos;

  const DicionarioDadosView({super.key, this.acoes, this.modulos, this.campos});

  @override
  State<DicionarioDadosView> createState() => _DicionarioDadosViewState();
}

class _DicionarioDadosViewState extends State<DicionarioDadosView> {
  late final AcaoJavaService _acoesSvc = widget.acoes ?? AcaoJavaService();
  late final ModuloJavaService _modulosSvc = widget.modulos ?? ModuloJavaService();
  late final DicionarioCampoService _camposSvc = widget.campos ?? DicionarioCampoService();

  List<CampoDicionario> _campos = const [];
  bool _carregandoCampos = false;
  bool _camposCarregados = false;
  String? _erroCampos;

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
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar(); // a mensagem nova nao espera a anterior sair da fila
    m.showSnackBar(SnackBar(content: Text(t), backgroundColor: erro ? Colors.red.shade700 : null));
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

  Future<void> _carregarCampos() async {
    final tela = _tela.text.trim();
    if (tela.isEmpty) {
      _aviso('Informe o nome da tela.', erro: true);
      return;
    }
    setState(() {
      _carregandoCampos = true;
      _erroCampos = null;
    });
    try {
      final lista = await _camposSvc.campos(tela);
      if (mounted) setState(() { _campos = lista; _camposCarregados = true; });
    } catch (e) {
      AppLogger.i.warn('DicionarioDadosView: erro ao listar campos: $e');
      if (mounted) setState(() => _erroCampos = '$e');
    }
    if (mounted) setState(() => _carregandoCampos = false);
  }

  Future<void> _alterarRotulo(CampoDicionario c) async {
    final novo = await _pedirTexto('Rótulo do campo ${c.fieldName}', 'Rótulo', c.label,
        ajuda: 'Original: ${c.labelOriginal}. O tipo e o nome do campo não mudam.');
    if (novo == null || novo.trim().isEmpty) return;
    try {
      await _camposSvc.alterarLabel(_tela.text.trim(), c.fieldName, novo.trim());
      _aviso('Rótulo salvo.');
      await _carregarCampos();
    } catch (e) {
      AppLogger.i.warn('DicionarioDadosView: erro ao alterar rótulo: $e');
      _aviso('$e', erro: true);
    }
  }

  Future<void> _incluirCampo() async {
    final r = await showDialog<List<String>>(
      context: context,
      builder: (_) => const _NovoCampoDialog(),
    );
    if (r == null) return;
    try {
      await _camposSvc.incluirCampo(_tela.text.trim(), r[0], r[1], r[2]);
      _aviso('Campo incluído.');
      await _carregarCampos();
    } catch (e) {
      AppLogger.i.warn('DicionarioDadosView: erro ao incluir campo: $e');
      _aviso('$e', erro: true);
    }
  }

  Future<void> _editarLigacao(CampoDicionario c) async {
    final r = await showDialog<_ResultadoLigacao>(
      context: context,
      builder: (_) => _LigacaoDialog(campo: c),
    );
    if (r == null) return;
    try {
      final tela = _tela.text.trim();
      if (r.remover) {
        await _camposSvc.excluirLigacao(tela, c.fieldName);
        _aviso('Ligação removida.');
      } else {
        await _camposSvc.salvarLigacao(tela, r.ligacao!);
        _aviso('Ligação salva.');
      }
      await _carregarCampos();
    } catch (e) {
      AppLogger.i.warn('DicionarioDadosView: erro na ligação: $e');
      _aviso('$e', erro: true);
    }
  }

  Future<String?> _pedirTexto(String titulo, String rotulo, String inicial, {String? ajuda}) {
    final ctrl = TextEditingController(text: inicial);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(titulo),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: ctrl, autofocus: true, maxLength: 100, decoration: InputDecoration(labelText: rotulo)),
          if (ajuda != null) Text(ajuda, style: const TextStyle(fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Salvar')),
        ],
      ),
    );
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
      length: 4,
      child: Column(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Dicionário de Dados',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
        ),
        const TabBar(isScrollable: true, tabs: [
          Tab(text: 'Campos'),
          Tab(text: 'Ligações'),
          Tab(text: 'Ações'),
          Tab(text: 'Eventos'),
        ]),
        Expanded(
          child: TabBarView(children: [_abaCampos(), _abaLigacoes(), _abaAcoes(), _abaEventos()]),
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

  Widget _abaCampos() {
    return Column(children: [
      _filtro(_tela, 'Tela (nome usado nas grids)', 'ex.: produto', _carregarCampos, _carregandoCampos),
      if (_camposCarregados)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
                onPressed: _incluirCampo, icon: const Icon(Icons.add), label: const Text('Incluir campo')),
          ),
        ),
      Expanded(
        child: _carregandoCampos
            ? const Center(child: CircularProgressIndicator())
            : _erroCampos != null
                ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_erroCampos!)))
                : !_camposCarregados
                    ? const Center(child: Text('Informe a tela e toque em Carregar.'))
                    : _campos.isEmpty
                        ? const Center(child: Text('A tela não tem campos.'))
                        : ListView.separated(
                            itemCount: _campos.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final c = _campos[i];
                              return ListTile(
                                minVerticalPadding: 8,
                                title: Text(c.label),
                                subtitle: Text('${c.fieldName} · ${c.fieldType}'
                                    '${c.labelPersonalizado ? ' · original: ${c.labelOriginal}' : ''}'),
                                trailing: IconButton(
                                    tooltip: 'Alterar rótulo',
                                    onPressed: () => _alterarRotulo(c),
                                    icon: const Icon(Icons.edit_outlined)),
                              );
                            }),
      ),
    ]);
  }

  Widget _abaLigacoes() {
    return Column(children: [
      _filtro(_tela, 'Tela (nome usado nas grids)', 'ex.: produto', _carregarCampos, _carregandoCampos),
      Expanded(
        child: _carregandoCampos
            ? const Center(child: CircularProgressIndicator())
            : _erroCampos != null
                ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_erroCampos!)))
                : !_camposCarregados
                    ? const Center(child: Text('Informe a tela e toque em Carregar.'))
                    : ListView.separated(
                        itemCount: _campos.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final c = _campos[i];
                          final l = c.ligacao;
                          return ListTile(
                            minVerticalPadding: 8,
                            leading: Icon(l == null ? Icons.link_off : Icons.link),
                            title: Text(c.label),
                            subtitle: Text(l == null
                                ? '${c.fieldName} · sem ligação'
                                : '${c.fieldName} → ${l.tabelaDestino} (${l.endpoint}) · ${l.campoChave}/${l.campoExibicao}'),
                            trailing: IconButton(
                                tooltip: 'Editar ligação',
                                onPressed: () => _editarLigacao(c),
                                icon: const Icon(Icons.edit_outlined)),
                          );
                        }),
      ),
    ]);
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

class _NovoCampoDialog extends StatefulWidget {
  const _NovoCampoDialog();

  @override
  State<_NovoCampoDialog> createState() => _NovoCampoDialogState();
}

class _NovoCampoDialogState extends State<_NovoCampoDialog> {
  final _form = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _rotulo = TextEditingController();
  String _tipo = 'text';

  @override
  void dispose() {
    _nome.dispose();
    _rotulo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Incluir campo'),
      content: Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextFormField(
            controller: _nome,
            decoration: const InputDecoration(labelText: 'Nome do campo *'),
            validator: (v) => RegExp(r'^[a-z][A-Za-z0-9_]{0,59}$').hasMatch((v ?? '').trim())
                ? null
                : 'Comece com letra minúscula; use letras, números e _',
          ),
          TextFormField(
            controller: _rotulo,
            maxLength: 100,
            decoration: const InputDecoration(labelText: 'Rótulo *'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o rótulo' : null,
          ),
          DropdownButtonFormField<String>(
            initialValue: _tipo,
            decoration: const InputDecoration(labelText: 'Tipo (não pode ser alterado depois)'),
            items: const [
              DropdownMenuItem(value: 'text', child: Text('Texto')),
              DropdownMenuItem(value: 'number', child: Text('Número inteiro')),
              DropdownMenuItem(value: 'decimal', child: Text('Número decimal')),
              DropdownMenuItem(value: 'date', child: Text('Data')),
              DropdownMenuItem(value: 'boolean', child: Text('Sim/Não')),
            ],
            onChanged: (v) => _tipo = v ?? 'text',
          ),
          const SizedBox(height: 8),
          const Text('Só é possível incluir campo em tela da própria empresa; telas compartilhadas aceitam apenas alterar o rótulo.',
              style: TextStyle(fontSize: 12)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(context, [_nome.text.trim(), _rotulo.text.trim(), _tipo]);
          },
          child: const Text('Incluir'),
        ),
      ],
    );
  }
}

class _ResultadoLigacao {
  final LigacaoCampo? ligacao;
  final bool remover;

  const _ResultadoLigacao.salvar(LigacaoCampo l)
      : ligacao = l,
        remover = false;
  const _ResultadoLigacao.remover()
      : ligacao = null,
        remover = true;
}

class _LigacaoDialog extends StatefulWidget {
  final CampoDicionario campo;

  const _LigacaoDialog({required this.campo});

  @override
  State<_LigacaoDialog> createState() => _LigacaoDialogState();
}

class _LigacaoDialogState extends State<_LigacaoDialog> {
  final _form = GlobalKey<FormState>();
  late final _tabela = TextEditingController(text: widget.campo.ligacao?.tabelaDestino ?? '');
  late final _endpoint = TextEditingController(text: widget.campo.ligacao?.endpoint ?? '/api/');
  late final _chave = TextEditingController(text: widget.campo.ligacao?.campoChave ?? 'id');
  late final _exibicao = TextEditingController(text: widget.campo.ligacao?.campoExibicao ?? 'nome');

  @override
  void dispose() {
    for (final c in [_tabela, _endpoint, _chave, _exibicao]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _identificador(String? v) =>
      RegExp(r'^[a-z][a-z0-9_]{0,62}$').hasMatch((v ?? '').trim().toLowerCase()) ? null : 'Use letras minúsculas, números e _';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Ligação de ${widget.campo.fieldName}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextFormField(controller: _tabela, decoration: const InputDecoration(labelText: 'Tabela de destino *'), validator: _identificador),
              TextFormField(
                controller: _endpoint,
                decoration: const InputDecoration(labelText: 'Endpoint da lista *', helperText: 'Caminho interno da API, ex.: /api/parceiro'),
                validator: (v) => RegExp(r'^/api/[a-z0-9_\-]+(/[a-z0-9_\-]+)*$').hasMatch((v ?? '').trim().toLowerCase())
                    ? null
                    : 'Use um caminho interno, ex.: /api/parceiro',
              ),
              TextFormField(controller: _chave, decoration: const InputDecoration(labelText: 'Campo chave'), validator: _identificador),
              TextFormField(controller: _exibicao, decoration: const InputDecoration(labelText: 'Campo exibido'), validator: _identificador),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        if (widget.campo.ligacao != null)
          TextButton(onPressed: () => Navigator.pop(context, const _ResultadoLigacao.remover()), child: const Text('Remover')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
              context,
              _ResultadoLigacao.salvar(LigacaoCampo(
                campo: widget.campo.fieldName,
                tabelaDestino: _tabela.text.trim().toLowerCase(),
                endpoint: _endpoint.text.trim().toLowerCase(),
                campoChave: _chave.text.trim().toLowerCase(),
                campoExibicao: _exibicao.text.trim().toLowerCase(),
              )),
            );
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
