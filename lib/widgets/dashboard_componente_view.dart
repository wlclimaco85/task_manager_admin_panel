import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/dashboard_personalizado_service.dart';

/// Converte o valor vindo do servidor (numero ou texto) em double; null quando nao e numerico.
double? numeroDeCelula(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(',', '.'));
}

/// Formata numeros para exibicao (milhares com ponto, ate 2 decimais).
String formatarNumero(dynamic v) {
  final n = numeroDeCelula(v);
  if (n == null) return v?.toString() ?? '-';
  final inteiro = n == n.roundToDouble();
  final texto = inteiro ? n.round().abs().toString() : n.abs().toStringAsFixed(2);
  final partes = texto.split('.');
  final milhar = partes[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  final sinal = n < 0 ? '-' : '';
  return partes.length > 1 ? '$sinal$milhar,${partes[1]}' : '$sinal$milhar';
}

const _cores = [
  Color(0xFF2E7D32), Color(0xFF1565C0), Color(0xFFEF6C00), Color(0xFF6A1B9A),
  Color(0xFF00838F), Color(0xFFC62828), Color(0xFF4E342E), Color(0xFF558B2F),
];

/// Um componente do dashboard: KPI, tabela ou grafico (linha, barras, colunas, pizza, donut), conforme o tipo.
/// Para graficos: 1a coluna = rotulo; demais colunas numericas = series.
class ComponenteDashboardView extends StatelessWidget {
  final ResultadoDash resultado;

  const ComponenteDashboardView({super.key, required this.resultado});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(resultado.titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (resultado.erro != null)
            Text(resultado.erro!, style: TextStyle(color: Theme.of(context).colorScheme.error))
          else if (resultado.linhas.isEmpty)
            const Text('Sem dados para o período/filtro.')
          else
            _corpo(context),
          if (resultado.truncado)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Resultado limitado às primeiras linhas.', style: TextStyle(fontSize: 11)),
            ),
        ]),
      ),
    );
  }

  Widget _corpo(BuildContext context) {
    switch (resultado.tipo) {
      case 'KPI':
        return Text(formatarNumero(resultado.linhas.first.first),
            key: const Key('kpi_valor'), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold));
      case 'PIZZA':
      case 'DONUT':
        return SizedBox(height: 220, child: _pizza(resultado.tipo == 'DONUT'));
      case 'LINHA':
        return SizedBox(height: 220, child: _linha());
      case 'BARRAS':
      case 'COLUNAS':
        return SizedBox(height: 220, child: _colunas());
      default:
        return _tabela();
    }
  }

  Widget _tabela() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [for (final c in resultado.colunas) DataColumn(label: Text(c))],
        rows: [
          for (final l in resultado.linhas)
            DataRow(cells: [
              for (final v in l) DataCell(Text(numeroDeCelula(v) != null && v is num ? formatarNumero(v) : (v?.toString() ?? '-'))),
            ]),
        ],
      ),
    );
  }

  int get _series => math.max(1, resultado.colunas.length - 1);

  Widget _pizza(bool donut) {
    final fatias = <PieChartSectionData>[];
    for (var i = 0; i < resultado.linhas.length; i++) {
      final l = resultado.linhas[i];
      final v = l.length > 1 ? numeroDeCelula(l[1]) : null;
      if (v == null || v <= 0) continue;
      fatias.add(PieChartSectionData(
        value: v,
        color: _cores[i % _cores.length],
        title: l.first?.toString() ?? '',
        radius: donut ? 50 : 80,
        titleStyle: const TextStyle(fontSize: 11, color: Colors.white),
      ));
    }
    if (fatias.isEmpty) return const Center(child: Text('Sem valores positivos para o gráfico.'));
    return PieChart(PieChartData(sections: fatias, centerSpaceRadius: donut ? 40 : 0, sectionsSpace: 2));
  }

  List<LineChartBarData> _barrasLinha() => [
        for (var s = 0; s < _series; s++)
          LineChartBarData(
            color: _cores[s % _cores.length],
            isCurved: false,
            barWidth: 2,
            dotData: const FlDotData(show: true),
            spots: [
              for (var i = 0; i < resultado.linhas.length; i++)
                if (resultado.linhas[i].length > s + 1 && numeroDeCelula(resultado.linhas[i][s + 1]) != null)
                  FlSpot(i.toDouble(), numeroDeCelula(resultado.linhas[i][s + 1])!),
            ],
          ),
      ];

  Widget _linha() {
    return LineChart(LineChartData(
      lineBarsData: _barrasLinha(),
      titlesData: _titulos(),
      borderData: FlBorderData(show: false),
    ));
  }

  Widget _colunas() {
    return BarChart(BarChartData(
      barGroups: [
        for (var i = 0; i < resultado.linhas.length; i++)
          BarChartGroupData(x: i, barRods: [
            for (var s = 0; s < _series; s++)
              BarChartRodData(
                toY: resultado.linhas[i].length > s + 1 ? (numeroDeCelula(resultado.linhas[i][s + 1]) ?? 0) : 0,
                color: _cores[s % _cores.length],
                width: _series > 1 ? 8 : 16,
              ),
          ]),
      ],
      titlesData: _titulos(),
      borderData: FlBorderData(show: false),
    ));
  }

  FlTitlesData _titulos() => FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            getTitlesWidget: (valor, meta) {
              final i = valor.toInt();
              if (i < 0 || i >= resultado.linhas.length || valor != i.toDouble()) return const SizedBox.shrink();
              final t = resultado.linhas[i].first?.toString() ?? '';
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(t.length > 8 ? '${t.substring(0, 7)}…' : t, style: const TextStyle(fontSize: 10)),
              );
            },
          ),
        ),
      );
}
