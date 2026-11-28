import 'package:flutter/material.dart';

import '../utils/campo_calculado.dart';

/// Lista das colunas por SELECT de um relatorio ou componente de dashboard, com incluir, editar e remover.
class ColunasPorSelect extends StatelessWidget {
  final List<CampoCalculado> campos;

  /// Colunas do ultimo "Testar": sao as opcoes de onde cada parametro pode vir.
  final List<String> colunas;
  final ValueChanged<List<CampoCalculado>> aoMudar;

  const ColunasPorSelect({super.key, required this.campos, required this.colunas, required this.aoMudar});

  Future<void> _abrir(BuildContext context, [int? i]) async {
    if (colunas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Clique em "Testar" antes: as colunas do resultado são as opções dos parâmetros.')));
      return;
    }
    final c = await showDialog<CampoCalculado>(
        context: context,
        builder: (_) => ColunaPorSelectDialog(colunas: colunas, editando: i == null ? null : campos[i]));
    if (c == null) return;
    final novos = List.of(campos);
    if (i == null) {
      novos.add(c);
    } else {
      novos[i] = c;
    }
    aoMudar(novos);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < campos.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.manage_search),
          title: Text(campos[i].coluna),
          subtitle: Text(campos[i].parametros.entries.map((p) => ':${p.key} = ${p.value}').join(', ')),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
                tooltip: 'Editar coluna por SELECT',
                onPressed: () => _abrir(context, i),
                icon: const Icon(Icons.edit_outlined)),
            IconButton(
                tooltip: 'Remover coluna por SELECT',
                onPressed: () => aoMudar(List.of(campos)..removeAt(i)),
                icon: const Icon(Icons.delete_outline)),
          ]),
        ),
      TextButton.icon(
        onPressed: () => _abrir(context),
        icon: const Icon(Icons.manage_search),
        label: const Text('Coluna por SELECT'),
      ),
    ]);
  }
}

class ColunaPorSelectDialog extends StatefulWidget {
  final List<String> colunas;
  final CampoCalculado? editando;

  const ColunaPorSelectDialog({super.key, required this.colunas, this.editando});

  @override
  State<ColunaPorSelectDialog> createState() => _ColunaPorSelectDialogState();
}

class _ColunaPorSelectDialogState extends State<ColunaPorSelectDialog> {
  late final _nome = TextEditingController(text: widget.editando?.coluna ?? '');
  late final _sql = TextEditingController(text: widget.editando?.sql ?? '');
  late final Map<String, String> _origem = Map.of(widget.editando?.parametros ?? const {});
  String? _erro;

  @override
  void dispose() {
    _nome.dispose();
    _sql.dispose();
    super.dispose();
  }

  void _salvar() {
    final parametros = parametrosDoSelect(_sql.text);
    String? erro;
    if (_nome.text.trim().isEmpty) {
      erro = 'Informe o nome da coluna. Se já existir no resultado, o valor dela é substituído.';
    } else if (parametros.isEmpty) {
      erro = 'Use ao menos um parâmetro no SELECT, por exemplo :codigo.';
    } else if (parametros.any((p) => !widget.colunas.contains(_origem[p]))) {
      erro = 'Escolha a coluna de cada parâmetro.';
    }
    if (erro != null) {
      setState(() => _erro = erro);
      return;
    }
    Navigator.pop(
        context,
        CampoCalculado(
            coluna: _nome.text.trim(),
            sql: _sql.text.trim(),
            parametros: {for (final p in parametros) p: _origem[p]!}));
  }

  @override
  Widget build(BuildContext context) {
    final parametros = parametrosDoSelect(_sql.text);
    return AlertDialog(
      title: const Text('Coluna por SELECT'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              key: const Key('coluna-nome'),
              controller: _nome,
              maxLength: 63,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Nome da coluna',
                  helperText: 'Nome novo cria a coluna no fim; nome existente troca o valor dela.',
                  helperMaxLines: 2),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('coluna-sql'),
              controller: _sql,
              minLines: 4,
              maxLines: 10,
              style: const TextStyle(fontFamily: 'monospace'),
              onChanged: (_) => setState(() => _erro = null),
              decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'SELECT que devolve o valor',
                  hintText: 'SELECT nome FROM parceiro WHERE id = :codigo',
                  helperText: 'Usa a primeira coluna da primeira linha. Empresa e parceiro do login são filtrados '
                      'automaticamente.',
                  helperMaxLines: 3),
            ),
            for (final p in parametros) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('origem-$p'),
                initialValue: widget.colunas.contains(_origem[p]) ? _origem[p] : null,
                isExpanded: true,
                decoration: InputDecoration(border: const OutlineInputBorder(), labelText: ':$p vem da coluna'),
                items: [for (final c in widget.colunas) DropdownMenuItem(value: c, child: Text(c))],
                onChanged: (v) => setState(() {
                  if (v != null) _origem[p] = v;
                  _erro = null;
                }),
              ),
            ],
            if (_erro != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
        FilledButton(onPressed: _salvar, child: const Text('Salvar coluna')),
      ],
    );
  }
}
