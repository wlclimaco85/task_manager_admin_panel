import 'package:flutter/material.dart';
import '../customization/generic_grid_card.dart';

class Setor {
  int? id;
  String? nome;

  Setor({this.id, this.nome});

  Setor.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    // backend usa 'descricao', mas aceita 'nome' também
    nome = json['descricao']?.toString() ?? json['nome']?.toString();
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'nome': nome, 'descricao': nome};
  }

  static List<FieldConfig> fieldConfigs = [
    const FieldConfig(
      label: "Nome",
      fieldName: "nome",
      icon: Icons.apartment,
      isInForm: true,
      isFilterable: true,
    ),
  ];
}
