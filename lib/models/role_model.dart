import 'package:flutter/material.dart';
import '../customization/generic_grid_card.dart';
import '../../../models/aplicativo_model.dart';
import '../../../config/api_links.dart';
import '../../../models/network_response.dart';
import '../../services/network_caller.dart';

class Role {
  int? id;
  String? description;
  bool? available;
  String? key;
  Aplicativo? aplicativo;
  String? moduloNecessario;

  Role({
    this.id,
    this.description,
    this.available,
    this.key,
    this.aplicativo,
    this.moduloNecessario,
  });

  Role.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    description = json['description'];
    available = json['available'];
    key = json['key'];
    aplicativo = json['aplicativo'] != null
        ? Aplicativo.fromJson(json['aplicativo'])
        : null;
    moduloNecessario = json['moduloNecessario'];
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'description': description,
      'available': available,
      'key': key,
      'aplicativo': aplicativo?.toJson(),
      'moduloNecessario': moduloNecessario,
    };
  }

  static Future<List<Map<String, dynamic>>> loadCategorias() async {
    final NetworkResponse response = await NetworkCaller().getRequest(
      ApiLinks.allAplicativos,
    );

    if (response.isSuccess && response.body != null) {
      final List<dynamic> data = response.body!['data']['dados'] ?? [];
      return data
          .map(
            (item) => {'value': item['id'].toString(), 'label': item['nome']},
          )
          .toList();
    }
    return [];
  }

  static List<FieldConfig> fieldConfigs = [
    const FieldConfig(
      label: "Descrição",
      fieldName: "description",
      icon: Icons.description,
      isInForm: true,
      isFilterable: true,
    ),
    const FieldConfig(
      label: "Disponível",
      fieldName: "available",
      icon: Icons.check_circle,
      isInForm: true,
      isFilterable: true,
    ),
    const FieldConfig(
      label: "Chave",
      fieldName: "key",
      icon: Icons.vpn_key,
      isInForm: true,
      isFilterable: true,
    ),
    FieldConfig(
      label: "Aplicativo",
      fieldName: "aplicativo", // Para o formulário (dropdown)
      displayFieldName: "aplicativo.nome", // Para exibição na grid
      icon: Icons.apps,
      isInForm: true,
      isFilterable: true,
      fieldType: FieldType.dropdown,
      dropdownFutureBuilder: () async {
        return await loadCategorias();
      },
      dropdownValueField: 'id',
      dropdownDisplayField: 'nome',
      isRequired: true,
    ),
  ];
}

class RolesModel {
  List<Role>? roles;

  RolesModel({this.roles});

  RolesModel.fromJson(Map<String, dynamic> json) {
    if (json['data'] != null) {
      roles = <Role>[];
      json['data'].forEach((v) {
        roles!.add(Role.fromJson(v));
      });
    }
  }
}
