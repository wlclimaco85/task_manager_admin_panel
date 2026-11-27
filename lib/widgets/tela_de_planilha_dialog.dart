import 'package:flutter/material.dart';

import '../services/planilha_service.dart';
import '../utils/app_logger.dart';
import '../utils/planilha_tabela.dart';
import '../utils/planilha_tenant.dart';

/// Dados confirmados para criar uma tela com dados proprios a partir de uma planilha salva.
class PedidoTelaDePlanilha {
  final String titulo;
  final TabelaDaPlanilha tabela;

  const PedidoTelaDePlanilha(this.titulo, this.tabela);
}

class TelaDePlanilhaDialog extends StatefulWidget {
  final PlanilhaService? servico;

  const TelaDePlanilhaDialog({super.key, this.servico});

  @override
  State<TelaDePlanilhaDialog> createState() => _TelaDePlanilhaDialogState();
}

class _TelaDePlanilhaDialogState extends State<TelaDePlanilhaDialog> {
  late final PlanilhaService _svc = widget.servico ?? PlanilhaService();
  final _titulo = TextEditingController();
  List<PlanilhaResumo>? _planilhas;
  TabelaDaPlanilha? _tabela;
  int? _id;
  String? _erro;
  bool _lendo = false;

  @override
  void initState() {
    super.initState();
    _listar();
  }

  @override
  void dispose() {
    _titulo.dispose();
    super.dispose();
  }

  Future<void> _listar() async {
    try {
      final lista = await _svc.listar();
      if (mounted) setState(() => _planilhas = lista);
    } catch (e) {
      AppLogger.i.warn('TelaDePlanilhaDialog: erro ao listar planilhas: $e');
      if (mounted) {
        setState(() {
          _planilhas = const [];
          _erro = '$e';
        });
      }
    }
  }

  Future<void> _escolher(int id) async {
    setState(() {
      _id = id;
      _tabela = null;
      _erro = null;
      _lendo = true;
    });
    try {
      final p = await _svc.abrir(id);
      if (!mounted || _id != id) return;
      final t = semColunasDeTenant(tabelaDaPlanilha(p.celulas));
      setState(() {
        _tabela = t;
        if (_titulo.text.trim().isEmpty) _titulo.text = p.nome;
        if (t.colunas.isEmpty) {
          _erro = 'Escreva os títulos das colunas na linha 1 da planilha.';
        } else if (t.comErro.isNotEmpty) {
          _erro = 'Corrija as fórmulas com erro nas células: ${t.comErro.take(10).join(', ')}.';
        }
      });
    } catch (e) {
      AppLogger.i.warn('TelaDePlanilhaDialog: erro ao abrir planilha $id: $e');
      if (mounted) setState(() => _erro = '$e');
    }
    if (mounted) setState(() => _lendo = false);
  }

  @override
  Widget build(BuildContext context) {
    final planilhas = _planilhas;
    final t = _tabela;
    final pronto = t != null && t.colunas.isNotEmpty && t.comErro.isEmpty;
    return AlertDialog(
      title: const Text('Tela a partir de planilha'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('A linha 1 vira os campos da tela e as demais linhas viram os primeiros registros. '
                'Depois de criada, a tela não muda se a planilha mudar.'),
            const SizedBox(height: 12),
            if (planilhas == null)
              const LinearProgressIndicator()
            else if (planilhas.isEmpty)
              const Text('Nenhuma planilha salva.')
            else
              DropdownButtonFormField<int>(
                initialValue: _id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Planilha *'),
                items: [for (final p in planilhas) DropdownMenuItem(value: p.id, child: Text(p.nome))],
                onChanged: (v) {
                  if (v != null) _escolher(v);
                },
              ),
            if (_lendo) const LinearProgressIndicator(),
            if (pronto) ...[
              const SizedBox(height: 8),
              Text('${t.colunas.length} campo(s): ${t.colunas.join(', ')}'),
              Text('${t.linhas.length} registro(s) serão importados.'),
              if (t.ignoradas.isNotEmpty)
                Text('Colunas sem título na linha 1 ficam de fora: ${t.ignoradas.join(', ')}.'),
              TextField(
                controller: _titulo,
                maxLength: 150,
                decoration: const InputDecoration(labelText: 'Título da tela *'),
              ),
            ],
            if (_erro != null) Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: !pronto
              ? null
              : () {
                  final titulo = _titulo.text.trim();
                  if (titulo.isEmpty) {
                    setState(() => _erro = 'Informe o título da tela.');
                    return;
                  }
                  Navigator.pop(context, PedidoTelaDePlanilha(titulo, t));
                },
          child: const Text('Criar'),
        ),
      ],
    );
  }
}
