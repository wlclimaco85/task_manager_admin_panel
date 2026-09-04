import 'package:flutter/material.dart';

import '../customization/generic_grid_card.dart';

class Aplicativo {
  int? id;
  String? nome;
  String? observacao;

  Aplicativo({this.id, this.nome, this.observacao});

  Aplicativo.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    nome = json['nome'];
    observacao = json['observacao'];
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'nome': nome, 'observacao': observacao};
  }

  static List<FieldConfig> fieldConfigs = [
    const FieldConfig(
      label: "ID",
      fieldName: "id",
      icon: Icons.numbers,
      isInForm: true,
      isFilterable: true,
    ),
    const FieldConfig(
      label: "Nome",
      fieldName: "nome",
      icon: Icons.label,
      isInForm: true,
      isFilterable: true,
    ),
    const FieldConfig(
      label: "Observação",
      fieldName: "observacao",
      icon: Icons.description,
      isInForm: true,
      isFilterable: true,
    ),
  ];
}
