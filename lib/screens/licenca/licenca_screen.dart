import 'package:flutter/material.dart';
import '../../config/api_links.dart';
import '../../widgets/generic_grid_windows_screen.dart';

/// LIC-01 Licenca. CRUD sobre backend ja pronto (`/api/licencas`), SEM
/// exclusao — o `LicencaController` nao expoe `DELETE` (ver RESEARCH.md
/// Pitfall 2); a acao equivalente e desativar via `ativo=false` no proprio
/// form de edicao. `deleteEndpoint: ''` faz o `GenericGridScreen` esconder o
/// icone de excluir (Fase 3 Task 03.3).
class LicencaScreen extends StatelessWidget {
  const LicencaScreen({super.key});

  static final _fields = [
    FieldConfigWindows(fieldName: 'broken', label: 'broken'),
    const FieldConfigWindows(fieldName: 'nomeApp', label: 'Nome do App'),
    const FieldConfigWindows(fieldName: 'ativo', label: 'Ativo', fieldType: FieldType.boolean),
    const FieldConfigWindows(
      fieldName: 'dataInicio',
      label: 'Inicio',
      fieldType: FieldType.date,
    ),
    const FieldConfigWindows(
      fieldName: 'dataVencimento',
      label: 'Vencimento',
      fieldType: FieldType.date,
      isRequired: true,
    ),
    const FieldConfigWindows(
      fieldName: 'observacao',
      label: 'Observacao',
      fieldType: FieldType.multiline,
      isInGrid: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GenericGridWindowsScreen(
      title: 'Licencas',
      fetchEndpoint: ApiLinks.allLicencas,
      createEndpoint: ApiLinks.createLicenca,
      updateEndpoint: ApiLinks.allLicencas,
      deleteEndpoint: '',
      fieldConfigs: _fields,
    );
  }
}
