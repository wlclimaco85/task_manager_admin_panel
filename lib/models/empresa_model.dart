import 'package:flutter/material.dart';

import '../../../models/aplicativo_model.dart';
import '../../../config/api_links.dart';
import '../../../widgets/generic_grid_windows_screen.dart'
    show FieldConfigWindows, FieldType;
import '../../services/network_caller.dart';

class Empresa {
  int? id;
  String? nome;
  String? razaoSocial;
  String? email;
  String? site;
  String? contato;
  String? emailContato;
  String? telefoneContato;
  String? telefone;
  String? rua;
  String? numero;
  String? cidade;
  String? cep;
  String? cnpj;
  String? ie;
  String? ambiente;
  Map<String, dynamic>? pais;
  Map<String, dynamic>? estado;
  Map<String, dynamic>? regime;
  Map<String, dynamic>? fileAttachment;
  Aplicativo? aplicativo;

  Empresa({
    this.id, this.nome, this.razaoSocial, this.email, this.site, this.contato,
    this.emailContato, this.telefoneContato, this.telefone, this.rua, this.numero,
    this.cidade, this.cep, this.cnpj, this.ie, this.ambiente,
    this.pais, this.estado, this.regime, this.fileAttachment, this.aplicativo,
  });

  Empresa.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    nome = json['nome']?.toString();
    razaoSocial = json['razaoSocial']?.toString();
    email = json['email']?.toString();
    site = json['site']?.toString();
    contato = json['contato']?.toString();
    emailContato = json['emailContato']?.toString();
    telefoneContato = json['telefoneContato']?.toString();
    telefone = json['telefone']?.toString();
    rua = json['rua']?.toString();
    numero = json['numero']?.toString();
    cnpj = json['cnpj']?.toString();
    ie = json['ie']?.toString();
    ambiente = json['ambiente']?.toString();
    cep = json['cep']?.toString();
    // cidade pode vir como objeto {id, nome} ou como string
    final cidadeRaw = json['cidade'];
    if (cidadeRaw is Map) {
      cidade = cidadeRaw['nome']?.toString();
    } else {
      cidade = cidadeRaw?.toString();
    }
    pais = json['pais'] is Map ? Map<String, dynamic>.from(json['pais']) : null;
    estado = json['estado'] is Map ? Map<String, dynamic>.from(json['estado']) : null;
    regime = json['regime'] is Map ? Map<String, dynamic>.from(json['regime']) : null;
    fileAttachment = json['fileAttachment'] is Map ? Map<String, dynamic>.from(json['fileAttachment']) : null;
    aplicativo = json['aplicativo'] != null
        ? Aplicativo.fromJson(json['aplicativo'])
        : null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nome': nome,
      'razaoSocial': razaoSocial,
      'email': email,
      'site': site,
      'contato': contato,
      'emailContato': emailContato,
      'telefoneContato': telefoneContato,
      'telefone': telefone,
      'rua': rua,
      'numero': numero,
      'cidade': cidade,
      'cep': cep,
      'cnpj': cnpj,
      'ie': ie,
      'ambiente': ambiente,
      'pais': pais,
      'estado': estado,
      'regime': regime,
      'fileAttachment': fileAttachment,
      'aplicativo': aplicativo?.toJson(),
    };
  }

  static Future<List<Map<String, dynamic>>> loadAplicativos() async {
    final response = await NetworkCaller().getRequest(ApiLinks.allAplicativos);

    if (response.isSuccess && response.body != null) {
      final lista = response.body!["data"]["dados"] as List;
      return lista
          .map((e) => {"value": e["id"].toString(), "label": e["nome"]})
          .toList();
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> loadCategorias() async {
    final response =
        await NetworkCaller().getRequest(ApiLinks.allRegimetributario);

    if (response.isSuccess && response.body != null) {
      final lista = response.body!["data"]["dados"] as List;
      return lista
          .map((e) => {"value": e["id"].toString(), "label": e["codigo"]})
          .toList();
    }
    return [];
  }

  /// NOVO — AGORA usando FieldConfigWindows
  static List<FieldConfigWindows> fieldConfigs = [
    const FieldConfigWindows(
      label: "Nome",
      fieldName: "nome",
      icon: Icons.business,
      isInForm: true,
      isFilterable: true,
      isVisibleByDefault: true,
    ),
    const FieldConfigWindows(
      label: "Razão Social",
      fieldName: "razaoSocial",
      icon: Icons.apartment,
      isInForm: true,
    ),
    const FieldConfigWindows(
      label: "Email",
      fieldName: "email",
      fieldType: FieldType.email,
      icon: Icons.email,
      isInForm: true,
    ),
    const FieldConfigWindows(
      label: "Email Contato",
      fieldName: "emailContato",
      fieldType: FieldType.email,
      icon: Icons.alternate_email,
      isInForm: true,
    ),
    const FieldConfigWindows(
      label: "Telefone",
      fieldName: "telefone",
      fieldType: FieldType.phone,
      icon: Icons.phone,
      isInForm: true,
    ),
    const FieldConfigWindows(
      label: "Telefone Contato",
      fieldName: "telefoneContato",
      fieldType: FieldType.phone,
      icon: Icons.phone_in_talk,
      isInForm: true,
    ),
    const FieldConfigWindows(
      label: "Contato",
      fieldName: "contato",
      icon: Icons.person,
      isInForm: true,
    ),
    const FieldConfigWindows(
      label: "Site",
      fieldName: "site",
      fieldType: FieldType.url,
      icon: Icons.language,
      isInForm: true,
    ),
    const FieldConfigWindows(
      label: "CEP",
      fieldName: "cep",
      fieldType: FieldType.cep,
      icon: Icons.search,
      isInForm: true,
    ),
    const FieldConfigWindows(
      label: "Rua",
      fieldName: "rua",
      icon: Icons.location_on,
      isInForm: true,
    ),
    const FieldConfigWindows(
      label: "Número",
      fieldName: "numero",
      icon: Icons.numbers,
      isInForm: true,
    ),
    const FieldConfigWindows(
      label: "Cidade",
      fieldName: "cidade",
      icon: Icons.location_city,
      isInForm: true,
      isFilterable: true,
    ),
    // ---- DROPDOWN Aplicativo ----
    const FieldConfigWindows(
      label: "Aplicativo",
      fieldName: "aplicativo",
      displayFieldName: "aplicativo.nome",
      fieldType: FieldType.dropdown,
      icon: Icons.apps,
      dropdownFutureBuilder: Empresa.loadAplicativos,
      dropdownValueField: "value",
      dropdownDisplayField: "label",
      isInForm: true,
      isRequired: true,
    ),
    // ---- DROPDOWN Regime ----
    const FieldConfigWindows(
      label: "Regime Tributário",
      fieldName: "regime",
      displayFieldName: "regime.codigo",
      fieldType: FieldType.dropdown,
      icon: Icons.business_center,
      dropdownFutureBuilder: Empresa.loadCategorias,
      dropdownValueField: "value",
      dropdownDisplayField: "label",
      isInForm: true,
    ),
  ];
}
