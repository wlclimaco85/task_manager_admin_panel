// Classe Endereco / Parceiro / Pais / Estado / Cidade
import 'dart:convert';
import 'package:flutter/material.dart';

import '../../../widgets/generic_grid_windows_screen.dart'
    show FieldConfigWindows, FieldType;

import '../../../models/empresa_model.dart';
import '../../../config/api_links.dart';
import '../../../models/network_response.dart';
import '../../services/network_caller.dart';
import '../../../models/regime_tributario_model.dart';

// FieldConfig do MOBILE (GenericMobileGridScreen / GenericGridCard)
import '../../../customization/generic_grid_card.dart' as mobile_grid
    show FieldConfig, FieldType;

class Endereco {
  int? id;
  String? rua;
  String? numero;
  String? bairro;
  Cidade? cidade;
  Estado? estado;
  Pais? pais;
  String? cep;
  int? parceiroId;

  Endereco({
    this.id,
    this.rua,
    this.numero,
    this.bairro,
    this.cidade,
    this.estado,
    this.cep,
    this.parceiroId,
  });

  Endereco.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    rua = json['rua'];
    numero = json['numero'];
    bairro = json['bairro'];
    pais = json['pais'] != null ? Pais.fromJson(json['pais']) : null;
    cidade = json['cidade'] != null ? Cidade.fromJson(json['cidade']) : null;
    estado = json['estado'] != null ? Estado.fromJson(json['estado']) : null;
    cep = json['cep'];
    parceiroId = json['parceiroId'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['rua'] = rua;
    data['numero'] = numero;
    data['bairro'] = bairro;
    data['cidade'] = cidade;
    data['estado'] = estado;
    data['cep'] = cep;
    data['parceiroId'] = parceiroId;
    return data;
  }
}

class ParceiroModel {
  String? status;
  String? token;
  List<Parceiro>? parceiros;

  ParceiroModel({this.status, this.token, this.parceiros});

  ParceiroModel.fromJson(Map<String, dynamic> json) {
    status = json['status'];
    token = json['token'];
    parceiros = json['data'] != null
        ? Parceiro.fromJsonList(json['data']['account'])
        : [];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['status'] = status;
    data['token'] = token;
    if (parceiros != null) {
      data['data'] = parceiros!.map((produto) => produto.toJson()).toList();
    }
    return data;
  }
}

// ======================================
// Classe Parceiro
// ======================================
class Parceiro {
  int? id;
  String? nome;
  String? cpf;
  String? codProdutor;
  String? email;
  String? telefone1;
  String? telefone2;
  String? razaoSocial;
  int? codPersonal;
  String? incrMun;
  String? status;
  Endereco? endereco;
  Empresa? empresa;
  RegimeTributario? regime;
  double? valorMensal;

  /// 1-30 = dia fixo do mes; 0 = "5º Dia Útil" (calculado pelo backend); null =
  /// nao configurado (tratado como 0 pelo job de cobranca).
  int? diaVencimentoMensalidade;

  String? observacao;

  Parceiro({
    this.id,
    this.nome,
    this.cpf,
    this.codProdutor,
    this.email,
    this.telefone1,
    this.telefone2,
    this.razaoSocial,
    this.codPersonal,
    this.incrMun,
    this.status,
    this.endereco,
    this.empresa,
    this.regime,
    this.valorMensal,
    this.diaVencimentoMensalidade,
    this.observacao,
  });

  Parceiro.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    nome = json['nome'];
    cpf = json['cpf'];
    codProdutor = json['codProdutor'];
    email = json['email'];
    telefone1 = json['telefone1'];
    telefone2 = json['telefone2'];
    razaoSocial = json['razaoSocial'];
    codPersonal = json['codPersonal'];
    incrMun = json['incrMun'];
    status = json['status'];
    endereco =
        json['endereco'] != null ? Endereco.fromJson(json['endereco']) : null;
    empresa =
        json['empresa'] != null ? Empresa.fromJson(json['empresa']) : null;
    regime = json['regime'] != null
        ? RegimeTributario.fromJson(json['regime'])
        : null;
    valorMensal = json['valorMensal']?.toDouble();
    diaVencimentoMensalidade =
        (json['diaVencimentoMensalidade'] as num?)?.toInt();
    observacao = json['observacao'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['nome'] = nome;
    data['cpf'] = cpf;
    data['codProdutor'] = codProdutor;
    data['email'] = email;
    data['telefone1'] = telefone1;
    data['telefone2'] = telefone2;
    data['razaoSocial'] = razaoSocial;
    data['codPersonal'] = codPersonal;
    data['incrMun'] = incrMun;
    data['status'] = status;
    if (endereco != null) data['endereco'] = endereco!.toJson();
    if (empresa != null) data['empresa'] = empresa!.toJson();
    if (regime != null) data['regime'] = regime!.toJson();
    data['regime'] = regime;
    data['valorMensal'] = valorMensal;
    data['diaVencimentoMensalidade'] = diaVencimentoMensalidade;
    data['observacao'] = observacao;
    return data;
  }

  static List<Parceiro> fromJsonList(List<dynamic> jsonList) {
    return jsonList
        .map((item) => Parceiro.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  // ============================
  // DROPDOWNS
  // ============================
  static Future<List<Map<String, dynamic>>> loadCategorias() async {
    final NetworkResponse response = await NetworkCaller().getRequest(
      ApiLinks.allRegimetributario,
    );

    if (response.isSuccess && response.body != null) {
      final List<dynamic> data = response.body!['data']['dados'] ?? [];
      return data
          .map(
            (item) => {'value': item['id'].toString(), 'label': item['codigo']},
          )
          .toList();
    }
    return [];
  }

  /// Opções do dropdown "Dia de Vencimento": 0 = "5º Dia Útil" (default quando
  /// não configurado), 1-30 = dia fixo do mês.
  static List<Map<String, dynamic>> get diaVencimentoOptions => [
        {'value': 0, 'label': '5º Dia Útil'},
        for (var dia = 1; dia <= 30; dia++)
          {'value': dia, 'label': 'Dia $dia'},
      ];

  // ==========================================================
  // CONFIG PADRÃO WINDOWS (DynamicGridWindows / Detail Windows)
  // ==========================================================
  static List<FieldConfigWindows> fieldConfigs = [
    const FieldConfigWindows(
      label: "Nome",
      fieldName: "nome",
      icon: Icons.person,
      isInForm: true,
      isFilterable: true,
      isVisibleByDefault: true,
      isFixed: true,
      fieldType: FieldType.text,
    ),
    const FieldConfigWindows(
      label: "CPF/CNPJ",
      fieldName: "cpf",
      icon: Icons.badge,
      isInForm: true,
      isFilterable: true,
      isVisibleByDefault: true,
      isFixed: true,
      fieldType: FieldType.cpfCnpj,
    ),
    const FieldConfigWindows(
      label: "Email",
      fieldName: "email",
      icon: Icons.email,
      isInForm: true,
      isVisibleByDefault: true,
      isFixed: true,
      fieldType: FieldType.email,
    ),
    const FieldConfigWindows(
      label: "Telefone",
      fieldName: "telefone1",
      icon: Icons.phone,
      isInForm: true,
      isVisibleByDefault: true,
      isFixed: true,
      fieldType: FieldType.phone,
    ),
    const FieldConfigWindows(
      label: "Razão Social",
      fieldName: "razaoSocial",
      icon: Icons.apartment,
      isInForm: true,
      isVisibleByDefault: false,
      isFixed: false,
      fieldType: FieldType.text,
    ),
    const FieldConfigWindows(
      label: "CEP",
      fieldName: "cep",
      icon: Icons.search,
      isInForm: true,
      isVisibleByDefault: false,
      isFixed: false,
      fieldType: FieldType.cep,
    ),
    const FieldConfigWindows(
      label: "Rua",
      fieldName: "rua",
      icon: Icons.location_on,
      isInForm: true,
      isVisibleByDefault: false,
      isFixed: false,
      fieldType: FieldType.text,
    ),
    const FieldConfigWindows(
      label: "Bairro",
      fieldName: "bairro",
      icon: Icons.map,
      isInForm: true,
      isVisibleByDefault: false,
      isFixed: false,
      fieldType: FieldType.text,
    ),
    const FieldConfigWindows(
      label: "Cidade",
      fieldName: "cidade",
      icon: Icons.location_city,
      isInForm: true,
      isVisibleByDefault: false,
      isFixed: false,
      fieldType: FieldType.text,
    ),
    const FieldConfigWindows(
      label: "Estado",
      fieldName: "estado",
      icon: Icons.map_outlined,
      isInForm: true,
      isVisibleByDefault: false,
      isFixed: false,
      fieldType: FieldType.text,
    ),
    const FieldConfigWindows(
      label: "País",
      fieldName: "pais",
      icon: Icons.public,
      isInForm: true,
      isVisibleByDefault: false,
      isFixed: false,
      fieldType: FieldType.text,
    ),
    const FieldConfigWindows(
      label: "Inscrição Municipal",
      fieldName: "incrMun",
      icon: Icons.assignment,
      isInForm: true,
      isVisibleByDefault: false,
      isFixed: false,
      fieldType: FieldType.number,
    ),
    const FieldConfigWindows(
      label: "Valor Mensal",
      fieldName: "valorMensal",
      icon: Icons.attach_money,
      isInForm: true,
      isVisibleByDefault: false,
      isFixed: false,
      fieldType: FieldType.currency,
    ),
    FieldConfigWindows(
      label: "Dia de Vencimento (mensalidade/módulos)",
      fieldName: "diaVencimentoMensalidade",
      icon: Icons.event,
      isInForm: true,
      isVisibleByDefault: false,
      isFixed: false,
      fieldType: FieldType.dropdown,
      dropdownOptions: diaVencimentoOptions,
      dropdownValueField: 'value',
      dropdownDisplayField: 'label',
    ),
    const FieldConfigWindows(
      label: "Observação",
      fieldName: "observacao",
      icon: Icons.notes,
      isInForm: true,
      isVisibleByDefault: false,
      isFixed: false,
      fieldType: FieldType.multiline,
    ),
    // Tipo Cliente — multiselect
    const FieldConfigWindows(
      label: "Tipo Cliente",
      fieldName: "tipoCliente",
      icon: Icons.category,
      isInForm: true,
      isVisibleByDefault: false,
      isFixed: false,
      fieldType: FieldType.dropdown,
      dropdownOptions: [
        {'value': 'CLIENTE', 'label': 'Cliente'},
        {'value': 'FORNECEDOR', 'label': 'Fornecedor'},
        {'value': 'FUNCIONARIO', 'label': 'Funcionário'},
        {'value': 'PARCEIRO', 'label': 'Parceiro'},
        {'value': 'TRANSPORTADORA', 'label': 'Transportadora'},
      ],
      dropdownValueField: 'value',
      dropdownDisplayField: 'label',
    ),
    // Arquivo
    const FieldConfigWindows(
      label: "Anexo",
      fieldName: "file",
      icon: Icons.attach_file,
      isInForm: true,
      isVisibleByDefault: false,
      isFixed: false,
      fieldType: FieldType.file,
    ),
    // Status — só no update (isInForm: false para insert)
    const FieldConfigWindows(
      label: "Status",
      fieldName: "status",
      icon: Icons.toggle_on,
      isInForm: false, // não aparece no insert; grid screen controla update
      isFilterable: true,
      isVisibleByDefault: true,
      isFixed: false,
      fieldType: FieldType.dropdown,
      dropdownOptions: [
        {'value': 'ATIVO', 'label': 'Ativo'},
        {'value': 'INATIVO', 'label': 'Inativo'},
        {'value': 'BLOQUEADO', 'label': 'Bloqueado'},
      ],
      dropdownValueField: 'value',
      dropdownDisplayField: 'label',
    ),
    FieldConfigWindows(
      label: "Regime",
      fieldName: "regime",
      displayFieldName: "regime.codigo",
      icon: Icons.business_center,
      isInForm: true,
      isFilterable: true,
      fieldType: FieldType.dropdown,
      dropdownFutureBuilder: () async => await loadCategorias(),
      dropdownValueField: 'value',
      dropdownDisplayField: 'label',
      isRequired: false,
      isVisibleByDefault: false,
    ),
  ];

  // ✅ AGORA EXISTE — usado onde você faz Parceiro.fieldConfigsWindows()
  static List<FieldConfigWindows> fieldConfigsWindows() => fieldConfigs;

  // ==========================================================
  // CONVERTE FieldConfigWindows → FieldConfig (para MOBILE)
  // ==========================================================
  static List<mobile_grid.FieldConfig> fieldConfigsMobile() {
    return fieldConfigsWindows().map((fw) {
      return mobile_grid.FieldConfig(
        label: fw.label,
        fieldName: fw.fieldName,
        icon: fw.icon,
        isInForm: fw.isInForm,
        isFilterable: true,
        isVisibleByDefault: fw.isVisibleByDefault,
        isFixed: fw.isFixed,
        fieldType: _mobileFieldType(fw.fieldType),
        dropdownOptions: fw.dropdownOptions,
        dropdownFutureBuilder: fw.dropdownFutureBuilder,
        dropdownValueField: fw.dropdownValueField,
        dropdownDisplayField: fw.dropdownDisplayField,
      );
    }).toList();
  }

  static mobile_grid.FieldType _mobileFieldType(FieldType type) {
    switch (type) {
      case FieldType.number:
        return mobile_grid.FieldType.number;
      case FieldType.email:
        return mobile_grid.FieldType.email;
      case FieldType.date:
        return mobile_grid.FieldType.date;
      case FieldType.multiline:
        return mobile_grid.FieldType.multiline;
      case FieldType.dropdown:
        return mobile_grid.FieldType.dropdown;
      case FieldType.boolean:
        return mobile_grid.FieldType.boolean;
      case FieldType.file:
        return mobile_grid.FieldType.file;
      case FieldType.password:
        return mobile_grid.FieldType.password;
      case FieldType.phone:
        return mobile_grid.FieldType.phone;
      case FieldType.cpf:
        return mobile_grid.FieldType.cpf;
      case FieldType.cnpj:
        return mobile_grid.FieldType.cnpj;
      case FieldType.cpfCnpj:
        return mobile_grid.FieldType.cpfCnpj;
      case FieldType.cep:
        return mobile_grid.FieldType.cep;
      case FieldType.currency:
        return mobile_grid.FieldType.currency;
      case FieldType.percentage:
        return mobile_grid.FieldType.percentage;
      case FieldType.url:
        return mobile_grid.FieldType.url;
      case FieldType.multiselect:
        return mobile_grid.FieldType.multiselect;
      case FieldType.text:
        return mobile_grid.FieldType.text;
    }
  }
}

// =====================================================
// MODELOS AUXILIARES: Pais / Estado / Cidade
// =====================================================

class PaisModel {
  String? status;
  String? token;
  List<Pais>? pais;

  PaisModel({this.status, this.token, this.pais});

  PaisModel.fromJson(Map<String, dynamic> json) {
    status = json['status'];
    token = json['token'];
    pais =
        json['data'] != null ? Pais.fromJsonList(json['data']['account']) : [];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['status'] = status;
    data['token'] = token;
    if (pais != null) {
      data['data'] = pais!.map((produto) => produto.toJson()).toList();
    }
    return data;
  }
}

class EstadoModel {
  String? status;
  String? token;
  List<Estado>? estados;

  EstadoModel({this.status, this.token, this.estados});

  EstadoModel.fromJson(Map<String, dynamic> json) {
    status = json['status'];
    token = json['token'];
    estados = json['data'] != null
        ? Estado.fromJsonList(json['data']['account'])
        : [];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['status'] = status;
    data['token'] = token;
    if (estados != null) {
      data['data'] = estados!.map((produto) => produto.toJson()).toList();
    }
    return data;
  }
}

class CidadeModel {
  String? status;
  String? token;
  List<Cidade>? estados;

  CidadeModel({this.status, this.token, this.estados});

  CidadeModel.fromJson(Map<String, dynamic> json) {
    status = json['status'];
    token = json['token'];
    estados = json['data'] != null
        ? Cidade.fromJsonList(json['data']['account'])
        : [];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['status'] = status;
    data['token'] = token;
    if (estados != null) {
      data['data'] = estados!.map((produto) => produto.toJson()).toList();
    }
    return data;
  }
}

class Pais {
  final int id;
  final String nome;
  final String nomePt;
  final String iso2;
  final String iso3;
  final int bacen;

  Pais({
    required this.id,
    required this.nome,
    required this.nomePt,
    required this.iso2,
    required this.iso3,
    required this.bacen,
  });

  factory Pais.fromJson(Map<String, dynamic> json) {
    return Pais(
      id: json['id'],
      nome: utf8.decode(latin1.encode(json['nome'])),
      nomePt: json['nomePt'],
      iso2: json['iso2'],
      iso3: json['iso3'] ?? '',
      bacen: json['bacen'],
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['nome'] = nome;
    data['nomePt'] = nomePt;
    data['iso2'] = iso2;
    data['iso3'] = iso3;
    data['bacen'] = bacen;
    return data;
  }

  static List<Pais> fromJsonList(List<dynamic> jsonList) {
    return jsonList
        .map((item) => Pais.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }
}

class Estado {
  final int id;
  final String nome;
  final String uf;
  final int ibge;
  final Pais pais;

  Estado({
    required this.id,
    required this.nome,
    required this.uf,
    required this.ibge,
    required this.pais,
  });

  factory Estado.fromJson(Map<String, dynamic> json) {
    final nomeRaw = json['nome'];
    String nomeFinal;

    try {
      nomeFinal = (nomeRaw is String)
          ? utf8.decode(latin1.encode(nomeRaw))
          : 'Sem nome';
    } catch (_) {
      nomeFinal = nomeRaw?.toString() ?? 'Sem nome';
    }

    return Estado(
      id: json['id'],
      nome: nomeFinal,
      uf: json['uf'],
      ibge: json['ibge'],
      pais: (json['pais'] != null && json['pais'] is Map<String, dynamic>)
          ? Pais.fromJson(json['pais'] as Map<String, dynamic>)
          : Pais(
              id: 0,
              nome: 'Brasil',
              nomePt: 'Brasil',
              iso2: 'BR',
              iso3: 'BRA',
              bacen: 1058,
            ),
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['nome'] = nome;
    data['uf'] = uf;
    data['ibge'] = ibge;
    data['pais'] = pais;
    return data;
  }

  static List<Estado> fromJsonList(List<dynamic> jsonList) {
    return jsonList
        .map((item) => Estado.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }
}

class Cidade {
  final int id;
  final String nome;
  final int ibge;
  final String latLon;

  Cidade({
    required this.id,
    required this.nome,
    required this.ibge,
    required this.latLon,
  });

  factory Cidade.fromJson(Map<String, dynamic> json) {
    return Cidade(
      id: json['id'],
      nome: json['nome']?.toString() ?? '',
      ibge: json['ibge'],
      latLon: json['latLon'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['nome'] = nome;
    data['ibge'] = ibge;
    data['latLon'] = latLon;
    return data;
  }

  static List<Cidade> fromJsonList(List<dynamic> jsonList) {
    return jsonList
        .map((item) => Cidade.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }
}
