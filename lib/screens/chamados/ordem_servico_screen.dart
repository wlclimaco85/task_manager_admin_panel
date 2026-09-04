import 'package:flutter/material.dart';
import '../../config/api_links.dart';
import '../../widgets/generic_grid_windows_screen.dart';

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
    const FieldConfigWindows(
      fieldName: 'titulo',
      label: 'Titulo',
      isRequired: true,
      isInGrid: true,
    ),
    const FieldConfigWindows(
      fieldName: 'descricao',
      label: 'Descricao',
      fieldType: FieldType.multiline,
      isInGrid: false,
    ),
    const FieldConfigWindows(
      fieldName: 'status',
      label: 'Status',
      fieldType: FieldType.dropdown,
      isInGrid: true,
      dropdownOptions: [
        {'value': 'ABERTO', 'label': 'Aberto'},
        {'value': 'EM_ANDAMENTO', 'label': 'Em andamento'},
        {'value': 'FECHADO', 'label': 'Fechado'},
        {'value': 'CANCELADO', 'label': 'Cancelado'},
        {'value': 'AGUARDANDO_CLIENTE', 'label': 'Aguardando cliente'},
        {'value': 'BLOQUEADO', 'label': 'Bloqueado'},
      ],
    ),
    const FieldConfigWindows(
      fieldName: 'prioridade',
      label: 'Prioridade',
      fieldType: FieldType.dropdown,
      isInGrid: true,
      dropdownOptions: [
        {'value': 'BAIXA', 'label': 'Baixa'},
        {'value': 'MEDIA', 'label': 'Media'},
        {'value': 'ALTA', 'label': 'Alta'},
        {'value': 'URGENTE', 'label': 'Urgente'},
        {'value': 'NORMAL', 'label': 'Normal'},
      ],
    ),
    FieldConfigWindows(
      fieldName: 'setor',
      label: 'Setor',
      fieldType: FieldType.dropdown,
      isRequired: false,
      isInGrid: false,
    ),
    const FieldConfigWindows(
      fieldName: 'dataAbertura',
      label: 'Data de abertura',
      fieldType: FieldType.date,
      fieldType: FieldType.datetime,
      isInGrid: false,
    ),
    const FieldConfigWindows(
      fieldName: 'dataFechamento',
      label: 'Data de fechamento',
      fieldType: FieldType.date,
      fieldType: FieldType.datetime,
      isInGrid: false,
    ),
    const FieldConfigWindows(
      fieldName: 'dataVencimentoObrigacao',
      label: 'Vencimento da obrigacao',
      fieldType: FieldType.date,
      isInGrid: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GenericGridWindowsScreen(
      title: 'Ordem de Servico',
      fetchEndpoint: ApiLinks.allChamadosOS,
      createEndpoint: ApiLinks.createChamado,
      updateEndpoint: ApiLinks.allChamadosOS,
      deleteEndpoint: ApiLinks.allChamadosOS,
      fieldConfigs: _fields,
      
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
