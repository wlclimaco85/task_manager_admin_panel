import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import '../models/network_response.dart';
import '../config/api_links.dart';
import '../utils/app_logger.dart';
import '../utils/tenant_context.dart';
import 'network_caller.dart';

/// Modulo Java (plataforma low-code, Etapa 1): cadastro do modulo e dos .jar de cada modulo.
class ModuloJava {
  final int? id;
  final String identificador;
  final String descricao;
  final bool ativo;

  const ModuloJava({
    this.id,
    required this.identificador,
    required this.descricao,
    this.ativo = true,
  });

  factory ModuloJava.fromJson(Map<String, dynamic> j) => ModuloJava(
        id: (j['id'] as num?)?.toInt(),
        identificador: j['identificador']?.toString() ?? '',
        descricao: j['descricao']?.toString() ?? '',
        ativo: j['ativo'] != false,
      );

  Map<String, dynamic> toJson() => {
        'identificador': identificador,
        'descricao': descricao,
        'ativo': ativo,
      };
}

/// Um .jar do modulo (linha da aba "Arquivo Modulo (Jar)").
class ModuloJavaArquivo {
  final int id;
  final String nomeArquivo;
  final String sha256;
  final int tamanho;
  final int versao;
  final List<String> classes;

  const ModuloJavaArquivo({
    required this.id,
    required this.nomeArquivo,
    required this.sha256,
    required this.tamanho,
    required this.versao,
    this.classes = const [],
  });

  factory ModuloJavaArquivo.fromJson(Map<String, dynamic> j) =>
      ModuloJavaArquivo(
        id: (j['id'] as num?)?.toInt() ?? 0,
        nomeArquivo: j['nomeArquivo']?.toString() ?? '',
        sha256: j['sha256']?.toString() ?? '',
        tamanho: (j['tamanho'] as num?)?.toInt() ?? 0,
        versao: (j['versao'] as num?)?.toInt() ?? 1,
        classes: classesDeJson(j['classesJson']?.toString()),
      );

  /// O backend devolve o inventario como JSON em texto: [{"nome":"a.B","tipo":"ACAO"}].
  static List<String> classesDeJson(String? texto) {
    if (texto == null || texto.trim().isEmpty) return const [];
    try {
      final lista = jsonDecode(texto) as List;
      return lista
          .whereType<Map>()
          .map((c) => '${c['nome']} (${c['tipo']})')
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

class ModuloJavaException implements Exception {
  final String mensagem;
  const ModuloJavaException(this.mensagem);

  @override
  String toString() => mensagem;
}

const int kModuloJavaTamanhoMaximoBytes = 10 * 1024 * 1024;

class ModuloJavaService {
  final NetworkCaller _rede;

  ModuloJavaService({NetworkCaller? rede}) : _rede = rede ?? NetworkCaller();

  Future<List<ModuloJava>> listar() async {
    final r = await _rede.getRequest(ApiLinks.modulosJava);
    _exigirSucesso(r, 'listar os módulos');
    final lista = r.body is List ? r.body as List : const [];
    return lista
        .whereType<Map<String, dynamic>>()
        .map(ModuloJava.fromJson)
        .toList();
  }

  Future<ModuloJava> salvar(ModuloJava modulo) async {
    final NetworkResponse r = modulo.id == null
        ? await _rede.postRequest(ApiLinks.modulosJava, modulo.toJson())
        : await _rede.putRequest(
            ApiLinks.moduloJava('${modulo.id}'), modulo.toJson());
    _exigirSucesso(r, 'salvar o módulo');
    return ModuloJava.fromJson(r.body as Map<String, dynamic>);
  }

  Future<void> excluir(int id) async {
    final r = await _rede.deleteRequest(ApiLinks.moduloJava('$id'));
    _exigirSucesso(r, 'excluir o módulo');
  }

  Future<List<ModuloJavaArquivo>> listarArquivos(int moduloId) async {
    final r = await _rede.getRequest(ApiLinks.moduloJavaArquivos('$moduloId'));
    _exigirSucesso(r, 'listar os arquivos');
    final lista = r.body is List ? r.body as List : const [];
    return lista
        .whereType<Map<String, dynamic>>()
        .map(ModuloJavaArquivo.fromJson)
        .toList();
  }

  /// Valida no cliente o que o servidor tambem valida (extensao .jar e 10MB), para dar erro rapido e claro.
  static String? validarArquivo(String nome, int tamanho) {
    if (!nome.toLowerCase().endsWith('.jar')) {
      return 'Selecione um arquivo .jar.';
    }
    if (tamanho <= 0) return 'O arquivo está vazio.';
    if (tamanho > kModuloJavaTamanhoMaximoBytes) {
      return 'O arquivo excede o tamanho máximo de 10 MB.';
    }
    return null;
  }

  Future<ModuloJavaArquivo> enviarArquivo(
      int moduloId, PlatformFile arquivo) async {
    final bytes = arquivo.bytes;
    if (bytes == null) {
      throw const ModuloJavaException('Não foi possível ler o arquivo.');
    }
    final erro = validarArquivo(arquivo.name, bytes.length);
    if (erro != null) throw ModuloJavaException(erro);

    final request = http.MultipartRequest(
      'POST',
      Uri.parse(TenantContext.applyToUrl(ApiLinks.moduloJavaArquivos('$moduloId'))),
    );
    request.headers.addAll(TenantContext.headers);
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: arquivo.name,
    ));
    try {
      final streamed = await request.send();
      final corpo = await streamed.stream.bytesToString();
      if (streamed.statusCode == 200 || streamed.statusCode == 201) {
        return ModuloJavaArquivo.fromJson(
            jsonDecode(corpo) as Map<String, dynamic>);
      }
      throw ModuloJavaException(
          _mensagemErro(corpo, streamed.statusCode, 'enviar o arquivo'));
    } on ModuloJavaException {
      rethrow;
    } catch (e, st) {
      AppLogger.i.error('ModuloJavaService: falha no upload do jar: $e', st);
      throw const ModuloJavaException(
          'Não foi possível enviar o arquivo. Verifique a conexão e tente de novo.');
    }
  }

  Future<void> excluirArquivo(int moduloId, int arquivoId) async {
    final r = await _rede
        .deleteRequest(ApiLinks.moduloJavaArquivo('$moduloId', '$arquivoId'));
    _exigirSucesso(r, 'excluir o arquivo');
  }

  void _exigirSucesso(NetworkResponse r, String acao) {
    if (r.isSuccess) return;
    final corpo = r.body is String ? r.body as String : jsonEncode(r.body);
    throw ModuloJavaException(_mensagemErro(corpo, r.statusCode, acao));
  }

  static String _mensagemErro(String corpo, int status, String acao) {
    if (status == 403) return 'Somente o usuário MASTER pode gerenciar módulos Java.';
    if (status == 409) return 'Já existe um registro igual (identificador ou arquivo duplicado).';
    try {
      final j = jsonDecode(corpo);
      if (j is Map && j['message'] != null) return j['message'].toString();
      if (j is Map && j['error'] != null) return j['error'].toString();
    } catch (_) {}
    return 'Não foi possível $acao (HTTP $status).';
  }
}
