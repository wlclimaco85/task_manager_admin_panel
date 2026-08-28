import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Card reutilizavel para acoes administrativas server-side (dashboard de
/// "Config. Sistema" — Fase 2, Task 05.2). Reune o padrao repetido no
/// arquivo original (`configuracoes_sistema_screen.dart`, `_actionCard`/
/// `_seedCard`/`_deleteEmpresaCard`): titulo/subtitulo/icone, estado de
/// carregamento no botao, e um card de resultado (JSON formatado) ou erro
/// apos a execucao.
///
/// [onExecute] deve retornar o corpo da resposta do backend em caso de
/// sucesso, ou lancar uma excecao em caso de falha (o card converte a
/// excecao em um card de erro). Retornar `null` sinaliza que a acao foi
/// cancelada (ex.: dialog de confirmacao nao confirmado) — nesse caso o
/// card volta ao estado ocioso sem exibir resultado nem erro.
class AdminActionCard extends StatefulWidget {
  const AdminActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onExecute,
    this.buttonLabel = 'Executar',
    this.content,
    this.buttonKey,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  /// Executa a acao. Retorna o corpo da resposta (para exibir como
  /// resultado) ou `null` se a acao foi cancelada antes de disparar a
  /// chamada de rede (ex.: dialog de confirmacao).
  final Future<Map<String, dynamic>?> Function() onExecute;

  final String buttonLabel;

  /// Conteudo extra exibido entre o subtitulo e o botao (ex.: campos de
  /// texto/checkboxes especificos da acao, como `quantidade`/`meses` do
  /// seed ou `forceUpdate`/`fullReset` da geracao de telas).
  final Widget? content;

  /// Key aplicada ao botao de executar, para uso em testes de widget.
  final Key? buttonKey;

  @override
  State<AdminActionCard> createState() => AdminActionCardState();
}

class AdminActionCardState extends State<AdminActionCard> {
  bool _loading = false;
  Map<String, dynamic>? _result;
  String? _error;

  /// Dispara [AdminActionCard.onExecute]. Exposto publicamente para permitir
  /// acionar a acao a partir de outro widget (ex.: testes) sem depender de
  /// localizar o botao interno.
  Future<void> execute() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.onExecute();
      if (!mounted) return;
      if (result == null) {
        // Acao cancelada (ex.: dialog de confirmacao nao confirmado) —
        // volta ao estado ocioso sem marcar sucesso nem erro.
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusDefault),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 20),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        style: TextStyle(
                            fontSize: 11, color: colors.onSurfaceMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (widget.content != null) ...[
              const SizedBox(height: AppSpacing.sm),
              widget.content!,
            ],
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: _loading
                  ? const SizedBox(
                      key: Key('admin_action_card_loading'),
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : ElevatedButton(
                      key: widget.buttonKey,
                      onPressed: execute,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.color,
                        foregroundColor: colors.onPrimary,
                      ),
                      child: Text(widget.buttonLabel),
                    ),
            ),
            if (_result != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _ResultPanel(
                key: const Key('admin_action_card_result'),
                text: _formatJson(_result!),
                color: colors.success,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _ResultPanel(
                key: const Key('admin_action_card_error'),
                text: _error!,
                color: colors.error,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatJson(Map<String, dynamic> data) {
    try {
      return const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      return data.toString();
    }
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 220),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusDefault),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Scrollbar(
        child: SingleChildScrollView(
          child: SelectableText(
            text,
            style: TextStyle(
                fontSize: 12, color: color, fontFamily: 'monospace'),
          ),
        ),
      ),
    );
  }
}
