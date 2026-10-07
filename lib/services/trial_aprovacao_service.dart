import 'dart:convert';

import '../config/api_links.dart';
import '../utils/app_logger.dart';
import '../utils/tenant_context.dart';
import '../widgets/generic_grid_windows_screen.dart';
import 'network_caller.dart';

/// Falha de negocio/rede ao aprovar uma solicitacao de trial. A mensagem e
/// pensada para ser mostrada ao usuario.
class TrialAprovacaoException implements Exception {
  const TrialAprovacaoException(this.mensagem);
  final String mensagem;

  @override
  String toString() => mensagem;
}

/// Resultado do mapeamento dos NOMES de modulos da solicitacao para os ids do
/// catalogo `modulo_servico`.
class ModulosMapeados {
  const ModulosMapeados({
    required this.ids,
    required this.nomesVinculados,
    required this.naoEncontrados,
  });

  final List<int> ids;
  final List<String> nomesVinculados;
  final List<String> naoEncontrados;

  bool get temCorrespondencia => ids.isNotEmpty;
}

/// Cliente (Parceiro) preparado para a concessao de licenca: parceiro
/// garantido + modulos vinculados. Guarda o estado anterior para permitir a
/// compensacao caso o fluxo seja cancelado antes da conclusao.
class ClienteTrialPreparado {
  ClienteTrialPreparado({
    required this.parceiroId,
    required this.parceiroNome,
    required this.parceiroCriado,
    required this.empresaId,
    required this.modulos,
    required this.modulosNomes,
    required this.modulosAnteriores,
    required this.modulosAlterados,
  });

  final int parceiroId;
  final String parceiroNome;

  /// `true` quando o parceiro foi criado por este fluxo (e nao reaproveitado).
  final bool parceiroCriado;
  final int? empresaId;
  final ModulosMapeados modulos;

  /// Nomes de TODOS os modulos do cliente apos o vinculo (anteriores + novos).
  final List<String> modulosNomes;

  /// Vinculos que o parceiro ja tinha antes (com valor/dia de vencimento).
  final List<Map<String, dynamic>> modulosAnteriores;

  /// `true` se o POST de vinculo foi executado (precisa ser revertido).
  final bool modulosAlterados;

  /// Logins criados durante o popup (etapa 2) — removidos se cancelar.
  final List<int> loginsCriados = <int>[];
}

/// Fluxo do botao "Aprovar" de Solicitacoes de Trial: transforma a solicitacao
/// em um cliente com licenca e modulos (mesmo processo de "Atribuicao de
/// Modulos"). Destinatario: **Parceiro** (cliente) sob a empresa do usuario
/// master logado — e' o destinatario que aparece em "Clientes com Licencas &
/// Modulos" (resumo) e o padrao da tela de atribuicao.
class TrialAprovacaoService {
  TrialAprovacaoService({NetworkCaller? caller, int? Function()? empresaIdProvider})
      : _caller = caller ?? NetworkCaller(),
        _donoDoCaller = caller == null,
        _empresaIdProvider = empresaIdProvider ?? (() => TenantContext.empresaId);

  final NetworkCaller _caller;
  final bool _donoDoCaller;
  final int? Function() _empresaIdProvider;

  void close() {
    if (_donoDoCaller) _caller.close();
  }

  // ---------------------------------------------------------------------------
  // Funcoes puras (testaveis sem rede)
  // ---------------------------------------------------------------------------

  /// A solicitacao guarda os modulos como JSON array de NOMES (ex.: ["NFC-e"]).
  /// Aceita tambem lista ja decodificada ou texto separado por virgula.
  static List<String> parseModulosNomes(dynamic bruto) {
    if (bruto == null) return const [];
    dynamic valor = bruto;
    if (valor is String) {
      final texto = valor.trim();
      if (texto.isEmpty) return const [];
      try {
        valor = jsonDecode(texto);
      } catch (_) {
        valor = texto.split(',');
      }
    }
    if (valor is! List) return const [];
    final vistos = <String>{};
    final nomes = <String>[];
    for (final item in valor) {
      final nome = (item is Map ? (item['nome'] ?? item['name']) : item)
              ?.toString()
              .trim() ??
          '';
      if (nome.isNotEmpty && vistos.add(normalizar(nome))) nomes.add(nome);
    }
    return nomes;
  }

  /// Minusculas, sem acentos e so' letras/numeros ("NFC-e" == "NFCe").
  static String normalizar(String texto) {
    const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const para = 'aaaaaeeeeiiiiooooouuuucn';
    final buffer = StringBuffer();
    for (final unidade in texto.toLowerCase().runes) {
      final c = String.fromCharCode(unidade);
      final idx = de.indexOf(c);
      final mapeado = idx >= 0 ? para[idx] : c;
      if (RegExp(r'[a-z0-9]').hasMatch(mapeado)) buffer.write(mapeado);
    }
    return buffer.toString();
  }

  /// Mapeia nomes -> ids do catalogo. Nomes sem correspondencia sao devolvidos
  /// em [ModulosMapeados.naoEncontrados] (nunca descartados em silencio).
  static ModulosMapeados mapearModulos(
      List<String> nomes, List<Map<String, dynamic>> catalogo) {
    final porNome = <String, Map<String, dynamic>>{};
    for (final modulo in catalogo) {
      final nome = (modulo['nome'] ?? '').toString();
      final id = _toInt(modulo['id'] ?? modulo['moduloId']);
      if (nome.isEmpty || id == null) continue;
      porNome.putIfAbsent(normalizar(nome), () => modulo);
    }
    final ids = <int>[];
    final vinculados = <String>[];
    final faltantes = <String>[];
    for (final nome in nomes) {
      final modulo = porNome[normalizar(nome)];
      final id = modulo == null ? null : _toInt(modulo['id'] ?? modulo['moduloId']);
      if (id == null) {
        faltantes.add(nome);
      } else if (!ids.contains(id)) {
        ids.add(id);
        vinculados.add((modulo!['nome'] ?? nome).toString());
      }
    }
    return ModulosMapeados(
        ids: ids, nomesVinculados: vinculados, naoEncontrados: faltantes);
  }

  /// Decisao pos-popup: so' marca APROVADO se o popup concluiu (true). Cancelar
  /// (false/null) mantem PENDENTE e dispara a compensacao.
  static bool deveMarcarAprovado(bool? resultadoPopup) => resultadoPopup == true;

  /// Documento (CNPJ tem prioridade sobre CPF), so' digitos.
  static String documentoDaSolicitacao(Map<String, dynamic> solicitacao) {
    final cnpj = _digitos(solicitacao['cnpj']?.toString() ?? '');
    if (cnpj.isNotEmpty) return cnpj;
    return _digitos(solicitacao['cpf']?.toString() ?? '');
  }

  // ---------------------------------------------------------------------------
  // Rede
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> carregarCatalogo() async {
    final res = await _caller.getRequest(ApiLinks.allModulosServico);
    if (!res.isSuccess) {
      throw TrialAprovacaoException(_mensagemHttp(
          'Nao foi possivel carregar o catalogo de modulos', res.statusCode));
    }
    return GenericGridWindowsScreen.extractRows(res.body);
  }

  /// Garante o parceiro (reaproveita por CNPJ/CPF ou e-mail; senao cria) e
  /// vincula os modulos mapeados, preservando os que o cliente ja tinha. Se
  /// qualquer passo falhar, desfaz o que ja foi feito e relanca a falha.
  Future<ClienteTrialPreparado> prepararCliente(
      Map<String, dynamic> solicitacao, ModulosMapeados mapa) async {
    if (!mapa.temCorrespondencia) {
      throw const TrialAprovacaoException(
          'Nenhum modulo da solicitacao existe no catalogo. Cadastre os modulos antes de aprovar.');
    }
    final empresaId = _empresaIdProvider();
    if (empresaId == null) {
      throw const TrialAprovacaoException(
          'Sessao sem empresa. Saia e entre novamente no Painel do Dono.');
    }

    int? parceiroId;
    String nome = (solicitacao['nome'] ?? '').toString().trim();
    var criado = false;
    var modulosAlterados = false;
    List<Map<String, dynamic>> anteriores = const [];
    try {
      final existente = await _buscarParceiroExistente(solicitacao);
      if (existente != null) {
        parceiroId = existente.$1;
        if (existente.$2.isNotEmpty) nome = existente.$2;
      } else {
        parceiroId = await _criarParceiro(solicitacao, empresaId);
        criado = true;
      }

      anteriores = criado ? const [] : await _modulosDoParceiro(parceiroId);
      final idsAnteriores = anteriores
          .map((m) => _toInt(m['id'] ?? m['moduloId']))
          .whereType<int>()
          .toList();
      final uniao = <int>{...idsAnteriores, ...mapa.ids}.toList();
      if (uniao.length != idsAnteriores.length) {
        modulosAlterados = true;
        await _vincularModulos(parceiroId, uniao, anteriores);
      }

      final nomes = <String>{
        ...anteriores.map((m) => (m['nome'] ?? '').toString()),
        ...mapa.nomesVinculados,
      }.where((n) => n.isNotEmpty).toList();

      return ClienteTrialPreparado(
        parceiroId: parceiroId,
        parceiroNome: nome.isEmpty ? 'Parceiro #$parceiroId' : nome,
        parceiroCriado: criado,
        empresaId: empresaId,
        modulos: mapa,
        modulosNomes: nomes,
        modulosAnteriores: anteriores,
        modulosAlterados: modulosAlterados,
      );
    } catch (e, st) {
      AppLogger.i.error('Aprovar trial: falha ao preparar cliente: $e', st);
      if (parceiroId != null) {
        await _compensar(
          parceiroId: parceiroId,
          parceiroCriado: criado,
          modulosAlterados: modulosAlterados,
          anteriores: anteriores,
          loginsCriados: const [],
        );
      }
      if (e is TrialAprovacaoException) rethrow;
      throw TrialAprovacaoException('Falha ao preparar o cliente: $e');
    }
  }

  /// Compensacao: usuario cancelou o popup (ou algo falhou depois do vinculo).
  /// Remove logins criados no popup, restaura os modulos anteriores e apaga o
  /// parceiro quando ele foi criado por este fluxo. Retorna `true` se tudo foi
  /// revertido; `false` (com log) se algo ficou para limpeza manual.
  Future<bool> desfazer(ClienteTrialPreparado cliente) {
    return _compensar(
      parceiroId: cliente.parceiroId,
      parceiroCriado: cliente.parceiroCriado,
      modulosAlterados: cliente.modulosAlterados,
      anteriores: cliente.modulosAnteriores,
      loginsCriados: cliente.loginsCriados,
    );
  }

  /// Marca a solicitacao (PUT simples, sem enriquecer o corpo).
  Future<void> atualizarStatus(int id, String status, {String? obs}) async {
    final res = await _caller.putRequest(
      ApiLinks.trialSolicitacaoStatus(id),
      {'status': status, if (obs != null && obs.isNotEmpty) 'obs': obs},
      enriquecerCorpo: false,
    );
    if (!res.isSuccess) {
      throw TrialAprovacaoException(
          _mensagemHttp('Falha ao atualizar o status da solicitacao', res.statusCode));
    }
  }

  // ---------------------------------------------------------------------------
  // Internos
  // ---------------------------------------------------------------------------

  /// (id, nome) do parceiro ja cadastrado com o mesmo documento ou e-mail.
  Future<(int, String)?> _buscarParceiroExistente(
      Map<String, dynamic> solicitacao) async {
    final documento = documentoDaSolicitacao(solicitacao);
    final email = (solicitacao['email'] ?? '').toString().trim().toLowerCase();
    final termos = <String>[
      if (documento.isNotEmpty) documento,
      if (email.isNotEmpty) email,
    ];
    for (final termo in termos) {
      final url = '${ApiLinks.allParceiros}?busca=${Uri.encodeQueryComponent(termo)}&tamanho=50';
      final res = await _caller.getRequest(url);
      if (!res.isSuccess) {
        throw TrialAprovacaoException(_mensagemHttp(
            'Nao foi possivel verificar se o cliente ja existe', res.statusCode));
      }
      for (final p in GenericGridWindowsScreen.extractRows(res.body)) {
        final doc = _digitos((p['cpf'] ?? p['cnpj'] ?? '').toString());
        final mail = (p['email'] ?? '').toString().trim().toLowerCase();
        final mesmoDoc = documento.isNotEmpty && doc == documento;
        final mesmoMail = documento.isEmpty && email.isNotEmpty && mail == email;
        final id = _toInt(p['id']);
        if (id != null && (mesmoDoc || mesmoMail)) {
          final nome =
              (p['nome'] ?? p['razaoSocial'] ?? p['razao_social'] ?? '').toString();
          return (id, nome);
        }
      }
    }
    return null;
  }

  Future<int> _criarParceiro(Map<String, dynamic> s, int empresaId) async {
    final documento = documentoDaSolicitacao(s);
    final localizacao = (s['localizacao'] ?? '').toString().trim();
    final uf = RegExp(r'([A-Za-z]{2})\s*$').firstMatch(localizacao)?.group(1);
    final cidade = uf == null
        ? localizacao
        : localizacao
            .substring(0, localizacao.length - uf.length)
            .replaceAll(RegExp(r'[\s,/\-]+$'), '')
            .trim();
    final payload = <String, dynamic>{
      'nome': (s['nome'] ?? '').toString().trim(),
      if (documento.isNotEmpty) 'cpf': documento,
      'email': (s['email'] ?? '').toString().trim(),
      if ((s['telefone'] ?? '').toString().isNotEmpty)
        'telefone1': s['telefone'].toString(),
      if (cidade.isNotEmpty) 'cidade': cidade,
      if (uf != null) 'estado': uf.toUpperCase(),
      'status': 'A',
      'tipo_cliente': 'CLIENTE',
      'empresa': {'id': empresaId},
      'tipos_parceiro': [
        {'id': 1}
      ],
    };
    final res = await _caller.postRequest(ApiLinks.insertParceiro, payload);
    if (!res.isSuccess) {
      throw TrialAprovacaoException(
          _mensagemHttp('Nao foi possivel cadastrar o cliente', res.statusCode));
    }
    final id = _extrairId(res.body);
    if (id == null) {
      throw const TrialAprovacaoException(
          'Cliente cadastrado, mas a API nao retornou o ID.');
    }
    return id;
  }

  Future<List<Map<String, dynamic>>> _modulosDoParceiro(int parceiroId) async {
    final res = await _caller.getRequest(ApiLinks.parceiroModulos(parceiroId.toString()));
    if (!res.isSuccess) {
      throw TrialAprovacaoException(_mensagemHttp(
          'Nao foi possivel ler os modulos atuais do cliente', res.statusCode));
    }
    return GenericGridWindowsScreen.extractRows(res.body);
  }

  /// POST de vinculo SUBSTITUI todo o conjunto (apaga e reinsere), o que zera
  /// valor mensal/dia de vencimento; por isso reaplica os valores anteriores.
  Future<void> _vincularModulos(
      int parceiroId, List<int> ids, List<Map<String, dynamic>> anteriores) async {
    final res = await _caller.postRequest(
        ApiLinks.vincularParceiroModulos, {'parceiroId': parceiroId, 'moduloIds': ids});
    if (!res.isSuccess) {
      throw TrialAprovacaoException(
          _mensagemHttp('Nao foi possivel vincular os modulos', res.statusCode));
    }
    await _restaurarValores(parceiroId, ids, anteriores);
  }

  Future<void> _restaurarValores(
      int parceiroId, List<int> idsAtuais, List<Map<String, dynamic>> anteriores) async {
    for (final m in anteriores) {
      final moduloId = _toInt(m['id'] ?? m['moduloId']);
      if (moduloId == null || !idsAtuais.contains(moduloId)) continue;
      final valor = _toDouble(m['valor'] ?? m['valorMensal'] ?? m['valor_mensal']);
      final dia = _toInt(m['diaVencimento'] ?? m['dia_vencimento']) ?? 0;
      if (valor <= 0 && dia <= 0) continue;
      try {
        final r = await _caller.putRequest(
          '${ApiLinks.vincularParceiroModulos}/$moduloId',
          {'parceiroId': parceiroId, 'valor': valor, 'diaVencimento': dia},
          enriquecerCorpo: false,
        );
        if (!r.isSuccess) {
          AppLogger.i.warn(
              'Aprovar trial: nao restaurou valor do modulo $moduloId do parceiro $parceiroId (HTTP ${r.statusCode})');
        }
      } catch (e) {
        AppLogger.i.warn(
            'Aprovar trial: erro ao restaurar valor do modulo $moduloId do parceiro $parceiroId: $e');
      }
    }
  }

  Future<bool> _compensar({
    required int parceiroId,
    required bool parceiroCriado,
    required bool modulosAlterados,
    required List<Map<String, dynamic>> anteriores,
    required List<int> loginsCriados,
  }) async {
    var tudoOk = true;
    for (final loginId in loginsCriados) {
      tudoOk &= await _tentar(
          'remover login $loginId', () => _caller.deleteRequest(ApiLinks.deleteLogin('$loginId')));
    }
    if (parceiroCriado) {
      tudoOk &= await _tentar('desvincular modulos do parceiro $parceiroId', () =>
          _caller.postRequest(ApiLinks.vincularParceiroModulos,
              {'parceiroId': parceiroId, 'moduloIds': <int>[]}));
      tudoOk &= await _tentar('remover parceiro $parceiroId',
          () => _caller.deleteRequest(ApiLinks.deleteParceiro('$parceiroId')));
    } else if (modulosAlterados) {
      final idsAnteriores = anteriores
          .map((m) => _toInt(m['id'] ?? m['moduloId']))
          .whereType<int>()
          .toList();
      tudoOk &= await _tentar('restaurar modulos do parceiro $parceiroId', () async {
        final r = await _caller.postRequest(ApiLinks.vincularParceiroModulos,
            {'parceiroId': parceiroId, 'moduloIds': idsAnteriores});
        if (r.isSuccess) await _restaurarValores(parceiroId, idsAnteriores, anteriores);
        return r;
      });
    }
    if (!tudoOk) {
      AppLogger.i.warn(
          'Aprovar trial: compensacao incompleta para o parceiro $parceiroId — revisar manualmente em Atribuicao de Modulos.');
    }
    return tudoOk;
  }

  Future<bool> _tentar(String acao, Future<dynamic> Function() fn) async {
    try {
      final r = await fn();
      final ok = r == null || (r.isSuccess as bool);
      if (!ok) {
        AppLogger.i.warn('Aprovar trial: falha ao $acao (HTTP ${r.statusCode})');
      }
      return ok;
    } catch (e) {
      AppLogger.i.warn('Aprovar trial: erro ao $acao: $e');
      return false;
    }
  }

  static String _mensagemHttp(String base, int status) {
    if (status == 401) {
      return '$base: sessao expirada. Entre novamente no Painel do Dono.';
    }
    if (status == 403) return '$base: sem permissao (HTTP 403).';
    return '$base (HTTP $status).';
  }

  static int? _extrairId(Map<String, dynamic>? body) {
    if (body == null) return null;
    final direto = _toInt(body['id']);
    if (direto != null) return direto;
    final data = body['data'];
    if (data is Map) return _extrairId(Map<String, dynamic>.from(data));
    if (data is List && data.isNotEmpty && data.first is Map) {
      return _extrairId(Map<String, dynamic>.from(data.first as Map));
    }
    for (final chave in ['parceiro', 'dados']) {
      final nested = body[chave];
      if (nested is Map) return _extrairId(Map<String, dynamic>.from(nested));
    }
    return null;
  }

  static int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse((v?.toString() ?? '').replaceAll(',', '.')) ?? 0;
  }

  static String _digitos(String s) => s.replaceAll(RegExp(r'\D'), '');
}
