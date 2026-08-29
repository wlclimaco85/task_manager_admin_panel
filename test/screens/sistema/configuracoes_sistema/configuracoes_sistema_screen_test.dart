import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/screens/sistema/configuracoes_sistema/configuracoes_sistema_screen.dart';

void main() {
  Widget wrap() => MaterialApp(
        theme: AppTheme.darkTheme,
        home: const ConfiguracoesSistemaScreen(),
      );

  testWidgets('renderiza as 4 abas das seções de Config. Sistema',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(find.byKey(const Key('config_sistema_tab_bar')), findsOneWidget);
    expect(find.byKey(const Key('config_sistema_tab_acoes')), findsOneWidget);
    expect(find.byKey(const Key('config_sistema_tab_jobs')), findsOneWidget);
    expect(
      find.byKey(const Key('config_sistema_tab_importacao_contas')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('config_sistema_tab_importacao_cadastros')),
      findsOneWidget,
    );
  });

  testWidgets('troca de aba funciona (Ações -> Importação Contas)',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(find.text('Ações'), findsWidgets);

    await tester.tap(
      find.byKey(const Key('config_sistema_tab_importacao_contas')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Importação Contas'), findsWidgets);
  });
}
