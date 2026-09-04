import 'package:flutter/material.dart';
import '../../config/api_links.dart';
import '../../widgets/generic_grid_windows_screen.dart';

/// CONT-01 Contatos. Dominio NOVO `ContatoComercial` (backend Fase 3
/// P01) — CRUD completo (inclusive exclusao) contra `/api/contato-comercial`,
/// nao o `/api/contatos` legado (log de negociacao de graos, domínio
/// errado, ver RESEARCH.md Item 2). Vinculo a Parceiro/Empresa e um detalhe
/// de modelagem do backend, nao entra como campo de formulario nesta
/// primeira versao da tela (ver PLAN.md Task 04.2).
class ContatoComercialScreen extends StatelessWidget {
  const ContatoComercialScreen({super.key});

  static const _fields = [
    FieldConfigWindows(fieldName: 'nome', label: 'Nome', isRequired: true),
    FieldConfigWindows(fieldName: 'email', label: 'E-mail', fieldType: FieldType.email),
    FieldConfigWindows(fieldName: 'telefone', label: 'Telefone'),
    FieldConfigWindows(fieldName: 'cargo', label: 'Cargo'),
    FieldConfigWindows(
      fieldName: 'observacao',
      label: 'Observacao',
      fieldType: FieldType.multiline,
      isInGrid: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GenericGridWindowsScreen(
      title: 'Contatos',
      fetchEndpoint: ApiLinks.allContatosComerciais,
      createEndpoint: ApiLinks.createContatoComercial,
      updateEndpoint: ApiLinks.allContatosComerciais,
      deleteEndpoint: ApiLinks.allContatosComerciais,
      fieldConfigs: _fields,
    );
  }
}
