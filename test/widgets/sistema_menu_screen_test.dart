import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/screens/sistema/sistema_menu_screen.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.darkTheme, home: child);

void main() {
  testWidgets('renderiza os 8 itens do menu Sistema', (tester) async {
    await tester.pumpWidget(_wrap(const SistemaMenuScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsNWidgets(8));
    expect(find.text('Aplicativo'), findsOneWidget);
    expect(find.text('Cadastro Empresa'), findsOneWidget);
    expect(find.text('Configurações Admin'), findsOneWidget);
    expect(find.text('Config. Sistema'), findsOneWidget);
    expect(find.text('Editor de Telas'), findsOneWidget);
    expect(find.text('Permissões'), findsOneWidget);
    expect(find.text('Teste de Endpoints'), findsOneWidget);
    expect(find.text('Query Builder'), findsOneWidget);
  });

  testWidgets('tocar em um item ainda nao implementado mostra SnackBar "Em construcao"',
      (tester) async {
    await tester.pumpWidget(_wrap(const SistemaMenuScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aplicativo'));
    await tester.pump();

    expect(find.textContaining('Em constru'), findsOneWidget);
  });
}
