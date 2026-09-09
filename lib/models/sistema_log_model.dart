class SistemaLogModel {
  final int? id;
  final DateTime? timestamp;
  final String nivel;
  final String origem;
  final String mensagem;
  final String? detalhes;
  final String? classeOuRota;
  final String? usuario;
  final int? empresaId;
  final int? parceiroId;
  final String? versaoApp;
  final String? ambiente;

  SistemaLogModel({
    this.id,
    this.timestamp,
    required this.nivel,
    required this.origem,
    required this.mensagem,
    this.detalhes,
    this.classeOuRota,
    this.usuario,
    this.empresaId,
    this.parceiroId,
    this.versaoApp,
    this.ambiente,
  });

  factory SistemaLogModel.fromJson(Map<String, dynamic> json) {
    return SistemaLogModel(
      id: json['id'] is int ? json['id'] : (json['id'] != null ? int.tryParse(json['id'].toString()) : null),
      timestamp: json['timestamp'] != null ? DateTime.tryParse(json['timestamp'].toString())?.toLocal() : null,
      nivel: json['nivel']?.toString().toUpperCase() ?? 'INFO',
      origem: json['origem']?.toString().toUpperCase() ?? 'DESCONHECIDO',
      mensagem: json['mensagem']?.toString() ?? '',
      detalhes: json['detalhes']?.toString(),
      classeOuRota: json['classeOuRota']?.toString(),
      usuario: json['usuario']?.toString(),
      empresaId: json['empresaId'] is int ? json['empresaId'] : (json['empresaId'] != null ? int.tryParse(json['empresaId'].toString()) : null),
      parceiroId: json['parceiroId'] is int ? json['parceiroId'] : (json['parceiroId'] != null ? int.tryParse(json['parceiroId'].toString()) : null),
      versaoApp: json['versaoApp']?.toString(),
      ambiente: json['ambiente']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (timestamp != null) 'timestamp': timestamp!.toUtc().toIso8601String(),
      'nivel': nivel,
      'origem': origem,
      'mensagem': mensagem,
      if (detalhes != null) 'detalhes': detalhes,
      if (classeOuRota != null) 'classeOuRota': classeOuRota,
      if (usuario != null) 'usuario': usuario,
      if (empresaId != null) 'empresaId': empresaId,
      if (parceiroId != null) 'parceiroId': parceiroId,
      if (versaoApp != null) 'versaoApp': versaoApp,
      if (ambiente != null) 'ambiente': ambiente,
    };
  }
}

class SistemaLogMetricasModel {
  final int totalErros24h;
  final int totalWarnings24h;
  final int totalErrosBackend24h;
  final int totalErrosApp24h;
  final int totalLogs7dias;

  SistemaLogMetricasModel({
    required this.totalErros24h,
    required this.totalWarnings24h,
    required this.totalErrosBackend24h,
    required this.totalErrosApp24h,
    required this.totalLogs7dias,
  });

  factory SistemaLogMetricasModel.fromJson(Map<String, dynamic> json) {
    return SistemaLogMetricasModel(
      totalErros24h: _toInt(json['totalErros24h']),
      totalWarnings24h: _toInt(json['totalWarnings24h']),
      totalErrosBackend24h: _toInt(json['totalErrosBackend24h']),
      totalErrosApp24h: _toInt(json['totalErrosApp24h']),
      totalLogs7dias: _toInt(json['totalLogs7dias']),
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value != null) return int.tryParse(value.toString()) ?? 0;
    return 0;
  }
}
