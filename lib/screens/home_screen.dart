import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/auth_utility.dart';
import 'chamados/ordem_servico_screen.dart';
import 'contatos/contato_comercial_screen.dart';
import 'dashboard/dashboard_crescimento_screen.dart';
import 'licenca/licenca_screen.dart';
import 'login_screen.dart';
import 'modulos/modulo_atribuicao_screen.dart';
import 'modulos/modulo_servico_screen.dart';
import 'monitoramento/sistema_logs_screen.dart';
import 'sistema/sistema_menu_screen.dart';

/// Shell pos-login do Painel do Dono. Fase 3: os 5 modulos reais (Licenca,
/// Contatos, Ordem de Servico, Modulos Contratados, Dashboard de
/// Crescimento) substituem o modulo de demonstracao da Fase 1. A migracao
/// do menu "Sistema" (Fase 2) continua disponivel.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await AuthService().logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final nome = AuthUtility.userInfo?.login?.nome ??
        AuthUtility.userInfo?.login?.email ??
        'usuario';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel do Dono'),
        actions: [
          IconButton(
            key: const Key('home_logout_button'),
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ola, $nome', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Fase 3: Licenca, Contatos, Ordem de Servico, Modulos Contratados e Dashboard de Crescimento.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xl),
            Card(
              child: ListTile(
                key: const Key('home_licenca_tile'),
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Licença'),
                subtitle: const Text(
                    'Criar, editar e ativar/desativar licenças de aplicativo.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LicencaScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: ListTile(
                key: const Key('home_contatos_tile'),
                leading: const Icon(Icons.contacts_outlined),
                title: const Text('Contatos'),
                subtitle: const Text(
                    'CRUD de contatos comerciais vinculados a parceiro/empresa.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ContatoComercialScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: ListTile(
                key: const Key('home_ordem_servico_tile'),
                leading: const Icon(Icons.build_outlined),
                title: const Text('Ordem de Serviço'),
                subtitle: const Text(
                    'Chamados de ordem de serviço: título, status, prioridade e vínculos.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const OrdemServicoScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(
                      top: AppSpacing.sm,
                      left: AppSpacing.md,
                      right: AppSpacing.md,
                    ),
                    child: Text('Módulos Contratados'),
                  ),
                  ListTile(
                    key: const Key('home_modulo_catalogo_tile'),
                    leading: const Icon(Icons.view_module_outlined),
                    title: const Text('Catálogo'),
                    subtitle: const Text('CRUD dos módulos de serviço disponíveis.'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ModuloServicoScreen(),
                      ),
                    ),
                  ),
                  ListTile(
                    key: const Key('home_modulo_atribuicao_tile'),
                    leading: const Icon(Icons.assignment_turned_in_outlined),
                    title: const Text('Atribuição'),
                    subtitle: const Text(
                        'Vincular módulos contratados a um Parceiro ou Empresa.'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ModuloAtribuicaoScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: ListTile(
                key: const Key('home_dashboard_crescimento_tile'),
                leading: const Icon(Icons.trending_up_outlined),
                title: const Text('Dashboard de Crescimento'),
                subtitle: const Text(
                    'Novos parceiros/empresas, módulos contratados por mês e projeção.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DashboardCrescimentoScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: ListTile(
                key: const Key('home_sistema_logs_tile'),
                leading: const Icon(Icons.monitor_heart_outlined, color: Colors.indigo),
                title: const Text('Logs & Monitoramento'),
                subtitle: const Text(
                    'Monitorar exceções e warnings do backend Java e apps Flutter (histórico de 7 dias).'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SistemaLogsScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: ListTile(
                key: const Key('home_sistema_tile'),
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Sistema'),
                subtitle: const Text(
                    'Aplicativo, Cadastro Empresa, Configurações Admin, Config. Sistema, Editor de Telas, Permissões, Teste de Endpoints, Query Builder.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SistemaMenuScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}
