import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/acao_java_service.dart';
import '../utils/app_logger.dart';

/// Ultimos valores digitados por acao/parametro (para os parametros com "sugerir ultimo valor").
final Map<String, String> _ultimosValores = {};

/// Valida o valor digitado de um parametro e devolve a mensagem de erro (ou null). Exposta para teste.
String? validarParametroAcaoJava(AcaoJavaParam p, String? bruto) {
  final v = bruto?.trim() ?? '';
  if (v.isEmpty) {
    return p.obrigatorio ? 'Informe ${p.descricao}' : null;
  }
  switch (p.tipo) {
    case 'INTEIRO':
      return int.tryParse(v) == null ? 'Número inteiro inválido' : null;
    case 'DECIMAL':
      return double.tryParse(v.replaceAll(',', '.')) == null
          ? 'Número inválido'
          : null;
    case 'DATA':
      return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) &&
              DateTime.tryParse(v) != null
          ? null
          : 'Use a data no formato AAAA-MM-DD';
    case 'LISTA':
      return p.listaOpcoes.contains(v) ? null : 'Escolha uma opção da lista';
    default:
      return null;
  }
}

/// Executa uma acao Java sobre as linhas selecionadas: confirma, pede os parametros num popup (se houver),
/// chama o servidor e mostra o resultado. Devolve true quando a grid deve recarregar.
Future<bool> executarAcaoJava(
  BuildContext context,
  AcaoJava acao,
  List<Map<String, dynamic>> linhas, {
  String idField = 'id',
  AcaoJavaService? servico,
}) async {
  final svc = servico ?? AcaoJavaService();
  final ids = linhas
      .map((l) => l[acao.idColuna == 'id' ? idField : acao.idColuna] ?? l[idField])
      .where((v) => v != null)
      .toList();

  Map<String, dynamic>? parametros = {};
  if (acao.params.isNotEmpty) {
    parametros = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AcaoJavaParametrosDialog(acao: acao, qtd: linhas.length),
    );
    if (parametros == null) return false;
  } else {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(acao.label),
        content: Text(acao.confirmMessage ??
            'Executar "${acao.label}" em ${linhas.length} registro(s)?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Executar')),
        ],
      ),
    );
    if (ok != true) return false;
  }
  if (!context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  try {
    final r = await svc.executar(acao.id!, ids, parametros);
    messenger.showSnackBar(SnackBar(
      content: Text(r.mensagem),
      backgroundColor: r.sucesso ? null : Colors.red.shade700,
    ));
    return r.sucesso && r.recarregar;
  } catch (e) {
    AppLogger.i.warn('executarAcaoJava: ${acao.label} falhou: $e');
    messenger.showSnackBar(SnackBar(
        content: Text('$e'), backgroundColor: Colors.red.shade700));
    return false;
  }
}

class _AcaoJavaParametrosDialog extends StatefulWidget {
  final AcaoJava acao;
  final int qtd;

  const _AcaoJavaParametrosDialog({required this.acao, required this.qtd});

  @override
  State<_AcaoJavaParametrosDialog> createState() =>
      _AcaoJavaParametrosDialogState();
}

class _AcaoJavaParametrosDialogState extends State<_AcaoJavaParametrosDialog> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _ctrl = {
    for (final p in widget.acao.params)
      p.nome: TextEditingController(
          text: p.sugerirUltimo
              ? (_ultimosValores['${widget.acao.id}:${p.nome}'] ?? '')
              : ''),
  };
  final Map<String, bool> _logicos = {};

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _campo(AcaoJavaParam p) {
    final rotulo = p.obrigatorio ? '${p.descricao} *' : p.descricao;
    switch (p.tipo) {
      case 'LOGICO':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(rotulo),
          value: _logicos[p.nome] ?? false,
          onChanged: (v) => setState(() => _logicos[p.nome] = v),
        );
      case 'LISTA':
        final opcoes = p.listaOpcoes;
        final atual = _ctrl[p.nome]!.text;
        return DropdownButtonFormField<String>(
          initialValue: opcoes.contains(atual) ? atual : null,
          decoration: InputDecoration(labelText: rotulo),
          items: [
            for (final o in opcoes) DropdownMenuItem(value: o, child: Text(o)),
          ],
          onChanged: (v) => _ctrl[p.nome]!.text = v ?? '',
          validator: (v) => validarParametroAcaoJava(p, v),
        );
      default:
        final numerico = p.tipo == 'INTEIRO' || p.tipo == 'DECIMAL';
        return TextFormField(
          controller: _ctrl[p.nome],
          decoration: InputDecoration(
            labelText: rotulo,
            hintText: p.tipo == 'DATA' ? 'AAAA-MM-DD' : null,
          ),
          keyboardType: numerico ? TextInputType.number : TextInputType.text,
          inputFormatters: p.tipo == 'INTEIRO'
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]'))]
              : null,
          validator: (v) => validarParametroAcaoJava(p, v),
        );
    }
  }

  void _confirmar() {
    if (!_form.currentState!.validate()) return;
    final valores = <String, dynamic>{};
    for (final p in widget.acao.params) {
      if (p.tipo == 'LOGICO') {
        valores[p.nome] = _logicos[p.nome] ?? false;
        continue;
      }
      final v = _ctrl[p.nome]!.text.trim();
      if (v.isEmpty) continue;
      valores[p.nome] = v;
      if (p.sugerirUltimo) _ultimosValores['${widget.acao.id}:${p.nome}'] = v;
    }
    Navigator.pop(context, valores);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.acao.label),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.acao.confirmMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(widget.acao.confirmMessage!),
                  ),
                Text('${widget.qtd} registro(s) selecionado(s)',
                    style: const TextStyle(fontSize: 12)),
                for (final p in widget.acao.params) _campo(p),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(onPressed: _confirmar, child: const Text('Executar')),
      ],
    );
  }
}

/// Icone (nome textual vindo do servidor) -> IconData; "bolt" (raio) e o padrao.
IconData iconeAcaoJava(String? nome) {
  switch (nome) {
    case 'add':
      return Icons.add_circle_outline;
    case 'check':
    case 'done':
      return Icons.check_circle_outline;
    case 'send':
      return Icons.send;
    case 'sync':
    case 'refresh':
      return Icons.sync;
    case 'file':
    case 'description':
      return Icons.description_outlined;
    default:
      return Icons.bolt;
  }
}
