import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/modulo_java_service.dart';
import '../utils/app_logger.dart';

/// Tela "Módulo Java" (plataforma low-code, Etapa 1), no padrão do Sankhya:
/// lista de módulos (Módulo, Identificador, Descrição) e detalhe com as abas
/// "Geral" e "Arquivo Módulo (Jar)". Mesma tela em Web/Windows/Mobile; em
/// largura estreita a lista e o detalhe se alternam (layout vertical).
class ModuloJavaView extends StatefulWidget {
  final ModuloJavaService? servico;

  const ModuloJavaView({super.key, this.servico});

  @override
  State<ModuloJavaView> createState() => _ModuloJavaViewState();
}

class _ModuloJavaViewState extends State<ModuloJavaView> {
  late final ModuloJavaService _servico = widget.servico ?? ModuloJavaService();

  List<ModuloJava> _modulos = const [];
  ModuloJava? _selecionado;
  bool _novo = false;
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar({int? manterId}) async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final lista = await _servico.listar();
      if (!mounted) return;
      setState(() {
        _modulos = lista;
        final id = manterId ?? _selecionado?.id;
        _selecionado = id == null
            ? null
            : lista.cast<ModuloJava?>().firstWhere((m) => m?.id == id,
                orElse: () => null);
        if (_selecionado == null && !_novo) _novo = false;
      });
    } catch (e, st) {
      AppLogger.i.error('ModuloJavaView: erro ao listar: $e', st);
      if (mounted) setState(() => _erro = '$e');
    }
    if (mounted) setState(() => _carregando = false);
  }

  void _abrirNovo() => setState(() {
        _selecionado = null;
        _novo = true;
      });

  void _selecionar(ModuloJava m) => setState(() {
        _selecionado = m;
        _novo = false;
      });

  void _fecharDetalhe() => setState(() {
        _selecionado = null;
        _novo = false;
      });

  bool get _temDetalhe => _novo || _selecionado != null;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final largo = c.maxWidth >= 900;
      final lista = _ListaModulos(
        modulos: _modulos,
        selecionado: _selecionado,
        carregando: _carregando,
        erro: _erro,
        onNovo: _abrirNovo,
        onSelecionar: _selecionar,
        onAtualizar: _carregar,
      );
      final detalhe = _temDetalhe
          ? _DetalheModulo(
              key: ValueKey(_selecionado?.id ?? 'novo'),
              servico: _servico,
              modulo: _selecionado,
              onSalvo: (m) {
                _novo = false;
                _carregar(manterId: m.id);
              },
              onExcluido: () {
                _fecharDetalhe();
                _carregar();
              },
              onFechar: largo ? null : _fecharDetalhe,
            )
          : const Center(
              child: Text('Selecione um módulo ou crie um novo.'));
      if (largo) {
        return Row(children: [
          SizedBox(width: 380, child: lista),
          const VerticalDivider(width: 1),
          Expanded(child: detalhe),
        ]);
      }
      return _temDetalhe ? detalhe : lista;
    });
  }
}

class _ListaModulos extends StatelessWidget {
  final List<ModuloJava> modulos;
  final ModuloJava? selecionado;
  final bool carregando;
  final String? erro;
  final VoidCallback onNovo;
  final void Function(ModuloJava) onSelecionar;
  final VoidCallback onAtualizar;

  const _ListaModulos({
    required this.modulos,
    required this.selecionado,
    required this.carregando,
    required this.erro,
    required this.onNovo,
    required this.onSelecionar,
    required this.onAtualizar,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Expanded(
            child: Text('Módulo Java',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          IconButton(
              tooltip: 'Atualizar',
              onPressed: onAtualizar,
              icon: const Icon(Icons.refresh)),
          FilledButton.icon(
              onPressed: onNovo,
              icon: const Icon(Icons.add),
              label: const Text('Novo')),
        ]),
      ),
      if (erro != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(erro!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      Expanded(
        child: carregando
            ? const Center(child: CircularProgressIndicator())
            : modulos.isEmpty
                ? const Center(child: Text('Nenhum módulo cadastrado.'))
                : ListView.separated(
                    itemCount: modulos.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final m = modulos[i];
                      return ListTile(
                        minVerticalPadding: 12,
                        selected: m.id == selecionado?.id,
                        leading: CircleAvatar(child: Text('${m.id}')),
                        title: Text(m.descricao),
                        subtitle: Text(m.identificador),
                        trailing: m.ativo
                            ? null
                            : const Chip(label: Text('Inativo')),
                        onTap: () => onSelecionar(m),
                      );
                    }),
      ),
    ]);
  }
}

class _DetalheModulo extends StatefulWidget {
  final ModuloJavaService servico;
  final ModuloJava? modulo;
  final void Function(ModuloJava) onSalvo;
  final VoidCallback onExcluido;
  final VoidCallback? onFechar;

  const _DetalheModulo({
    super.key,
    required this.servico,
    required this.modulo,
    required this.onSalvo,
    required this.onExcluido,
    this.onFechar,
  });

  @override
  State<_DetalheModulo> createState() => _DetalheModuloState();
}

class _DetalheModuloState extends State<_DetalheModulo> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _descricao =
      TextEditingController(text: widget.modulo?.descricao ?? '');
  late final TextEditingController _identificador =
      TextEditingController(text: widget.modulo?.identificador ?? '');
  late bool _ativo = widget.modulo?.ativo ?? true;
  bool _salvando = false;

  List<ModuloJavaArquivo> _arquivos = const [];
  bool _carregandoArquivos = false;
  bool _enviando = false;

  bool get _existe => widget.modulo?.id != null;

  @override
  void initState() {
    super.initState();
    if (_existe) _carregarArquivos();
  }

  @override
  void dispose() {
    _descricao.dispose();
    _identificador.dispose();
    super.dispose();
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _carregarArquivos() async {
    setState(() => _carregandoArquivos = true);
    try {
      final lista = await widget.servico.listarArquivos(widget.modulo!.id!);
      if (mounted) setState(() => _arquivos = lista);
    } catch (e) {
      AppLogger.i.warn('ModuloJavaView: erro ao listar arquivos: $e');
      _aviso('$e');
    }
    if (mounted) setState(() => _carregandoArquivos = false);
  }

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _salvando = true);
    try {
      final salvo = await widget.servico.salvar(ModuloJava(
        id: widget.modulo?.id,
        identificador: _identificador.text.trim(),
        descricao: _descricao.text.trim(),
        ativo: _ativo,
      ));
      _aviso('Módulo salvo.');
      widget.onSalvo(salvo);
    } catch (e) {
      AppLogger.i.warn('ModuloJavaView: erro ao salvar: $e');
      _aviso('$e');
    }
    if (mounted) setState(() => _salvando = false);
  }

  Future<void> _excluir() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir módulo'),
        content: const Text(
            'Excluir este módulo e todos os seus arquivos .jar? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.servico.excluir(widget.modulo!.id!);
      _aviso('Módulo excluído.');
      widget.onExcluido();
    } catch (e) {
      AppLogger.i.warn('ModuloJavaView: erro ao excluir: $e');
      _aviso('$e');
    }
  }

  Future<void> _enviarJar() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jar'],
      withData: true,
    );
    if (r == null || r.files.isEmpty) return;
    final arquivo = r.files.first;
    final erro = ModuloJavaService.validarArquivo(arquivo.name, arquivo.size);
    if (erro != null) {
      _aviso(erro);
      return;
    }
    setState(() => _enviando = true);
    try {
      final novo = await widget.servico.enviarArquivo(widget.modulo!.id!, arquivo);
      _aviso('Arquivo ${novo.nomeArquivo} enviado (versão ${novo.versao}).');
      await _carregarArquivos();
    } catch (e) {
      AppLogger.i.warn('ModuloJavaView: erro no upload: $e');
      _aviso('$e');
    }
    if (mounted) setState(() => _enviando = false);
  }

  Future<void> _excluirArquivo(ModuloJavaArquivo a) async {
    try {
      await widget.servico.excluirArquivo(widget.modulo!.id!, a.id);
      await _carregarArquivos();
    } catch (e) {
      AppLogger.i.warn('ModuloJavaView: erro ao excluir arquivo: $e');
      _aviso('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(children: [
            if (widget.onFechar != null)
              IconButton(
                  tooltip: 'Voltar',
                  onPressed: widget.onFechar,
                  icon: const Icon(Icons.arrow_back)),
            Expanded(
              child: Text(
                _existe
                    ? '${widget.modulo!.id} - ${widget.modulo!.descricao}'
                    : 'Novo módulo',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            if (_existe)
              IconButton(
                  tooltip: 'Excluir',
                  onPressed: _excluir,
                  icon: const Icon(Icons.delete_outline)),
          ]),
        ),
        const TabBar(tabs: [
          Tab(text: 'Geral'),
          Tab(text: 'Arquivo Módulo (Jar)'),
        ]),
        Expanded(
          child: TabBarView(children: [_abaGeral(), _abaArquivos()]),
        ),
      ]),
    );
  }

  Widget _abaGeral() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextFormField(
            controller: _descricao,
            decoration: const InputDecoration(labelText: 'Descrição *'),
            maxLength: 255,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Informe a descrição' : null,
          ),
          TextFormField(
            controller: _identificador,
            enabled: !_existe,
            decoration: const InputDecoration(labelText: 'Identificador *'),
            maxLength: 200,
            validator: (v) {
              final t = v?.trim() ?? '';
              if (t.isEmpty) return 'Informe o identificador';
              if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(t)) {
                return 'Use letras, números, ponto, hífen e sublinhado';
              }
              return null;
            },
          ),
          const SizedBox(height: 4),
          const Text(
            'Atenção: o identificador é a única forma de evitar conflitos entre módulos '
            'e não pode ser alterado depois de criado. Use como prefixo o domínio da sua '
            'empresa, por exemplo "br.com.suaempresa.modulo-1.0.0".',
            style: TextStyle(fontSize: 12),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ativo'),
            value: _ativo,
            onChanged: (v) => setState(() => _ativo = v),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _salvando ? null : _salvar,
            icon: _salvando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: const Text('Salvar'),
          ),
        ]),
      ),
    );
  }

  Widget _abaArquivos() {
    if (!_existe) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Salve o módulo para enviar arquivos .jar.'),
      ));
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          FilledButton.icon(
            onPressed: _enviando ? null : _enviarJar,
            icon: _enviando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_file),
            label: const Text('Enviar .jar'),
          ),
          const SizedBox(width: 8),
          IconButton(
              tooltip: 'Atualizar',
              onPressed: _carregarArquivos,
              icon: const Icon(Icons.refresh)),
          const Spacer(),
          const Text('Máx. 10 MB', style: TextStyle(fontSize: 12)),
        ]),
      ),
      Expanded(
        child: _carregandoArquivos
            ? const Center(child: CircularProgressIndicator())
            : _arquivos.isEmpty
                ? const Center(child: Text('Nenhum arquivo enviado.'))
                : ListView.separated(
                    itemCount: _arquivos.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final a = _arquivos[i];
                      return ListTile(
                        minVerticalPadding: 10,
                        leading: CircleAvatar(child: Text('${a.id}')),
                        title: Text('${a.nomeArquivo}  (v${a.versao})'),
                        subtitle: Text(
                          '${_formatarTamanho(a.tamanho)} · SHA-256 ${a.sha256.length >= 12 ? a.sha256.substring(0, 12) : a.sha256}…'
                          '${a.classes.isEmpty ? '\nSem classes do SDK' : '\n${a.classes.join('\n')}'}',
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                            tooltip: 'Excluir arquivo',
                            onPressed: () => _excluirArquivo(a),
                            icon: const Icon(Icons.delete_outline)),
                      );
                    }),
      ),
    ]);
  }

  static String _formatarTamanho(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
}
