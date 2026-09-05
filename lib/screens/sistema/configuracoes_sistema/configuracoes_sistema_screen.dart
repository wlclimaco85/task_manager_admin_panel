import 'package:flutter/material.dart';

import 'acoes_screen.dart';
import 'importacao_cadastros_screen.dart';
import 'importacao_contas_screen.dart';
import 'jobs_screen.dart';
import 'importacao_fiscal_screen.dart';

/// SIS-04 Config. Sistema. Tab container único que agrupa as 4 seções já
/// implementadas nas waves anteriores (Ações simples, Jobs, Importação de
/// Contas, Importação de Cadastros) sob um único item do menu "Sistema" —
/// mesmo padrão de [ConfiguracoesAdminScreen] (Task 02.2), evitando o
/// anti-padrão de arquivo monolítico do `configuracoes_sistema_screen.dart`
/// original (ver PLAN.md da Fase 2, Task 13.1). Cada seção continua em seu
/// próprio arquivo; este container só orquestra a navegação por abas.
class ConfiguracoesSistemaScreen extends StatefulWidget {
  const ConfiguracoesSistemaScreen({super.key});

  @override
  State<ConfiguracoesSistemaScreen> createState() =>
      _ConfiguracoesSistemaScreenState();
}

class _ConfiguracoesSistemaScreenState
    extends State<ConfiguracoesSistemaScreen>
    with SingleTickerProviderStateMixin {
  static const _tabs = [
    Tab(text: 'Ações', key: Key('config_sistema_tab_acoes')),
    Tab(text: 'Jobs', key: Key('config_sistema_tab_jobs')),
    Tab(
      text: 'Importação Contas',
      key: Key('config_sistema_tab_importacao_contas'),
    ),
    Tab(
      text: 'Importação Cadastros',
      key: Key('config_sistema_tab_importacao_cadastros'),
    ),
    Tab(
      text: 'Importação Fiscal',
      key: Key('config_sistema_tab_importacao_fiscal'),
    ),
  ];

  late final TabController _tabController =
      TabController(length: _tabs.length, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Config. Sistema'),
        bottom: TabBar(
          key: const Key('config_sistema_tab_bar'),
          controller: _tabController,
          isScrollable: true,
          tabs: _tabs,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const ConfiguracoesSistemaAcoesScreen(),
          const JobsScreen(),
          ImportacaoContasScreen(),
          ImportacaoCadastrosScreen(),
          const ImportacaoFiscalScreen(),
        ],
      ),
    );
  }
}
