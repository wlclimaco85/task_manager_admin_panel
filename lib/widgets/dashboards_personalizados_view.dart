import 'package:flutter/material.dart';

import '../services/dashboard_personalizado_service.dart';
import '../utils/app_logger.dart';
import 'dashboard_componente_view.dart';

/// Dashboards Personalizados: lista os dashboards ativos da empresa e abre o escolhido, com filtros no topo.
/// Em largura estreita (celular) os componentes ficam em coluna; em tela larga, em grade de 2 colunas.
class DashboardsPersonalizadosView extends StatefulWidget {
  final DashboardPersonalizadoService? servico;

  const DashboardsPersonalizadosView({super.key, this.servico});

  @override
  State<DashboardsPersonalizadosView> createState() => _DashboardsPersonalizadosViewState();
}

class _DashboardsPersonalizadosViewState extends State<DashboardsPersonalizadosView> {
  late final DashboardPersonalizadoService _svc = widget.servico ?? DashboardPersonalizadoService();
  List<DashboardPersonalizado> _lista = const [];
  DashboardPersonalizado? _aberto;
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
      AppLogger.i.warn('DashboardsPersonalizadosView: erro ao listar: $e');
      if (mounted) setState(() => _erro = '$e');
    }
    if (mounted) setState(() => _carregando = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_aberto != null) {
      return DashboardPersonalizadoViewer(
          key: ValueKey(_aberto!.id), dashboard: _aberto!, servico: _svc, onVoltar: () => setState(() => _aberto = null));
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Expanded(child: Text('Dashboards', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          IconButton(tooltip: 'Atualizar', onPressed: _carregar, icon: const Icon(Icons.refresh)),
        ]),
      ),
      Expanded(
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
                ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_erro!)))
                : _lista.isEmpty
                    ? const Center(child: Text('Nenhum dashboard disponível.'))
                    : ListView.separated(
                        itemCount: _lista.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final d = _lista[i];
                          return ListTile(
                            minVerticalPadding: 12,
                            leading: const Icon(Icons.insights_outlined),
                            title: Text(d.titulo),
                            subtitle: Text([if (d.grupo != null) d.grupo!, if (d.descricao != null) d.descricao!].join(' · ')),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => setState(() => _aberto = d),
                          );
                        }),
      ),
    ]);
  }
}

/// Um dashboard aberto: filtros + componentes. Carrega a definicao (filtros e componentes) e executa os SQLs no servidor.
class DashboardPersonalizadoViewer extends StatefulWidget {
  final DashboardPersonalizado dashboard;
  final DashboardPersonalizadoService servico;
  final VoidCallback? onVoltar;

  const DashboardPersonalizadoViewer({super.key, required this.dashboard, required this.servico, this.onVoltar});

  @override
  State<DashboardPersonalizadoViewer> createState() => _DashboardPersonalizadoViewerState();
}

class _DashboardPersonalizadoViewerState extends State<DashboardPersonalizadoViewer> {
  late DashboardPersonalizado _def = widget.dashboard;
  final Map<String, TextEditingController> _ctrl = {};
  final Map<String, bool> _logicos = {};
  List<ResultadoDash> _resultados = const [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _abrir();
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _abrir() async {
    try {
      final d = await widget.servico.buscar(widget.dashboard.id!);
      if (!mounted) return;
      _def = d;
      for (final f in d.filtros) {
        _ctrl.putIfAbsent(f.nome, () => TextEditingController(text: _sugestao(f)));
      }
    } catch (e) {
      AppLogger.i.warn('DashboardPersonalizadoViewer: erro ao abrir definicao: $e');
      if (mounted) setState(() { _erro = '$e'; _carregando = false; });
      return;
    }
    await _executar();
  }

  /// Padrao de data (HOJE, INICIO_MES, INICIO_ANO) e resolvido no servidor quando o campo fica vazio.
  String _sugestao(DashFiltro f) => f.tipo == 'DATA' ? '' : (f.padrao ?? '');

  Map<String, dynamic> _parametros() {
    final m = <String, dynamic>{};
    for (final f in _def.filtros) {
      if (f.tipo == 'LOGICO') {
        m[f.nome] = (_logicos[f.nome] ?? (f.padrao?.toLowerCase() == 'true')).toString();
      } else {
        final t = _ctrl[f.nome]?.text.trim() ?? '';
        if (t.isNotEmpty) m[f.nome] = t;
      }
    }
    return m;
  }

  Future<void> _executar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = await widget.servico.executar(widget.dashboard.id!, _parametros());
      if (mounted) setState(() => _resultados = r);
    } catch (e) {
      AppLogger.i.warn('DashboardPersonalizadoViewer: erro ao executar: $e');
      if (mounted) setState(() => _erro = '$e');
    }
    if (mounted) setState(() => _carregando = false);
  }

  Widget _filtro(DashFiltro f) {
    if (f.tipo == 'LOGICO') {
      return SizedBox(
        width: 220,
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
      width: 200,
      child: TextField(
        controller: _ctrl[f.nome],
        decoration: InputDecoration(
          labelText: f.descricao,
          hintText: f.tipo == 'DATA' ? (f.padrao != null && f.padrao!.isNotEmpty ? f.padrao : 'AAAA-MM-DD') : null,
          isDense: true,
        ),
        keyboardType: f.tipo == 'INTEIRO' || f.tipo == 'DECIMAL' ? TextInputType.number : TextInputType.text,
        onSubmitted: (_) => _executar(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 12, 0),
        child: Row(children: [
          if (widget.onVoltar != null)
            IconButton(tooltip: 'Voltar', onPressed: widget.onVoltar, icon: const Icon(Icons.arrow_back)),
          Expanded(child: Text(_def.titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          IconButton(tooltip: 'Atualizar', onPressed: _executar, icon: const Icon(Icons.refresh)),
        ]),
      ),
      if (_def.filtros.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final f in _def.filtros) _filtro(f),
            FilledButton.icon(onPressed: _executar, icon: const Icon(Icons.search), label: const Text('Aplicar')),
          ]),
        ),
      Expanded(
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
                ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_erro!)))
                : LayoutBuilder(builder: (context, c) {
                    final duasColunas = c.maxWidth >= 900;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final r in _resultados)
                          SizedBox(
                            width: duasColunas && r.largura != 2 ? (c.maxWidth - 32) / 2 : c.maxWidth - 24,
                            child: ComponenteDashboardView(resultado: r),
                          ),
                      ]),
                    );
                  }),
      ),
    ]);
  }
}
