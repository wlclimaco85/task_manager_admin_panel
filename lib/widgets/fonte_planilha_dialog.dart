import 'package:flutter/material.dart';

import '../services/planilha_service.dart';
import '../utils/app_logger.dart';
import '../utils/planilha_formula.dart';

/// Escolhe a planilha e as colunas que alimentam um componente de dashboard.
/// Devolve a fonte no formato do servidor: "planilha:12:A,C".
class FontePlanilhaDialog extends StatefulWidget {
  final PlanilhaService? servico;

  const FontePlanilhaDialog({super.key, this.servico});

  @override
  State<FontePlanilhaDialog> createState() => _FontePlanilhaDialogState();
}

class _FontePlanilhaDialogState extends State<FontePlanilhaDialog> {
  late final PlanilhaService _svc = widget.servico ?? PlanilhaService();
  List<PlanilhaResumo>? _planilhas;
  int? _id;
  Map<int, String> _titulos = const {};
  final List<int> _escolhidas = []; // na ordem em que foram marcadas
  String? _erro;
  bool _lendo = false;

  @override
  void initState() {
    super.initState();
    _tentar(() async => _planilhas = await _svc.listar(), aoFalhar: () => _planilhas = const []);
  }

  Future<void> _tentar(Future<void> Function() tarefa, {VoidCallback? aoFalhar}) async {
    try {
      await tarefa();
      _erro = null;
    } catch (e) {
      AppLogger.i.warn('FontePlanilhaDialog: $e');
      _erro = '$e';
      aoFalhar?.call();
    }
    if (mounted) setState(() {});
  }

  Future<void> _escolher(int id) async {
    setState(() {
      _id = id;
      _titulos = const {};
      _escolhidas.clear();
      _lendo = true;
    });
    await _tentar(() async {
      final p = await _svc.abrir(id);
      if (_id != id) return;
      final calculo = PlanilhaCalculo(p.celulas);
      final titulos = <int, String>{};
      for (final ref in p.celulas.keys) {
        final pos = posicao(ref);
        if (pos == null || pos.$1 != 0) continue;
        final texto = calculo.exibir(ref).trim();
        if (texto.isNotEmpty) titulos[pos.$2] = texto;
      }
      _titulos = {for (final c in titulos.keys.toList()..sort()) c: titulos[c]!};
      if (_titulos.isEmpty) throw const PlanilhaException('A planilha precisa de títulos na linha 1.');
    });
    if (mounted) setState(() => _lendo = false);
  }

  @override
  Widget build(BuildContext context) {
    final planilhas = _planilhas;
    return AlertDialog(
      title: const Text('Usar planilha como fonte'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Em gráficos, marque primeiro a coluna dos nomes e depois as dos valores. '
                'Quem vê o dashboard, no mesmo cadastro, vê esses dados.'),
            if (planilhas == null || _lendo) const LinearProgressIndicator(),
            if (planilhas != null && planilhas.isEmpty && _erro == null) const Text('Nenhuma planilha salva.'),
            if (planilhas != null && planilhas.isNotEmpty)
              DropdownButtonFormField<int>(
                initialValue: _id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Planilha'),
                items: [for (final p in planilhas) DropdownMenuItem(value: p.id, child: Text(p.nome))],
                onChanged: (v) {
                  if (v != null) _escolher(v);
                },
              ),
            for (final e in _titulos.entries)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(e.value),
                subtitle: Text(_escolhidas.contains(e.key)
                    ? 'Coluna ${nomeColuna(e.key)} · ${_escolhidas.indexOf(e.key) + 1}ª'
                    : 'Coluna ${nomeColuna(e.key)}'),
                value: _escolhidas.contains(e.key),
                onChanged: (v) => setState(() => v == true ? _escolhidas.add(e.key) : _escolhidas.remove(e.key)),
              ),
            if (_erro != null) Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _escolhidas.isEmpty
              ? null
              : () => Navigator.pop(context, 'planilha:$_id:${_escolhidas.map(nomeColuna).join(',')}'),
          child: const Text('Usar'),
        ),
      ],
    );
  }
}
