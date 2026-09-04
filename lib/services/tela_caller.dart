import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/network_caller.dart';
import '../../../config/api_links.dart';
import '../models/telas_model.dart';
import '../../../utils/app_logger.dart';

class TelaService {
  final NetworkCaller networkCaller;
  late Future<SharedPreferences> _prefs;

  TelaService({required this.networkCaller}) {
    _prefs = SharedPreferences.getInstance();
  }

  // 🔍 Busca tela por nome diretamente da API
  // Retorna null se não encontrou; lança _TelaHttpException para erros definitivos (4xx)
  Future<TelaConfig?> getTelaByNome(String nome, {int? empId, int? clienteId}) async {
    try {
      final url = '';
      AppLogger.i
          .info('🌐 [TelaService] Chamando API para obter tela "$nome" → $url');

      final response = await networkCaller.getRequest(url);

      AppLogger.i.info('📡 [TelaService] Resposta recebida: '
          'status=${response.statusCode}, sucesso=${response.isSuccess}');
      AppLogger.i.info('🧠 [TelaService] Corpo bruto: ${response.body}');

      if (response.statusCode == -1) {
        AppLogger.i.info('⚠️ [TelaService] NetworkCaller retornou status -1 → '
            'provável erro de conexão, timeout ou URL inválida.');
      }

      // Erros definitivos — não adianta retentar
      if (response.statusCode == 400 ||
          response.statusCode == 403 ||
          response.statusCode == 404) {
        AppLogger.i.info(
            '🚫 [TelaService] Erro definitivo ${response.statusCode} para "$nome". Não vai retentar.');
        throw _TelaHttpException(response.statusCode);
      }

      if (response.isSuccess && response.body != null) {
        final body = response.body!;

        // Endpoint GET /api/telas/{nome} retorna Tela diretamente
        final bodyMap = body as Map?;
        if (bodyMap != null && bodyMap.containsKey('id')) {
          AppLogger.i.info('✅ [TelaService] Tela recebida diretamente.');
          return TelaConfig.fromJson(Map<String, dynamic>.from(bodyMap));
        }

        // Fallback: estrutura paginada {data: {dados: [...]}}
        final data = body['data'];
        final dados = data != null ? data['dados'] : null;

        if (dados == null) {
          AppLogger.i.info('⚠️ [TelaService] Nenhum campo "dados" encontrado. '
              'Estrutura recebida: ${response.body}');
          return null;
        }

        if (dados is List && dados.isNotEmpty) {
          AppLogger.i.info(
              '✅ [TelaService] Estrutura de lista detectada (${dados.length} itens).');
          final primeiro = dados.first;
          if (primeiro is Map<String, dynamic>) {
            AppLogger.i.info(
                '✅ [TelaService] Convertendo primeiro item em TelaConfig.');
            return TelaConfig.fromJson(Map<String, dynamic>.from(primeiro));
          } else {
            AppLogger.i.info(
                '❌ [TelaService] Tipo inesperado dentro da lista: ${primeiro.runtimeType}');
          }
        } else if (dados is Map<String, dynamic>) {
          AppLogger.i.info(
              '✅ [TelaService] Estrutura única detectada, convertendo...');
          return TelaConfig.fromJson(dados);
        } else {
          AppLogger.i.info(
              '❌ [TelaService] Tipo de "dados" não suportado: ${dados.runtimeType}');
        }
      } else {
        AppLogger.i.info(
            '❌ [TelaService] Requisição falhou: status=${response.statusCode}');
      }

      return null;
    } on _TelaHttpException {
      rethrow;
    } catch (e, stack) {
      AppLogger.i.info('💥 [TelaService] Erro ao buscar tela "$nome": $e');
      AppLogger.i.info('📄 StackTrace: $stack');
      return null;
    }
  }

  // 🔧 Buscar preferências de campos
  Future<List<UserFieldPreference>> getUserPreferences(
      int telaId, int userId) async {
    try {
      final response = await networkCaller.getRequest(
        '',
      );

      AppLogger.i.info(
          '⚙️ [TelaService] getUserPreferences resposta: ${response.statusCode}');

      if (response.isSuccess && response.body != null) {
        return (response.body! as List)
            .map((pref) => UserFieldPreference.fromJson(pref))
            .toList();
      }
      return [];
    } catch (e) {
      AppLogger.i.info('💥 [TelaService] Erro ao buscar preferências: $e');
      return [];
    }
  }

  // 💾 Salvar preferências do usuário
  Future<bool> saveUserPreferences(
      int telaId, int userId, Map<String, bool> fieldVisibility) async {
    try {
      final response = await networkCaller.postRequest(
        '',
        fieldVisibility,
      );

      AppLogger.i.info(
          '💾 [TelaService] Salvando preferências → ${response.statusCode}');
      return response.isSuccess;
    } catch (e) {
      AppLogger.i.info('💥 [TelaService] Erro ao salvar preferências: $e');
      return false;
    }
  }

  // 🧱 Salvar tela em cache local
  Future<void> saveTelaToCache(String nome, TelaConfig tela) async {
    final prefs = await _prefs;
    final jsonData = tela.toJson();

    AppLogger.i.info('💾 [TelaService] Salvando tela "$nome" no cache...');
    AppLogger.i.info('📦 JSON salvo: $jsonData');

    await prefs.setString('tela_$nome', json.encode(jsonData));
  }

  /// Limpa todo o cache de telas (SharedPreferences com prefixo 'tela_')
  static Future<void> clearAllTelaCache() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('tela_')).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
    AppLogger.i.info('🗑️ [TelaService] Cache de telas limpo (${keys.length} entradas)');
  }

  // 🔍 Buscar tela sempre da API (cache apenas como fallback de conexão)
  Future<TelaConfig?> getTelaFromCache(String nome, {int? empId, int? clienteId}) async {
    // Sempre busca da API para garantir config atualizada (endpoints, dropdowns, etc.)
    final fresh = await _getFromApiWithRetry(nome, empId: empId, clienteId: clienteId);
    if (fresh != null) return fresh;

    // Fallback: usa cache se API não respondeu
    try {
      final prefs = await _prefs;
      final cached = prefs.getString('tela_$nome');
      if (cached == null || cached.isEmpty) return null;
      final decoded = json.decode(cached);
      if (decoded is Map<String, dynamic> && _isCacheValid(decoded)) {
        AppLogger.i.info('⚠️ [TelaService] API indisponível — usando cache para "$nome"');
        return TelaConfig.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  bool _isCacheValid(Map<String, dynamic> decoded) {
    return decoded['id'] != null &&
        decoded['id'] > 0 &&
        decoded['nome'] != null &&
        decoded['nome'].toString().isNotEmpty;
  }

  // 🔁 Tenta buscar a tela até 3 vezes da API (apenas em erros transitórios)
  Future<TelaConfig?> _getFromApiWithRetry(String nome, {int? empId, int? clienteId}) async {
    const maxTentativas = 3;
    for (int tentativa = 1; tentativa <= maxTentativas; tentativa++) {
      AppLogger.i.info(
          '🔄 [TelaService] Tentativa $tentativa/$maxTentativas para buscar "$nome"...');

      try {
        final freshTela = await getTelaByNome(nome, empId: empId, clienteId: clienteId);

        if (freshTela != null) {
          AppLogger.i.info(
              '✅ [TelaService] Tela encontrada na tentativa $tentativa: ${freshTela.nome}');
          await saveTelaToCache(nome, freshTela);
          return freshTela;
        } else {
          AppLogger.i.info(
              '⚠️ [TelaService] Tentativa $tentativa falhou (retornou null).');
          return null;
        }
      } on _TelaHttpException catch (e) {
        AppLogger.i.info(
            '🚫 [TelaService] Erro HTTP definitivo ${e.statusCode} para "$nome". Abortando retentativas.');
        return null;
      } catch (e) {
        AppLogger.i.info('💥 [TelaService] Erro na tentativa $tentativa: $e');
        if (tentativa < maxTentativas) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }

    AppLogger.i
        .info('💀 [TelaService] Todas as tentativas falharam para "$nome".');
    return null;
  }
}

// Exceção interna para erros HTTP definitivos (não retentar)
class _TelaHttpException implements Exception {
  final int statusCode;
  _TelaHttpException(this.statusCode);
}
