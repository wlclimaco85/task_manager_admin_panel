
import 'package:flutter/material.dart';

import '../utils/app_logger.dart';
import '../utils/dropdown_helpers.dart';
import '../utils/grid_colors.dart';
import '../services/network_caller.dart';
import 'searchable_dropdown.dart';

/// Servidor de emissao de NFS-e configurado para um municipio.
class NfseServidorConfig {
  final int? id;
  final int codigoIbge;
  final String uf;
  final String municipio;
  final String servidor;

  const NfseServidorConfig({
    this.id,
    required this.codigoIbge,
    required this.uf,
    required this.municipio,
    required this.servidor,
  });

  factory NfseServidorConfig.fromJson(Map<String, dynamic> json) {
    return NfseServidorConfig(
      id: (json['id'] as num?)?.toInt(),
      codigoIbge: (json['codigoIbge'] as num?)?.toInt() ?? 0,
      uf: (json['uf'] ?? '').toString(),
      municipio: (json['municipio'] ?? '').toString(),
      servidor: (json['servidor'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'codigoIbge': codigoIbge,
        'uf': uf,
        'municipio': municipio,
        'servidor': servidor,
      };
}

typedef NfseServidoresLoader = Future<List<NfseServidorConfig>> Function();
typedef NfseServidorOpcoesLoader = Future<List<Map<String, dynamic>>>
    Function();
typedef NfseServidorCidadesLoader = Future<List<Map<String, dynamic>>>
    Function(String estadoId);
typedef NfseServidorSalvar = Future<String?> Function(NfseServidorConfig item);
typedef NfseServidorExcluir = Future<String?> Function(int id);

/// Box "Configurar servidor NFS-e" (Config. Sistema): define, por municipio,
/// qual servidor emite a NFS-e (WebISS especifico ou Portal Nacional).
/// Municipio sem configuracao usa o Portal Nacional.
class NfseServidorConfigCard extends StatefulWidget {
  final String baseUrl;
  final NfseServidoresLoader? carregar;
  final NfseServidorOpcoesLoader? carregarServidores;
  final NfseServidorOpcoesLoader? carregarEstados;
  final NfseServidorCidadesLoader? carregarCidades;
  final NfseServidorSalvar? salvar;
  final NfseServidorExcluir? excluir;

  const NfseServidorConfigCard({
    super.key,
    required this.baseUrl,
    this.carregar,
    this.carregarServidores,
    this.carregarEstados,
    this.carregarCidades,
    this.salvar,
    this.excluir,
  });

  @override
  State<NfseServidorConfigCard> createState() => _NfseServidorConfigCardState();
}

class _NfseServidorConfigCardState extends State<NfseServidorConfigCard> {
  List<NfseServidorConfig> _itens = [];
  List<Map<String, dynamic>> _servidores = [];
  bool _carregando = true;
  String? _erro;

  String get _url => '${widget.baseUrl}/api/nfse-servidor-municipio';

  @override
  void initState() {
    super.initState();
    _recarregar();
  }

  Future<void> _recarregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final itens = await (widget.carregar ?? _carregarPadrao)();
      final servidores =
          await (widget.carregarServidores ?? _carregarServidoresPadrao)();
      if (!mounted) return;
      setState(() {
        _itens = itens;
        _servidores = servidores;
        _carregando = false;
      });
    } catch (e, st) {
      AppLogger.i.error('[NFSE-SERVIDOR] falha ao carregar configuracao: $e', st);
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = 'Nao foi possivel carregar a configuracao dos servidores.';
      });
    }
  }

  Future<List<NfseServidorConfig>> _carregarPadrao() async {
    final resp = await NetworkCaller().getRequest(_url);
    if (!resp.isSuccess) throw Exception('HTTP ${resp.statusCode}');
    final lista = resp.body?['data'];
    if (lista is! List) return [];
    return lista
        .whereType<Map>()
        .map((e) => NfseServidorConfig.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<Map<String, dynamic>>> _carregarServidoresPadrao() async {
    final resp = await NetworkCaller().getRequest('$_url/servidores');
    if (!resp.isSuccess) throw Exception('HTTP ${resp.statusCode}');
    final lista = resp.body?['data'];
    if (lista is! List) return [];
    return lista
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<Map<String, dynamic>>> _estadosPadrao() => DropdownHelpers.load(
      '${widget.baseUrl}/api/estados?tamanho=100',
      displayField: 'nome');

  Future<List<Map<String, dynamic>>> _cidadesPadrao(String estadoId) =>
      DropdownHelpers.load('${widget.baseUrl}/api/cidade/by-estado/$estadoId',
          displayField: 'nome');

  /// Retorna a mensagem de erro ou null em caso de sucesso.
  Future<String?> _salvarPadrao(NfseServidorConfig item) async {
    final caller = NetworkCaller();
    final resp = item.id == null
        ? await caller.postRequest(_url, item.toJson())
        : await caller.putRequest('$_url/${item.id}', item.toJson());
    if (resp.isSuccess) return null;
    return _mensagemDeErro(resp.body, resp.statusCode);
  }

  Future<String?> _excluirPadrao(int id) async {
    final resp = await NetworkCaller().deleteRequest('$_url/$id');
    if (resp.isSuccess) return null;
    return _mensagemDeErro(resp.body, resp.statusCode);
  }

  String _mensagemDeErro(Map<String, dynamic>? body, int status) {
    final msg = body?['message'] ?? body?['mensagem'] ?? body?['error'];
    if (msg != null && msg.toString().isNotEmpty) return msg.toString();
    return 'Falha ao salvar (HTTP $status).';
  }

  String _rotuloServidor(String valor) {
    for (final s in _servidores) {
      if (s['value'] == valor) return (s['label'] ?? valor).toString();
    }
    return valor;
  }

  Future<void> _abrirDialogo({NfseServidorConfig? editando}) async {
    final resultado = await showDialog<NfseServidorConfig>(
      context: context,
      builder: (_) => _NfseServidorDialog(
        servidores: _servidores,
        editando: editando,
        carregarEstados: widget.carregarEstados ?? _estadosPadrao,
        carregarCidades: widget.carregarCidades ?? _cidadesPadrao,
      ),
    );
    if (resultado == null || !mounted) return;
    try {
      final erro = await (widget.salvar ?? _salvarPadrao)(resultado);
      if (!mounted) return;
      if (erro != null) {
        AppLogger.i.warn('[NFSE-SERVIDOR] salvar recusado: $erro');
        _snack(erro, erroFlag: true);
        return;
      }
      _snack('Servidor de ${resultado.municipio}/${resultado.uf} salvo.');
      await _recarregar();
    } catch (e, st) {
      AppLogger.i.error('[NFSE-SERVIDOR] falha ao salvar: $e', st);
      if (mounted) _snack('Erro ao salvar a configuracao.', erroFlag: true);
    }
  }

  Future<void> _confirmarExclusao(NfseServidorConfig item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover configuracao'),
        content: Text('${item.municipio}/${item.uf} voltara a emitir pelo '
            'Portal Nacional (padrao). Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remover')),
        ],
      ),
    );
    if (ok != true || item.id == null || !mounted) return;
    try {
      final erro = await (widget.excluir ?? _excluirPadrao)(item.id!);
      if (!mounted) return;
      if (erro != null) {
        AppLogger.i.warn('[NFSE-SERVIDOR] exclusao recusada: $erro');
        _snack(erro, erroFlag: true);
        return;
      }
      await _recarregar();
    } catch (e, st) {
      AppLogger.i.error('[NFSE-SERVIDOR] falha ao excluir: $e', st);
      if (mounted) _snack('Erro ao remover a configuracao.', erroFlag: true);
    }
  }

  void _snack(String msg, {bool erroFlag = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: erroFlag ? Colors.red.shade700 : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFDDDDDD)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dns_outlined, color: GridColors.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Configurar servidor NFS-e',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                IconButton.filled(
                  key: const Key('nfse-servidor-adicionar'),
                  tooltip: 'Adicionar municipio',
                  style: IconButton.styleFrom(
                      backgroundColor: GridColors.primary,
                      minimumSize: const Size(44, 44)),
                  onPressed: _carregando ? null : () => _abrirDialogo(),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Defina, por municipio, qual servidor emite a NFS-e. Municipio '
              'sem configuracao emite pelo Portal Nacional (padrao).',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            if (_carregando)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator()))
            else if (_erro != null)
              Text(_erro!, style: const TextStyle(color: Colors.red))
            else if (_itens.isEmpty)
              const Text('Nenhum municipio configurado: todos usam o Portal '
                  'Nacional.')
            else
              for (final item in _itens) _linha(item),
          ],
        ),
      ),
    );
  }

  Widget _linha(NfseServidorConfig item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE3E3E3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${item.municipio} / ${item.uf}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(_rotuloServidor(item.servidor),
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ],
            ),
          ),
          IconButton(
            key: Key('nfse-servidor-editar-${item.id}'),
            tooltip: 'Editar',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: () => _abrirDialogo(editando: item),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            key: Key('nfse-servidor-excluir-${item.id}'),
            tooltip: 'Excluir',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: () => _confirmarExclusao(item),
            icon: const Icon(Icons.delete_outline, color: Colors.red),
          ),
        ],
      ),
    );
  }
}

class _NfseServidorDialog extends StatefulWidget {
  final List<Map<String, dynamic>> servidores;
  final NfseServidorConfig? editando;
  final NfseServidorOpcoesLoader carregarEstados;
  final NfseServidorCidadesLoader carregarCidades;

  const _NfseServidorDialog({
    required this.servidores,
    required this.editando,
    required this.carregarEstados,
    required this.carregarCidades,
  });

  @override
  State<_NfseServidorDialog> createState() => _NfseServidorDialogState();
}

class _NfseServidorDialogState extends State<_NfseServidorDialog> {
  List<Map<String, dynamic>> _estados = [];
  List<Map<String, dynamic>> _cidades = [];
  String? _estadoId;
  String? _cidadeId;
  String? _servidor;
  bool _carregandoEstados = true;
  bool _carregandoCidades = false;
  String? _erro;

  bool get _edicao => widget.editando != null;

  @override
  void initState() {
    super.initState();
    _servidor = widget.editando?.servidor ??
        (widget.servidores.isNotEmpty
            ? widget.servidores.first['value']?.toString()
            : null);
    if (!_edicao) _carregarEstados();
  }

  Future<void> _carregarEstados() async {
    try {
      final estados = await widget.carregarEstados();
      if (!mounted) return;
      setState(() {
        _estados = estados;
        _carregandoEstados = false;
      });
    } catch (e, st) {
      AppLogger.i.error('[NFSE-SERVIDOR] falha ao carregar estados: $e', st);
      if (!mounted) return;
      setState(() {
        _carregandoEstados = false;
        _erro = 'Nao foi possivel carregar os estados.';
      });
    }
  }

  Future<void> _selecionarEstado(String? id) async {
    setState(() {
      _estadoId = id;
      _cidadeId = null;
      _cidades = [];
      _carregandoCidades = id != null;
      _erro = null;
    });
    if (id == null) return;
    try {
      final cidades = await widget.carregarCidades(id);
      if (!mounted || _estadoId != id) return;
      setState(() {
        _cidades = cidades;
        _carregandoCidades = false;
      });
    } catch (e, st) {
      AppLogger.i.error('[NFSE-SERVIDOR] falha ao carregar municipios: $e', st);
      if (!mounted) return;
      setState(() {
        _carregandoCidades = false;
        _erro = 'Nao foi possivel carregar os municipios.';
      });
    }
  }

  Map<String, dynamic>? _porId(List<Map<String, dynamic>> lista, String? id) {
    for (final e in lista) {
      if (e['id']?.toString() == id) return e;
    }
    return null;
  }

  void _confirmar() {
    if (_servidor == null) {
      setState(() => _erro = 'Selecione o servidor.');
      return;
    }
    if (_edicao) {
      final e = widget.editando!;
      Navigator.pop(
          context,
          NfseServidorConfig(
              id: e.id,
              codigoIbge: e.codigoIbge,
              uf: e.uf,
              municipio: e.municipio,
              servidor: _servidor!));
      return;
    }
    final estado = _porId(_estados, _estadoId);
    final cidade = _porId(_cidades, _cidadeId);
    final ibge = (cidade?['ibge'] as num?)?.toInt();
    if (estado == null || cidade == null || ibge == null) {
      setState(() => _erro = 'Selecione o estado e o municipio.');
      return;
    }
    Navigator.pop(
        context,
        NfseServidorConfig(
            codigoIbge: ibge,
            uf: (estado['uf'] ?? '').toString(),
            municipio: (cidade['nome'] ?? '').toString(),
            servidor: _servidor!));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_edicao ? 'Editar servidor NFS-e' : 'Adicionar municipio'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_edicao)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                      '${widget.editando!.municipio} / ${widget.editando!.uf}',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                )
              else ...[
                if (_carregandoEstados)
                  const LinearProgressIndicator()
                else
                  SearchableDropdownField(
                    label: 'Estado',
                    value: _estadoId,
                    items: _estados,
                    valueField: 'id',
                    displayField: 'nome',
                    isRequired: true,
                    onChanged: _selecionarEstado,
                  ),
                const SizedBox(height: 12),
                if (_carregandoCidades)
                  const LinearProgressIndicator()
                else
                  SearchableDropdownField(
                    key: ValueKey('cidades-$_estadoId'),
                    label: 'Municipio',
                    value: _cidadeId,
                    items: _cidades,
                    valueField: 'id',
                    displayField: 'nome',
                    isRequired: true,
                    enabled: _estadoId != null,
                    onChanged: (v) => setState(() => _cidadeId = v),
                  ),
                const SizedBox(height: 12),
              ],
              DropdownButtonFormField<String>(
                key: const Key('nfse-servidor-dropdown'),
                value: _servidor,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Servidor',
                    border: OutlineInputBorder(),
                    isDense: true),
                items: widget.servidores
                    .map((s) => DropdownMenuItem<String>(
                        value: s['value']?.toString(),
                        child: Text((s['label'] ?? s['value']).toString())))
                    .toList(),
                onChanged: (v) => setState(() => _servidor = v),
              ),
              if (_erro != null) ...[
                const SizedBox(height: 10),
                Text(_erro!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
            key: const Key('nfse-servidor-confirmar'),
            onPressed: _confirmar,
            child: const Text('Salvar')),
      ],
    );
  }
}
