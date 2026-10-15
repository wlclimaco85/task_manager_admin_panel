class ModuloServicoTelaModel {
  final int id;
  final int moduloId;
  final String moduloNome;
  final String telaNome;
  final String? rotaApi;
  final String? descricao;
  final bool ativo;

  ModuloServicoTelaModel({
    required this.id,
    required this.moduloId,
    required this.moduloNome,
    required this.telaNome,
    this.rotaApi,
    this.descricao,
    required this.ativo,
  });

  factory ModuloServicoTelaModel.fromJson(Map<String, dynamic> json) {
    final mod = json['modulo'] is Map ? json['modulo'] as Map<String, dynamic> : null;
    return ModuloServicoTelaModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      moduloId: mod != null && mod['id'] != null
          ? (mod['id'] is int ? mod['id'] : int.tryParse(mod['id'].toString()) ?? 0)
          : (json['moduloId'] is int ? json['moduloId'] : int.tryParse(json['moduloId']?.toString() ?? '0') ?? 0),
      moduloNome: mod != null && mod['nome'] != null
          ? mod['nome'].toString()
          : (json['moduloNome']?.toString() ?? 'Módulo Geral'),
      telaNome: json['telaNome']?.toString() ?? '',
      rotaApi: json['rotaApi']?.toString(),
      descricao: json['descricao']?.toString(),
      ativo: json['ativo'] == true || json['ativo'] == 1 || json['ativo']?.toString() == 'true',
    );
  }

  Map<String, dynamic> toJson() => {
    if (id > 0) 'id': id,
    'modulo': {'id': moduloId},
    'telaNome': telaNome,
    'rotaApi': rotaApi,
    'descricao': descricao,
    'ativo': ativo,
  };
}
