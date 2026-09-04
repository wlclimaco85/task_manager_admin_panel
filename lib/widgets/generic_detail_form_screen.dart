import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/api_links.dart';
import '../../../utils/grid_colors.dart';
import '../../../utils/tenant_context.dart';
import '../../../services/network_caller.dart';
import '../models/telas_model.dart';
import '../services/tela_caller.dart';
import '../customization/dynamic_grid_dynamic_screen.dart' as mobile_dyn;
import '../customization/dynamic_grid_windows_screen.dart' as dyn;
import 'generic_grid_windows_screen.dart'
    show
        FieldConfigWindows,
        FieldType,
        SecurityCheck,
        FileConfig,
        platformFileToDataUri;

/// Avalia a expressão `visibleWhen` (formato "<fieldName>==<valor>") contra o
/// estado atual do formulário. Sem expressão, o campo é sempre visível.
///
/// Quando o campo referenciado não existe no estado, usa o valor padrão do
/// tipo esperado: bool ausente == false; demais tipos ausentes == null.
bool avaliarVisibleWhen(
    String? expressao, Map<String, dynamic> estadoFormulario) {
  if (expressao == null || expressao.trim().isEmpty) return true;

  final partes = expressao.split('==');
  if (partes.length != 2) return true;

  final fieldName = partes[0].trim();
  final valorEsperadoTexto = partes[1].trim();

  dynamic valorEsperado;
  if (valorEsperadoTexto == 'true') {
    valorEsperado = true;
  } else if (valorEsperadoTexto == 'false') {
    valorEsperado = false;
  } else {
    valorEsperado = valorEsperadoTexto;
  }

  dynamic valorAtual = estadoFormulario[fieldName];
  if (!estadoFormulario.containsKey(fieldName)) {
    valorAtual = valorEsperado is bool ? false : null;
  }

  return valorAtual == valorEsperado;
}

/// Decide se um campo de `tela.fields` (config vinda do backend) deve
/// entrar no formulário, dado um possível [override] client-side.
///
/// Bug de produção (sistêmico -- reproduzido em Login > Cadastro, mas
/// afeta QUALQUER tela que use `fieldOverrides` pra esconder um campo):
/// `_buildFormTab` checava `if (!f.isInForm) continue` usando SÓ o
/// `isInForm` que o backend manda pra aquele campo -- um override
/// declarando `isInForm: false` nunca era consultado nesse gate, então um
/// campo "fantasma"/redundante que o backend já expõe como `isInForm:true`
/// (ex.: "Setores" texto solto, sem uso real, com a gestão de verdade numa
/// aba dedicada) continuava aparecendo no Cadastro mesmo com o override
/// pedindo pra escondê-lo. Regra correta: o override, quando existe, tem
/// prioridade TOTAL sobre o `isInForm` do backend -- pra mostrar OU pra
/// esconder.
@visibleForTesting
bool resolveFieldVisibility(
    {required bool backendIsInForm, FieldConfigWindows? override}) {
  if (override != null) return override.isInForm;
  return backendIsInForm;
}

/// Resolve o rótulo exibido no chip de um valor já selecionado num campo
/// multiselect (ex.: Roles, Setores).
///
/// Bug de produção: um valor JÁ selecionado (ex.: `roles: [{"id":"21"}]`
/// salvo no registro) que a lista de OPÇÕES disponíveis (buscada de forma
/// assíncrona, ex. roles filtradas por parceiro/empresa) não devolve de
/// volta -- ex. role atribuída manualmente, fora do fallback "sempre
/// disponível" do backend -- nunca virava chip. O campo aparecia
/// "Selecione..." (como se nada estivesse selecionado) mesmo com o dado
/// real salvo no registro. Esta função resolve o rótulo em 3 níveis:
/// 1) a opção carregada (rótulo real e atualizado), 2) o rótulo capturado
/// do PRÓPRIO registro na inicialização (`savedLabels`, independente da
/// lista de opções ter chegado ou não), 3) o id bruto como último recurso.
@visibleForTesting
String resolveMultiSelectChipLabel({
  required String selectedId,
  required List<Map<String, dynamic>> loadedOptions,
  required String valueField,
  required String displayField,
  required Map<String, String> savedLabels,
}) {
  for (final opcao in loadedOptions) {
    if (opcao[valueField]?.toString() == selectedId) {
      return opcao[displayField]?.toString() ?? '';
    }
  }
  return savedLabels[selectedId] ?? '#$selectedId';
}

@visibleForTesting
dynamic resolveGenericDetailFormValue(
    Map<String, dynamic> item, String fieldName) {
  if (item.containsKey(fieldName)) return item[fieldName];
  final aliases = _genericDetailFieldAliases(fieldName);
  for (final alias in aliases) {
    if (item.containsKey(alias)) return item[alias];
  }

  final normalizedField = _normalizeGenericDetailFieldName(fieldName);
  for (final entry in item.entries) {
    if (_normalizeGenericDetailFieldName(entry.key.toString()) ==
        normalizedField) {
      return entry.value;
    }
  }
  return null;
}

/// Alias irregulares que a conversão camel<->snake genérica não resolve.
///
/// Bug de produção (parceiro/empresa: campos "Tipo Parceiros" e "Modulo
/// Servicos" sempre voltavam vazios ao reabrir um registro já salvo, mesmo
/// com o PUT retornando os dados certos): o gerador de tela no backend
/// (`TelaGeneratorServiceImpl.loadFields`) nomeia campos multiselect
/// ManyToMany auto-detectados como `otherTable + "s"` (ex.: tabela
/// `tipo_parceiro` -> campo de tela `tipo_parceiros`), mas o nome real da
/// propriedade serializada na entidade/DTO é `tiposParceiro` (plural
/// irregular, "tipos" na frente). `tipo_parceiros` normalizado vira
/// "tipoparceiros" e `tiposParceiro` normalizado vira "tiposparceiro" — o
/// "s" troca de posição, então nenhuma conversão camel<->snake genérica
/// encontra o valor salvo, e o multiselect sempre inicializa vazio.
/// Mapear aqui os dois sentidos até o backend nomear o campo de forma
/// consistente com a propriedade real da entidade.
const Map<String, List<String>> _genericDetailIrregularAliases = {
  'tipo_parceiros': ['tiposParceiro', 'tipos_parceiro'],
  'tiposparceiro': ['tipo_parceiros', 'tiposParceiro'],
};

List<String> _genericDetailFieldAliases(String fieldName) {
  final aliases = <String>[];
  final snake = _genericDetailCamelToSnake(fieldName);
  final camel = _genericDetailSnakeToCamel(fieldName);
  if (snake != fieldName) aliases.add(snake);
  if (camel != fieldName) aliases.add(camel);
  final irregular = _genericDetailIrregularAliases[fieldName.toLowerCase()];
  if (irregular != null) aliases.addAll(irregular);
  return aliases;
}

String _normalizeGenericDetailFieldName(String value) =>
    value.replaceAll('_', '').toLowerCase();

String _genericDetailCamelToSnake(String value) {
  return value
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)}_${match.group(2)}',
      )
      .toLowerCase();
}

String _genericDetailSnakeToCamel(String value) {
  if (!value.contains('_')) return value;
  final parts = value.split('_');
  return parts.first +
      parts.skip(1).map((part) {
        if (part.isEmpty) return part;
        return part[0].toUpperCase() + part.substring(1);
      }).join();
}

// ---------------------------------------------------------------
// GenericDetailFormScreen
// ---------------------------------------------------------------
/// Explicit grid tab — shown as a full DynamicGridWindowsScreen tab.
/// [extraParamKey] is the query param name sent to the backend (e.g. 'loginId').
/// [extraParamValue] is the value (usually the parent id).
class RelatedGridTab {
  final String title;
  final IconData icon;
  final String? telaNome;
  final Map<String, dynamic>? extraParams;
  final List<FieldConfigWindows>? fieldOverrides;

  /// Sobrescreve o endpoint de exclusão do grid. Use `:id` como placeholder do
  /// id da linha. Útil quando "excluir" nesta aba deve DESVINCULAR em vez de
  /// apagar a entidade (ex.: aba Roles do login → DELETE /api/logins/{loginId}/roles/:id).
  final String? deleteEndpointOverride;

  /// Dados fixos injetados no payload ao salvar (ex.: aplicativo fixo).
  final Map<String, dynamic>? additionalFormData;

  /// Transforma o formData final antes do submit (ex.: ajustar formato de
  /// data para o tipo esperado pelo backend). Ver card #431.
  final Map<String, dynamic> Function(Map<String, dynamic> formData)?
      transformFormData;

  /// Widget customizado — quando informado, ignora telaNome e exibe este widget na aba
  final Widget? customWidget;
  final Widget Function(Map<String, dynamic> item)? customWidgetBuilder;

  /// Ver GenericGridScreen.prefetchExtraFields/onAfterSave — repassados como
  /// estão até o grid (Map<String,dynamic> porque RelatedGridTab sempre usa o
  /// grid dinâmico genérico, nunca um T tipado).
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> item)?
      prefetchExtraFields;
  final Future<void> Function(
      Map<String, dynamic> formData, Map<String, dynamic>? item)? onAfterSave;

  const RelatedGridTab({
    required this.title,
    required this.icon,
    this.telaNome,
    this.extraParams,
    this.fieldOverrides,
    this.additionalFormData,
    this.transformFormData,
    this.deleteEndpointOverride,
    this.customWidget,
    this.customWidgetBuilder,
    this.prefetchExtraFields,
    this.onAfterSave,
  }) : assert(
          telaNome != null ||
              customWidget != null ||
              customWidgetBuilder != null,
          'RelatedGridTab requer telaNome, customWidget ou customWidgetBuilder',
        );
}

class GenericDetailFormScreen extends StatefulWidget {
  final Map<String, dynamic> item;
  final String telaNome;
  final SecurityCheck hasPermission;
  final List<FieldConfigWindows>? fieldOverrides;

  /// Explicit related grid tabs (e.g. roles, chamados).
  final List<RelatedGridTab>? relatedTabs;

  /// Callback após salvar o formulário principal.
  final Future<void> Function(
      Map<String, dynamic> formData, Map<String, dynamic>? item)? onAfterSave;

  /// Ajusta o payload enviado ao endpoint principal sem alterar o estado
  /// original repassado ao [onAfterSave].
  final Map<String, dynamic> Function(Map<String, dynamic> formData)?
      transformFormData;

  const GenericDetailFormScreen({
    super.key,
    required this.item,
    required this.telaNome,
    required this.hasPermission,
    this.fieldOverrides,
    this.relatedTabs,
    this.onAfterSave,
    this.transformFormData,
  });

  @override
  State<GenericDetailFormScreen> createState() =>
      _GenericDetailFormScreenState();
}

class _GenericDetailFormScreenState extends State<GenericDetailFormScreen>
    with SingleTickerProviderStateMixin {
  late Future<TelaConfig> _telaFuture;
  TabController? _tabController;

  final _formKey = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  final _dropdownValues = <String, dynamic>{};
  // Bug de producao: _save() sempre serializava todo campo dropdown como
  // {"id": valor} -- correto pra dropdown de RELACAO JPA (empresa, parceiro,
  // unidadeMedida: o backend espera um objeto com o id da entidade), mas
  // errado pra dropdown de valor ESCALAR usando uma lista de opcoes so pra
  // UI (ex.: "origem" Integer com lista fixa da SEFAZ, "unidadeComercial"
  // String com opcoes vindas de /api/unidade_medida mas persistida como
  // texto puro) -- backend rejeitava com 500 "Cannot deserialize... START_OBJECT".
  // Sinal usado pra distinguir os dois casos: dropdownValueField != 'id'
  // (explicitamente outro campo, ex. 'nome'/'value') indica valor escalar,
  // enviado cru; dropdownValueField == 'id' (ou omitido) mantem o
  // comportamento antigo de relacao JPA.
  final _dropdownValueFieldByName = <String, String>{};
  final _multiValues = <String, List<dynamic>>{};
  // Bug de producao: multiselect (ex.: Roles) abria "Selecione..." mesmo com
  // o registro tendo valores reais salvos, sempre que a lista de OPCOES
  // disponiveis (buscada de forma assincrona, ex. roles filtradas por
  // parceiro/empresa) nao trazia de volta um item ja selecionado (ex.: role
  // atribuida manualmente, fora do fallback "sempre disponivel" do backend).
  // O valor continuava certo em _multiValues (e era enviado certinho no
  // save), so o CHIP nunca aparecia porque _multiWidget so desenhava chips
  // pra selecionados que batessem com as opcoes carregadas. Este mapa guarda
  // o rotulo de cada selecionado a partir do PROPRIO dado do registro (ex.:
  // roles[].description), independente da lista de opcoes ter chegado ou
  // nao -- assim o chip aparece sempre que ha um valor real salvo.
  final _multiValueLabels = <String, Map<String, String>>{};
  final _checkboxValues = <String, bool>{};
  final _dropdownCache = <String, List<Map<String, dynamic>>>{};
  // Memoiza o Future em andamento por campo: evita recriar a requisição HTTP
  // (e reiniciar o FutureBuilder em ConnectionState.waiting) a cada rebuild
  // do formulário enquanto o fetch ainda não terminou.
  final _dropdownFutures = <String, Future<List<Map<String, dynamic>>>>{};

  bool _saving = false;
  bool _initialized = false;
  late Map<String, dynamic> _currentItem;
  int _relatedTabsReloadVersion = 0;

  Map<String, FieldConfigWindows> _overrideMap = {};
  Set<String> _suppressedFkFields = {};

  @override
  void initState() {
    super.initState();
    _currentItem = Map<String, dynamic>.from(widget.item);
    _buildOverrideMaps();
    _telaFuture = _loadTela();
  }

  void _buildOverrideMaps() {
    _overrideMap = {
      for (final o in (widget.fieldOverrides ?? [])) o.fieldName: o,
    };
    final dropdownNames = (widget.fieldOverrides ?? [])
        .where((o) => o.fieldType == FieldType.dropdown)
        .map((o) => o.fieldName.toLowerCase())
        .toSet();
    final suppressed = <String>{};
    for (final name in dropdownNames) {
      suppressed.add('${name}_id');
      suppressed.add('id_$name');
    }
    _suppressedFkFields = suppressed;
  }

  Future<TelaConfig> _loadTela() async {
    final svc = await _TelaServiceHelper.load(widget.telaNome);
    return svc;
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _tabController?.dispose();
    super.dispose();
  }

  void _initControllers(TelaConfig tela) {
    final item = _currentItem;
    for (final f in tela.fields) {
      final fn = f.fieldName;
      final fnL = fn.toLowerCase();
      if (fnL == 'dhcreatedat' ||
          fnL == 'dhupdatedat' ||
          fnL == 'dh_created_at' ||
          fnL == 'dh_updated_at') {
        continue;
      }
      // Campo com fieldOverride correspondente: renderizacao (_buildFormTab)
      // ja da precedencia ao override (vField/label/etc próprios da tela).
      // Deixa a inicializacao do valor tambem exclusivamente pro bloco de
      // overrides abaixo, senao o valor inicial pode ser calculado com o
      // dropdownValueField de tela.fields e nao bater com o vField usado
      // pelo widget (que vem do override) — o dropdown pareceria vazio de
      // novo mesmo com o item tendo um valor salvo.
      if (_overrideMap.containsKey(fn)) continue;
      final val = _valueFromItem(fn);
      if (f.fieldType == TelaFieldType.boolean) {
        _checkboxValues.putIfAbsent(fn, () => val == true);
      } else if (f.fieldType == TelaFieldType.dropdown) {
        // Bug: campo dropdown vindo de tela.fields nunca era inicializado
        // com o valor ja existente do registro — o dropdown sempre abria
        // vazio ao editar, mesmo quando o item ja tinha um valor salvo. Ao
        // salvar sem re-selecionar, o campo era omitido do payload (nao
        // enviado como vazio, simplesmente ausente), dando a impressao de
        // que "nao salvou"/"o valor sumiu".
        _initDropdownValue(fn, val, f.dropdownValueField);
        _dropdownValueFieldByName[fn] =
            f.dropdownValueField.isNotEmpty ? f.dropdownValueField : 'id';
      } else if (f.fieldType == TelaFieldType.multiselect) {
        // Mesmo bug do dropdown, para multiselect (ex.: Modulo Servicos,
        // Tipo Parceiros): chips sempre voltavam a "Selecione..." ao editar.
        _initMultiValue(fn, val, f.dropdownValueField, f.dropdownDisplayField);
      } else {
        _controllers.putIfAbsent(
            fn, () => TextEditingController(text: _getValue(val)));
      }
    }
    // Init overrides
    for (final o in (widget.fieldOverrides ?? [])) {
      if (!o.isInForm) continue;
      final fn = o.fieldName;
      final val = _valueFromItem(fn);
      if (o.fieldType == FieldType.dropdown) {
        _initDropdownValue(fn, val, o.dropdownValueField);
        _dropdownValueFieldByName[fn] =
            o.dropdownValueField.isNotEmpty ? o.dropdownValueField : 'id';
      } else if (o.fieldType == FieldType.multiselect) {
        _initMultiValue(fn, val, o.dropdownValueField, o.dropdownDisplayField);
      } else {
        _controllers.putIfAbsent(
            fn, () => TextEditingController(text: _getValue(val)));
      }
    }
  }

  /// Inicializa _dropdownValues[fn] a partir do valor ja existente do
  /// registro (widget.item), usando o mesmo campo (dropdownValueField) que
  /// o widget de dropdown usa pra resolver qual opcao esta pre-selecionada
  /// (_dropdownWidget) — evita divergencia entre o valor guardado no estado
  /// e o valor comparado nas opcoes da lista. Compartilhado entre o caminho
  /// de tela.fields e o de fieldOverrides (antes duplicado e com ordem de
  /// fallback inconsistente entre os dois).
  void _initDropdownValue(String fn, dynamic val, String dropdownValueField) {
    if (_dropdownValues.containsKey(fn)) return;
    final vf = dropdownValueField.isNotEmpty ? dropdownValueField : 'id';
    if (val is Map) {
      _dropdownValues[fn] = (val[vf] ?? val['id'])?.toString();
    } else if (val != null) {
      _dropdownValues[fn] = val.toString();
    }
  }

  dynamic _valueFromItem(String fieldName) {
    return resolveGenericDetailFormValue(_currentItem, fieldName);
  }

  Map<String, dynamic>? _resolveRelatedExtraParams(
      Map<String, dynamic>? extraParams) {
    if (extraParams == null) return null;
    final resolved = Map<String, dynamic>.from(extraParams);
    final id = _currentItem['id'];
    if (id != null) {
      if (resolved.containsKey('loginId')) resolved['loginId'] = id.toString();
      if (resolved.containsKey('usuarioAberturaId')) {
        resolved['usuarioAberturaId'] = id.toString();
      }
    }
    final empresaId = _extractId(_currentItem['empresa']) ??
        _currentItem['empresaId'] ??
        _currentItem['empId'];
    if (empresaId != null && resolved.containsKey('empresaId')) {
      resolved['empresaId'] = empresaId.toString();
    }
    final parceiroId = _extractId(_currentItem['parceiro']) ??
        _currentItem['parceiroId'] ??
        _currentItem['parcId'];
    if (parceiroId != null && resolved.containsKey('parceiroId')) {
      resolved['parceiroId'] = parceiroId.toString();
    }
    return resolved;
  }

  dynamic _extractId(dynamic value) {
    if (value is Map) return value['id'];
    return null;
  }

  void _resetFormState(Map<String, dynamic> item) {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    _dropdownValues.clear();
    _multiValues.clear();
    _multiValueLabels.clear();
    _checkboxValues.clear();
    _dropdownCache.clear();
    _dropdownFutures.clear();
    _currentItem = item;
    _relatedTabsReloadVersion++;
    _initialized = false;
  }

  /// Mesma logica de _initDropdownValue, para multiselect.
  ///
  /// [dropdownDisplayField] captura o rotulo de cada selecionado a partir do
  /// PROPRIO dado do registro (ex.: roles[].description), guardado em
  /// _multiValueLabels -- garante que o chip apareca mesmo se a lista de
  /// opcoes disponiveis (async, separada) nao trouxer esse item de volta.
  void _initMultiValue(String fn, dynamic val, String dropdownValueField,
      [String dropdownDisplayField = '']) {
    if (_multiValues.containsKey(fn)) return;
    final vf = dropdownValueField.isNotEmpty ? dropdownValueField : 'id';
    final df = dropdownDisplayField.isNotEmpty ? dropdownDisplayField : 'nome';
    if (val is List) {
      final labels = <String, String>{};
      _multiValues[fn] = val
          .map((e) {
            if (e is Map) {
              final id = (e[vf] ?? e['id'])?.toString();
              if (id != null) {
                final label = e[df]?.toString() ??
                    e['nome']?.toString() ??
                    e['description']?.toString();
                if (label != null && label.isNotEmpty) labels[id] = label;
              }
              return id;
            }
            return e?.toString();
          })
          .whereType<String>()
          .toList();
      if (labels.isNotEmpty) _multiValueLabels[fn] = labels;
    } else {
      _multiValues[fn] = [];
    }
  }

  String _getValue(dynamic val) {
    if (val == null) return '';
    if (val is Map)
      return val['nome']?.toString() ??
          val['name']?.toString() ??
          val['id']?.toString() ??
          '';
    return val.toString();
  }

  FieldType _telaType(TelaFieldType tft, String fieldName) {
    final fn = fieldName.toLowerCase();
    if (fn == 'senha' || fn == 'password') return FieldType.password;
    if (fn == 'email') return FieldType.email;
    if (fn == 'cpf') return FieldType.cpf;
    if (fn == 'cnpj') return FieldType.cnpj;
    if (fn == 'cpfcnpj' || fn == 'cpf_cnpj') return FieldType.text;
    if (fn == 'telefone' || fn == 'celular') return FieldType.phone;
    // Bug: TelaFieldType (backend) e FieldType (widget) tem "cpfCnpj"/"cep"
    // extras a partir do indice 12 que nao existem em FieldType — mapear por
    // indice numerico desalinha os dois enums a partir dali (ex.: currency
    // do backend virava percentage no widget). Mapeia por NOME, robusto a
    // qualquer enum ganhar/perder valores no futuro.
    switch (tft) {
      case TelaFieldType.text:
        return FieldType.text;
      case TelaFieldType.number:
        return FieldType.number;
      case TelaFieldType.email:
        return FieldType.email;
      case TelaFieldType.date:
        return FieldType.date;
      case TelaFieldType.multiline:
        return FieldType.multiline;
      case TelaFieldType.dropdown:
        return FieldType.dropdown;
      case TelaFieldType.boolean:
        return FieldType.boolean;
      case TelaFieldType.file:
        return FieldType.file;
      case TelaFieldType.password:
        return FieldType.password;
      case TelaFieldType.phone:
        return FieldType.phone;
      case TelaFieldType.cpf:
        return FieldType.cpf;
      case TelaFieldType.cnpj:
        return FieldType.cnpj;
      case TelaFieldType.cpfCnpj:
      case TelaFieldType.cep:
        return FieldType.text;
      case TelaFieldType.currency:
        return FieldType.currency;
      case TelaFieldType.percentage:
        return FieldType.percentage;
      case TelaFieldType.url:
        return FieldType.url;
      case TelaFieldType.multiselect:
        return FieldType.multiselect;
    }
  }

  Future<void> _save(TelaConfig tela) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{};
      final id = _currentItem['id'];
      if (id != null) body['id'] = id;

      for (final entry in _controllers.entries) {
        body[entry.key] = entry.value.text;
      }
      for (final entry in _checkboxValues.entries) {
        body[entry.key] = entry.value;
      }
      for (final entry in _dropdownValues.entries) {
        if (entry.value == null) continue;
        final vf = _dropdownValueFieldByName[entry.key] ?? 'id';
        body[entry.key] = vf == 'id' ? {'id': entry.value} : entry.value;
      }
      for (final entry in _multiValues.entries) {
        body[entry.key] = entry.value.map((v) => {'id': v}).toList();
      }

      final requestBody = widget.transformFormData != null
          ? widget.transformFormData!(Map<String, dynamic>.from(body))
          : body;

      final isCreate = id == null;
      final endpoint = isCreate
          ? tela.createEndpoint
          : tela.updateEndpoint.replaceAll(':id', id?.toString() ?? '');
      final url =
          endpoint.startsWith('http') ? endpoint : ApiLinks.baseUrl + endpoint;
      final resp = isCreate
          ? await NetworkCaller().postRequest(url, requestBody)
          : await NetworkCaller().putRequest(url, requestBody);
      if (!mounted) return;
      if (resp.isSuccess) {
        final msg = isCreate ? 'Criado com sucesso' : 'Salvo com sucesso';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(msg, style: const TextStyle(color: Colors.white)),
              backgroundColor: GridColors.success),
        );
        if (widget.onAfterSave != null) {
          await widget.onAfterSave!(body, _currentItem);
        }
        if (resp.body is Map) {
          setState(() {
            _resetFormState(Map<String, dynamic>.from(resp.body as Map));
          });
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao salvar: ${resp.statusCode}',
                  style: const TextStyle(color: Colors.white)),
              backgroundColor: GridColors.error),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Erro: $e', style: const TextStyle(color: Colors.white)),
              backgroundColor: GridColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<_AutoTab> _detectAutoTabs(TelaConfig tela) {
    final tabs = <_AutoTab>[];
    // Apenas relatedGrids do backend — sem auto-detect de listas do JSON
    // (evita duplicação com explicitTabs)
    for (final rg in tela.relatedGrids) {
      if (rg.gridTelaNome.isNotEmpty) {
        tabs.add(_AutoTab(
          title: rg.title,
          icon: _iconFromName(rg.icon),
          gridTelaNome: rg.gridTelaNome,
        ));
      }
    }
    return tabs;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TelaConfig>(
      future: _telaFuture,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError || !snap.hasData) {
          return Scaffold(body: Center(child: Text('Erro: ${snap.error}')));
        }
        final tela = snap.data!;
        if (!_initialized) {
          _initControllers(tela);
          _initialized = true;
        }

        // Explicit relatedTabs from widget (highest priority)
        final explicitTabs = (widget.relatedTabs ?? []).map((rt) {
          return _AutoTab(
            title: rt.title,
            icon: rt.icon,
            gridTelaNome: rt.telaNome,
            extraParams: _resolveRelatedExtraParams(rt.extraParams),
            fieldOverrides: rt.fieldOverrides,
            additionalFormData: rt.additionalFormData,
            transformFormData: rt.transformFormData,
            deleteEndpointOverride: rt.deleteEndpointOverride,
            customWidget: rt.customWidget,
            customWidgetBuilder: rt.customWidgetBuilder,
            prefetchExtraFields: rt.prefetchExtraFields,
            onAfterSave: rt.onAfterSave,
          );
        }).toList();

        // Se há explicitTabs, usa APENAS eles — sem auto-detect do backend para evitar duplicação
        final autoTabs =
            explicitTabs.isNotEmpty ? <_AutoTab>[] : _detectAutoTabs(tela);

        final allTabs = [...explicitTabs, ...autoTabs];
        final tabCount = 1 + allTabs.length;

        if (_tabController == null || _tabController!.length != tabCount) {
          _tabController?.dispose();
          _tabController = TabController(length: tabCount, vsync: this);
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF6F8FB),
          appBar: AppBar(
            title: Text(tela.titulo),
            backgroundColor: GridColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Column(
            children: [
              if (tabCount > 1) _buildTopTabs(allTabs),
              Expanded(
                child: tabCount > 1
                    ? TabBarView(
                        controller: _tabController,
                        children: [
                          _buildFormTab(tela),
                          for (var i = 0; i < allTabs.length; i++)
                            _LazyTab(
                              key: ValueKey(
                                  'related-tab-$i-$_relatedTabsReloadVersion'),
                              controller: _tabController!,
                              tabIndex: i + 1,
                              builder: () => _buildAutoTab(allTabs[i]),
                            ),
                        ],
                      )
                    : _buildFormTab(tela),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopTabs(List<_AutoTab> tabs) {
    return Container(
      width: double.infinity,
      color: GridColors.card,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: GridColors.primaryLight,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: GridColors.divider),
          ),
          labelColor: GridColors.primary,
          unselectedLabelColor: GridColors.textSecondary,
          labelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          unselectedLabelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          labelPadding: const EdgeInsets.symmetric(horizontal: 10),
          tabs: [
            const Tab(
              height: 56,
              icon: Icon(Icons.edit_note, size: 16),
              text: 'Cadastro',
            ),
            ...tabs.map(
              (t) => Tab(
                height: 56,
                icon: Icon(t.icon, size: 16),
                text: t.title,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Monta o estado atual do formulário (checkbox, dropdown, multiselect,
  /// texto) para avaliação de `visibleWhen`.
  Map<String, dynamic> _estadoFormularioAtual() {
    final estado = <String, dynamic>{};
    estado.addAll(_checkboxValues);
    estado.addAll(_dropdownValues);
    estado.addAll(_multiValues);
    for (final entry in _controllers.entries) {
      estado[entry.key] = entry.value.text;
    }
    return estado;
  }

  Widget _buildFormTab(TelaConfig tela) {
    final effectiveFields = <_EF>[];
    final inserted = <String>{};

    // Pré-computa todos os nomes de dropdown (overrides + backend) para suprimir IDs brutos
    final allDropdownNames = <String>{
      for (final o in (widget.fieldOverrides ?? []))
        if (o.fieldType == FieldType.dropdown ||
            o.fieldType == FieldType.multiselect)
          o.fieldName.toLowerCase(),
      for (final f in tela.fields)
        if (f.dropdownEndpoint != null && f.dropdownEndpoint!.isNotEmpty)
          f.fieldName.toLowerCase(),
    };

    for (final f in tela.fields) {
      final fnL = f.fieldName.toLowerCase();
      if (fnL == 'dh_created_at' ||
          fnL == 'dh_updated_at' ||
          fnL == 'dhcreatedat' ||
          fnL == 'dhupdatedat') {
        continue;
      }
      if (fnL == 'id') continue;

      // 1. Override explícito -- tem PRIORIDADE TOTAL sobre a config do
      // backend, inclusive pra ESCONDER um campo que o backend marca
      // isInForm=true.
      //
      // Bug de producao (sistemico, reproduzido em Login > Cadastro): um
      // campo "fantasma"/redundante que o backend expunha como isInForm=true
      // (ex.: "setores" -- texto solto sem uso real, com a gestao de
      // verdade acontecendo numa aba dedicada) continuava aparecendo no
      // formulario MESMO com um override client-side declarando
      // isInForm:false -- porque o gate `if (!f.isInForm) continue` logo
      // acima so olhava o isInForm DO BACKEND, nunca o do override, e so
      // depois disso o override era consultado. Qualquer tela que usasse
      // fieldOverrides pra esconder um campo ja visivel no backend tinha o
      // mesmo problema (afeta o componente inteiro, nao so uma tela).
      if (_overrideMap.containsKey(f.fieldName)) {
        if (!inserted.contains(f.fieldName)) {
          final override = _overrideMap[f.fieldName]!;
          if (resolveFieldVisibility(
              backendIsInForm: f.isInForm, override: override)) {
            effectiveFields.add(_EF.fromOverride(override));
          }
          inserted.add(f.fieldName);
        }
        continue;
      }

      if (!resolveFieldVisibility(backendIsInForm: f.isInForm)) continue;

      // 2. Campo FK de um override (ex: empresa_id → override 'empresa')
      if (_suppressedFkFields.contains(fnL)) {
        final base = fnL.endsWith('_id')
            ? fnL.substring(0, fnL.length - 3)
            : fnL.substring(3);
        if (_overrideMap.containsKey(base) && !inserted.contains(base)) {
          effectiveFields.add(_EF.fromOverride(_overrideMap[base]!));
          inserted.add(base);
        }
        continue;
      }

      // 3. Suprimir IDs brutos quando já existe dropdown correspondente
      if (_isRawIdField(fnL, allDropdownNames)) continue;

      // 4. Skip list fields (handled as tabs)
      final val = _valueFromItem(f.fieldName);
      if (val is List) continue;

      // 5. Auto-dropdown: campo com dropdownEndpoint do backend
      if (f.dropdownEndpoint != null &&
          f.dropdownEndpoint!.isNotEmpty &&
          !inserted.contains(f.fieldName)) {
        final isMulti =
            f.multiSelect || f.fieldType == TelaFieldType.multiselect;
        effectiveFields.add(_EF(
          fieldName: f.fieldName,
          label: f.label,
          type: isMulti ? FieldType.multiselect : FieldType.dropdown,
          isRequired: f.isRequired,
          // Bug: quando o backend configurava explicitamente 'value'/'label'
          // (dropdowns baseados em enum, ex. /api/enums/Ambiente), o codigo
          // tratava isso como "nao customizado" e trocava para 'id'/'nome' —
          // que nao existem nesses objetos, entao o dropdown caia no
          // fallback o[vf].toString() e mostrava o id numerico bruto da
          // linha da tabela enum_values (ex. "651") em vez do valor do enum
          // (ex. "HOMOLOGACAO"/"Homologação"). Usa a config do backend
          // diretamente sempre que ela vier preenchida.
          vField: f.dropdownValueField.isNotEmpty ? f.dropdownValueField : 'id',
          dField: f.dropdownDisplayField.isNotEmpty
              ? f.dropdownDisplayField
              : 'nome',
          dropdownEndpoint: f.dropdownEndpoint,
        ));
        inserted.add(f.fieldName);
        continue;
      }

      effectiveFields
          .add(_EF.fromTelaField(f, _telaType(f.fieldType, f.fieldName)));
      inserted.add(f.fieldName);
    }

    // Overrides não inseridos
    for (final o in (widget.fieldOverrides ?? [])) {
      if (!inserted.contains(o.fieldName)) {
        if (resolveFieldVisibility(backendIsInForm: false, override: o)) {
          effectiveFields.add(_EF.fromOverride(o));
        }
        inserted.add(o.fieldName);
      }
    }

    // Aplica visibilidade condicional (visibleWhen) com base no estado atual
    final estadoFormulario = _estadoFormularioAtual();
    effectiveFields.removeWhere(
        (f) => !avaliarVisibleWhen(f.visibleWhen, estadoFormulario));

    return Form(
      key: _formKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            primary: false,
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Container(
                  decoration: BoxDecoration(
                    color: GridColors.card,
                    border: Border.all(color: GridColors.divider),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: GridColors.primaryLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.edit_note,
                                color: GridColors.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Cadastro',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: GridColors.secondary,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Edite os dados principais do registro selecionado.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: GridColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: GridColors.divider),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: LayoutBuilder(
                          builder: (context, formConstraints) {
                            final maxWidth = formConstraints.maxWidth;
                            final columnCount = maxWidth >= 1100
                                ? 3
                                : maxWidth >= 720
                                    ? 2
                                    : 1;
                            final gap = columnCount == 1 ? 0.0 : 12.0;
                            final fieldWidth =
                                (maxWidth - ((columnCount - 1) * gap)) /
                                    columnCount;

                            return Wrap(
                              spacing: gap,
                              runSpacing: 0,
                              children: [
                                for (final field in effectiveFields)
                                  SizedBox(
                                    width: _isWideField(field)
                                        ? maxWidth
                                        : fieldWidth,
                                    child: _buildField(field),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                      const Divider(height: 1, color: GridColors.divider),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: constraints.maxWidth < 560
                                ? double.infinity
                                : 220,
                            child: ElevatedButton.icon(
                              onPressed: _saving ? null : () => _save(tela),
                              icon: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: Text(
                                _saving ? 'Salvando...' : 'Salvar alterações',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: GridColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  bool _isWideField(_EF field) {
    final name = field.fieldName.toLowerCase();
    return field.type == FieldType.multiline ||
        name.contains('observacao') ||
        name.contains('descricao') ||
        name.contains('complemento');
  }

  Widget _buildAutoTab(_AutoTab tab) {
    if (tab.customWidgetBuilder != null) {
      return tab.customWidgetBuilder!(_currentItem);
    }
    // Widget customizado (ex: CertificadoEmpresaScreen)
    if (tab.customWidget != null) {
      return tab.customWidget!;
    }
    if (tab.gridTelaNome != null) {
      final isMobileWidth = MediaQuery.of(context).size.width < 720;
      // Quando há deleteEndpointOverride (ex.: desvincular role do login) usa
      // sempre o grid desktop, pois só ele aplica o override — evita que o grid
      // mobile faça o delete destrutivo padrão (apagar a entidade global).
      if (isMobileWidth &&
          tab.fieldOverrides == null &&
          tab.deleteEndpointOverride == null &&
          tab.prefetchExtraFields == null &&
          tab.onAfterSave == null) {
        return const Center(child: Text('Custom grid removed'));
      }
      return const Center(child: Text('Custom grid removed'));
    }
    final rows = tab.listData ?? [];
    if (rows.isEmpty) {
      return const Center(
          child: Text('Nenhum item', style: TextStyle(color: Colors.grey)));
    }
    final cols = rows.first.keys.where((k) {
      final v = rows.first[k];
      return v is! Map && v is! List;
    }).toList();
    return SingleChildScrollView(
      primary: false,
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        primary: false,
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(GridColors.primary),
          headingTextStyle:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          columns: cols
              .map((c) => DataColumn(label: Text(_toTitleCase(c))))
              .toList(),
          rows: rows
              .map((row) => DataRow(
                    cells: cols
                        .map((c) => DataCell(
                              Text(row[c]?.toString() ?? '',
                                  style: const TextStyle(fontSize: 13)),
                            ))
                        .toList(),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildField(_EF ef) {
    switch (ef.type) {
      case FieldType.boolean:
        return _buildCheckbox(ef);
      case FieldType.dropdown:
        return _buildDropdown(ef);
      case FieldType.multiselect:
        return _buildMultiSelect(ef);
      case FieldType.file:
        return _buildFileField(ef);
      case FieldType.date:
        return _buildDate(ef);
      case FieldType.password:
        return _buildPassword(ef);
      case FieldType.email:
        return _buildText(ef,
            keyboardType: TextInputType.emailAddress,
            prefix: const Icon(Icons.email_outlined));
      case FieldType.phone:
        return _buildText(ef,
            keyboardType: TextInputType.phone,
            prefix: const Icon(Icons.phone_outlined));
      case FieldType.cpf:
      case FieldType.cnpj:
        return _buildText(ef,
            keyboardType: TextInputType.number,
            formatters: [FilteringTextInputFormatter.digitsOnly]);
      case FieldType.number:
        return _buildText(ef,
            keyboardType: TextInputType.number,
            formatters: [FilteringTextInputFormatter.digitsOnly]);
      case FieldType.currency:
        return _buildText(ef,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            prefix: const Icon(Icons.attach_money));
      case FieldType.multiline:
        return _buildText(ef,
            maxLines: 4, keyboardType: TextInputType.multiline);
      default:
        return _buildText(ef);
    }
  }

  InputDecoration _dec(String label,
          {Widget? prefix, Widget? suffix, bool req = false}) =>
      InputDecoration(
        labelText: label + (req ? ' *' : ''),
        filled: true,
        fillColor: const Color(0xFFFBFCFE),
        labelStyle: const TextStyle(color: GridColors.textSecondary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: GridColors.divider)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide:
                const BorderSide(color: GridColors.primary, width: 1.5)),
        prefixIcon: prefix,
        suffixIcon: suffix,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
      );

  Widget _buildText(_EF ef,
      {TextInputType? keyboardType,
      List<TextInputFormatter>? formatters,
      Widget? prefix,
      int? maxLines}) {
    _controllers.putIfAbsent(ef.fieldName, () => TextEditingController());
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: _controllers[ef.fieldName],
        enabled: ef.enabled,
        keyboardType: keyboardType,
        inputFormatters: formatters,
        maxLines: maxLines ?? 1,
        decoration: _dec(ef.label, prefix: prefix, req: ef.isRequired),
        validator: ef.isRequired
            ? (v) => (v == null || v.trim().isEmpty)
                ? '${ef.label} é obrigatório'
                : null
            : null,
      ),
    );
  }

  // Bug de producao: o campo "Foto" da tela de Cadastro do Login (e de
  // qualquer outra tela que usasse fieldType: FieldType.file no formulario
  // de DETALHE) sempre caia no `default: _buildText(ef)` -- este widget
  // generico nunca teve implementacao pra FieldType.file (so o dialogo de
  // criar/editar do GRID tinha, em generic_grid_windows_screen.dart). O
  // campo aparecia como texto puro mostrando a representacao bruta do valor
  // salvo (ex.: "{id: 0, nome: }"), sem nenhuma forma de selecionar uma foto
  // de verdade.
  //
  // Login.foto (backend) e uma coluna String simples -- sem endpoint de
  // upload multipart dedicado. Por isso a foto escolhida e convertida pra
  // data URI base64 e enviada como texto normal no mesmo PUT/POST JSON que
  // ja existe (via _controllers, igual qualquer outro campo de texto), sem
  // precisar de nenhuma mudanca no backend.
  final _filePickedNames = <String, String>{};

  Widget _buildFileField(_EF ef) {
    _controllers.putIfAbsent(ef.fieldName, () => TextEditingController());
    final valorAtual = _controllers[ef.fieldName]!.text;
    final nomeEscolhido = _filePickedNames[ef.fieldName];
    final temImagemValida = valorAtual.startsWith('data:image') ||
        valorAtual.startsWith('http://') ||
        valorAtual.startsWith('https://');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ef.label + (ef.isRequired ? ' *' : ''),
              style: const TextStyle(
                  color: GridColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFFBFCFE),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: GridColors.divider),
                ),
                clipBehavior: Clip.antiAlias,
                child: temImagemValida
                    ? (valorAtual.startsWith('data:image')
                        ? Image.memory(
                            base64Decode(valorAtual.split(',').last),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.person,
                                color: GridColors.textSecondary),
                          )
                        : Image.network(
                            valorAtual,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.person,
                                color: GridColors.textSecondary),
                          ))
                    : const Icon(Icons.person,
                        color: GridColors.textSecondary, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ElevatedButton.icon(
                      onPressed: ef.enabled
                          ? () => _selecionarFoto(ef.fieldName, ef.fileConfig)
                          : null,
                      icon: const Icon(Icons.photo_camera, size: 18),
                      label: const Text('Selecionar Foto'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: GridColors.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    if (nomeEscolhido != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(nomeEscolhido,
                            style: const TextStyle(
                                fontSize: 12, color: GridColors.textSecondary)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _selecionarFoto(String fieldName, FileConfig? fileConfig) async {
    final config = fileConfig ?? const FileConfig();
    try {
      final resultado = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: config.allowedExtensions.isNotEmpty
            ? config.allowedExtensions
            : const ['jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );
      if (resultado == null || resultado.files.isEmpty) return;
      final arquivo = resultado.files.first;

      if (config.maxFileSize > 0 &&
          (arquivo.bytes?.length ?? arquivo.size) > config.maxFileSize) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Arquivo maior que o limite permitido (${(config.maxFileSize / (1024 * 1024)).toStringAsFixed(1)} MB).'),
          backgroundColor: GridColors.error,
        ));
        return;
      }

      // Reaproveita o mesmo helper ja usado no dialogo de criar/editar do
      // grid generico (generic_grid_windows_screen.dart) -- ja trata Web
      // (bytes) e desktop/mobile (path via dart:io, guardado por !kIsWeb).
      final dataUri = await platformFileToDataUri(arquivo);
      if (dataUri == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível ler o arquivo selecionado.'),
          backgroundColor: GridColors.error,
        ));
        return;
      }

      setState(() {
        _controllers.putIfAbsent(fieldName, () => TextEditingController());
        _controllers[fieldName]!.text = dataUri;
        _filePickedNames[fieldName] = arquivo.name;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro ao selecionar foto: $e'),
        backgroundColor: GridColors.error,
      ));
    }
  }

  Widget _buildPassword(_EF ef) {
    _controllers.putIfAbsent(ef.fieldName, () => TextEditingController());
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _PasswordField(
          controller: _controllers[ef.fieldName]!,
          label: ef.label,
          isRequired: ef.isRequired),
    );
  }

  Widget _buildDate(_EF ef) {
    _controllers.putIfAbsent(ef.fieldName, () => TextEditingController());
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: _controllers[ef.fieldName],
        readOnly: true,
        enabled: ef.enabled,
        decoration: _dec(ef.label,
            prefix: const Icon(Icons.calendar_today_outlined),
            suffix: const Icon(Icons.arrow_drop_down),
            req: ef.isRequired),
        onTap: ef.enabled
            ? () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.tryParse(
                          _controllers[ef.fieldName]?.text ?? '') ??
                      DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  _controllers[ef.fieldName]?.text =
                      '${picked.year.toString().padLeft(4, '0')}-'
                      '${picked.month.toString().padLeft(2, '0')}-'
                      '${picked.day.toString().padLeft(2, '0')}';
                }
              }
            : null,
      ),
    );
  }

  Widget _buildCheckbox(_EF ef) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFBFCFE),
            border: Border.all(color: GridColors.divider),
            borderRadius: BorderRadius.circular(6),
          ),
          child: CheckboxListTile(
            title: Text(ef.label),
            value: _checkboxValues[ef.fieldName] ?? false,
            activeColor: GridColors.primary,
            onChanged: ef.enabled
                ? (v) =>
                    setState(() => _checkboxValues[ef.fieldName] = v ?? false)
                : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),
      );

  Widget _buildDropdown(_EF ef) {
    if (_dropdownCache.containsKey(ef.fieldName)) {
      return _dropdownWidget(ef, _dropdownCache[ef.fieldName]!);
    }
    final future = _dropdownFutures.putIfAbsent(
      ef.fieldName,
      () => ef.dropdownFutureBuilder != null
          ? ef.dropdownFutureBuilder!()
          : ef.dropdownEndpoint != null
              ? _loadEndpoint(ef.dropdownEndpoint!)
              : Future.value(ef.dropdownOptions ?? <Map<String, dynamic>>[]),
    );
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: InputDecorator(
                  decoration: _dec(ef.label),
                  child: const LinearProgressIndicator()));
        }
        final opts = snap.data ?? [];
        _dropdownCache[ef.fieldName] = opts;
        return _dropdownWidget(ef, opts);
      },
    );
  }

  Widget _dropdownWidget(_EF ef, List<Map<String, dynamic>> options) {
    final vf = ef.vField;
    final df = ef.dField;
    final seen = <dynamic>{};
    final unique = options.where((o) {
      final k = o[vf];
      return k != null && seen.add(k);
    }).toList();
    dynamic current = _dropdownValues[ef.fieldName];
    if (!unique.any((o) => o[vf]?.toString() == current?.toString()))
      current = null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<dynamic>(
        initialValue: current,
        decoration: _dec(ef.label, req: ef.isRequired),
        isExpanded: true,
        menuMaxHeight: 300,
        items: unique
            .map((o) => DropdownMenuItem(
                  value: o[vf]?.toString(),
                  child: Text(o[df]?.toString() ?? o[vf].toString(),
                      overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: ef.enabled
            ? (val) => setState(() => _dropdownValues[ef.fieldName] = val)
            : null,
        validator: ef.isRequired
            ? (v) => v == null ? '${ef.label} é obrigatório' : null
            : null,
      ),
    );
  }

  Widget _buildMultiSelect(_EF ef) {
    final cacheKey = '${ef.fieldName}_ms';
    if (_dropdownCache.containsKey(cacheKey)) {
      return _multiWidget(ef, _dropdownCache[cacheKey]!);
    }
    final future = _dropdownFutures.putIfAbsent(
      cacheKey,
      () => ef.dropdownFutureBuilder != null
          ? ef.dropdownFutureBuilder!()
          : ef.dropdownEndpoint != null
              ? _loadEndpoint(ef.dropdownEndpoint!)
              : Future.value(ef.dropdownOptions ?? <Map<String, dynamic>>[]),
    );
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: InputDecorator(
                  decoration: _dec(ef.label),
                  child: const LinearProgressIndicator()));
        }
        final opts = snap.data ?? [];
        _dropdownCache[cacheKey] = opts;
        return _multiWidget(ef, opts);
      },
    );
  }

  Widget _multiWidget(_EF ef, List<Map<String, dynamic>> options) {
    final vf = ef.vField;
    final df = ef.dField;
    final selected = _multiValues[ef.fieldName] ?? [];
    final rotulosSalvos = _multiValueLabels[ef.fieldName] ?? const {};

    Widget chip(String texto) => Container(
          margin: const EdgeInsets.only(right: 4, bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
              color: GridColors.secondary,
              borderRadius: BorderRadius.circular(12)),
          child: Text(texto,
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        );

    // Bug de producao: um valor ja selecionado que a lista de opcoes
    // (assincrona, ex.: roles filtradas por parceiro/empresa) NAO devolve --
    // ex. role atribuida manualmente, fora do fallback "sempre disponivel"
    // do backend -- nunca virava chip, mesmo com o dado real salvo em
    // _multiValues. resolveMultiSelectChipLabel usa o rotulo real da opcao
    // quando ela veio carregada; senao cai pro rotulo capturado do proprio
    // registro na inicializacao (_multiValueLabels); so cai pro id bruto se
    // nem isso existir (situacao rara, sem nenhum dado de rotulo).
    final chips = selected
        .map((s) => chip(resolveMultiSelectChipLabel(
              selectedId: s.toString(),
              loadedOptions: options,
              valueField: vf,
              displayField: df,
              savedLabels: rotulosSalvos,
            )))
        .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: ef.enabled ? () => _openMultiDialog(ef, options, vf, df) : null,
        borderRadius: BorderRadius.circular(8),
        child: InputDecorator(
          decoration: _dec(ef.label,
              suffix: const Icon(Icons.arrow_drop_down), req: ef.isRequired),
          child: chips.isEmpty
              ? Text('Selecione...',
                  style: TextStyle(color: Colors.grey.shade500))
              : Wrap(spacing: 4, runSpacing: 4, children: chips),
        ),
      ),
    );
  }

  Future<void> _openMultiDialog(
      _EF ef, List<Map<String, dynamic>> options, String vf, String df) async {
    final result = await showDialog<List<dynamic>>(
      context: context,
      builder: (ctx) => _MultiSelectDialog(
        title: ef.label,
        options: options,
        valueField: vf,
        displayField: df,
        initialSelected: List.from(_multiValues[ef.fieldName] ?? []),
      ),
    );
    if (result != null) setState(() => _multiValues[ef.fieldName] = result);
  }

  Future<List<Map<String, dynamic>>> _loadEndpoint(String endpoint) async {
    final url =
        endpoint.startsWith('http') ? endpoint : ApiLinks.baseUrl + endpoint;
    final resp = await NetworkCaller().getRequest(url);
    if (!resp.isSuccess || resp.body == null) return [];
    dynamic raw = resp.body;
    List lista = [];
    if (raw is List) {
      lista = raw;
    } else if (raw is Map) {
      final d = raw['data'] ?? raw['dados'] ?? raw['items'] ?? raw['content'];
      if (d is List) {
        lista = d;
      } else if (d is Map && d['dados'] is List) {
        lista = d['dados'];
      }
    }
    return lista
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  IconData _iconFromName(String? name) {
    switch (name) {
      case 'people':
        return Icons.people;
      case 'support_agent':
        return Icons.support_agent;
      case 'account_balance':
        return Icons.account_balance;
      case 'shopping_cart':
        return Icons.shopping_cart;
      case 'inventory':
        return Icons.inventory;
      case 'receipt':
        return Icons.receipt;
      case 'description':
        return Icons.description;
      case 'person':
        return Icons.person;
      case 'location_on':
        return Icons.location_on;
      case 'security':
        return Icons.security;
      case 'roles':
        return Icons.security;
      case 'chamados':
        return Icons.support_agent;
      default:
        return Icons.list;
    }
  }

  String _toTitleCase(String text) => text
      .split(RegExp(r'[_\s]+'))
      .map((w) =>
          w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');

  /// Suprime campos que são IDs brutos de FK quando já existe dropdown correspondente
  static bool _isRawIdField(String fnLower, Set<String> allDropdownNames) {
    const alwaysHide = {
      'file_id',
      'foto_id',
      'foto_perfil_id',
      'academia_id',
      'cod_personal',
      'cod_produtor',
      'parent_id',
      'user_id',
      'audit_id',
    };
    if (alwaysHide.contains(fnLower)) return true;

    final isIdPattern = (fnLower.endsWith('_id') && fnLower != 'id') ||
        fnLower.startsWith('id_') ||
        fnLower.startsWith('cod_');
    if (!isIdPattern) return false;

    String base;
    if (fnLower.endsWith('_id')) {
      base = fnLower.substring(0, fnLower.length - 3);
    } else if (fnLower.startsWith('id_'))
      base = fnLower.substring(3);
    else
      base = fnLower.substring(4); // cod_

    if (base.length < 2) return false;

    for (final name in allDropdownNames) {
      if (name == base || name.contains(base) || base.contains(name))
        return true;
    }
    return false;
  }
}

// ---------------------------------------------------------------
// Helper to load TelaConfig — uses SharedPreferences cache (same as DynamicGridWindowsScreen)
// ---------------------------------------------------------------
class _TelaServiceHelper {
  static Future<TelaConfig> load(String telaNome) async {
    final tela =
        await TelaService(networkCaller: NetworkCaller()).getTelaFromCache(
      telaNome,
      empId: TenantContext.empresaId,
      clienteId: null,
    );
    if (tela == null) throw Exception('Tela $telaNome não encontrada no cache');
    return tela;
  }
}

// ---------------------------------------------------------------
// Lazy tab — só constrói (e dispara fetch) o conteúdo da aba quando ela é
// selecionada pela primeira vez. Evita que TODAS as abas relacionadas
// (Parceiros, Logins, Contas a Pagar, etc.) disparem requisições HTTP ao
// montar a tela de detalhe — TabBarView constrói todos os children de
// imediato, então sem essa proteção cada DynamicGridWindowsScreen chamaria
// initState/fetch simultaneamente, causando lentidão e loaders concorrentes.
// Uma vez construída, a aba permanece viva (AutomaticKeepAlive) para não
// recarregar ao trocar de aba.
// ---------------------------------------------------------------
class _LazyTab extends StatefulWidget {
  final TabController controller;
  final int tabIndex;
  final WidgetBuilder0 builder;

  const _LazyTab({
    super.key,
    required this.controller,
    required this.tabIndex,
    required this.builder,
  });

  @override
  State<_LazyTab> createState() => _LazyTabState();
}

typedef WidgetBuilder0 = Widget Function();

class _LazyTabState extends State<_LazyTab> with AutomaticKeepAliveClientMixin {
  bool _activated = false;

  @override
  bool get wantKeepAlive => _activated;

  @override
  void initState() {
    super.initState();
    _checkActive();
    widget.controller.addListener(_onTabChanged);
  }

  @override
  void didUpdateWidget(covariant _LazyTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTabChanged);
      widget.controller.addListener(_onTabChanged);
      _checkActive();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() => _checkActive();

  void _checkActive() {
    final isActive = widget.controller.index == widget.tabIndex;
    if (isActive && !_activated) {
      setState(() => _activated = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_activated) {
      return const Center(child: CircularProgressIndicator());
    }
    return widget.builder();
  }
}

// ---------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------
class _AutoTab {
  final String title;
  final IconData icon;
  final List<Map<String, dynamic>>? listData;
  final String? gridTelaNome;
  final Map<String, dynamic>? extraParams;
  final List<FieldConfigWindows>? fieldOverrides;
  final Map<String, dynamic>? additionalFormData;
  final Map<String, dynamic> Function(Map<String, dynamic> formData)?
      transformFormData;
  final String? deleteEndpointOverride;
  final Widget? customWidget;
  final Widget Function(Map<String, dynamic> item)? customWidgetBuilder;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> item)?
      prefetchExtraFields;
  final Future<void> Function(
      Map<String, dynamic> formData, Map<String, dynamic>? item)? onAfterSave;
  _AutoTab(
      {required this.title,
      required this.icon,
      this.listData,
      this.gridTelaNome,
      this.extraParams,
      this.fieldOverrides,
      this.additionalFormData,
      this.transformFormData,
      this.deleteEndpointOverride,
      this.customWidget,
      this.customWidgetBuilder,
      this.prefetchExtraFields,
      this.onAfterSave});
}

class _EF {
  final String fieldName;
  final String label;
  final FieldType type;
  final bool isRequired;
  final bool enabled;
  final String vField;
  final String dField;
  final String? dropdownEndpoint;
  final Future<List<Map<String, dynamic>>> Function()? dropdownFutureBuilder;
  final List<Map<String, dynamic>>? dropdownOptions;
  final String? visibleWhen;
  final FileConfig? fileConfig;

  _EF(
      {required this.fieldName,
      required this.label,
      required this.type,
      this.isRequired = false,
      this.enabled = true,
      this.vField = 'id',
      this.dField = 'nome',
      this.dropdownEndpoint,
      this.dropdownFutureBuilder,
      this.dropdownOptions,
      this.visibleWhen,
      this.fileConfig});

  factory _EF.fromTelaField(TelaField f, FieldType type) => _EF(
        fieldName: f.fieldName,
        label: f.label,
        type: type,
        isRequired: f.isRequired,
        enabled: f.enabled,
        vField: f.dropdownValueField.isNotEmpty ? f.dropdownValueField : 'id',
        dField:
            f.dropdownDisplayField.isNotEmpty ? f.dropdownDisplayField : 'nome',
        dropdownEndpoint: f.dropdownEndpoint,
        dropdownOptions: f.dropdownOptions
            .map((e) => <String, dynamic>{
                  'id': e.optionValue,
                  'nome': e.optionLabel ?? e.optionValue.toString()
                })
            .toList(),
        visibleWhen: f.visibleWhen,
      );

  factory _EF.fromOverride(FieldConfigWindows o) => _EF(
        fieldName: o.fieldName,
        label: o.label,
        type: o.fieldType,
        isRequired: o.isRequired,
        enabled: o.enabled,
        vField: o.dropdownValueField.isNotEmpty ? o.dropdownValueField : 'id',
        dField:
            o.dropdownDisplayField.isNotEmpty ? o.dropdownDisplayField : 'nome',
        dropdownFutureBuilder: o.dropdownFutureBuilder,
        dropdownOptions: o.dropdownOptions
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        visibleWhen: null,
        fileConfig: o.fileConfig,
      );
}

// ---------------------------------------------------------------
// Password field widget
// ---------------------------------------------------------------
class _PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool isRequired;
  const _PasswordField(
      {required this.controller,
      required this.label,
      required this.isRequired});
  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _visible = false;
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: !_visible,
      decoration: InputDecoration(
        labelText: widget.label + (widget.isRequired ? ' *' : ''),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:
                const BorderSide(color: GridColors.primary, width: 1.5)),
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _visible = !_visible),
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      ),
      validator: widget.isRequired
          ? (v) => (v == null || v.trim().isEmpty)
              ? '${widget.label} é obrigatório'
              : null
          : null,
    );
  }
}

// ---------------------------------------------------------------
// MultiSelect dialog
// ---------------------------------------------------------------
class _MultiSelectDialog extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> options;
  final String valueField;
  final String displayField;
  final List<dynamic> initialSelected;
  const _MultiSelectDialog(
      {required this.title,
      required this.options,
      required this.valueField,
      required this.displayField,
      required this.initialSelected});
  @override
  State<_MultiSelectDialog> createState() => _MultiSelectDialogState();
}

class _MultiSelectDialogState extends State<_MultiSelectDialog> {
  late List<dynamic> _selected;
  late List<Map<String, dynamic>> _filtered;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.initialSelected);
    _filtered = widget.options;
    _ctrl.addListener(() {
      final q = _ctrl.text.toLowerCase();
      setState(() {
        _filtered = q.isEmpty
            ? widget.options
            : widget.options
                .where((o) =>
                    o[widget.displayField]
                        ?.toString()
                        .toLowerCase()
                        .contains(q) ??
                    false)
                .toList();
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool _isSel(dynamic val) =>
      _selected.any((s) => s.toString() == val?.toString());
  void _toggle(dynamic val) {
    setState(() {
      if (_isSel(val)) {
        _selected.removeWhere((s) => s.toString() == val?.toString());
      } else {
        _selected.add(val);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520, maxWidth: 420),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: GridColors.primary,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              const Icon(Icons.checklist, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(widget.title,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white))),
              Text('${_selected.length} selecionado(s)',
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Buscar...',
                prefixIcon: const Icon(Icons.search, color: GridColors.primary),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                        color: GridColors.primary, width: 1.5)),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
              child: ListView.builder(
            itemCount: _filtered.length,
            itemBuilder: (ctx, i) {
              final opt = _filtered[i];
              final val = opt[widget.valueField];
              final label =
                  opt[widget.displayField]?.toString() ?? val.toString();
              return CheckboxListTile(
                title: Text(label, style: const TextStyle(fontSize: 14)),
                value: _isSel(val),
                activeColor: GridColors.primary,
                checkColor: Colors.white,
                onChanged: (_) => _toggle(val),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
              );
            },
          )),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCELAR')),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, _selected),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GridColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                child: const Text('CONFIRMAR'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
