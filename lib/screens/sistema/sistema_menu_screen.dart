import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../monitoramento/sistema_logs_screen.dart';
import 'aplicativo_screen.dart';
import 'cadastro_empresa_wizard_screen.dart';
import 'configuracoes_admin_screen.dart';
import 'configuracoes_sistema/configuracoes_sistema_screen.dart';
import 'endpoint_tester_screen.dart';
import 'query_builder_screen.dart';
import 'role_permissao_screen.dart';
import 'sessoes_screen.dart';
import 'tela_editor_screen.dart';

/// Menu "Sistema" (Fase 2). Lista os 8 itens migrados de `menu_config.dart`
/// (grupo `sistema`, exceto "Empresas" — fica no cliente, ver
/// PLAN.md/RESEARCH.md desta fase). Cada item navega para a tela real
/// correspondente (Task 13.2, Wave 4 — wiring final, depois que todos os 8
/// itens já existiam das waves anteriores).
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
    _SistemaMenuItem(
      id: 'sistema_logs',
      titulo: 'Logs & Monitoramento',
      subtitulo: 'Exceções, erros e warnings do Backend Java e Apps Flutter (7 dias).',
      icone: Icons.monitor_heart_outlined,
    ),
    _SistemaMenuItem(
      id: 'sessoes',
      titulo: 'Sessões',
      subtitulo: 'Matar sessão de um usuário; meia-noite e ociosidade (>1h) são automáticas.',
      icone: Icons.no_accounts_outlined,
    ),
  ];

  static const _builders = <String, WidgetBuilder>{
    'aplicativo': _buildAplicativo,
    'cadastro_empresa': _buildCadastroEmpresa,
    'config_admin': _buildConfigAdmin,
    'config_sistema': _buildConfigSistema,
    'editor_telas': _buildEditorTelas,
    'permissoes': _buildPermissoes,
    'teste_endpoints': _buildTesteEndpoints,
    'query_builder': _buildQueryBuilder,
    'sistema_logs': _buildSistemaLogs,
    'sessoes': _buildSessoes,
  };

  static Widget _buildAplicativo(BuildContext context) =>
      const AplicativoScreen();
  static Widget _buildCadastroEmpresa(BuildContext context) =>
      const CadastroEmpresaWizardScreen();
  static Widget _buildConfigAdmin(BuildContext context) =>
      const ConfiguracoesAdminScreen();
  static Widget _buildConfigSistema(BuildContext context) =>
      const ConfiguracoesSistemaScreen();
  static Widget _buildEditorTelas(BuildContext context) =>
      const TelaEditorScreen();
  static Widget _buildPermissoes(BuildContext context) =>
      const RolePermissaoScreen();
  static Widget _buildTesteEndpoints(BuildContext context) =>
      const EndpointTesterScreen();
  static Widget _buildQueryBuilder(BuildContext context) =>
      const QueryBuilderScreen();
  static Widget _buildSistemaLogs(BuildContext context) =>
      const SistemaLogsScreen();
  static Widget _buildSessoes(BuildContext context) => const SessoesScreen();

  void _onTap(BuildContext context, _SistemaMenuItem item) {
    final builder = _builders[item.id];
    if (builder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Em construção — ${item.titulo}')),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: builder));
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
