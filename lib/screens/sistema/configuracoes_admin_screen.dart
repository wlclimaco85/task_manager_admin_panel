import 'package:flutter/material.dart';
import '../../config/api_links.dart';
import '../../widgets/generic_grid_windows_screen.dart';

/// SIS-03 Configuracoes Admin. Tab container unico com os 6 sub-CRUDs
/// (Decisao do PO item 2 do RESEARCH.md da Fase 2: "menor ruido no menu,
/// mais coeso"). Cada aba e um [GenericGridScreen] embutido (Task 01.4 —
/// sem Scaffold/AppBar/FAB proprios, evitando chrome duplicado dentro da
/// aba); create/edit/delete sao herdados do widget generico, sem logica
/// nova aqui.
class ConfiguracoesAdminScreen extends StatefulWidget {
  const ConfiguracoesAdminScreen({super.key});

  @override
  State<ConfiguracoesAdminScreen> createState() =>
      _ConfiguracoesAdminScreenState();
}

class _ConfiguracoesAdminScreenState extends State<ConfiguracoesAdminScreen>
    with SingleTickerProviderStateMixin {
  static const _tabs = [
    Tab(text: 'Cargos', key: Key('config_admin_tab_cargos')),
    Tab(text: 'Centro de Custo', key: Key('config_admin_tab_centro_custo')),
    Tab(text: 'Departamentos', key: Key('config_admin_tab_departamentos')),
    Tab(text: 'Feriados', key: Key('config_admin_tab_feriados')),
    Tab(text: 'Horários', key: Key('config_admin_tab_horarios')),
    Tab(text: 'Tipos de Produto', key: Key('config_admin_tab_tipos_produto')),
  ];

  static const _cargoFields = [
    FieldConfigWindows(fieldName: 'nome', label: 'Nome', isRequired: true),
  ];

  static const _centroCustoFields = [
    FieldConfigWindows(fieldName: 'nome', label: 'Nome', isRequired: true),
  ];

  static const _departamentoFields = [
    FieldConfigWindows(fieldName: 'nome', label: 'Nome', isRequired: true),
    FieldConfigWindows(
      fieldName: 'numeroFolha',
      label: 'Número da Folha',
      fieldType: FieldType.number,
    ),
  ];

  static const _feriadoFields = [
    FieldConfigWindows(fieldName: 'nome', label: 'Nome', isRequired: true),
    FieldConfigWindows(fieldName: 'data', label: 'Data', isRequired: true),
    FieldConfigWindows(
      fieldName: 'repeteAno',
      label: 'Repete todo ano',
      fieldType: FieldType.boolean,
    ),
  ];

  static const _horarioFuncFields = [
    FieldConfigWindows(fieldName: 'nome', label: 'Nome', isRequired: true),
    FieldConfigWindows(fieldName: 'tipo', label: 'Tipo'),
    FieldConfigWindows(fieldName: 'ativo', label: 'Ativo', fieldType: FieldType.boolean),
  ];

  static const _tipoProdutoFields = [
    FieldConfigWindows(fieldName: 'tipoProduto', label: 'Tipo de Produto', isRequired: true),
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
        title: const Text('Configurações Admin'),
        bottom: TabBar(
          key: const Key('config_admin_tab_bar'),
          controller: _tabController,
          isScrollable: true,
          tabs: _tabs,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          GenericGridWindowsScreen(
            title: 'Cargos',
            fetchEndpoint: ApiLinks.allCargos,
            createEndpoint: ApiLinks.createCargo,
            updateEndpoint: ApiLinks.allCargos,
            deleteEndpoint: ApiLinks.allCargos,
            fieldConfigs: _cargoFields,
          ),
          GenericGridWindowsScreen(
            title: 'Centro de Custo',
            fetchEndpoint: ApiLinks.allCentroCusto,
            createEndpoint: ApiLinks.createCentroCusto,
            updateEndpoint: ApiLinks.allCentroCusto,
            deleteEndpoint: ApiLinks.allCentroCusto,
            fieldConfigs: _centroCustoFields,
          ),
          GenericGridWindowsScreen(
            title: 'Departamentos',
            fetchEndpoint: ApiLinks.allDepartamento,
            createEndpoint: ApiLinks.createDepartamento,
            updateEndpoint: ApiLinks.allDepartamento,
            deleteEndpoint: ApiLinks.allDepartamento,
            fieldConfigs: _departamentoFields,
          ),
          GenericGridWindowsScreen(
            title: 'Feriados',
            fetchEndpoint: ApiLinks.allFeriado,
            createEndpoint: ApiLinks.createFeriado,
            updateEndpoint: ApiLinks.allFeriado,
            deleteEndpoint: ApiLinks.allFeriado,
            fieldConfigs: _feriadoFields,
          ),
          GenericGridWindowsScreen(
            title: 'Horários',
            fetchEndpoint: ApiLinks.allHorarioFunc,
            createEndpoint: ApiLinks.createHorarioFunc,
            updateEndpoint: ApiLinks.allHorarioFunc,
            deleteEndpoint: ApiLinks.allHorarioFunc,
            fieldConfigs: _horarioFuncFields,
          ),
          GenericGridWindowsScreen(
            title: 'Tipos de Produto',
            fetchEndpoint: ApiLinks.allTipoProduto,
            createEndpoint: ApiLinks.createTipoProduto,
            updateEndpoint: ApiLinks.allTipoProduto,
            deleteEndpoint: ApiLinks.allTipoProduto,
            fieldConfigs: _tipoProdutoFields,
          ),
        ],
      ),
    );
  }
}
