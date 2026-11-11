import 'package:flutter/material.dart';

import '../services/dashboard_personalizado_service.dart' show DashFiltro;
import '../services/relatorio_personalizado_service.dart';
import '../utils/app_logger.dart';
import 'package:file_saver/file_saver.dart';

/// Relatórios Personalizados: lista os relatórios ativos da empresa; ao abrir, mostra os filtros e gera o PDF no
/// servidor (o app só baixa/salva o arquivo). O SQL nunca chega ao usuário.
class RelatoriosPersonalizadosView extends StatefulWidget {
  final RelatorioPersonalizadoService? servico;

  /// Entrega o PDF ao usuario (padrao: FileSaver; injetavel para teste).
  final Future<void> Function(PdfRelatorio pdf)? salvar;

  const RelatoriosPersonalizadosView({super.key, this.servico, this.salvar});

  @override
  State<RelatoriosPersonalizadosView> createState() => _RelatoriosPersonalizadosViewState();
}

class _RelatoriosPersonalizadosViewState extends State<RelatoriosPersonalizadosView> {
  late final RelatorioPersonalizadoService _svc = widget.servico ?? RelatorioPersonalizadoService();
  List<RelatorioPersonalizado> _lista = const [];
  RelatorioPersonalizado? _aberto;
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final l = await _svc.ativos();
      if (mounted) setState(() => _lista = l);
    } catch (e) {
      AppLogger.i.warn('RelatoriosPersonalizadosView: erro ao listar: $e');
      if (mounted) setState(() => _erro = '$e');
    }
    if (mounted) setState(() => _carregando = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_aberto != null) {
      return RelatorioGerarView(
        key: ValueKey(_aberto!.id),
        relatorio: _aberto!,
        servico: _svc,
        salvar: widget.salvar,
        onVoltar: () => setState(() => _aberto = null),
      );
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Expanded(child: Text('Relatórios', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          IconButton(tooltip: 'Atualizar', onPressed: _carregar, icon: const Icon(Icons.refresh)),
        ]),
      ),
      Expanded(
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
                ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_erro!)))
                : _lista.isEmpty
                    ? const Center(child: Text('Nenhum relatório disponível.'))
                    : ListView.separated(
                        itemCount: _lista.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final r = _lista[i];
                          return ListTile(
                            minVerticalPadding: 12,
                            leading: const Icon(Icons.picture_as_pdf_outlined),
                            title: Text(r.titulo),
                            subtitle: Text([if (r.grupo != null) r.grupo!, if (r.descricao != null) r.descricao!].join(' · ')),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => setState(() => _aberto = r),
                          );
                        }),
      ),
    ]);
  }
}

/// Tela de um relatório: filtros + botão "Gerar PDF".
class RelatorioGerarView extends StatefulWidget {
  final RelatorioPersonalizado relatorio;
  final RelatorioPersonalizadoService servico;
  final Future<void> Function(PdfRelatorio pdf)? salvar;
  final VoidCallback? onVoltar;

  const RelatorioGerarView({super.key, required this.relatorio, required this.servico, this.salvar, this.onVoltar});

  @override
  State<RelatorioGerarView> createState() => _RelatorioGerarViewState();
}

class _RelatorioGerarViewState extends State<RelatorioGerarView> {
  final Map<String, TextEditingController> _ctrl = {};
  final Map<String, bool> _logicos = {};
  bool _gerando = false;

  @override
  void initState() {
    super.initState();
    for (final f in widget.relatorio.filtros) {
      _ctrl[f.nome] = TextEditingController(text: f.tipo == 'DATA' ? '' : (f.padrao ?? ''));
    }
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _aviso(String t, {bool erro = false}) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(t), backgroundColor: erro ? Colors.red.shade700 : null));
  }

  Map<String, dynamic> _parametros() {
    final m = <String, dynamic>{};
    for (final f in widget.relatorio.filtros) {
      if (f.tipo == 'LOGICO') {
        m[f.nome] = (_logicos[f.nome] ?? (f.padrao?.toLowerCase() == 'true')).toString();
      } else {
        final t = _ctrl[f.nome]?.text.trim() ?? '';
        if (t.isNotEmpty) m[f.nome] = t;
      }
    }
    return m;
  }

  Future<void> _salvarPadrao(PdfRelatorio pdf) async {
    await FileSaver.instance.saveFile(
      name: pdf.nomeArquivo.toLowerCase().endsWith('.pdf') ? pdf.nomeArquivo.substring(0, pdf.nomeArquivo.length - 4) : pdf.nomeArquivo,
      bytes: pdf.bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
    );
  }

  Future<void> _gerar() async {
    setState(() => _gerando = true);
    try {
      final pdf = await widget.servico.gerarPdf(widget.relatorio.id!, _parametros(),
          nomePadrao: '${widget.relatorio.titulo}.pdf');
      await (widget.salvar ?? _salvarPadrao)(pdf);
      _aviso('Relatório gerado: ${pdf.nomeArquivo}');
    } catch (e) {
      AppLogger.i.warn('RelatorioGerarView: erro ao gerar: $e');
      _aviso('$e', erro: true);
    }
    if (mounted) setState(() => _gerando = false);
  }

  Widget _campo(DashFiltro f) {
    if (f.tipo == 'LOGICO') {
      return SizedBox(
        width: 240,
        child: SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(f.descricao),
          value: _logicos[f.nome] ?? (f.padrao?.toLowerCase() == 'true'),
          onChanged: (v) => setState(() => _logicos[f.nome] = v),
        ),
      );
    }
    return SizedBox(
      width: 240,
      child: TextField(
        controller: _ctrl[f.nome],
        decoration: InputDecoration(
          labelText: f.descricao,
          hintText: f.tipo == 'DATA' ? (f.padrao != null && f.padrao!.isNotEmpty ? f.padrao : 'AAAA-MM-DD') : null,
        ),
        keyboardType: f.tipo == 'INTEIRO' || f.tipo == 'DECIMAL' ? TextInputType.number : TextInputType.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.relatorio;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 12, 0),
        child: Row(children: [
          if (widget.onVoltar != null)
            IconButton(tooltip: 'Voltar', onPressed: widget.onVoltar, icon: const Icon(Icons.arrow_back)),
          Expanded(child: Text(r.titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
        ]),
      ),
      if (r.descricao != null)
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 0), child: Text(r.descricao!)),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final f in r.filtros) _campo(f),
          FilledButton.icon(
            onPressed: _gerando ? null : _gerar,
            icon: _gerando
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf),
            label: const Text('Gerar PDF'),
          ),
        ]),
      ),
    ]);
  }
}
