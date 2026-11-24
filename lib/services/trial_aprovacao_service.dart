import 'dart:convert';

import '../config/api_links.dart';
import '../utils/app_logger.dart';
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

/// Resposta de `GET /api/admin/trial/resolver-cnpj`: a quem o CNPJ/CPF
/// pertence (empresa ou parceiro) e os usuarios/roles SO desse escopo.
class ResolucaoCnpj {
  const ResolucaoCnpj({
    required this.tipoAlvo,
    this.empresaId,
    this.empresaNome,
    this.parceiroId,
    this.parceiroNome,
    this.usuarios = const [],
    this.roles = const [],
  });

  /// `EMPRESA`, `PARCEIRO` ou `NAO_ENCONTRADO`.
  final String tipoAlvo;
  final int? empresaId;
  final String? empresaNome;
  final int? parceiroId;
  final String? parceiroNome;
  final List<Map<String, dynamic>> usuarios;
  final List<Map<String, dynamic>> roles;

  bool get naoEncontrado => tipoAlvo == 'NAO_ENCONTRADO';
  bool get ehParceiro => tipoAlvo == 'PARCEIRO';

  factory ResolucaoCnpj.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> lista(dynamic v) => v is List
        ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
        : const [];
    return ResolucaoCnpj(
      tipoAlvo: (json['tipoAlvo'] ?? 'NAO_ENCONTRADO').toString(),
      empresaId: TrialAprovacaoService._toInt(json['empresaId']),
      empresaNome: json['empresaNome']?.toString(),
      parceiroId: TrialAprovacaoService._toInt(json['parceiroId']),
      parceiroNome: json['parceiroNome']?.toString(),
      usuarios: lista(json['usuarios']),
      roles: lista(json['roles']),
    );
  }
}

/// Cliente da solicitacao preparado para a concessao de licenca: alvo
/// (empresa OU parceiro, resolvido pelo CNPJ) + modulos vinculados. Guarda o
/// estado anterior para compensar caso o fluxo seja cancelado.
class ClienteTrialPreparado {
  ClienteTrialPreparado({
    required this.resolucao,
    required this.modulos,
    required this.modulosNomes,
    required this.modulosAnteriores,
    required this.modulosAlterados,
  });

  final ResolucaoCnpj resolucao;
  final ModulosMapeados modulos;

  /// Nomes de TODOS os modulos do alvo apos o vinculo (anteriores + novos).
  final List<String> modulosNomes;

  /// Vinculos que o alvo ja tinha antes (com valor/dia de vencimento, no parceiro).
  final List<Map<String, dynamic>> modulosAnteriores;

  /// `true` se o POST de vinculo foi executado (precisa ser revertido).
  final bool modulosAlterados;

  /// Logins criados durante o popup (etapa 2) — removidos se cancelar.
  final List<int> loginsCriados = <int>[];

  bool get ehParceiro => resolucao.ehParceiro;

  /// Id do alvo dos modulos: parceiro quando o CNPJ e' de parceiro, senao a empresa.
  int get alvoId => ehParceiro ? resolucao.parceiroId! : resolucao.empresaId!;
  String get alvoNome {
    final nome = ehParceiro ? resolucao.parceiroNome : resolucao.empresaNome;
    return (nome == null || nome.isEmpty) ? '#$alvoId' : nome;
  }
}

/// Fluxo do botao "Aprovar" de Solicitacoes de Trial (30 dias gratis). O
/// destinatario e' descoberto pelo CNPJ/CPF da PROPRIA solicitacao — empresa
/// ou parceiro — e nunca pela empresa de quem esta logado no Painel do Dono.
class TrialAprovacaoService {
  TrialAprovacaoService({NetworkCaller? caller})
      : _caller = caller ?? NetworkCaller(),
        _donoDoCaller = caller == null;

  final NetworkCaller _caller;
  final bool _donoDoCaller;

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

  /// Descobre pelo CNPJ/CPF se o cliente e' empresa ou parceiro e traz so' os
  /// usuarios e roles desse escopo.
  Future<ResolucaoCnpj> resolverCnpj(String documento) async {
    final res = await _caller.getRequest(ApiLinks.trialResolverCnpj(documento));
    if (!res.isSuccess || res.body == null) {
      final erro = res.body?['erro']?.toString();
      throw TrialAprovacaoException(erro != null && erro.isNotEmpty
          ? erro
          : _mensagemHttp('Nao foi possivel localizar o cliente pelo CNPJ', res.statusCode));
    }
    return ResolucaoCnpj.fromJson(res.body!);
  }

  /// Cria no backend a empresa (tenant proprio) do CNPJ da solicitacao.
  Future<ResolucaoCnpj> criarEmpresa(dynamic solicitacaoId) async {
    final id = int.tryParse('$solicitacaoId');
    if (id == null) {
      throw const TrialAprovacaoException('Solicitacao sem id valido.');
    }
    final res = await _caller.postRequest(ApiLinks.trialCriarEmpresa(id), {});
    if (!res.isSuccess || res.body == null) {
      final erro = res.body?['erro']?.toString();
      throw TrialAprovacaoException(erro != null && erro.isNotEmpty
          ? erro
          : _mensagemHttp('Nao foi possivel criar a empresa', res.statusCode));
    }
    return ResolucaoCnpj.fromJson(res.body!);
  }

  /// Resolve o cliente pelo CNPJ/CPF da solicitacao e vincula os modulos mapeados
  /// ao alvo (empresa ou parceiro), preservando os que ele ja tinha. Se o
  /// documento nao pertence a nenhuma empresa/parceiro, falha com mensagem clara:
  /// nunca cria cadastro sob a empresa de quem esta logado. Se o vinculo falhar,
  /// desfaz o que foi feito e relanca.
  Future<ClienteTrialPreparado> prepararCliente(
      Map<String, dynamic> solicitacao, ModulosMapeados mapa,
      {Future<bool> Function(String documento)? confirmarCriarEmpresa}) async {
    if (!mapa.temCorrespondencia) {
      throw const TrialAprovacaoException(
          'Nenhum modulo da solicitacao existe no catalogo. Cadastre os modulos antes de aprovar.');
    }
    final documento = documentoDaSolicitacao(solicitacao);
    if (documento.isEmpty) {
      throw const TrialAprovacaoException(
          'A solicitacao nao tem CNPJ/CPF. Sem o documento nao e possivel localizar o cliente.');
    }

    var resolucao = await resolverCnpj(documento);
    if (resolucao.naoEncontrado) {
      final criar = confirmarCriarEmpresa != null && await confirmarCriarEmpresa(documento);
      if (!criar) {
        throw TrialAprovacaoException(
            'CNPJ/CPF $documento nao pertence a nenhuma empresa nem parceiro cadastrado. Crie a empresa do cliente para conceder o trial.');
      }
      resolucao = await criarEmpresa(solicitacao['id']);
    }

    var modulosAlterados = false;
    List<Map<String, dynamic>> anteriores = const [];
    final preparado = ClienteTrialPreparado(
      resolucao: resolucao,
      modulos: mapa,
      modulosNomes: const [],
      modulosAnteriores: const [],
      modulosAlterados: false,
    );
    try {
      anteriores = await _modulosDoAlvo(preparado);
      final idsAnteriores = _idsDe(anteriores);
      final uniao = <int>{...idsAnteriores, ...mapa.ids}.toList();
      if (uniao.length != idsAnteriores.length) {
        modulosAlterados = true;
        await _vincularModulos(preparado, uniao, anteriores);
      }

      final nomes = <String>{
        ...anteriores.map((m) => (m['nome'] ?? '').toString()),
        ...mapa.nomesVinculados,
      }.where((n) => n.isNotEmpty).toList();

      return ClienteTrialPreparado(
        resolucao: resolucao,
        modulos: mapa,
        modulosNomes: nomes,
        modulosAnteriores: anteriores,
        modulosAlterados: modulosAlterados,
      );
    } catch (e, st) {
      AppLogger.i.error('Aprovar trial: falha ao preparar cliente: $e', st);
      if (modulosAlterados) {
        await _compensar(
          cliente: preparado,
          modulosAlterados: true,
          anteriores: anteriores,
          loginsCriados: const [],
        );
      }
      if (e is TrialAprovacaoException) rethrow;
      throw TrialAprovacaoException('Falha ao preparar o cliente: $e');
    }
  }

  /// Compensacao: usuario cancelou o popup (ou algo falhou depois do vinculo).
  /// Remove logins criados no popup e restaura os modulos anteriores. Retorna
  /// `true` se tudo foi revertido; `false` (com log) se algo ficou para limpeza manual.
  Future<bool> desfazer(ClienteTrialPreparado cliente) {
    return _compensar(
      cliente: cliente,
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

  List<int> _idsDe(List<Map<String, dynamic>> modulos) =>
      modulos.map((m) => _toInt(m['id'] ?? m['moduloId'])).whereType<int>().toList();

  Future<List<Map<String, dynamic>>> _modulosDoAlvo(ClienteTrialPreparado c) async {
    final url = c.ehParceiro
        ? ApiLinks.parceiroModulos(c.alvoId.toString())
        : ApiLinks.empresaModulos(c.alvoId.toString());
    final res = await _caller.getRequest(url);
    if (!res.isSuccess) {
      throw TrialAprovacaoException(_mensagemHttp(
          'Nao foi possivel ler os modulos atuais do cliente', res.statusCode));
    }
    return GenericGridWindowsScreen.extractRows(res.body);
  }

  Future<dynamic> _postVinculo(ClienteTrialPreparado c, List<int> ids) {
    return c.ehParceiro
        ? _caller.postRequest(
            ApiLinks.vincularParceiroModulos, {'parceiroId': c.alvoId, 'moduloIds': ids})
        : _caller.postRequest(
            ApiLinks.vincularEmpresaModulos, {'empresaId': c.alvoId, 'moduloIds': ids});
  }

  /// POST de vinculo SUBSTITUI todo o conjunto (apaga e reinsere), o que zera
  /// valor mensal/dia de vencimento do parceiro; por isso reaplica os valores anteriores.
  Future<void> _vincularModulos(ClienteTrialPreparado c, List<int> ids,
      List<Map<String, dynamic>> anteriores) async {
    final res = await _postVinculo(c, ids);
    if (!res.isSuccess) {
      throw TrialAprovacaoException(
          _mensagemHttp('Nao foi possivel vincular os modulos', res.statusCode));
    }
    if (c.ehParceiro) await _restaurarValores(c.alvoId, ids, anteriores);
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
    required ClienteTrialPreparado cliente,
    required bool modulosAlterados,
    required List<Map<String, dynamic>> anteriores,
    required List<int> loginsCriados,
  }) async {
    var tudoOk = true;
    for (final loginId in loginsCriados) {
      tudoOk &= await _tentar(
          'remover login $loginId', () => _caller.deleteRequest(ApiLinks.deleteLogin('$loginId')));
    }
    if (modulosAlterados) {
      final idsAnteriores = _idsDe(anteriores);
      tudoOk &= await _tentar('restaurar modulos de ${cliente.alvoNome}', () async {
        final r = await _postVinculo(cliente, idsAnteriores);
        if (r.isSuccess && cliente.ehParceiro) {
          await _restaurarValores(cliente.alvoId, idsAnteriores, anteriores);
        }
        return r;
      });
    }
    if (!tudoOk) {
      AppLogger.i.warn(
          'Aprovar trial: compensacao incompleta para ${cliente.alvoNome} — revisar manualmente em Atribuicao de Modulos.');
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
