import 'package:flutter/material.dart';
import '../../config/api_links.dart';
import '../../widgets/generic/field_config.dart';
import '../../widgets/generic/generic_grid_screen.dart';

/// CONT-01 Contatos. Dominio NOVO `ContatoComercial` (backend Fase 3
/// P01) — CRUD completo (inclusive exclusao) contra `/api/contato-comercial`,
/// nao o `/api/contatos` legado (log de negociacao de graos, domínio
/// errado, ver RESEARCH.md Item 2). Vinculo a Parceiro/Empresa e um detalhe
/// de modelagem do backend, nao entra como campo de formulario nesta
/// primeira versao da tela (ver PLAN.md Task 04.2).
class ContatoComercialScreen extends StatelessWidget {
  const ContatoComercialScreen({super.key});

  static const _fields = [
    FieldConfig(key: 'nome', label: 'Nome', required: true),
    FieldConfig(key: 'email', label: 'E-mail', type: FieldType.email),
    FieldConfig(key: 'telefone', label: 'Telefone'),
    FieldConfig(key: 'cargo', label: 'Cargo'),
    FieldConfig(
      key: 'observacao',
      label: 'Observacao',
      type: FieldType.multiline,
      showInGrid: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GenericGridScreen(
      title: 'Contatos',
      listUrl: ApiLinks.allContatosComerciais,
      createUrl: ApiLinks.createContatoComercial,
      updateUrl: ApiLinks.updateContatoComercial,
      deleteUrl: ApiLinks.deleteContatoComercial,
      fields: _fields,
    );
  }
}
