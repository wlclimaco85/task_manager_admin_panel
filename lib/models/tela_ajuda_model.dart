class TelaAjudaModel {
  final int? id;
  final TelaAjudaTela? tela;
  final String titulo;
  final String? resumo;
  final String? comoUsar;
  final String? camposImportantes;
  final String? observacoes;
  final bool ativo;

  const TelaAjudaModel({
    this.id,
    this.tela,
    required this.titulo,
    this.resumo,
    this.comoUsar,
    this.camposImportantes,
    this.observacoes,
    this.ativo = true,
  });

  factory TelaAjudaModel.fromJson(Map<String, dynamic> json) {
    final telaJson = json['tela'];
    return TelaAjudaModel(
      id: _intValue(json['id']),
      tela: telaJson is Map
          ? TelaAjudaTela.fromJson(Map<String, dynamic>.from(telaJson))
          : null,
      titulo: json['titulo']?.toString() ?? '',
      resumo: _text(json['resumo']),
      comoUsar: _text(json['comoUsar'] ?? json['como_usar']),
      camposImportantes:
          _text(json['camposImportantes'] ?? json['campos_importantes']),
      observacoes: _text(json['observacoes']),
      ativo: json['ativo'] == null ? true : json['ativo'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (tela != null) 'tela': {'id': tela!.id},
        'titulo': titulo,
        'resumo': resumo,
        'comoUsar': comoUsar,
        'camposImportantes': camposImportantes,
        'observacoes': observacoes,
        'ativo': ativo,
      };
}

class TelaAjudaTela {
  final int? id;
  final String? nome;
  final String? titulo;

  const TelaAjudaTela({this.id, this.nome, this.titulo});

  factory TelaAjudaTela.fromJson(Map<String, dynamic> json) {
    return TelaAjudaTela(
      id: _intValue(json['id']),
      nome: _text(json['nome']),
      titulo: _text(json['titulo']),
    );
  }
}

String? _text(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int? _intValue(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value == null) return null;
  return int.tryParse(value.toString());
}
