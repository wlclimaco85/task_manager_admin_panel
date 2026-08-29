import 'package:flutter/material.dart';
import '../../config/api_links.dart';
import '../../widgets/generic/dropdown_source.dart';
import '../../widgets/generic/field_config.dart';
import '../../widgets/generic/generic_grid_screen.dart';

/// LIC-01 Licenca. CRUD sobre backend ja pronto (`/api/licencas`), SEM
/// exclusao — o `LicencaController` nao expoe `DELETE` (ver RESEARCH.md
/// Pitfall 2); a acao equivalente e desativar via `ativo=false` no proprio
/// form de edicao. `deleteUrl: null` faz o `GenericGridScreen` esconder o
/// icone de excluir (Fase 3 Task 03.3).
class LicencaScreen extends StatelessWidget {
  const LicencaScreen({super.key});

  static final _fields = [
    FieldConfig(
      key: 'codApp',
      label: 'Aplicativo',
      type: FieldType.dropdown,
      required: true,
      showInGrid: true,
      optionsLoader: remoteDropdownSource(
        url: ApiLinks.allAplicativos,
        valueKey: 'id',
        labelBuilder: (r) => r['nome']?.toString() ?? '',
      ),
    ),
    const FieldConfig(key: 'nomeApp', label: 'Nome do App'),
    const FieldConfig(key: 'ativo', label: 'Ativo', type: FieldType.boolean),
    const FieldConfig(
      key: 'dataInicio',
      label: 'Inicio',
      type: FieldType.date,
    ),
    const FieldConfig(
      key: 'dataVencimento',
      label: 'Vencimento',
      type: FieldType.date,
      required: true,
    ),
    const FieldConfig(
      key: 'observacao',
      label: 'Observacao',
      type: FieldType.multiline,
      showInGrid: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GenericGridScreen(
      title: 'Licencas',
      listUrl: ApiLinks.allLicencas,
      createUrl: ApiLinks.createLicenca,
      updateUrl: ApiLinks.updateLicenca,
      deleteUrl: null,
      fields: _fields,
    );
  }
}
