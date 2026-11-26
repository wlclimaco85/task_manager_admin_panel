import 'package:flutter/material.dart';

import '../services/planilha_service.dart';
import '../utils/app_logger.dart';
import '../utils/planilha_tipos.dart';

/// Escolhe o tipo de uma coluna. Devolve a nova definicao; tipo "texto" significa coluna sem tipo.
class TipoDeColunaDialog extends StatefulWidget {
  final String letra;
  final ColunaPlanilha? atual;

  const TipoDeColunaDialog({super.key, required this.letra, this.atual});

  @override
  State<TipoDeColunaDialog> createState() => _TipoDeColunaDialogState();
}

class _TipoDeColunaDialogState extends State<TipoDeColunaDialog> {
  late String _tipo = widget.atual?.tipo ?? 'texto';
  late final _opcoes = TextEditingController(text: widget.atual?.opcoes.join('\n') ?? '');
  String? _erro;

  bool get _temOpcoes => _tipo == 'lista' || _tipo == 'pesquisa';

  /// Pesquisa ligada a um cadastro (veio de uma tabela): continua ligada enquanto o tipo for pesquisa.
  bool get _ligada => _tipo == 'pesquisa' && widget.atual?.endpoint != null;

  @override
  void dispose() {
    _opcoes.dispose();
    super.dispose();
  }

  void _aplicar() {
    final opcoes = {for (final l in _opcoes.text.split('\n')) l.trim()}..remove('');
    if (_temOpcoes && !_ligada && opcoes.isEmpty) {
      setState(() => _erro = 'Escreva pelo menos uma opção, uma por linha.');
      return;
    }
    Navigator.pop(
        context,
        ColunaPlanilha(_tipo,
            opcoes: _temOpcoes && !_ligada ? opcoes.toList() : const [],
            endpoint: _ligada ? widget.atual!.endpoint : null,
            campoRotulo: _ligada ? widget.atual!.campoRotulo : null));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Tipo da coluna ${widget.letra}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: [for (final e in kTiposDeColuna.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() {
                  _tipo = v ?? 'texto';
                  _erro = null;
                }),
              ),
              if (_ligada)
                const Padding(padding: EdgeInsets.only(top: 8), child: Text('Pesquisa no cadastro do sistema.'))
              else if (_temOpcoes)
                TextField(
                  controller: _opcoes,
                  minLines: 4,
                  maxLines: 10,
                  decoration: const InputDecoration(labelText: 'Opções (uma por linha)'),
                ),
              const SizedBox(height: 8),
              const Text('A linha 1 continua sendo o título; o tipo vale da linha 2 em diante.',
                  style: TextStyle(fontSize: 12)),
              if (_erro != null) Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: _aplicar, child: const Text('Aplicar')),
        ],
      );
}

/// Escolha de um valor de lista ou pesquisa. Devolve o texto escolhido ('' limpa a celula).
class EscolherValorDialog extends StatefulWidget {
  final ColunaPlanilha coluna;
  final PlanilhaService servico;

  const EscolherValorDialog({super.key, required this.coluna, required this.servico});

  @override
  State<EscolherValorDialog> createState() => _EscolherValorDialogState();
}

class _EscolherValorDialogState extends State<EscolherValorDialog> {
  List<String> _opcoes = const [];
  bool _buscando = false;
  String? _erro;
  int _pedido = 0;

  bool get _remota => widget.coluna.endpoint != null;

  @override
  void initState() {
    super.initState();
    _filtrar('');
  }

  Future<void> _filtrar(String termo) async {
    if (!_remota) {
      final t = termo.trim().toLowerCase();
      setState(() => _opcoes = widget.coluna.opcoes.where((o) => o.toLowerCase().contains(t)).toList());
      return;
    }
    final pedido = ++_pedido;
    setState(() {
      _buscando = true;
      _erro = null;
    });
    try {
      final r = await widget.servico.pesquisar(widget.coluna.endpoint!, widget.coluna.campoRotulo ?? 'nome', termo);
      if (!mounted || pedido != _pedido) return; // resposta antiga nao sobrescreve a nova
      setState(() => _opcoes = r);
    } catch (e) {
      AppLogger.i.warn('EscolherValorDialog: $e');
      if (!mounted || pedido != _pedido) return;
      setState(() => _erro = '$e');
    }
    if (mounted && pedido == _pedido) setState(() => _buscando = false);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Escolher'),
        content: SizedBox(
          width: 380,
          height: 380,
          child: Column(children: [
            if (widget.coluna.tipo == 'pesquisa')
              TextField(
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Pesquisar', prefixIcon: Icon(Icons.search)),
                onChanged: _filtrar,
              ),
            if (_buscando) const LinearProgressIndicator(),
            if (_erro != null) Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            Expanded(
              child: _opcoes.isEmpty && !_buscando
                  ? const Center(child: Text('Nenhuma opção encontrada.'))
                  : ListView(children: [
                      for (final o in _opcoes) ListTile(title: Text(o), onTap: () => Navigator.pop(context, o)),
                    ]),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Limpar célula')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ],
      );
}
