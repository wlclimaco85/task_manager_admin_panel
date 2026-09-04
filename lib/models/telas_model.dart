// lib/data/models/telas_model.dart
// ------------------------------------------------------------
// Modelo de tela (TelaConfig) + campos (TelaField) + ações (TelaAction)
// - Suporta actions vindas do banco (lista "actions")
// - Parser resiliente para estruturas com "data", "dados", etc.
// - Enum TelaFieldType (modelo) separado do FieldType do UI para evitar conflitos.
// ------------------------------------------------------------

import 'package:flutter/material.dart';

import '../../../widgets/generic_grid_windows_screen.dart'
    show FieldConfigWindows, FileConfig, FieldType;

// IMPORTA O NETWORK CALLER CORRETO
import '../services/network_caller.dart';
import '../../../config/api_links.dart';

extension TelaFieldConverter on TelaField {
  FieldConfigWindows toFieldWindows() {
    return FieldConfigWindows(
      label: label,
      fieldName: fieldName,
      displayFieldName: displayFieldName,
      fieldType: FieldType.values[fieldType.index],
      isVisibleByDefault: isVisibleByDefault,
      isRequired: isRequired,
      isFilterable: isFilterable,
      isSortable: isSortable,
      isInForm: isInForm,
      icon: iconData,
      maxLines: maxLines,
      defaultValue: defaultValue,
      dropdownOptions: dropdownOptions
          .map((e) => {
                "value": e.optionValue,
                "label": e.optionLabel ?? e.optionValue.toString(),
              })
          .toList(),
      dropdownValueField: dropdownValueField,
      dropdownDisplayField: dropdownDisplayField,
      dropdownFutureBuilder:
          dropdownEndpoint != null ? _futureDropdown() : null,
      fileConfig: fieldType == TelaFieldType.file
          ? FileConfig(
              allowedExtensions: allowedExtensions,
              allowMultiple: allowMultipleFiles,
              maxFileSize: maxFileSize,
              fileFieldName: fileFieldName,
            )
          : null,
    );
  }

  Future<List<Map<String, dynamic>>> Function() _futureDropdown() {
    return () async {
      final fullUrl = dropdownEndpoint!.startsWith('http')
          ? dropdownEndpoint!
          : '${ApiLinks.baseUrl}$dropdownEndpoint';
      final response = await NetworkCaller().getRequest(fullUrl);

      if (!response.isSuccess || response.body == null) {
        return <Map<String, dynamic>>[];
      }

      final dynamic raw = response.body;

      // ============================================================
      // 1) SE FOR LISTA → CONVERTE E RETORNA
      // ============================================================
      if (raw is List) {
        return _convertList(raw);
      }

      // ============================================================
      // 2) SE FOR MAP → CONTINUA O PARSE
      // ============================================================
      if (raw is Map) {
        final Map<String, dynamic> body = Map<String, dynamic>.from(raw);

        dynamic data = body["data"] ??
            body["dados"] ??
            body["items"] ??
            body["content"] ??
            body["result"];

        // se data for lista
        if (data is List) {
          return _convertList(data);
        }

        // se data for mapa (ex: {dados: [...], totalElements: N})
        if (data is Map) {
          final inner = data["dados"] ?? data["content"] ?? data["items"];
          if (inner is List) return _convertList(inner);
          return <Map<String, dynamic>>[Map<String, dynamic>.from(data)];
        }

        // nada útil
        return <Map<String, dynamic>>[];
      }

      // ============================================================
      // 3) QUALQUER OUTRA COISA → RETORNA LISTA VAZIA
      // ============================================================
      return <Map<String, dynamic>>[];
    };
  }

  List<Map<String, dynamic>> _convertList(List lista) {
    final List<Map<String, dynamic>> result = [];

    for (final item in lista) {
      if (item is Map<String, dynamic>) {
        result.add(item);
      } else if (item is Map) {
        result.add(Map<String, dynamic>.from(item));
      }
    }

    return result;
  }
}

/// Enum de tipos de campo vindo do servidor.
/// (Separado do FieldType do grid para evitar colisão de tipos.)
enum TelaFieldType {
  text,
  number,
  email,
  date,
  multiline,
  dropdown,
  boolean,
  file,
  password,
  phone,
  cpf,
  cnpj,
  cpfCnpj,
  cep,
  currency,
  percentage,
  url,
  multiselect,
}

class DropdownOption {
  final dynamic optionValue;
  final String? optionLabel;

  DropdownOption({required this.optionValue, this.optionLabel});

  factory DropdownOption.fromJson(Map<String, dynamic> json) {
    return DropdownOption(
      optionValue: json['optionValue'] ?? json['value'] ?? json['id'],
      optionLabel: json['optionLabel'] ?? json['label'] ?? json['name'],
    );
  }

  Map<String, dynamic> toJson() => {
        'optionValue': optionValue,
        'optionLabel': optionLabel,
      };
}

class TelaField {
  final String label;
  final String fieldName;
  final String? displayFieldName;

  final bool isFilterable;
  final bool isInForm;
  final bool showInInsert; // para filtrar no insert
  final bool showInUpdate; // para filtrar no update
  final bool isSortable;

  final int flex;
  final int maxLines;

  final String? icon; // nome textual recebido do back
  final IconData? iconData; // derivado do "icon", se quiser usar direto
  final TelaFieldType fieldType;

  final List<DropdownOption> dropdownOptions;
  final String? dropdownEndpoint;
  final String dropdownValueField;
  final String dropdownDisplayField;
  final dynamic dropdownSelectedValue;

  final bool isRequired;
  final bool isVisibleByDefault;
  final bool isFixed; // não pode ocultar no selector
  final bool enabled;
  final dynamic defaultValue;

  // arquivo
  final List<String> allowedExtensions;
  final bool allowMultipleFiles;
  final int maxFileSize;
  final String fileFieldName;

  // data
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String dateFormat;

  final bool showInCard;
  final bool multiSelect; // dropdown com seleção múltipla
  final int fieldOrder; // ordem do campo no form

  /// Visibilidade condicional, formato "<fieldName>==<valor>" (ex.: "isServico==false").
  /// Quando nulo, o campo é sempre visível.
  final String? visibleWhen;

  TelaField({
    required this.label,
    required this.fieldName,
    this.displayFieldName,
    this.isFilterable = true,
    this.isInForm = true,
    this.showInInsert = true,
    this.showInUpdate = true,
    this.isSortable = true,
    this.flex = 1,
    this.maxLines = 1,
    this.icon,
    this.iconData,
    this.fieldType = TelaFieldType.text,
    this.dropdownOptions = const [],
    this.dropdownEndpoint,
    this.dropdownValueField = 'value',
    this.dropdownDisplayField = 'label',
    this.dateFormat = 'dd/MM/yyyy',
    this.firstDate,
    this.lastDate,
    this.defaultValue,
    this.dropdownSelectedValue,
    this.isRequired = false,
    this.isVisibleByDefault = true,
    this.isFixed = false,
    this.enabled = true,
    this.allowedExtensions = const ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'],
    this.allowMultipleFiles = false,
    this.maxFileSize = 5 * 1024 * 1024,
    this.fileFieldName = 'file',
    this.showInCard = true,
    this.multiSelect = false,
    this.fieldOrder = 0,
    this.visibleWhen,
  });

  factory TelaField.fromJson(Map<String, dynamic> json) {
    final rawType = json['fieldType'];
    TelaFieldType tft;
    if (rawType is int) {
      const tftValues = TelaFieldType.values;
      tft = rawType >= 0 && rawType < tftValues.length
          ? tftValues[rawType]
          : TelaFieldType.text;
    } else if (rawType is String) {
      tft = _fieldTypeFromString(rawType);
    } else {
      tft = TelaFieldType.text;
    }

    final iconName = json['icon']?.toString();
    return TelaField(
      label: json['label']?.toString() ?? json['titulo']?.toString() ?? 'Campo',
      fieldName:
          json['fieldName']?.toString() ?? json['nome']?.toString() ?? '',
      displayFieldName: json['displayFieldName']?.toString(),
      isFilterable:
          json['isFilterable'] == null ? true : (json['isFilterable'] == true),
      isInForm:
          json['isInForm'] == null ? true : (json['isInForm'] as bool? ?? true),
      showInInsert: json['showInInsert'] == null
          ? true
          : (json['showInInsert'] as bool? ?? true),
      showInUpdate: json['showInUpdate'] == null
          ? true
          : (json['showInUpdate'] as bool? ?? true),
      isSortable: json['isSortable'] == null
          ? true
          : (json['isSortable'] as bool? ?? true),
      flex: json['flex'] is int ? json['flex'] as int : 1,
      maxLines: json['maxLines'] is int ? json['maxLines'] as int : 1,
      icon: iconName,
      iconData: _iconFromName(iconName),
      fieldType: tft,
      dropdownOptions: (json['dropdownOptions'] is List
              ? (json['dropdownOptions'] as List)
              : const [])
          .whereType<Map>()
          .map((e) => DropdownOption.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      dropdownEndpoint: json['dropdownEndpoint']?.toString(),
      dropdownValueField: json['dropdownValueField']?.toString() ?? 'value',
      dropdownDisplayField: json['dropdownDisplayField']?.toString() ?? 'label',
      dropdownSelectedValue: json['dropdownSelectedValue'],
      isRequired: json['isRequired'] == true,
      isVisibleByDefault: json['isVisibleByDefault'] ?? true,
      isFixed: json['isFixed'] == true,
      enabled:
          json['enabled'] == null ? true : (json['enabled'] as bool? ?? true),
      defaultValue: json['defaultValue'],
      allowedExtensions: (json['allowedExtensions'] is List
              ? (json['allowedExtensions'] as List)
              : const [])
          .whereType<String>()
          .toList(),
      allowMultipleFiles: json['allowMultipleFiles'] == true,
      maxFileSize:
          json['maxFileSize'] is int ? json['maxFileSize'] : 5 * 1024 * 1024,
      fileFieldName: json['fileFieldName']?.toString() ?? 'file',
      firstDate: json['firstDate'] != null
          ? DateTime.tryParse(json['firstDate'].toString())
          : null,
      lastDate: json['lastDate'] != null
          ? DateTime.tryParse(json['lastDate'].toString())
          : null,
      dateFormat: json['dateFormat']?.toString() ?? 'dd/MM/yyyy',
      showInCard: json['showInCard'] == null
          ? true
          : (json['showInCard'] as bool? ?? true),
      multiSelect: json['multiSelect'] == true,
      fieldOrder: json['fieldOrder'] is int ? json['fieldOrder'] : 0,
      visibleWhen: json['visibleWhen'] as String?,
    );
  }

  static TelaFieldType _fieldTypeFromString(String type) {
    switch (type.toLowerCase()) {
      case 'number':
        return TelaFieldType.number;
      case 'email':
        return TelaFieldType.email;
      case 'date':
        return TelaFieldType.date;
      case 'multiline':
        return TelaFieldType.multiline;
      case 'dropdown':
        return TelaFieldType.dropdown;
      case 'boolean':
        return TelaFieldType.boolean;
      case 'file':
        return TelaFieldType.file;
      case 'password':
        return TelaFieldType.password;
      case 'phone':
        return TelaFieldType.phone;
      case 'cpf':
        return TelaFieldType.cpf;
      case 'cnpj':
        return TelaFieldType.cnpj;
      case 'cpfcnpj':
        return TelaFieldType.cpfCnpj;
      case 'cep':
        return TelaFieldType.cep;
      case 'currency':
        return TelaFieldType.currency;
      case 'percentage':
        return TelaFieldType.percentage;
      case 'url':
        return TelaFieldType.url;
      case 'multiselect':
        return TelaFieldType.multiselect;
      default:
        return TelaFieldType.text;
    }
  }

  static IconData? _iconFromName(String? name) {
    if (name == null) return null;
    switch (name) {
      case 'add':
        return Icons.add;
      case 'edit':
        return Icons.edit;
      case 'delete':
        return Icons.delete;
      case 'visibility':
      case 'view':
        return Icons.visibility;
      case 'file':
        return Icons.attach_file;
      case 'email':
        return Icons.email;
      case 'phone':
        return Icons.phone;
      case 'calendar':
        return Icons.calendar_today;
      default:
        return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'fieldName': fieldName,
        'displayFieldName': displayFieldName,
        'isFilterable': isFilterable,
        'isInForm': isInForm,
        'showInInsert': showInInsert,
        'showInUpdate': showInUpdate,
        'isSortable': isSortable,
        'flex': flex,
        'maxLines': maxLines,
        'icon': icon,
        'fieldType': fieldType.index,
        'dropdownOptions': dropdownOptions.map((e) => e.toJson()).toList(),
        'dropdownEndpoint': dropdownEndpoint,
        'dropdownValueField': dropdownValueField,
        'dropdownDisplayField': dropdownDisplayField,
        'dropdownSelectedValue': dropdownSelectedValue,
        'isRequired': isRequired,
        'isVisibleByDefault': isVisibleByDefault,
        'isFixed': isFixed,
        'enabled': enabled,
        'defaultValue': defaultValue,
        'allowedExtensions': allowedExtensions,
        'allowMultipleFiles': allowMultipleFiles,
        'maxFileSize': maxFileSize,
        'fileFieldName': fileFieldName,
        'firstDate': firstDate?.toIso8601String(),
        'lastDate': lastDate?.toIso8601String(),
        'dateFormat': dateFormat,
        'showInCard': showInCard,
        'multiSelect': multiSelect,
        'fieldOrder': fieldOrder,
        'visibleWhen': visibleWhen,
      };
}

class TelaRelatedGrid {
  final String title;
  final String icon;
  final String gridTelaNome;
  final int tabOrder;

  TelaRelatedGrid({
    required this.title,
    required this.icon,
    required this.gridTelaNome,
    this.tabOrder = 0,
  });

  factory TelaRelatedGrid.fromJson(Map<String, dynamic> json) {
    return TelaRelatedGrid(
      title: json['title']?.toString() ?? '',
      icon: json['icon']?.toString() ?? 'list',
      gridTelaNome: json['gridTelaNome']?.toString() ?? '',
      tabOrder: json['tabOrder'] is int ? json['tabOrder'] : 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'icon': icon,
        'gridTelaNome': gridTelaNome,
        'tabOrder': tabOrder,
      };
}

class TelaAction {
  final String label;
  final String? icon; // nome textual
  final String method; // GET/POST/PUT/DELETE
  final String endpoint; // pode conter :id
  final String? confirmMessage; // opcional (se não vier, usa padrão)

  // opcional (se quiser permissionamento por ação):
  final String? requiredPermission; // ex: "approve", "close" etc.

  TelaAction({
    required this.label,
    this.icon,
    required this.method,
    required this.endpoint,
    this.confirmMessage,
    this.requiredPermission,
  });

  factory TelaAction.fromJson(Map<String, dynamic> json) {
    return TelaAction(
      label: json['label']?.toString() ?? 'Ação',
      icon: json['icon']?.toString(),
      method: (json['method']?.toString() ?? 'GET').toUpperCase(),
      endpoint: json['endpoint']?.toString() ?? '',
      confirmMessage: json['confirmMessage']?.toString(),
      requiredPermission: json['requiredPermission']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'icon': icon,
        'method': method,
        'endpoint': endpoint,
        'confirmMessage': confirmMessage,
        'requiredPermission': requiredPermission,
      };
}

class TelaConfig {
  final int id;
  final String nome;
  final String titulo;

  final String fetchEndpoint;
  final String createEndpoint;
  final String updateEndpoint; // ':id'
  final String deleteEndpoint; // ':id'

  final List<TelaField> fields;

  final String idFieldName;
  final String? dateFieldName;
  final String? storageKey;

  final bool enableSearch;
  final bool enableDebugMode;
  final bool useUserBannerAppBar;

  // 🔥 novas ações vindas do banco
  final List<TelaAction> actions;

  // 🔥 abas relacionadas vindas do banco
  final List<TelaRelatedGrid> relatedGrids;

  TelaConfig({
    required this.id,
    required this.nome,
    required this.titulo,
    required this.fetchEndpoint,
    required this.createEndpoint,
    required this.updateEndpoint,
    required this.deleteEndpoint,
    required this.fields,
    this.idFieldName = 'id',
    this.dateFieldName,
    this.storageKey,
    this.enableSearch = true,
    this.enableDebugMode = false,
    this.useUserBannerAppBar = false,
    this.actions = const [],
    this.relatedGrids = const [],
  });

  factory TelaConfig.fromJson(Map<String, dynamic> raw) {
    // aceita tanto "direto" quanto {data: {...}} ou {dados: {...}}
    final json = _unwrapDataOrDados(raw);

    final fieldsJson = (json['fields'] is List ? json['fields'] as List : [])
        .whereType<Map>()
        .map((e) => TelaField.fromJson(Map<String, dynamic>.from(e)))
        .toList()
      ..sort((a, b) => a.fieldOrder.compareTo(b.fieldOrder));

    final actionsJson =
        (json['actions'] is List ? json['actions'] as List : const [])
            .whereType<Map>()
            .map((e) => TelaAction.fromJson(Map<String, dynamic>.from(e)))
            .toList();

    final relatedGridsJson =
        (json['relatedGrids'] is List ? json['relatedGrids'] as List : const [])
            .whereType<Map>()
            .map((e) => TelaRelatedGrid.fromJson(Map<String, dynamic>.from(e)))
            .toList()
          ..sort((a, b) => a.tabOrder.compareTo(b.tabOrder));

    return TelaConfig(
      id: json['id'] is int ? json['id'] : int.tryParse('${json['id']}') ?? 0,
      nome: json['nome']?.toString() ?? 'tela',
      titulo: json['titulo']?.toString() ?? json['title']?.toString() ?? 'Tela',
      fetchEndpoint: json['fetchEndpoint']?.toString() ?? '',
      createEndpoint: json['createEndpoint']?.toString() ?? '',
      updateEndpoint: json['updateEndpoint']?.toString() ?? '',
      deleteEndpoint: json['deleteEndpoint']?.toString() ?? '',
      fields: fieldsJson,
      idFieldName: json['idFieldName']?.toString() ?? 'id',
      dateFieldName: json['dateFieldName']?.toString(),
      storageKey: json['storageKey']?.toString(),
      enableSearch: json['enableSearch'] == null
          ? true
          : (json['enableSearch'] as bool? ?? true),
      enableDebugMode: json['enableDebugMode'] == true,
      useUserBannerAppBar: json['useUserBannerAppBar'] == true,
      actions: actionsJson,
      relatedGrids: relatedGridsJson,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'titulo': titulo,
        'fetchEndpoint': fetchEndpoint,
        'createEndpoint': createEndpoint,
        'updateEndpoint': updateEndpoint,
        'deleteEndpoint': deleteEndpoint,
        'fields': fields.map((e) => e.toJson()).toList(),
        'idFieldName': idFieldName,
        'dateFieldName': dateFieldName,
        'storageKey': storageKey,
        'enableSearch': enableSearch,
        'enableDebugMode': enableDebugMode,
        'useUserBannerAppBar': useUserBannerAppBar,
        'actions': actions.map((e) => e.toJson()).toList(),
        'relatedGrids': relatedGrids.map((e) => e.toJson()).toList(),
      };

  static Map<String, dynamic> _unwrapDataOrDados(Map<String, dynamic> raw) {
    dynamic cur = raw;
    if (cur is Map && (cur['data'] != null || cur['dados'] != null)) {
      final sub = cur['data'] ?? cur['dados'];
      if (sub is Map) return Map<String, dynamic>.from(sub);
      if (sub is List && sub.isNotEmpty && sub.first is Map) {
        return Map<String, dynamic>.from(sub.first as Map);
      }
    }
    if (cur is Map && cur.containsKey('content') && cur['content'] is Map) {
      return Map<String, dynamic>.from(cur['content']);
    }
    if (cur is Map) return Map<String, dynamic>.from(cur);
    return <String, dynamic>{};
  }
}

class UserFieldPreference {
  final int id;
  final int userId;
  final int telaId;
  final String fieldName;
  final bool isVisible;
  final double? widthPreference;
  final int orderPreference;

  UserFieldPreference({
    required this.id,
    required this.userId,
    required this.telaId,
    required this.fieldName,
    required this.isVisible,
    this.widthPreference,
    this.orderPreference = 0,
  });

  factory UserFieldPreference.fromJson(Map<String, dynamic> json) {
    return UserFieldPreference(
      id: json['id'] ?? 0,
      userId: json['userId'] ?? 0,
      telaId: json['telaId'] ??
          (json['tela'] != null ? json['tela']['id'] ?? 0 : 0),
      fieldName: json['fieldName'] ?? '',
      isVisible: json['isVisible'] ?? true,
      widthPreference: json['widthPreference']?.toDouble(),
      orderPreference: json['orderPreference'] ?? 0,
    );
  }
}
