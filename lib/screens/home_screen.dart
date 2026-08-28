import 'package:flutter/material.dart';
import '../config/api_links.dart';
import '../core/theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/auth_utility.dart';
import '../widgets/generic/field_config.dart';
import '../widgets/generic/generic_grid_screen.dart';
import 'login_screen.dart';

/// Shell pos-login do Painel do Dono. Nesta Fase 1, expoe um unico modulo
/// de demonstracao (Contatos) que prova o par grid+form+detail ponta a
/// ponta contra o backend. Os modulos reais (licenca, OS, migracao do
/// menu "Sistema" etc.) entram nas fases seguintes do ROADMAP.md.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _contatoFields = [
    FieldConfig(key: 'nome', label: 'Nome', required: true),
    FieldConfig(key: 'email', label: 'E-mail', type: FieldType.email),
    FieldConfig(key: 'telefone', label: 'Telefone'),
  ];

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
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ola, $nome', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Fase 1: scaffold + autenticacao + grid/form/detail base.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xl),
            Card(
              child: ListTile(
                key: const Key('home_contatos_tile'),
                leading: const Icon(Icons.contacts_outlined),
                title: const Text('Contatos (demonstracao)'),
                subtitle: const Text(
                    'Modulo de exemplo provando grid + form + detail.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GenericGridScreen(
                      title: 'Contatos',
                      listUrl: ApiLinks.allContatos,
                      createUrl: ApiLinks.createContato,
                      updateUrl: ApiLinks.updateContato,
                      deleteUrl: ApiLinks.deleteContato,
                      fields: _contatoFields,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
