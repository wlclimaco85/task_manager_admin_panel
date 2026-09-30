import 'dart:convert';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../config/api_links.dart';
import '../../services/network_caller.dart';
import '../../utils/tenant_context.dart';

class NfseAdminScreen extends StatefulWidget {
  const NfseAdminScreen({super.key, this.networkCaller});

  final NetworkCaller? networkCaller;

  @override
  State<NfseAdminScreen> createState() => _NfseAdminScreenState();
}

class _NfseAdminScreenState extends State<NfseAdminScreen> {
  late final NetworkCaller _caller = widget.networkCaller ?? NetworkCaller();
  bool get _ownsCaller => widget.networkCaller == null;
  final _buscaCtrl = TextEditingController();
  List<Map<String, dynamic>> _notas = [];
  bool _carregando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    if (_ownsCaller) _caller.close();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final response = await _caller.getRequest(ApiLinks.allNfse);
      if (!mounted) return;
      if (!response.isSuccess) {
        setState(() {
          _erro = _mensagemErro(response.body, response.statusCode);
          _carregando = false;
        });
        return;
      }
      final body = response.body;
      final data = body?['data'];
      final List<dynamic> lista = data is List
          ? data
          : data is Map && data['dados'] is List
              ? List<dynamic>.from(data['dados'] as List)
              : const <dynamic>[];
      setState(() {
        _notas = lista
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _carregando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = e.toString();
          _carregando = false;
        });
      }
    }
  }

  String _mensagemErro(dynamic body, int status) {
    if (body is Map) {
      return (body['message'] ??
              body['mensagem'] ??
              body['erro'] ??
              'Erro HTTP $status')
          .toString();
    }
    return 'Erro HTTP $status';
  }

  Future<void> _post(String url, String sucesso) async {
    final response = await _caller.postRequest(url, const {});
    if (!mounted) return;
    if (!response.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_mensagemErro(response.body, response.statusCode)),
        backgroundColor: Colors.red.shade800,
      ));
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(sucesso)));
    await _carregar();
  }

  Future<void> _excluir(Object id) async {
    final response = await _caller.deleteRequest(ApiLinks.nfseById(id));
    if (!mounted) return;
    if (!response.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_mensagemErro(response.body, response.statusCode)),
        backgroundColor: Colors.red.shade800,
      ));
      return;
    }
    await _carregar();
  }

  Future<void> _baixarDanfse(Object id) async {
    final url = TenantContext.applyToUrl(ApiLinks.nfseDanfse(id));
    final response =
        await http.get(Uri.parse(url), headers: TenantContext.headers);
    if (!mounted) return;
    if (response.statusCode != 200) {
      dynamic body;
      try {
        body = jsonDecode(response.body);
      } catch (_) {
        body = response.body;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_mensagemErro(body, response.statusCode)),
        backgroundColor: Colors.red.shade800,
      ));
      return;
    }
    await FileSaver.instance.saveFile(
      name: 'nfse-$id.pdf',
      bytes: response.bodyBytes,
      fileExtension: 'pdf',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('DANFSE salvo com sucesso.')),
      );
    }
  }

  void _detalhes(Map<String, dynamic> nota) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('NFS-e #${nota['id']}'),
        content: SelectionArea(
          child: Text(
            'Tomador: ${nota['parceiro'] ?? '-'}\n'
            'Empresa emissora: ${nota['empresa'] ?? '-'}\n'
            'Numero: ${nota['numero'] ?? '-'}\n'
            'Serie: ${nota['serie'] ?? '-'}\n'
            'Status: ${nota['status'] ?? '-'}\n'
            'Ambiente: ${nota['ambiente'] ?? '-'}\n'
            'Emissao: ${nota['data_emissao'] ?? nota['dataEmissao'] ?? '-'}\n'
            'Valor: R\$ ${nota['valor_servicos'] ?? nota['valorServicos'] ?? '0,00'}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Widget _acoes(Map<String, dynamic> nota) {
    final id = nota['id'];
    final status = (nota['status'] ?? '').toString().toUpperCase();
    return Wrap(
      spacing: 4,
      children: [
        IconButton(
          key: Key('nfse_admin_detalhes_$id'),
          tooltip: 'Ver detalhes',
          onPressed: () => _detalhes(nota),
          icon: const Icon(Icons.visibility_outlined),
        ),
        IconButton(
          key: Key('nfse_admin_confirmar_$id'),
          tooltip: 'Confirmar NFS-e',
          onPressed: status == 'RASCUNHO'
              ? () => _post(ApiLinks.nfseConfirmar(id), 'NFS-e confirmada.')
              : null,
          icon: const Icon(Icons.task_alt_outlined),
        ),
        IconButton(
          key: Key('nfse_admin_emitir_$id'),
          tooltip: 'Emitir NFS-e',
          onPressed: status == 'CONFIRMADA' || status == 'PENDENTE'
              ? () => _post(ApiLinks.nfseEmitir(id), 'NFS-e emitida.')
              : null,
          icon: const Icon(Icons.send_outlined),
        ),
        IconButton(
          key: Key('nfse_admin_danfse_$id'),
          tooltip: 'Baixar DANFSE',
          onPressed: status == 'AUTORIZADA' ? () => _baixarDanfse(id) : null,
          icon: const Icon(Icons.picture_as_pdf_outlined),
        ),
        IconButton(
          key: Key('nfse_admin_excluir_$id'),
          tooltip: 'Excluir NFS-e',
          color: Colors.red.shade700,
          onPressed:
              const {'RASCUNHO', 'CONFIRMADA', 'PENDENTE'}.contains(status)
                  ? () => _excluir(id)
                  : null,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtro = _buscaCtrl.text.trim().toLowerCase();
    final notas = _notas.where((nota) {
      if (filtro.isEmpty) return true;
      return ['id', 'numero', 'status', 'parceiro', 'empresa'].any((campo) =>
          (nota[campo] ?? '').toString().toLowerCase().contains(filtro));
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(title: const Text('NFS-e dos clientes')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('nfse_admin_busca'),
                        controller: _buscaCtrl,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(color: Color(0xFF17212B)),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText:
                              'Buscar por parceiro, empresa, numero ou status',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      key: const Key('nfse_admin_recarregar'),
                      tooltip: 'Recarregar',
                      onPressed: _carregando ? null : _carregar,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                child: _carregando
                    ? const Center(child: CircularProgressIndicator())
                    : _erro != null
                        ? Center(
                            child: Text(_erro!,
                                style: const TextStyle(color: Colors.red)))
                        : notas.isEmpty
                            ? const Center(
                                child: Text(
                                  'Nenhuma NFS-e encontrada.',
                                  style: TextStyle(color: Color(0xFF455A64)),
                                ),
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) => constraints
                                            .maxWidth <
                                        760
                                    ? ListView.separated(
                                        padding: const EdgeInsets.all(12),
                                        itemCount: notas.length,
                                        separatorBuilder: (_, __) =>
                                            const Divider(),
                                        itemBuilder: (context, index) {
                                          final nota = notas[index];
                                          return ListTile(
                                            title: Text(
                                              (nota['parceiro'] ??
                                                      'Sem tomador')
                                                  .toString(),
                                              style: const TextStyle(
                                                color: Color(0xFF17212B),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            subtitle: Text(
                                              '#${nota['id']} | ${nota['status'] ?? '-'} | R\$ ${nota['valor_servicos'] ?? '0,00'}',
                                              style: const TextStyle(
                                                  color: Color(0xFF455A64)),
                                            ),
                                            trailing: PopupMenuButton<String>(
                                              onSelected: (acao) {
                                                if (acao == 'detalhes')
                                                  _detalhes(nota);
                                                if (acao == 'confirmar') {
                                                  _post(
                                                      ApiLinks.nfseConfirmar(
                                                          nota['id']),
                                                      'NFS-e confirmada.');
                                                }
                                                if (acao == 'emitir') {
                                                  _post(
                                                      ApiLinks.nfseEmitir(
                                                          nota['id']),
                                                      'NFS-e emitida.');
                                                }
                                                if (acao == 'danfse')
                                                  _baixarDanfse(nota['id']);
                                              },
                                              itemBuilder: (_) => const [
                                                PopupMenuItem(
                                                    value: 'detalhes',
                                                    child: Text('Detalhes')),
                                                PopupMenuItem(
                                                    value: 'confirmar',
                                                    child: Text('Confirmar')),
                                                PopupMenuItem(
                                                    value: 'emitir',
                                                    child: Text('Emitir')),
                                                PopupMenuItem(
                                                    value: 'danfse',
                                                    child:
                                                        Text('Baixar DANFSE')),
                                              ],
                                            ),
                                          );
                                        },
                                      )
                                    : SingleChildScrollView(
                                        child: DataTable(
                                          columns: const [
                                            DataColumn(label: Text('ID')),
                                            DataColumn(label: Text('Parceiro')),
                                            DataColumn(label: Text('Empresa')),
                                            DataColumn(label: Text('Status')),
                                            DataColumn(label: Text('Valor')),
                                            DataColumn(label: Text('Acoes')),
                                          ],
                                          rows: notas
                                              .map((nota) => DataRow(cells: [
                                                    DataCell(
                                                        Text('${nota['id']}')),
                                                    DataCell(Text(
                                                        '${nota['parceiro'] ?? '-'}')),
                                                    DataCell(Text(
                                                        '${nota['empresa'] ?? '-'}')),
                                                    DataCell(Text(
                                                        '${nota['status'] ?? '-'}')),
                                                    DataCell(Text(
                                                        'R\$ ${nota['valor_servicos'] ?? '0,00'}')),
                                                    DataCell(_acoes(nota)),
                                                  ]))
                                              .toList(),
                                        ),
                                      ),
                              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
