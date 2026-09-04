import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/screens/dashboard/dashboard_crescimento_screen.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';

void main() {
  testWidgets(
      'DashboardCrescimentoScreen mostra loading e depois o KPI do mes mais recente',
      (tester) async {
    final client = MockClient((request) async {
      final url = request.url.toString();
      if (url.contains('parceiros-por-mes')) {
        return http.Response(
          jsonEncode([
            {'mes': '2026-06', 'total': 3},
            {'mes': '2026-07', 'total': 5},
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (url.contains('empresas-por-mes')) {
        return http.Response(
          jsonEncode([
            {'mes': '2026-07', 'total': 2},
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      // modulos-por-mes: com dados, para cobrir o aviso de limitacao visivel
      // ao expandir o card (estado vazio e' coberto no 2o teste).
      return http.Response(
        jsonEncode([
          {'mes': '2026-07', 'total': 8},
        ]),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final caller = NetworkCaller(client: client);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: DashboardCrescimentoScreen(),
    ));

    // Antes de resolver as requests: os 3 cards mostram "Carregando...".
    expect(find.text('Carregando...'), findsNWidgets(3));

    await tester.pumpAndSettle();

    expect(find.text('Novos parceiros'), findsOneWidget);
    expect(find.text('Novas empresas'), findsOneWidget);
    expect(find.text('Módulos contratados'), findsOneWidget);

    // KPI do mes mais recente de cada serie.
    expect(find.text('5 no mês mais recente'), findsOneWidget);
    expect(find.text('2 no mês mais recente'), findsOneWidget);

    expect(find.text('8 no mês mais recente'), findsOneWidget);

    // Expande o card de parceiros e confirma que o grafico + aviso (quando
    // aplicavel) aparecem.
    await tester.tap(find.text('Módulos contratados'));
    await tester.pumpAndSettle();
    expect(find.textContaining('reconfiguração de módulos'), findsOneWidget);
  });

  testWidgets('DashboardCrescimentoScreen mostra estado vazio ao expandir card sem dados',
      (tester) async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode([]),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final caller = NetworkCaller(client: client);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: DashboardCrescimentoScreen(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Novos parceiros').first);
    await tester.pumpAndSettle();

    expect(find.text('Nenhum dado disponível.'), findsOneWidget);
  });
}
