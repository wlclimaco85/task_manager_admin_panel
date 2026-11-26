import 'package:flutter/material.dart';

import '../utils/planilha_acrescentar.dart';
import '../utils/planilha_tabela.dart';

/// Como juntar o arquivo importado a uma planilha que ja tem dados.
class EscolhaImportacao {
  final bool substituir;
  final String? colunaChave;
  final LinhaRepetida repetida;

  const EscolhaImportacao.substituir()
      : substituir = true,
        colunaChave = null,
        repetida = LinhaRepetida.ignorar;

  const EscolhaImportacao.acrescentar({this.colunaChave, this.repetida = LinhaRepetida.ignorar}) : substituir = false;
}

class ImportarPlanilhaDialog extends StatefulWidget {
  final Map<String, String> atual;
  final Map<String, String> arquivo;

  const ImportarPlanilhaDialog({super.key, required this.atual, required this.arquivo});

  @override
  State<ImportarPlanilhaDialog> createState() => _ImportarPlanilhaDialogState();
}

class _ImportarPlanilhaDialogState extends State<ImportarPlanilhaDialog> {
  bool _substituir = false;
  String? _chave;
  LinhaRepetida _repetida = LinhaRepetida.ignorar;

  /// So pode ser chave a coluna que existe nos dois lados.
  late final List<String> _comuns = () {
    final atuais = tabelaDaPlanilha(widget.atual).colunas.map(chaveDeTitulo).toSet();
    return tabelaDaPlanilha(widget.arquivo).colunas.where((c) => atuais.contains(chaveDeTitulo(c))).toList();
  }();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Importar para esta planilha'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(
                label: const Text('Acrescentar linhas'),
                selected: !_substituir,
                onSelected: (_) => setState(() => _substituir = false),
              ),
              ChoiceChip(
                label: const Text('Substituir tudo'),
                selected: _substituir,
                onSelected: (_) => setState(() => _substituir = true),
              ),
            ]),
            const SizedBox(height: 12),
            if (_substituir)
              const Text('Todo o conteúdo atual da tela é trocado pelo do arquivo.')
            else ...[
              const Text('As colunas são casadas pelo título da linha 1. Título novo vira coluna no fim.'),
              DropdownButtonFormField<String?>(
                initialValue: _chave,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Coluna que identifica a linha'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Nenhuma (acrescentar todas)')),
                  for (final c in _comuns) DropdownMenuItem<String?>(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => _chave = v),
              ),
              if (_chave != null)
                DropdownButtonFormField<LinhaRepetida>(
                  initialValue: _repetida,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Linha que já existe'),
                  items: const [
                    DropdownMenuItem(value: LinhaRepetida.ignorar, child: Text('Ignorar a do arquivo')),
                    DropdownMenuItem(value: LinhaRepetida.atualizar, child: Text('Atualizar com os dados do arquivo')),
                  ],
                  onChanged: (v) => setState(() => _repetida = v ?? LinhaRepetida.ignorar),
                ),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(
              context,
              _substituir
                  ? const EscolhaImportacao.substituir()
                  : EscolhaImportacao.acrescentar(colunaChave: _chave, repetida: _repetida)),
          child: const Text('Importar'),
        ),
      ],
    );
  }
}
