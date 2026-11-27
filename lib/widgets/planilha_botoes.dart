import 'package:flutter/material.dart';

import '../services/acao_java_service.dart';
import '../services/modulo_java_service.dart';
import '../services/planilha_service.dart';
import '../utils/app_logger.dart';
import '../utils/planilha_acao.dart';
import 'acao_java_dialog.dart';

/// Executa um botao na planilha. Devolve SO as celulas que a rotina mandou gravar (vazio = nada): quem chama as
/// aplica sobre o conteudo ATUAL, para nao apagar o que foi digitado enquanto o servidor respondia.
Future<List<AlteracaoDeCelula>> executarBotaoDaPlanilha(
  BuildContext context, {
  required AcaoJava acao,
  required int planilhaId,
  required Map<String, String> celulas,
  required int linhaAtual,
  required PlanilhaService servico,
  AcaoJavaService? acoes,
}) async {
  void avisar(String texto) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

  var linhas = <Map<String, dynamic>>[];
  if (acao.exigeSelecao) {
    final todas = await showDialog<bool>(
      context: context,
      builder: (c) => SimpleDialog(title: Text('${acao.label}: em quais linhas?'), children: [
        if (linhaAtual > 1)
          SimpleDialogOption(onPressed: () => Navigator.pop(c, false), child: Text('Linha selecionada ($linhaAtual)')),
        SimpleDialogOption(onPressed: () => Navigator.pop(c, true), child: const Text('Todas as linhas com dados')),
      ]),
    );
    if (todas == null || !context.mounted) return const [];
    linhas = linhasParaAcao(celulas, linha: todas ? null : linhaAtual);
    if (linhas.isEmpty) {
      avisar('Não há dados nas linhas escolhidas (a linha 1 é o título).');
      return const [];
    }
  }

  if (acao.tabelaNome != kTabelaPlanilha) {
    // registros reais: o servidor busca cada um pelo codigo, pela mesma execucao das grids
    final codigos = codigosDaColuna(linhas, acao.idColuna);
    if (codigos == null) {
      avisar('A planilha precisa de uma coluna com o título "${acao.idColuna}" com o código do registro.');
      return const [];
    }
    await executarAcaoJava(context, acao, [for (final c in codigos) {'id': c, acao.idColuna: c}], servico: acoes);
    return const [];
  }

  final naPlanilha = _AcaoNaPlanilha(servico, planilhaId, linhas);
  await executarAcaoJava(context, acao, linhas, servico: naPlanilha);
  return naPlanilha.alteracoes;
}

/// Reaproveita a confirmacao e o popup de parametros das grids, trocando so a chamada ao servidor.
class _AcaoNaPlanilha extends AcaoJavaService {
  final PlanilhaService servico;
  final int planilhaId;
  final List<Map<String, dynamic>> linhas;
  List<AlteracaoDeCelula> alteracoes = const [];

  _AcaoNaPlanilha(this.servico, this.planilhaId, this.linhas);

  @override
  Future<AcaoJavaResultado> executar(int acaoId, List<Object?> ids, Map<String, dynamic> parametros) async {
    final j = await servico.executarBotao(planilhaId, acaoId, linhas, parametros);
    alteracoes = [
      for (final a in (j['alteracoes'] as List?) ?? const [])
        AlteracaoDeCelula((a['linha'] as num).toInt(), '${a['coluna']}', '${a['valor']}')
    ];
    return AcaoJavaResultado(sucesso: j['sucesso'] == true, mensagem: '${j['mensagem']}', recarregar: false);
  }
}

/// MASTER: cadastra os botoes que aparecem nesta planilha ou em todas.
class BotoesDaPlanilhaDialog extends StatefulWidget {
  final int planilhaId;
  final AcaoJavaService? acoes;
  final ModuloJavaService? modulos;

  const BotoesDaPlanilhaDialog({super.key, required this.planilhaId, this.acoes, this.modulos});

  @override
  State<BotoesDaPlanilhaDialog> createState() => _BotoesDaPlanilhaDialogState();
}

class _BotoesDaPlanilhaDialogState extends State<BotoesDaPlanilhaDialog> {
  late final AcaoJavaService _acoes = widget.acoes ?? AcaoJavaService();
  late final ModuloJavaService _modulos = widget.modulos ?? ModuloJavaService();
  List<AcaoJava> _lista = const [];
  List<ModuloJava> _listaModulos = const [];
  bool _ocupado = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _executar(() async {
      _listaModulos = await _modulos.listar();
      await _carregar();
    });
  }

  Future<void> _carregar() async => _lista = [
        ...await _acoes.listarTodas(kTabelaPlanilha),
        ...await _acoes.listarTodas('$kTabelaPlanilha:${widget.planilhaId}'),
      ];

  Future<void> _executar(Future<void> Function() tarefa) async {
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    try {
      await tarefa();
    } catch (e) {
      AppLogger.i.warn('BotoesDaPlanilhaDialog: $e');
      _erro = '$e';
    }
    if (mounted) setState(() => _ocupado = false);
  }

  Future<void> _editar(AcaoJava? atual) async {
    final a = await showDialog<AcaoJava>(
      context: context,
      builder: (_) =>
          _BotaoDialog(planilhaId: widget.planilhaId, atual: atual, modulos: _listaModulos, acoes: _acoes),
    );
    if (a == null) return;
    await _executar(() async {
      await _acoes.salvarAcao(a);
      await _carregar();
    });
  }

  Future<void> _excluir(AcaoJava a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(content: Text('Excluir o botão "${a.label}"?'), actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Excluir')),
      ]),
    );
    if (ok != true) return;
    await _executar(() async {
      await _acoes.excluirAcao(a.id!);
      await _carregar();
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Botões de ação (Módulo Java)'),
        content: SizedBox(
          width: 480,
          height: 360,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_ocupado) const LinearProgressIndicator(),
            if (_erro != null) Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            Expanded(
              child: _lista.isEmpty && !_ocupado
                  ? const Center(child: Text('Nenhum botão cadastrado.'))
                  : ListView(children: [
                      for (final a in _lista)
                        ListTile(
                          title: Text(a.label),
                          subtitle: Text([
                            a.telaNome == kTabelaPlanilha ? 'Todas as planilhas' : 'Só nesta planilha',
                            a.tabelaNome == kTabelaPlanilha ? 'valores digitados' : 'registros de ${a.tabelaNome}',
                            if (!a.ativo) 'desativado',
                          ].join(' · ')),
                          onTap: () => _editar(a),
                          trailing: IconButton(
                              tooltip: 'Excluir botão',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _excluir(a)),
                        ),
                    ]),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
          FilledButton(onPressed: _ocupado ? null : () => _editar(null), child: const Text('Novo botão')),
        ],
      );
}

class _BotaoDialog extends StatefulWidget {
  final int planilhaId;
  final AcaoJava? atual;
  final List<ModuloJava> modulos;
  final AcaoJavaService acoes;

  const _BotaoDialog({required this.planilhaId, required this.atual, required this.modulos, required this.acoes});

  @override
  State<_BotaoDialog> createState() => _BotaoDialogState();
}

class _BotaoDialogState extends State<_BotaoDialog> {
  late final _label = TextEditingController(text: widget.atual?.label ?? '');
  late final _confirmacao = TextEditingController(text: widget.atual?.confirmMessage ?? '');
  late final bool _eraDeTabela = widget.atual != null && widget.atual!.tabelaNome != kTabelaPlanilha;
  late bool _deTabela = _eraDeTabela;
  late final _tabela = TextEditingController(text: _eraDeTabela ? widget.atual!.tabelaNome ?? '' : '');
  late final _colunaId = TextEditingController(text: widget.atual?.idColuna ?? 'id');
  late bool _todas = widget.atual?.telaNome == kTabelaPlanilha;
  late bool _exige = widget.atual?.exigeSelecao ?? true;
  late bool _ativo = widget.atual?.ativo ?? true;
  late int? _moduloId = widget.atual?.moduloJavaId;
  late String? _classe = widget.atual?.classe;
  List<String> _classes = const [];
  String? _erro;

  @override
  void initState() {
    super.initState();
    if (_moduloId != null) _carregarClasses(_moduloId!);
  }

  @override
  void dispose() {
    for (final c in [_label, _confirmacao, _tabela, _colunaId]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _carregarClasses(int modulo) async {
    try {
      final r = await widget.acoes.listarClasses(modulo);
      if (!mounted || _moduloId != modulo) return;
      setState(() => _classes = [for (final c in r) if (c.tipo == 'ACAO') c.nome]);
    } catch (e) {
      AppLogger.i.warn('_BotaoDialog: erro ao listar classes: $e');
      if (mounted) setState(() => _erro = '$e');
    }
  }

  void _salvar() {
    final faltando = _label.text.trim().isEmpty
        ? 'Informe o texto do botão.'
        : _moduloId == null || _classe == null || _classe!.isEmpty
            ? 'Escolha o módulo e a classe.'
            : _deTabela && _tabela.text.trim().isEmpty
                ? 'Informe a tabela dos registros.'
                : null;
    if (faltando != null) {
      setState(() => _erro = faltando);
      return;
    }
    Navigator.pop(
      context,
      AcaoJava(
        id: widget.atual?.id,
        telaNome: _todas ? kTabelaPlanilha : '$kTabelaPlanilha:${widget.planilhaId}',
        label: _label.text.trim(),
        icon: widget.atual?.icon ?? 'bolt',
        confirmMessage: _confirmacao.text.trim().isEmpty ? null : _confirmacao.text.trim(),
        moduloJavaId: _moduloId,
        classe: _classe!,
        tabelaNome: _deTabela ? _tabela.text.trim() : kTabelaPlanilha,
        idColuna: _deTabela && _colunaId.text.trim().isNotEmpty ? _colunaId.text.trim() : 'id',
        exigeSelecao: _exige,
        ativo: _ativo,
        ordem: widget.atual?.ordem ?? 0,
        params: widget.atual?.params ?? const [], // parametros do popup sao preservados
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.atual == null ? 'Novo botão' : 'Editar botão'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: _label, decoration: const InputDecoration(labelText: 'Texto do botão *')),
              DropdownButtonFormField<int>(
                initialValue: widget.modulos.any((m) => m.id == _moduloId) ? _moduloId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Módulo Java *'),
                items: [for (final m in widget.modulos) DropdownMenuItem(value: m.id, child: Text(m.descricao.isEmpty ? m.identificador : m.descricao))],
                onChanged: (v) {
                  setState(() {
                    _moduloId = v;
                    _classe = null;
                    _classes = const [];
                  });
                  if (v != null) _carregarClasses(v);
                },
              ),
              DropdownButtonFormField<String>(
                key: ValueKey('classes-$_moduloId-${_classes.length}'),
                initialValue: _classes.contains(_classe) ? _classe : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Classe da ação *'),
                items: [for (final c in _classes) DropdownMenuItem(value: c, child: Text(c.split('.').last))],
                onChanged: (v) => _classe = v,
              ),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mostrar em todas as planilhas'),
                  value: _todas,
                  onChanged: (v) => setState(() => _todas = v)),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Age sobre registros do sistema'),
                  subtitle: Text(_deTabela
                      ? 'A planilha envia só o código; o servidor busca o registro.'
                      : 'A rotina recebe os valores digitados e pode preencher células.'),
                  value: _deTabela,
                  onChanged: (v) => setState(() => _deTabela = v)),
              if (_deTabela) ...[
                TextField(controller: _tabela, decoration: const InputDecoration(labelText: 'Tabela dos registros *')),
                TextField(
                    controller: _colunaId, decoration: const InputDecoration(labelText: 'Título da coluna do código')),
              ],
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Precisa de linhas'),
                  value: _exige,
                  onChanged: (v) => setState(() => _exige = v)),
              TextField(
                  controller: _confirmacao, decoration: const InputDecoration(labelText: 'Mensagem de confirmação')),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ativo'),
                  value: _ativo,
                  onChanged: (v) => setState(() => _ativo = v)),
              if (_erro != null) Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: _salvar, child: const Text('Salvar')),
        ],
      );
}
