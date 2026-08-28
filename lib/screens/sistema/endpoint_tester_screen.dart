import 'dart:convert';

import 'package:flutter/material.dart';

import '../../config/api_links.dart';
import '../../core/theme/app_theme.dart';
import '../../services/network_caller.dart';

/// SIS-07 Teste de Endpoints — terminal HTTP livre.
///
/// Reconstruido do zero (nao portado) a partir da 3a aba de
/// `system_test_screen.dart` (cliente): aquele arquivo original tinha uma
/// lista hardcoded de ~50 paths e nao permitia editar o corpo da
/// requisicao — decisao do PO registrada no RESEARCH.md ("Item 7") desta
/// fase e' NAO replicar essa limitacao. Aqui o path e' digitavel livremente,
/// o verbo e o corpo JSON sao editaveis, e [ApiLinks.adminEndpointsReflection]
/// e' usado apenas para SUGERIR paths conhecidos (autocomplete opcional),
/// nunca para restringir o campo a uma lista fixa.
enum HttpVerb { get, post, put, delete }

extension on HttpVerb {
  String get label => switch (this) {
        HttpVerb.get => 'GET',
        HttpVerb.post => 'POST',
        HttpVerb.put => 'PUT',
        HttpVerb.delete => 'DELETE',
      };

  bool get aceitaCorpo => this == HttpVerb.post || this == HttpVerb.put;
}

class EndpointTesterScreen extends StatefulWidget {
  const EndpointTesterScreen({super.key, this.networkCaller});

  final NetworkCaller? networkCaller;

  @override
  State<EndpointTesterScreen> createState() => _EndpointTesterScreenState();
}

class _EndpointTesterScreenState extends State<EndpointTesterScreen> {
  late final NetworkCaller _caller =
      widget.networkCaller ?? NetworkCaller();

  /// So fecha o client HTTP no dispose quando esta tela o criou (mesmo
  /// cuidado ja adotado em GenericGridScreen: nao fechar um client
  /// injetado por quem chamou o widget).
  bool get _ownsCaller => widget.networkCaller == null;

  final _pathController = TextEditingController(text: '/api/');
  final _bodyController = TextEditingController();

  HttpVerb _verb = HttpVerb.get;
  bool _executing = false;
  int? _statusCode;
  bool? _statusSuccess;
  String? _responseText;
  List<String> _sugestoes = [];

  @override
  void initState() {
    super.initState();
    _pathController.addListener(() => setState(() {}));
    _bodyController.addListener(() => setState(() {}));
    _carregarSugestoes();
  }

  @override
  void dispose() {
    _pathController.dispose();
    _bodyController.dispose();
    if (_ownsCaller) _caller.close();
    super.dispose();
  }

  /// Autocomplete opcional (nao bloqueante para o Done desta task):
  /// popula sugestoes de paths conhecidos via reflection do backend.
  /// Falha silenciosamente — a ausencia de sugestoes nao impede o uso do
  /// terminal livre.
  Future<void> _carregarSugestoes() async {
    try {
      final response =
          await _caller.getRequest(ApiLinks.adminEndpointsReflection);
      if (!mounted || !response.isSuccess) return;

      dynamic data = response.body?['data'] ?? response.body?['dados'] ?? [];
      if (data is Map) {
        data = data['dados'] ?? data['content'] ?? [];
      }
      if (data is! List) return;

      final paths = data
          .map((e) {
            if (e is String) return e;
            if (e is Map) {
              return (e['path'] ?? e['url'] ?? e['endpoint'])?.toString();
            }
            return null;
          })
          .whereType<String>()
          .toSet()
          .toList()
        ..sort();

      if (!mounted) return;
      setState(() => _sugestoes = paths);
    } catch (_) {
      // Sugestao e' um extra opcional — qualquer falha (rede, parsing)
      // nao deve impedir o uso do terminal livre.
    }
  }

  Map<String, dynamic>? _corpoValidado() {
    final texto = _bodyController.text.trim();
    if (texto.isEmpty) return const {};
    final decoded = jsonDecode(texto);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const FormatException('Corpo JSON deve ser um objeto.');
  }

  bool get _corpoValido {
    if (!_verb.aceitaCorpo) return true;
    try {
      _corpoValidado();
      return true;
    } catch (_) {
      return false;
    }
  }

  bool get _podeExecutar =>
      !_executing && _pathController.text.trim().isNotEmpty && _corpoValido;

  String get _urlCompleta {
    var path = _pathController.text.trim();
    if (!path.startsWith('/')) path = '/$path';
    return '${ApiLinks.baseUrl}$path';
  }

  Future<void> _executar() async {
    if (!_podeExecutar) return;

    setState(() {
      _executing = true;
      _statusCode = null;
      _statusSuccess = null;
      _responseText = null;
    });

    final url = _urlCompleta;
    final corpo = _verb.aceitaCorpo ? (_corpoValidado() ?? const {}) : null;

    final response = switch (_verb) {
      HttpVerb.get => await _caller.getRequest(url),
      HttpVerb.post => await _caller.postRequest(url, corpo ?? const {}),
      HttpVerb.put => await _caller.putRequest(url, corpo ?? const {}),
      HttpVerb.delete => await _caller.deleteRequest(url),
    };

    if (!mounted) return;

    setState(() {
      _executing = false;
      _statusCode = response.statusCode;
      _statusSuccess = response.isSuccess;
      _responseText = const JsonEncoder.withIndent('  ')
          .convert(response.body ?? <String, dynamic>{});
    });
  }

  void _selecionarSugestao(String path) {
    _pathController.text = path;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Teste de Endpoints')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<HttpVerb>(
                    key: const Key('endpoint_tester_verb_dropdown'),
                    initialValue: _verb,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Metodo'),
                    items: HttpVerb.values
                        .map((v) => DropdownMenuItem(
                              value: v,
                              child: Text(v.label),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _verb = v);
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextField(
                    key: const Key('endpoint_tester_path_field'),
                    controller: _pathController,
                    decoration: const InputDecoration(
                      labelText: 'Path',
                      hintText: '/api/aplicativo',
                    ),
                  ),
                ),
              ],
            ),
            if (_sugestoes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                key: const Key('endpoint_tester_sugestoes'),
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: _sugestoes
                    .map((p) => ActionChip(
                          label: Text(p),
                          onPressed: () => _selecionarSugestao(p),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('endpoint_tester_body_field'),
              controller: _bodyController,
              maxLines: 8,
              enabled: _verb.aceitaCorpo,
              decoration: InputDecoration(
                labelText: 'Corpo (JSON)',
                hintText: _verb.aceitaCorpo
                    ? '{"campo": "valor"}'
                    : 'Metodo ${_verb.label} nao envia corpo',
                errorText:
                    _verb.aceitaCorpo && !_corpoValido ? 'JSON invalido' : null,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton.icon(
              key: const Key('endpoint_tester_execute_button'),
              onPressed: _podeExecutar ? _executar : null,
              icon: _executing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: const Text('Executar'),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_statusCode != null)
              Text(
                'Status: $_statusCode',
                key: const Key('endpoint_tester_status_text'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color:
                      (_statusSuccess ?? false) ? colors.success : colors.error,
                ),
              ),
            if (_responseText != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: SingleChildScrollView(
                  child: Container(
                    key: const Key('endpoint_tester_response_text'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: colors.surfaceVariant,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusDefault),
                    ),
                    child: SelectableText(
                      _responseText!,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
