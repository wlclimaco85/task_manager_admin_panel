import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/screens/sistema/aplicativo_screen.dart';
import 'package:task_manager_admin_panel/screens/sistema/cadastro_empresa_wizard_screen.dart';
import 'package:task_manager_admin_panel/screens/sistema/configuracoes_admin_screen.dart';
import 'package:task_manager_admin_panel/screens/sistema/configuracoes_sistema/configuracoes_sistema_screen.dart';
import 'package:task_manager_admin_panel/screens/sistema/endpoint_tester_screen.dart';
import 'package:task_manager_admin_panel/screens/monitoramento/sistema_logs_screen.dart';
import 'package:task_manager_admin_panel/screens/sistema/query_builder_screen.dart';
import 'package:task_manager_admin_panel/screens/sistema/role_permissao_screen.dart';
import 'package:task_manager_admin_panel/screens/sistema/sessoes_screen.dart';
import 'package:task_manager_admin_panel/screens/sistema/sistema_menu_screen.dart';
import 'package:task_manager_admin_panel/screens/sistema/tela_editor_screen.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.darkTheme, home: child);

void main() {
  testWidgets('renderiza os 10 itens do menu Sistema', (tester) async {
    await tester.pumpWidget(_wrap(const SistemaMenuScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsNWidgets(10));
    expect(find.text('Aplicativo'), findsOneWidget);
    expect(find.text('Cadastro Empresa'), findsOneWidget);
    expect(find.text('Configurações Admin'), findsOneWidget);
    expect(find.text('Config. Sistema'), findsOneWidget);
    expect(find.text('Editor de Telas'), findsOneWidget);
    expect(find.text('Permissões'), findsOneWidget);
    expect(find.text('Teste de Endpoints'), findsOneWidget);
    expect(find.text('Query Builder'), findsOneWidget);
    expect(find.text('Logs & Monitoramento'), findsOneWidget);
    expect(find.text('Sessões'), findsOneWidget);
  });

  final casos = <String, Type>{
    'Aplicativo': AplicativoScreen,
    'Cadastro Empresa': CadastroEmpresaWizardScreen,
    'Configurações Admin': ConfiguracoesAdminScreen,
    'Config. Sistema': ConfiguracoesSistemaScreen,
    'Editor de Telas': TelaEditorScreen,
    'Permissões': RolePermissaoScreen,
    'Teste de Endpoints': EndpointTesterScreen,
    'Query Builder': QueryBuilderScreen,
    'Logs & Monitoramento': SistemaLogsScreen,
    'Sessões': SessoesScreen,
  };

  for (final entry in casos.entries) {
    testWidgets('tocar em "${entry.key}" navega para ${entry.value}',
        (tester) async {
      await tester.pumpWidget(_wrap(const SistemaMenuScreen()));
      await tester.pumpAndSettle();

      final finder = find.text(entry.key);
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();

      expect(find.byType(entry.value), findsOneWidget);
      expect(find.textContaining('Em constru'), findsNothing);
    });
  }
}
