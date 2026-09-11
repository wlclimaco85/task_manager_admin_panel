import 'dart:async';

import 'package:http/http.dart' as http;

import '../config/api_links.dart';
import '../utils/app_logger.dart';
import 'network_caller.dart';
import 'sistema_log_service.dart';

/// Status de um servico monitorado.
enum ServerStatus { checking, online, offline }

/// Resultado consolidado de uma verificacao de saude.
class ServerStatusResult {
  final ServerStatus backend;
  final ServerStatus frontendWeb;
  final int totalExcecoes;
  final DateTime verificadoEm;

  const ServerStatusResult({
    required this.backend,
    required this.frontendWeb,
    required this.totalExcecoes,
    required this.verificadoEm,
  });

  static ServerStatusResult checking() => ServerStatusResult(
        backend: ServerStatus.checking,
        frontendWeb: ServerStatus.checking,
        totalExcecoes: 0,
        verificadoEm: DateTime.now(),
      );
}

/// Verifica a saude dos servicos da plataforma Railway.
///
/// - Backend: GET /actuator/health — considera online se status 2xx ou 4xx
///   (qualquer resposta do servidor, mesmo autenticacao bloqueada).
///   Offline apenas em timeout ou erro de conexao ou 5xx.
/// - Frontend Web: HEAD na URL configurada via FRONTEND_WEB_URL.
///   Se vazio, retorna [ServerStatus.offline] com indicacao nao configurado.
/// - Excecoes: usa [SistemaLogService.obterMetricas()] para pegar countErro.
class ServerStatusService {
  ServerStatusService({NetworkCaller? caller})
      : _caller = caller ?? NetworkCaller(),
        _logService = SistemaLogService(caller: caller ?? NetworkCaller());

  final NetworkCaller _caller;
  final SistemaLogService _logService;

  static const Duration _timeout = Duration(seconds: 10);

  Future<ServerStatusResult> checkAll() async {
    final results = await Future.wait([
      _checkBackend(),
      _checkFrontendWeb(),
      _countExcecoes(),
    ]);

    return ServerStatusResult(
      backend: results[0] as ServerStatus,
      frontendWeb: results[1] as ServerStatus,
      totalExcecoes: results[2] as int,
      verificadoEm: DateTime.now(),
    );
  }

  Future<ServerStatus> _checkBackend() async {
    try {
      final response = await _caller
          .getRequest(ApiLinks.backendHealth)
          .timeout(_timeout);
      // < 500: online mesmo com 4xx (ex.: auth bloqueada, mas servidor de pe).
      // >= 500 (ex.: Actuator retorna 503 quando a app esta DOWN) conta como
      // offline -- alinhado com _checkFrontendWeb logo abaixo.
      if (response.statusCode < 500) {
        return ServerStatus.online;
      }
      AppLogger.i.warn(
          'ServerStatusService: backend respondeu status ${response.statusCode} (tratado como offline)');
      return ServerStatus.offline;
    } catch (e) {
      AppLogger.i.warn('ServerStatusService: falha ao checar backend: $e');
      return ServerStatus.offline;
    }
  }

  Future<ServerStatus> _checkFrontendWeb() async {
    final url = ApiLinks.frontendWebUrl;
    if (url.isEmpty) return ServerStatus.offline;
    try {
      final response = await http.head(Uri.parse(url)).timeout(_timeout);
      return (response.statusCode < 500)
          ? ServerStatus.online
          : ServerStatus.offline;
    } catch (e) {
      AppLogger.i.warn('ServerStatusService: falha ao checar frontend web: $e');
      return ServerStatus.offline;
    }
  }

  Future<int> _countExcecoes() async {
    try {
      final metricas = await _logService.obterMetricas();
      return metricas?.totalErros24h ?? 0;
    } catch (e) {
      AppLogger.i.warn('ServerStatusService: falha ao obter metricas de excecoes: $e');
      return 0;
    }
  }
}
