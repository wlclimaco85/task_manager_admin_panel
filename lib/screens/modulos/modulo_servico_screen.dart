import 'package:flutter/material.dart';
import '../../config/api_links.dart';
import '../../widgets/generic/field_config.dart';
import '../../widgets/generic/generic_grid_screen.dart';

/// MOD-01 Modulos Contratados — catalogo `ModuloServico`. CRUD simples via
/// par generico, sem adaptacao especial: `ModuloServicoController` ja usa o
/// envelope padrao `{data:{dados,total}}` e tem `DELETE`.
class ModuloServicoScreen extends StatelessWidget {
  const ModuloServicoScreen({super.key});

  static final _fields = [
    const FieldConfig(key: 'nome', label: 'Nome', required: true),
    const FieldConfig(key: 'descricao', label: 'Descricao'),
    const FieldConfig(key: 'ativo', label: 'Ativo', type: FieldType.boolean),
  ];

  @override
  Widget build(BuildContext context) {
    return GenericGridScreen(
      title: 'Modulos (catalogo)',
      listUrl: ApiLinks.allModulosServico,
      createUrl: ApiLinks.createModuloServico,
      updateUrl: ApiLinks.updateModuloServico,
      deleteUrl: ApiLinks.deleteModuloServico,
      fields: _fields,
    );
  }
}
