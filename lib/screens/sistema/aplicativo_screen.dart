import 'package:flutter/material.dart';
import '../../config/api_links.dart';
import '../../widgets/generic/field_config.dart';
import '../../widgets/generic/generic_grid_screen.dart';

/// SIS-01 Aplicativo. Wrapper fino sobre [GenericGridScreen] — sem logica
/// nova, mesmo padrao do `aplicativo_screen.dart` original do cliente,
/// adaptado ao par generico do admin panel (ver PLAN.md da Fase 2, Task
/// 02.1).
class AplicativoScreen extends StatelessWidget {
  const AplicativoScreen({super.key});

  static const _fields = [
    FieldConfig(key: 'nome', label: 'Nome', required: true),
    FieldConfig(
      key: 'observacao',
      label: 'Observação',
      type: FieldType.multiline,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GenericGridScreen(
      title: 'Aplicativo',
      listUrl: ApiLinks.allAplicativos,
      createUrl: ApiLinks.createAplicativo,
      updateUrl: ApiLinks.updateAplicativo,
      deleteUrl: ApiLinks.deleteAplicativo,
      fields: _fields,
    );
  }
}
