import '../config/api_links.dart';
import '../models/sistema_log_model.dart';
import 'network_caller.dart';

class SistemaLogService {
  final NetworkCaller _caller;

  SistemaLogService({NetworkCaller? caller}) : _caller = caller ?? NetworkCaller();

  Future<List<SistemaLogModel>> listarLogs({
    String? nivel,
    String? origem,
    String? busca,
    int? empresaId,
    int? parceiroId,
    String? usuario,
    String? plataforma,
    DateTime? dataInicio,
    DateTime? dataFim,
    int page = 0,
    int size = 50,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'size': size.toString(),
    };
    if (nivel != null && nivel.isNotEmpty && nivel != 'TODOS') params['nivel'] = nivel;
    if (origem != null && origem.isNotEmpty && origem != 'TODOS') params['origem'] = origem;
    if (busca != null && busca.trim().isNotEmpty) params['busca'] = busca.trim();
    if (empresaId != null) params['empresaId'] = empresaId.toString();
    if (parceiroId != null) params['parceiroId'] = parceiroId.toString();
    if (usuario != null && usuario.trim().isNotEmpty) params['usuario'] = usuario.trim();
    if (plataforma != null && plataforma.isNotEmpty && plataforma != 'TODAS') params['plataforma'] = plataforma;
    if (dataInicio != null) params['dataInicio'] = dataInicio.toUtc().toIso8601String();
    if (dataFim != null) params['dataFim'] = dataFim.toUtc().toIso8601String();

    final uri = Uri.parse(ApiLinks.sistemaLogs).replace(queryParameters: params);
    final resp = await _caller.getRequest(uri.toString());

    if (!resp.isSuccess || resp.body == null) {
      return [];
    }

    final data = resp.body!;
    final dynamic content = data['content'] ?? data['data'];
    if (content is List) {
      return content
          .whereType<Map<String, dynamic>>()
          .map((m) => SistemaLogModel.fromJson(m))
          .toList();
    }
    return [];
  }

  Future<SistemaLogMetricasModel?> obterMetricas() async {
    final resp = await _caller.getRequest(ApiLinks.sistemaLogsMetricas);
    if (resp.isSuccess && resp.body != null) {
      return SistemaLogMetricasModel.fromJson(resp.body!);
    }
    return null;
  }

  Future<int> expurgarLogs({int dias = 7}) async {
    final resp = await _caller.deleteRequest(ApiLinks.expurgarSistemaLogs(dias));
    if (resp.isSuccess && resp.body != null) {
      final val = resp.body!['data'] ?? resp.body!['valor'];
      if (val is int) return val;
      if (val != null) return int.tryParse(val.toString()) ?? 0;
    }
    return 0;
  }
}
