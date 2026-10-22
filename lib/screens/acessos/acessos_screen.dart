import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../services/acessos_service.dart';
import '../../services/auth_utility.dart';

/// Painel do dono: usuarios ativos, novos usuarios (primeiro acesso) com graficos,
/// a grade de ultimos acessos por modulo e os acessos por dia.
class AcessosScreen extends StatefulWidget {
  const AcessosScreen({super.key, this.service});

  final AcessosService? service;

  @override
  State<AcessosScreen> createState() => _AcessosScreenState();
}

class _AcessosScreenState extends State<AcessosScreen> {
  static const int _diasNovos = 14;

  late final AcessosService _service = widget.service ?? AcessosService();
  Map<String, dynamic> _resumo = const {};
  Map<String, dynamic> _novos = const {};
  List<Map<String, dynamic>> _usuarios = const [];
  List<Map<String, dynamic>> _diario = const [];
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
    final token = AuthUtility.userInfo?.token ?? '';
    try {
      final resumo = await _service.resumo(token);
      final novos = await _service.novos(token, dias: _diasNovos);
      final usuarios = await _service.usuarios(token);
      final diario = await _service.diario(token);
      if (!mounted) return;
      setState(() {
        _resumo = resumo;
        _novos = novos;
        _usuarios = usuarios;
        _diario = diario;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar os acessos: $e';
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Acessos'),
          actions: [
            IconButton(
              tooltip: 'Atualizar',
              onPressed: _carregando ? null : _carregar,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Visão geral'),
            Tab(text: 'Por dia'),
          ]),
        ),
        body: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_erro!)))
                : TabBarView(children: [
                    _visaoGeral(context),
                    _listaDiario(context),
                  ]),
      ),
    );
  }

  // ─── Visao geral ─────────────────────────────────────────────────────────

  Widget _visaoGeral(BuildContext context) {
    final cor = Theme.of(context).colorScheme;
    final totais = (_resumo['totais'] as Map?) ?? const {};
    final totaisNovos = (_novos['totais'] as Map?) ?? const {};
    final porApp = _lista(_resumo['porAplicacao']);
    final novosPorApp = _lista(_novos['porAplicacao']);
    final novosPorDia = _lista(_novos['porDia']);
    final primeiros = _lista(_novos['primeiros']);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _titulo(context, 'Usuários ativos', Icons.people_alt_outlined),
        _kpis([
          _Kpi('Total', totais['total'], Icons.groups_2_outlined, cor.primary),
          _Kpi('Últimos 7 dias', totais['semana'], Icons.date_range_outlined, cor.tertiary),
          _Kpi('Hoje', totais['hoje'], Icons.today_outlined, cor.secondary),
        ]),
        const SizedBox(height: 24),
        _titulo(context, 'Novos usuários (primeiro acesso)', Icons.person_add_alt_1_outlined),
        _kpis([
          _Kpi('Total', totaisNovos['total'], Icons.person_add_alt_1_outlined, cor.primary),
          _Kpi('Últimos 7 dias', totaisNovos['semana'], Icons.date_range_outlined, cor.tertiary),
          _Kpi('Hoje', totaisNovos['hoje'], Icons.today_outlined, cor.secondary),
        ]),
        const SizedBox(height: 16),
        _cartao(
          context,
          titulo: 'Novos usuários por dia',
          subtitulo: 'Últimos $_diasNovos dias',
          child: SizedBox(height: 220, child: _graficoNovosPorDia(context, novosPorDia)),
        ),
        const SizedBox(height: 16),
        _cartao(
          context,
          titulo: 'Novos usuários por aplicação',
          subtitulo: 'Total e últimos 7 dias',
          child: _barrasPorAplicacao(context, novosPorApp),
        ),
        const SizedBox(height: 16),
        _cartao(
          context,
          titulo: 'Primeiro acesso',
          subtitulo: 'Quem entrou pela primeira vez (mais recentes primeiro)',
          child: _tabelaPrimeiros(context, primeiros),
        ),
        const SizedBox(height: 24),
        _titulo(context, 'Usuários ativos por aplicação', Icons.apps_outlined),
        _cartao(
          context,
          titulo: 'Acessos por aplicação',
          child: _tabelaPorApp(context, porApp),
        ),
        const SizedBox(height: 16),
        _cartao(
          context,
          titulo: 'Último acesso por usuário e módulo',
          subtitulo: 'Web, app ou windows: um registro por módulo',
          child: _gradeUsuarios(context),
        ),
      ],
    );
  }

  Widget _titulo(BuildContext context, String texto, IconData icone) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Icon(icone, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(texto, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _kpis(List<_Kpi> itens) {
    return LayoutBuilder(builder: (context, constraints) {
      final largura = constraints.maxWidth;
      final colunas = largura >= 640 ? itens.length : 1;
      final espaco = 12.0;
      final tamanho = (largura - espaco * (colunas - 1)) / colunas;
      return Wrap(
        spacing: espaco,
        runSpacing: espaco,
        children: [for (final k in itens) SizedBox(width: tamanho, child: _kpiCard(context, k))],
      );
    });
  }

  Widget _kpiCard(BuildContext context, _Kpi k) {
    final tema = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: tema.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: k.cor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(k.icone, color: k.cor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(k.titulo, style: tema.textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(
                '${k.valor ?? 0}',
                style: tema.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _cartao(BuildContext context, {required String titulo, String? subtitulo, required Widget child}) {
    final tema = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: tema.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: tema.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          if (subtitulo != null) ...[
            const SizedBox(height: 2),
            Text(subtitulo, style: tema.textTheme.bodySmall),
          ],
          const SizedBox(height: 14),
          child,
        ]),
      ),
    );
  }

  Widget _graficoNovosPorDia(BuildContext context, List<Map<String, dynamic>> dias) {
    final cor = Theme.of(context).colorScheme;
    if (dias.isEmpty) return const Center(child: Text('Sem dados no período.'));
    final maior = dias.map((d) => _inteiro(d['novos'])).fold<int>(0, (a, b) => a > b ? a : b);
    return BarChart(
      BarChartData(
        maxY: (maior + 1).toDouble(),
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: cor.outlineVariant, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 28, interval: 1),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (valor, _) {
                final i = valor.toInt();
                if (i < 0 || i >= dias.length) return const SizedBox();
                if (dias.length > 10 && i.isOdd) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_diaCurto('${dias[i]['dia']}'), style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < dias.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: _inteiro(dias[i]['novos']).toDouble(),
                color: cor.primary,
                width: 14,
                borderRadius: BorderRadius.circular(4),
              ),
            ]),
        ],
      ),
    );
  }

  Widget _barrasPorAplicacao(BuildContext context, List<Map<String, dynamic>> apps) {
    final tema = Theme.of(context);
    if (apps.isEmpty) return const Text('Nenhum novo usuário no período.');
    final maior = apps.map((a) => _inteiro(a['total'])).fold<int>(1, (a, b) => a > b ? a : b);
    return Column(children: [
      for (final a in apps)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(children: [
            SizedBox(
              width: 150,
              child: Text('${a['aplicacao']}', overflow: TextOverflow.ellipsis),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _inteiro(a['total']) / maior,
                  minHeight: 12,
                  backgroundColor: tema.colorScheme.surfaceContainerHighest,
                  color: tema.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 96,
              child: Text(
                '${a['total']}  •  7d ${a['semana']}',
                textAlign: TextAlign.right,
                style: tema.textTheme.bodySmall,
              ),
            ),
          ]),
        ),
    ]);
  }

  Widget _tabelaPrimeiros(BuildContext context, List<Map<String, dynamic>> lista) {
    if (lista.isEmpty) return const Text('Nenhum primeiro acesso registrado ainda.');
    return _tabelaRolavel([
      const DataColumn(label: Text('Login')),
      const DataColumn(label: Text('Primeiro acesso')),
      const DataColumn(label: Text('Aplicação')),
      const DataColumn(label: Text('Módulo')),
    ], [
      for (final p in lista)
        DataRow(cells: [
          DataCell(Text('${p['email'] ?? p['nome'] ?? '—'}')),
          DataCell(Text(_formatarData(p['primeiroAcessoEm']))),
          DataCell(Text('${p['aplicacao'] ?? ''}')),
          DataCell(Text(_rotuloModulo(p['plataforma']))),
        ]),
    ]);
  }

  Widget _tabelaPorApp(BuildContext context, List<Map<String, dynamic>> apps) {
    if (apps.isEmpty) return const Text('Nenhum acesso registrado ainda.');
    return _tabelaRolavel([
      const DataColumn(label: Text('Aplicação')),
      const DataColumn(label: Text('Total'), numeric: true),
      const DataColumn(label: Text('7 dias'), numeric: true),
      const DataColumn(label: Text('Hoje'), numeric: true),
    ], [
      for (final a in apps)
        DataRow(cells: [
          DataCell(Text('${a['aplicacao']}')),
          DataCell(Text('${a['total']}')),
          DataCell(Text('${a['semana']}')),
          DataCell(Text('${a['hoje']}')),
        ]),
    ]);
  }

  Widget _gradeUsuarios(BuildContext context) {
    if (_usuarios.isEmpty) return const Text('Nenhum acesso registrado ainda.');
    return _tabelaRolavel([
      const DataColumn(label: Text('Login')),
      const DataColumn(label: Text('Data logada')),
      const DataColumn(label: Text('Módulo')),
      const DataColumn(label: Text('Versão')),
      const DataColumn(label: Text('Aplicação')),
    ], [
      for (final u in _usuarios)
        DataRow(cells: [
          DataCell(Text('${u['email'] ?? u['nome'] ?? '—'}')),
          DataCell(Text(_formatarData(u['ultimoAcessoEm']))),
          DataCell(Text(_rotuloModulo(u['plataforma']))),
          DataCell(Text('${u['versao'] ?? ''}')),
          DataCell(Text('${u['aplicacao'] ?? ''}')),
        ]),
    ]);
  }

  Widget _tabelaRolavel(List<DataColumn> colunas, List<DataRow> linhas) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 40,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 44,
        columns: colunas,
        rows: linhas,
      ),
    );
  }

  // ─── Por dia ─────────────────────────────────────────────────────────────

  Widget _listaDiario(BuildContext context) {
    if (_diario.isEmpty) return const Center(child: Text('Nenhum acesso nos últimos dias.'));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _diario.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final d = _diario[i];
        return Card(
          elevation: 0,
          child: ListTile(
            title: Text('${_formatarDia('${d['dia']}')} • ${d['acessos']} acessos'),
            subtitle: Text('${d['aplicacao']} • ${_rotuloModulo(d['plataforma'])} • ${d['versao']}'),
          ),
        );
      },
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> _lista(Object? valor) {
    return (valor as List?)?.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() ?? const [];
  }

  static int _inteiro(Object? valor) => valor is num ? valor.toInt() : int.tryParse('$valor') ?? 0;

  /// Modulo como o usuario entende: WEB, Windows ou App (MOBILE).
  static String _rotuloModulo(Object? plataforma) {
    return switch ('$plataforma') {
      'WEB' => 'Web',
      'WINDOWS' => 'Windows',
      'MOBILE' => 'App',
      _ => 'Desconhecido',
    };
  }

  /// Data e hora no formato dd/MM/aaaa HH:mm (o backend devolve horario de Brasilia sem fuso).
  static String _formatarData(Object? iso) {
    final data = DateTime.tryParse('$iso');
    if (data == null) return '${iso ?? ''}';
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(data.day)}/${dois(data.month)}/${data.year} ${dois(data.hour)}:${dois(data.minute)}';
  }

  static String _formatarDia(String iso) {
    final data = DateTime.tryParse(iso);
    if (data == null) return iso;
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(data.day)}/${dois(data.month)}/${data.year}';
  }

  /// dd/MM a partir de aaaa-MM-dd, para rotulos de grafico.
  static String _diaCurto(String iso) {
    final data = DateTime.tryParse(iso);
    if (data == null) return iso;
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(data.day)}/${dois(data.month)}';
  }
}

class _Kpi {
  const _Kpi(this.titulo, this.valor, this.icone, this.cor);

  final String titulo;
  final Object? valor;
  final IconData icone;
  final Color cor;
}
