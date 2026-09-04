import 'package:flutter/material.dart';
import '../../config/api_links.dart';
import '../../widgets/generic_grid_windows_screen.dart';

/// SIS-01 Aplicativo. Wrapper fino sobre [GenericGridScreen] — sem logica
/// nova, mesmo padrao do `aplicativo_screen.dart` original do cliente,
/// adaptado ao par generico do admin panel (ver PLAN.md da Fase 2, Task
/// 02.1).
class AplicativoScreen extends StatelessWidget {
  const AplicativoScreen({super.key});

  static const _fields = [
    FieldConfigWindows(fieldName: 'nome', label: 'Nome', isRequired: true),
    FieldConfigWindows(
      fieldName: 'observacao',
      label: 'Observação',
      fieldType: FieldType.multiline,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GenericGridWindowsScreen(
      title: 'Aplicativo',
      fetchEndpoint: ApiLinks.allAplicativos,
      createEndpoint: ApiLinks.createAplicativo,
      updateEndpoint: ApiLinks.allAplicativos,
      deleteEndpoint: ApiLinks.allAplicativos,
      fieldConfigs: _fields,
    );
  }
}
