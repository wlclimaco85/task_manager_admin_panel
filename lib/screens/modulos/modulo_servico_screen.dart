import 'package:flutter/material.dart';
import '../../config/api_links.dart';
import '../../widgets/generic_grid_windows_screen.dart';

/// MOD-01 Modulos Contratados — catalogo `ModuloServico`. CRUD simples via
/// par generico, sem adaptacao especial: `ModuloServicoController` ja usa o
/// envelope padrao `{data:{dados,total}}` e tem `DELETE`.
class ModuloServicoScreen extends StatelessWidget {
  const ModuloServicoScreen({super.key});

  static final _fields = [
    const FieldConfigWindows(fieldName: 'nome', label: 'Nome', isRequired: true),
    const FieldConfigWindows(fieldName: 'descricao', label: 'Descricao'),
    const FieldConfigWindows(fieldName: 'ativo', label: 'Ativo', fieldType: FieldType.boolean),
  ];

  @override
  Widget build(BuildContext context) {
    return GenericGridWindowsScreen(
      title: 'Modulos (catalogo)',
      fetchEndpoint: ApiLinks.allModulosServico,
      createEndpoint: ApiLinks.createModuloServico,
      updateEndpoint: ApiLinks.allModulosServico,
      deleteEndpoint: ApiLinks.allModulosServico,
      fieldConfigs: _fields,
    );
  }
}
