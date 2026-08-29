import 'package:flutter/material.dart';
import '../../config/api_links.dart';
import '../../widgets/generic/dropdown_source.dart';
import '../../widgets/generic/field_config.dart';
import '../../widgets/generic/generic_grid_screen.dart';

/// OS-01 Ordem de Servico, via dominio `Chamado` ja existente (nao ha
/// endpoint literal "OrdemServico" no backend, ver RESEARCH.md A1). Reusa
/// `ApiLinks.createChamado`/`deleteChamado` (Fase 2 SIS-02) e os getters de
/// leitura/atualizacao proprios da Fase 3 (`allChamadosOS`/`updateChamadoOS`).
///
/// ATENCAO — contrato assimetrico POST vs PUT do `Chamado` (achado desta
/// sessao de planning, ver PLAN.md `## Achados desta sessao` item 3):
/// `ChamadoDTO` (`POST /api/chamados`) aceita `empresa:{id}`/`setor:{id}`
/// aninhados mas `parceiroId` PLANO; ja `PUT /api/chamados/{id}` (`JsonNode`
/// livre) aceita `parceiro:{id}`/`empresa:{id}`/`setor:{id}` TODOS
/// aninhados. `transformChamadoPayload` resolve essa diferenca por verbo.
class OrdemServicoScreen extends StatelessWidget {
  const OrdemServicoScreen({super.key});

  static final _fields = [
    const FieldConfig(
      key: 'titulo',
      label: 'Titulo',
      required: true,
      showInGrid: true,
    ),
    const FieldConfig(
      key: 'descricao',
      label: 'Descricao',
      type: FieldType.multiline,
      showInGrid: false,
    ),
    const FieldConfig(
      key: 'status',
      label: 'Status',
      type: FieldType.dropdown,
      showInGrid: true,
      options: [
        DropdownOption(value: 'ABERTO', label: 'Aberto'),
        DropdownOption(value: 'EM_ANDAMENTO', label: 'Em andamento'),
        DropdownOption(value: 'FECHADO', label: 'Fechado'),
        DropdownOption(value: 'CANCELADO', label: 'Cancelado'),
        DropdownOption(value: 'AGUARDANDO_CLIENTE', label: 'Aguardando cliente'),
        DropdownOption(value: 'BLOQUEADO', label: 'Bloqueado'),
      ],
    ),
    const FieldConfig(
      key: 'prioridade',
      label: 'Prioridade',
      type: FieldType.dropdown,
      showInGrid: true,
      options: [
        DropdownOption(value: 'BAIXA', label: 'Baixa'),
        DropdownOption(value: 'MEDIA', label: 'Media'),
        DropdownOption(value: 'ALTA', label: 'Alta'),
        DropdownOption(value: 'URGENTE', label: 'Urgente'),
        DropdownOption(value: 'NORMAL', label: 'Normal'),
      ],
    ),
    FieldConfig(
      key: 'empresa',
      label: 'Empresa',
      type: FieldType.dropdown,
      required: false,
      showInGrid: false,
      optionsLoader: remoteDropdownSource(
        url: ApiLinks.dropdownEmpresas,
        valueKey: 'id',
        labelBuilder: (r) => r['nome']?.toString() ?? '',
      ),
    ),
    FieldConfig(
      key: 'parceiro',
      label: 'Parceiro',
      type: FieldType.dropdown,
      required: false,
      showInGrid: false,
      optionsLoader: remoteDropdownSource(
        url: ApiLinks.dropdownParceiros,
        valueKey: 'id',
        labelBuilder: (r) => r['nome']?.toString() ?? '',
      ),
    ),
    FieldConfig(
      key: 'setor',
      label: 'Setor',
      type: FieldType.dropdown,
      required: false,
      showInGrid: false,
      optionsLoader: remoteDropdownSource(
        url: ApiLinks.dropdownSetores,
        valueKey: 'id',
        labelBuilder: (r) => r['descricao']?.toString() ?? '',
      ),
    ),
    const FieldConfig(
      key: 'dataAbertura',
      label: 'Data de abertura',
      type: FieldType.date,
      dateTime: true,
      showInGrid: false,
    ),
    const FieldConfig(
      key: 'dataFechamento',
      label: 'Data de fechamento',
      type: FieldType.date,
      dateTime: true,
      showInGrid: false,
    ),
    const FieldConfig(
      key: 'dataVencimentoObrigacao',
      label: 'Vencimento da obrigacao',
      type: FieldType.date,
      showInGrid: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GenericGridScreen(
      title: 'Ordem de Servico',
      listUrl: ApiLinks.allChamadosOS,
      createUrl: ApiLinks.createChamado,
      updateUrl: ApiLinks.updateChamadoOS,
      deleteUrl: ApiLinks.deleteChamado,
      fields: _fields,
      transformPayload: transformChamadoPayload,
    );
  }
}

/// Monta o payload correto por verbo para `Chamado` (ver contrato
/// assimetrico documentado acima). Funcao pura/testavel isoladamente,
/// separada da tela para nao precisar montar o widget completo no teste.
Map<String, dynamic> transformChamadoPayload(
  Map<String, dynamic> raw,
  bool isEditing,
) {
  final data = Map<String, dynamic>.from(raw);
  final parceiro = data.remove('parceiro');
  final empresa = data.remove('empresa');
  final setor = data.remove('setor');

  if (isEditing) {
    // PUT /api/chamados/{id} (JsonNode livre): parceiro/empresa/setor TODOS
    // aninhados como {id: valor}.
    if (parceiro != null) data['parceiro'] = {'id': parceiro};
    if (empresa != null) data['empresa'] = {'id': empresa};
    if (setor != null) data['setor'] = {'id': setor};
  } else {
    // POST /api/chamados (ChamadoDTO): parceiroId PLANO, empresa/setor
    // aninhados como {id: valor}.
    if (parceiro != null) data['parceiroId'] = parceiro;
    if (empresa != null) data['empresa'] = {'id': empresa};
    if (setor != null) data['setor'] = {'id': setor};
  }

  return data;
}
