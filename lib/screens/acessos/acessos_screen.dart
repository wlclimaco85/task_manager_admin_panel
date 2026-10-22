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

  /// Largura minima para lado a lado (dois cartoes ou grafico + legenda).
  static const double _larguraDuasColunas = 720;
  static const double _larguraPizzaLado = 420;
  static const double _espacoCartoes = 16;

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
                ? _estadoErro(context, _erro!)
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _titulo(context, 'Usuários ativos', Icons.people_alt_outlined),
        _kpis([
          _Kpi('Total', totais['total'], Icons.groups_2_outlined, cor.primary),
          _Kpi('Últimos 7 dias', totais['semana'], Icons.date_range_outlined, cor.tertiary),
          _Kpi('Hoje', totais['hoje'], Icons.today_outlined, cor.secondary),
        ]),
        const SizedBox(height: 28),
        _titulo(context, 'Usuários ativos por aplicação', Icons.apps_outlined),
        _duasColunas(
          _cartao(
            context,
            titulo: 'Participação por aplicação',
            subtitulo: 'Fatia de usuarios ativos em cada aplicação',
            child: _pizzaPorAplicacao(
              context,
              porApp,
              campo: 'total',
              rotuloCentro: 'ativos',
              vazio: 'Nenhum acesso registrado ainda.',
            ),
          ),
          _cartao(
            context,
            titulo: 'Acessos por aplicação',
            subtitulo: 'Total, últimos 7 dias e hoje',
            child: _tabelaPorApp(context, porApp),
          ),
        ),
        const SizedBox(height: 28),
        _titulo(context, 'Novos usuários (primeiro acesso)', Icons.person_add_alt_1_outlined),
        _kpis([
          _Kpi('Total', totaisNovos['total'], Icons.person_add_alt_1_outlined, cor.primary),
          _Kpi('Últimos 7 dias', totaisNovos['semana'], Icons.date_range_outlined, cor.tertiary),
          _Kpi('Hoje', totaisNovos['hoje'], Icons.today_outlined, cor.secondary),
        ]),
        const SizedBox(height: _espacoCartoes),
        _cartao(
          context,
          titulo: 'Novos usuários por dia',
          subtitulo: 'Últimos $_diasNovos dias',
          child: SizedBox(height: 240, child: _graficoNovosPorDia(context, novosPorDia)),
        ),
        const SizedBox(height: _espacoCartoes),
        _duasColunas(
          _cartao(
            context,
            titulo: 'Novos usuários por aplicação',
            subtitulo: 'Total e últimos 7 dias',
            child: _barrasPorAplicacao(context, novosPorApp),
          ),
          _cartao(
            context,
            titulo: 'Participação dos novos',
            subtitulo: 'Fatia de novos usuários por aplicação',
            child: _pizzaPorAplicacao(
              context,
              novosPorApp,
              campo: 'total',
              rotuloCentro: 'novos',
              vazio: 'Nenhum novo usuário no período.',
            ),
          ),
        ),
        const SizedBox(height: _espacoCartoes),
        _cartao(
          context,
          titulo: 'Primeiro acesso',
          subtitulo: 'Quem entrou pela primeira vez (mais recentes primeiro)',
          child: _tabelaPrimeiros(context, primeiros),
        ),
        const SizedBox(height: 28),
        _titulo(context, 'Acessos por usuário e módulo', Icons.grid_view_outlined),
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
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: tema.colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icone, size: 18, color: tema.colorScheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            texto,
            style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: tema.colorScheme.onSurface),
          ),
        ),
      ]),
    );
  }

  Widget _kpis(List<_Kpi> itens) {
    return LayoutBuilder(builder: (context, constraints) {
      final largura = constraints.maxWidth;
      final colunas = largura >= _larguraDuasColunas ? itens.length : 1;
      const espaco = 12.0;
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
      margin: EdgeInsets.zero,
      elevation: 0,
      color: tema.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: tema.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: k.cor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(k.icone, color: k.cor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                k.titulo,
                style: tema.textTheme.labelLarge?.copyWith(color: tema.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(
                '${k.valor ?? 0}',
                style: tema.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: tema.colorScheme.onSurface),
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
      margin: EdgeInsets.zero,
      elevation: 0,
      color: tema.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: tema.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            titulo,
            style: tema.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: tema.colorScheme.onSurface),
          ),
          if (subtitulo != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitulo,
              style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 16),
          child,
        ]),
      ),
    );
  }

  /// Dois cartoes lado a lado em telas largas; em coluna no celular.
  Widget _duasColunas(Widget esquerda, Widget direita) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < _larguraDuasColunas) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [esquerda, const SizedBox(height: _espacoCartoes), direita],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: esquerda),
          const SizedBox(width: _espacoCartoes),
          Expanded(child: direita),
        ],
      );
    });
  }

  Widget _vazio(BuildContext context, String texto) {
    final cor = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Icon(Icons.info_outline, size: 18, color: cor.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cor.onSurfaceVariant),
          ),
        ),
      ]),
    );
  }

  Widget _estadoErro(BuildContext context, String mensagem) {
    final cor = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 40, color: cor.error),
          const SizedBox(height: 12),
          Text(
            mensagem,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cor.onSurface),
          ),
        ]),
      ),
    );
  }

  Widget _graficoNovosPorDia(BuildContext context, List<Map<String, dynamic>> dias) {
    final cor = Theme.of(context).colorScheme;
    final tema = Theme.of(context);
    if (dias.isEmpty) return Center(child: _vazio(context, 'Sem dados no período.'));
    final maior = dias.map((d) => _inteiro(d['novos'])).fold<int>(0, (a, b) => a > b ? a : b);
    return BarChart(
      BarChartData(
        maxY: (maior + 1).toDouble(),
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: cor.outlineVariant, strokeWidth: 1, dashArray: [4, 4]),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (valor, _) => Text(
                '${valor.toInt()}',
                style: tema.textTheme.labelSmall?.copyWith(color: cor.onSurfaceVariant),
              ),
            ),
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
                  child: Text(
                    _diaCurto('${dias[i]['dia']}'),
                    style: tema.textTheme.labelSmall?.copyWith(color: cor.onSurfaceVariant),
                  ),
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
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              ),
            ]),
        ],
      ),
    );
  }

  Widget _barrasPorAplicacao(BuildContext context, List<Map<String, dynamic>> apps) {
    final tema = Theme.of(context);
    final cor = tema.colorScheme;
    if (apps.isEmpty) return _vazio(context, 'Nenhum novo usuário no período.');
    final maior = apps.map((a) => _inteiro(a['total'])).fold<int>(1, (a, b) => a > b ? a : b);
    return Column(children: [
      for (final a in apps)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                  '${a['aplicacao']}',
                  overflow: TextOverflow.ellipsis,
                  style: tema.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${a['total']}',
                style: tema.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: cor.onSurface),
              ),
              const SizedBox(width: 6),
              Text(
                '· 7d ${a['semana']}',
                style: tema.textTheme.bodySmall?.copyWith(color: cor.onSurfaceVariant),
              ),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _inteiro(a['total']) / maior,
                minHeight: 10,
                backgroundColor: cor.surfaceContainerHighest,
                color: cor.primary,
              ),
            ),
          ]),
        ),
    ]);
  }

  /// Pizza com legenda e percentuais. [campo] indica qual valor de cada item define a fatia.
  Widget _pizzaPorAplicacao(
    BuildContext context,
    List<Map<String, dynamic>> apps, {
    required String campo,
    required String rotuloCentro,
    required String vazio,
  }) {
    final tema = Theme.of(context);
    final cor = tema.colorScheme;
    final paleta = _paletaGrafico(cor);
    final total = apps.fold<int>(0, (soma, a) => soma + _inteiro(a[campo]));
    if (total == 0) return _vazio(context, vazio);

    final grafico = SizedBox(
      width: 200,
      height: 200,
      child: Stack(alignment: Alignment.center, children: [
        PieChart(
          PieChartData(
            sectionsSpace: 2,
            centerSpaceRadius: 58,
            sections: [
              for (var i = 0; i < apps.length; i++)
                PieChartSectionData(
                  value: _inteiro(apps[i][campo]).toDouble(),
                  color: paleta[i % paleta.length],
                  radius: 34,
                  showTitle: false,
                ),
            ],
          ),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            '$total',
            style: tema.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: cor.onSurface),
          ),
          Text(rotuloCentro, style: tema.textTheme.labelSmall?.copyWith(color: cor.onSurfaceVariant)),
        ]),
      ]),
    );

    final legenda = Column(children: [
      for (var i = 0; i < apps.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: paleta[i % paleta.length],
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${apps[i]['aplicacao']}',
                overflow: TextOverflow.ellipsis,
                style: tema.textTheme.bodyMedium,
              ),
            ),
            Text(
              '${_inteiro(apps[i][campo])}',
              style: tema.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 56,
              child: Text(
                _percentual(_inteiro(apps[i][campo]), total),
                textAlign: TextAlign.right,
                style: tema.textTheme.bodySmall?.copyWith(color: cor.onSurfaceVariant),
              ),
            ),
          ]),
        ),
    ]);

    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < _larguraPizzaLado) {
        return Column(children: [grafico, const SizedBox(height: 16), legenda]);
      }
      return Row(children: [
        grafico,
        const SizedBox(width: 20),
        Expanded(child: legenda),
      ]);
    });
  }

  Widget _tabelaPrimeiros(BuildContext context, List<Map<String, dynamic>> lista) {
    if (lista.isEmpty) return _vazio(context, 'Nenhum primeiro acesso registrado ainda.');
    return _tabelaRolavel(context, [
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
    if (apps.isEmpty) return _vazio(context, 'Nenhum acesso registrado ainda.');
    return _tabelaRolavel(context, [
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
    if (_usuarios.isEmpty) return _vazio(context, 'Nenhum acesso registrado ainda.');
    return _tabelaRolavel(context, [
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

  /// Tabela que ocupa a largura disponivel e fica centralizada.
  /// So rola na horizontal quando as colunas nao cabem na largura.
  Widget _tabelaRolavel(BuildContext context, List<DataColumn> colunas, List<DataRow> linhas) {
    final tema = Theme.of(context);
    final cor = tema.colorScheme;
    // Table com colunas flexiveis: a grade ocupa a largura toda do cartao, alinhada a esquerda,
    // e so rola na horizontal quando a largura da tela for menor que o minimo.
    Widget celula(Widget conteudo, bool numerica) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Align(
            alignment: numerica ? Alignment.centerRight : Alignment.centerLeft,
            child: conteudo,
          ),
        );

    return LayoutBuilder(builder: (context, constraints) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: Table(
            columnWidths: {for (var i = 0; i < colunas.length; i++) i: const FlexColumnWidth()},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: TableBorder(horizontalInside: BorderSide(color: cor.outlineVariant)),
            children: [
              TableRow(
                decoration: BoxDecoration(color: cor.surfaceContainerHighest),
                children: [
                  for (final c in colunas)
                    celula(
                      DefaultTextStyle.merge(
                        style: tema.textTheme.labelLarge?.copyWith(
                          color: cor.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ) ?? const TextStyle(fontWeight: FontWeight.w700),
                        child: c.label,
                      ),
                      c.numeric,
                    ),
                ],
              ),
              for (final linha in linhas)
                TableRow(children: [
                  for (var i = 0; i < linha.cells.length; i++)
                    celula(
                      DefaultTextStyle.merge(
                        style: tema.textTheme.bodyMedium?.copyWith(color: cor.onSurface) ?? const TextStyle(),
                        child: linha.cells[i].child,
                      ),
                      colunas[i].numeric,
                    ),
                ]),
            ],
          ),
        ),
      );
    });
  }

  // ─── Por dia ─────────────────────────────────────────────────────────────

  Widget _listaDiario(BuildContext context) {
    final cor = Theme.of(context).colorScheme;
    if (_diario.isEmpty) return Center(child: _vazio(context, 'Nenhum acesso nos últimos dias.'));
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: _diario.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final d = _diario[i];
        return Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: cor.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cor.outlineVariant),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cor.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.calendar_today_outlined, color: cor.primary, size: 20),
            ),
            title: Text(
              '${_formatarDia('${d['dia']}')} • ${d['acessos']} acessos',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            subtitle: Text('${d['aplicacao']} • ${_rotuloModulo(d['plataforma'])} • ${d['versao']}'),
          ),
        );
      },
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  /// Cores bem distintas entre si, para cada aplicacao ter uma fatia facil de identificar.
  static List<Color> _paletaGrafico(ColorScheme cor) => const [
        Color(0xFF3B82F6),
        Color(0xFF10B981),
        Color(0xFFF59E0B),
        Color(0xFF8B5CF6),
        Color(0xFFEC4899),
        Color(0xFF06B6D4),
        Color(0xFFEF4444),
      ];

  static List<Map<String, dynamic>> _lista(Object? valor) {
    return (valor as List?)?.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() ?? const [];
  }

  static int _inteiro(Object? valor) => valor is num ? valor.toInt() : int.tryParse('$valor') ?? 0;

  /// Percentual com virgula decimal (pt-BR), ex.: 37,5%.
  static String _percentual(int valor, int total) {
    if (total <= 0) return '0%';
    final p = valor * 100 / total;
    final texto = p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(1).replaceAll('.', ',');
    return '$texto%';
  }

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
