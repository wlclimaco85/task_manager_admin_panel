import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Esqueleto de navegacao do menu "Sistema" (Fase 2, Task 01b.2). Lista os 8
/// itens migrados de `menu_config.dart` (grupo `sistema`, exceto
/// "Empresas" — fica no cliente, ver PLAN.md/RESEARCH.md desta fase). Nesta
/// task todos os itens mostram um `SnackBar` de "Em construcao" — o wiring
/// real para cada tela bespoke/CRUD entra na Task 13.2 (Wave 4), depois que
/// todos os 8 itens existirem.
class SistemaMenuScreen extends StatelessWidget {
  const SistemaMenuScreen({super.key});

  static const _itens = [
    _SistemaMenuItem(
      id: 'aplicativo',
      titulo: 'Aplicativo',
      subtitulo: 'Cadastro de aplicativos (SIS-01).',
      icone: Icons.apps_outlined,
    ),
    _SistemaMenuItem(
      id: 'cadastro_empresa',
      titulo: 'Cadastro Empresa',
      subtitulo: 'Wizard de criacao completa de uma empresa (SIS-02).',
      icone: Icons.business_outlined,
    ),
    _SistemaMenuItem(
      id: 'config_admin',
      titulo: 'Configurações Admin',
      subtitulo:
          'Cargos, Centro de Custo, Departamentos, Feriados, Horarios, Tipos de Produto (SIS-03).',
      icone: Icons.admin_panel_settings_outlined,
    ),
    _SistemaMenuItem(
      id: 'config_sistema',
      titulo: 'Config. Sistema',
      subtitulo:
          'Acoes administrativas, jobs, importacao de CSV, banco de dados (SIS-04).',
      icone: Icons.build_outlined,
    ),
    _SistemaMenuItem(
      id: 'editor_telas',
      titulo: 'Editor de Telas',
      subtitulo: 'Editor visual de metadados de tela e campos (SIS-05).',
      icone: Icons.view_column_outlined,
    ),
    _SistemaMenuItem(
      id: 'permissoes',
      titulo: 'Permissões',
      subtitulo: 'Matriz de permissoes Role x Tela x Campo (SIS-06).',
      icone: Icons.security_outlined,
    ),
    _SistemaMenuItem(
      id: 'teste_endpoints',
      titulo: 'Teste de Endpoints',
      subtitulo: 'Terminal HTTP livre para testar a API (SIS-07).',
      icone: Icons.science_outlined,
    ),
    _SistemaMenuItem(
      id: 'query_builder',
      titulo: 'Query Builder',
      subtitulo: 'Editor SQL ad-hoc (somente SELECT/WITH) (SIS-08).',
      icone: Icons.storage_outlined,
    ),
  ];

  void _onTap(BuildContext context, _SistemaMenuItem item) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Em construção — ${item.titulo}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sistema')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            for (final item in _itens) ...[
              Card(
                child: ListTile(
                  key: Key('sistema_menu_tile_${item.id}'),
                  leading: Icon(item.icone),
                  title: Text(item.titulo),
                  subtitle: Text(item.subtitulo),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _onTap(context, item),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}

class _SistemaMenuItem {
  const _SistemaMenuItem({
    required this.id,
    required this.titulo,
    required this.subtitulo,
    required this.icone,
  });

  final String id;
  final String titulo;
  final String subtitulo;
  final IconData icone;
}
