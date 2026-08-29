import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../config/api_links.dart';
import '../../core/theme/app_theme.dart';
import '../../services/network_caller.dart';
import '../../utils/growth_projection.dart';
import '../../widgets/generic/generic_grid_screen.dart';

/// DASH-01 Dashboard de Crescimento — item adicionado durante o planejamento
/// da Fase 3 a pedido explicito do usuario (nao estava no ROADMAP.md
/// original). 3 series mensais (novos Parceiros, novas Empresas, Modulos
/// contratados) mais projecao linear simples dos proximos meses.
///
/// Layout "progressive disclosure" (pesquisa de mercado feita no
/// planejamento: dashboards de SaaS calmos mostram o minimo necessario
/// primeiro — 1 metrica por card — e detalham sob demanda, em vez de
/// relatorios densos): cada card mostra so o KPI do mes corrente por
/// padrao, e revela o grafico completo (historico + projecao) ao expandir.
class DashboardCrescimentoScreen extends StatelessWidget {
  const DashboardCrescimentoScreen({super.key, this.networkCaller});

  final NetworkCaller? networkCaller;

  @override
  Widget build(BuildContext context) {
    final caller = networkCaller ?? NetworkCaller();
    final colors = Theme.of(context).appColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard de Crescimento')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          GrowthMetricCard(
            key: const Key('card-parceiros'),
            title: 'Novos parceiros',
            icon: Icons.handshake_outlined,
            color: colors.primary,
            url: ApiLinks.parceirosPorMes(),
            networkCaller: caller,
          ),
          const SizedBox(height: AppSpacing.md),
          GrowthMetricCard(
            key: const Key('card-empresas'),
            title: 'Novas empresas',
            icon: Icons.apartment_outlined,
            color: colors.info,
            url: ApiLinks.empresasPorMes(),
            networkCaller: caller,
          ),
          const SizedBox(height: AppSpacing.md),
          GrowthMetricCard(
            key: const Key('card-modulos'),
            title: 'Módulos contratados',
            icon: Icons.extension_outlined,
            color: colors.secondary,
            url: ApiLinks.modulosPorMes(),
            networkCaller: caller,
            // Achado de modelagem (PLAN.md "Achados desta sessao" item 5):
            // parceiro_modulo/empresa_modulo fazem DELETE+INSERT total do
            // conjunto a cada atribuicao, entao "mes de contratacao"
            // reflete a ultima reconfiguracao, nao a contratacao original.
            avisoLimitacao:
                'Picos podem refletir reconfiguração de módulos de um '
                'cliente existente, não necessariamente contratação nova '
                '(o backend regrava a data de todos os módulos do '
                'parceiro/empresa a cada atribuição).',
          ),
        ],
      ),
    );
  }
}

/// Ponto mensal `{mes: 'YYYY-MM', total: N}` retornado pelos 3 endpoints de
/// `DashboardCrescimentoController`.
class MonthlyPoint {
  final String mes;
  final double total;

  const MonthlyPoint(this.mes, this.total);

  factory MonthlyPoint.fromJson(Map<String, dynamic> json) {
    final rawTotal = json['total'];
    final double total;
    if (rawTotal == null) {
      total = 0;
    } else if (rawTotal is num) {
      total = rawTotal.toDouble();
    } else {
      total = double.tryParse(rawTotal.toString()) ?? 0;
    }
    return MonthlyPoint(json['mes']?.toString() ?? '', total);
  }
}

/// Card de uma serie do dashboard: KPI compacto do mes corrente + grafico
/// (historico + projecao) revelado ao expandir. Busca independente por
/// card (mesmo padrao de `chats_daily_chart.dart` do task_manager_flutter)
/// — erro/loading de uma serie nao trava as outras.
@visibleForTesting
class GrowthMetricCard extends StatefulWidget {
  const GrowthMetricCard({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.url,
    required this.networkCaller,
    this.avisoLimitacao,
    this.mesesProjetados = 3,
  });

  final String title;
  final IconData icon;
  final Color color;
  final String url;
  final NetworkCaller networkCaller;
  final String? avisoLimitacao;
  final int mesesProjetados;

  @override
  State<GrowthMetricCard> createState() => _GrowthMetricCardState();
}

class _GrowthMetricCardState extends State<GrowthMetricCard> {
  bool _loading = true;
  String? _error;
  List<MonthlyPoint> _points = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await widget.networkCaller.getRequest(widget.url);
      if (!response.isSuccess) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final rows = GenericGridScreen.extractRows(response.body);
      final points = rows.map(MonthlyPoint.fromJson).toList();
      if (!mounted) return;
      setState(() {
        _points = points;
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
    final theme = Theme.of(context);
    final kpiAtual = _points.isNotEmpty ? _points.last.total : 0.0;

    return Card(
      child: ExpansionTile(
        leading: Icon(widget.icon, color: widget.color),
        title: Text(widget.title, style: theme.textTheme.titleMedium),
        subtitle: _loading
            ? const Text('Carregando...')
            : _error != null
                ? Text('Erro ao carregar', style: TextStyle(color: theme.colorScheme.error))
                : Text('${kpiAtual.toInt()} no mês mais recente'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: _buildBody(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return SizedBox(
        height: 220,
        child: Center(
          child: Text(
            _error!,
            style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
          ),
        ),
      );
    }
    if (_points.isEmpty) {
      return const SizedBox(
        height: 220,
        child: Center(child: Text('Nenhum dado disponível.')),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 220, child: _buildChart()),
        if (widget.avisoLimitacao != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 16, color: theme.colorScheme.error),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  widget.avisoLimitacao!,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildChart() {
    final historico = _points.map((p) => p.total).toList();
    final projecao = projectNextMonths(
      historico,
      mesesProjetados: widget.mesesProjetados,
    );
    final n = _points.length;

    final historicoSpots = [
      for (var i = 0; i < n; i++) FlSpot(i.toDouble(), historico[i]),
    ];
    // Comeca no ultimo ponto real para a linha de projecao parecer
    // continua visualmente (nao ha um "salto" entre historico e projecao).
    final projecaoSpots = [
      FlSpot((n - 1).toDouble(), historico.last),
      for (var i = 0; i < projecao.length; i++)
        FlSpot((n + i).toDouble(), projecao[i]),
    ];

    final labels = [
      for (final p in _points) _formatMes(p.mes),
      for (var i = 0; i < projecao.length; i++)
        _incrementMes(_points.last.mes, i + 1),
    ];

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        minY: 0,
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= labels.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(labels[i], style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 32),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineTouchData: const LineTouchData(handleBuiltInTouches: true),
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            color: widget.color,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: true),
            spots: historicoSpots,
          ),
          LineChartBarData(
            isCurved: true,
            color: widget.color.withValues(alpha: 0.5),
            barWidth: 2,
            dashArray: const [6, 4],
            dotData: const FlDotData(show: false),
            spots: projecaoSpots,
          ),
        ],
      ),
    );
  }

  static String _formatMes(String mes) {
    final parts = mes.split('-');
    if (parts.length != 2) return mes;
    return '${parts[1]}/${parts[0].substring(2)}';
  }

  static String _incrementMes(String mes, int offset) {
    final parts = mes.split('-');
    if (parts.length != 2) return mes;
    final year = int.tryParse(parts[0]) ?? 0;
    final month = int.tryParse(parts[1]) ?? 1;
    final total = (year * 12 + (month - 1)) + offset;
    final novoAno = total ~/ 12;
    final novoMes = (total % 12) + 1;
    return '${novoMes.toString().padLeft(2, '0')}/${novoAno.toString().substring(2)}';
  }
}
