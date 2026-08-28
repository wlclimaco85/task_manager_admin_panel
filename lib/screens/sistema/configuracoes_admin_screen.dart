import 'package:flutter/material.dart';
import '../../config/api_links.dart';
import '../../widgets/generic/field_config.dart';
import '../../widgets/generic/generic_grid_screen.dart';

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
    FieldConfig(key: 'nome', label: 'Nome', required: true),
  ];

  static const _centroCustoFields = [
    FieldConfig(key: 'nome', label: 'Nome', required: true),
  ];

  static const _departamentoFields = [
    FieldConfig(key: 'nome', label: 'Nome', required: true),
    FieldConfig(
      key: 'numeroFolha',
      label: 'Número da Folha',
      type: FieldType.number,
    ),
  ];

  static const _feriadoFields = [
    FieldConfig(key: 'nome', label: 'Nome', required: true),
    FieldConfig(key: 'data', label: 'Data', required: true),
    FieldConfig(
      key: 'repeteAno',
      label: 'Repete todo ano',
      type: FieldType.boolean,
    ),
  ];

  static const _horarioFuncFields = [
    FieldConfig(key: 'nome', label: 'Nome', required: true),
    FieldConfig(key: 'tipo', label: 'Tipo'),
    FieldConfig(key: 'ativo', label: 'Ativo', type: FieldType.boolean),
  ];

  static const _tipoProdutoFields = [
    FieldConfig(key: 'tipoProduto', label: 'Tipo de Produto', required: true),
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
          GenericGridScreen(
            title: 'Cargos',
            listUrl: ApiLinks.allCargos,
            createUrl: ApiLinks.createCargo,
            updateUrl: ApiLinks.updateCargo,
            deleteUrl: ApiLinks.deleteCargo,
            fields: _cargoFields,
            embedded: true,
          ),
          GenericGridScreen(
            title: 'Centro de Custo',
            listUrl: ApiLinks.allCentroCusto,
            createUrl: ApiLinks.createCentroCusto,
            updateUrl: ApiLinks.updateCentroCusto,
            deleteUrl: ApiLinks.deleteCentroCusto,
            fields: _centroCustoFields,
            embedded: true,
          ),
          GenericGridScreen(
            title: 'Departamentos',
            listUrl: ApiLinks.allDepartamento,
            createUrl: ApiLinks.createDepartamento,
            updateUrl: ApiLinks.updateDepartamento,
            deleteUrl: ApiLinks.deleteDepartamento,
            fields: _departamentoFields,
            embedded: true,
          ),
          GenericGridScreen(
            title: 'Feriados',
            listUrl: ApiLinks.allFeriado,
            createUrl: ApiLinks.createFeriado,
            updateUrl: ApiLinks.updateFeriado,
            deleteUrl: ApiLinks.deleteFeriado,
            fields: _feriadoFields,
            embedded: true,
          ),
          GenericGridScreen(
            title: 'Horários',
            listUrl: ApiLinks.allHorarioFunc,
            createUrl: ApiLinks.createHorarioFunc,
            updateUrl: ApiLinks.updateHorarioFunc,
            deleteUrl: ApiLinks.deleteHorarioFunc,
            fields: _horarioFuncFields,
            embedded: true,
          ),
          GenericGridScreen(
            title: 'Tipos de Produto',
            listUrl: ApiLinks.allTipoProduto,
            createUrl: ApiLinks.createTipoProduto,
            updateUrl: ApiLinks.updateTipoProduto,
            deleteUrl: ApiLinks.deleteTipoProduto,
            fields: _tipoProdutoFields,
            embedded: true,
          ),
        ],
      ),
    );
  }
}
