import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/screens/sistema/configuracoes_admin_screen.dart';

void main() {
  Widget wrap() => MaterialApp(
        theme: AppTheme.darkTheme,
        home: const ConfiguracoesAdminScreen(),
      );

  testWidgets('renderiza as 6 abas dos sub-CRUDs', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(find.byKey(const Key('config_admin_tab_bar')), findsOneWidget);
    expect(find.byKey(const Key('config_admin_tab_cargos')), findsOneWidget);
    expect(find.byKey(const Key('config_admin_tab_centro_custo')),
        findsOneWidget);
    expect(find.byKey(const Key('config_admin_tab_departamentos')),
        findsOneWidget);
    expect(
        find.byKey(const Key('config_admin_tab_feriados')), findsOneWidget);
    expect(
        find.byKey(const Key('config_admin_tab_horarios')), findsOneWidget);
    expect(find.byKey(const Key('config_admin_tab_tipos_produto')),
        findsOneWidget);
  });

  testWidgets('troca de aba funciona (Cargos -> Feriados)', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(find.text('Cargos'), findsWidgets);

    await tester.tap(find.byKey(const Key('config_admin_tab_feriados')));
    await tester.pumpAndSettle();

    // A aba Feriados tem o campo "Data", exclusivo dela entre as 6 abas.
    expect(find.text('Feriados'), findsWidgets);
  });
}
