import 'package:flutter/material.dart';
import '../../config/api_links.dart';
import '../../services/network_caller.dart';
import '../../utils/snackbar_utils.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/generic_error_widget.dart';

class TermoContratoSaasScreen extends StatefulWidget {
  const TermoContratoSaasScreen({super.key});

  @override
  State<TermoContratoSaasScreen> createState() => _TermoContratoSaasScreenState();
}

class _TermoContratoSaasScreenState extends State<TermoContratoSaasScreen> {
  final NetworkCaller _networkCaller = NetworkCaller();
  bool _isLoading = false;
  List<dynamic> _termos = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchTermos();
  }

  @override
  void dispose() {
    _networkCaller.close();
    super.dispose();
  }

  Future<void> _fetchTermos() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _networkCaller.getRequest(ApiLinks.trialTermos);
      if (response.isSuccess) {
        setState(() {
          _termos = response.body?['data'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Falha ao carregar termos (${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro de rede: $e';
        _isLoading = false;
      });
    }
  }

  void _abrirFormularioTermo([Map<String, dynamic>? termoEdicao]) {
    final versaoCtrl = TextEditingController(text: termoEdicao?['versao'] ?? '');
    final conteudoCtrl = TextEditingController(text: termoEdicao?['conteudo'] ?? '');
    bool saving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(termoEdicao == null ? 'Novo Termo' : 'Editar Termo'),
              content: SizedBox(
                width: 600,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: versaoCtrl,
                        decoration: const InputDecoration(labelText: 'Versão (ex: 1.0)'),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: conteudoCtrl,
                        maxLines: 15,
                        decoration: const InputDecoration(
                          labelText: 'Conteúdo (Texto ou Markdown)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (versaoCtrl.text.trim().isEmpty || conteudoCtrl.text.trim().isEmpty) {
                            SnackbarUtils.showError(ctx, 'Preencha todos os campos.');
                            return;
                          }

                          setStateDialog(() => saving = true);

                          final body = {
                            'versao': versaoCtrl.text.trim(),
                            'conteudo': conteudoCtrl.text.trim(),
                          };

                          final resp = termoEdicao == null
                              ? await _networkCaller.postRequest(ApiLinks.trialTermos, body)
                              : await _networkCaller.putRequest(ApiLinks.trialTermo(termoEdicao['id']), body);

                          if (resp.isSuccess) {
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                              SnackbarUtils.showSuccess(context, 'Termo salvo com sucesso!');
                              _fetchTermos();
                            }
                          } else {
                            if (ctx.mounted) {
                              SnackbarUtils.showError(ctx, 'Falha ao salvar: ${resp.statusCode}');
                            }
                            setStateDialog(() => saving = false);
                          }
                        },
                  child: saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _excluirTermo(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Termo'),
        content: const Text('Tem certeza que deseja excluir este termo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final response = await _networkCaller.deleteRequest(ApiLinks.trialTermo(id));
      if (response.isSuccess && mounted) {
        SnackbarUtils.showSuccess(context, 'Termo excluído!');
        _fetchTermos();
      } else if (mounted) {
        SnackbarUtils.showError(context, 'Falha ao excluir termo.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Termos de Contrato SaaS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchTermos,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _abrirFormularioTermo(),
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? GenericErrorWidget(
                  message: _errorMessage!,
                  onRetry: _fetchTermos,
                )
              : _termos.isEmpty
                  ? const Center(child: Text('Nenhum termo cadastrado.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      itemCount: _termos.length,
                      itemBuilder: (context, index) {
                        final termo = _termos[index];
                        final isAtivo = termo['ativo'] == true;

                        return Card(
                          margin: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: ListTile(
                            title: Text('Versão: ${termo['versao']}'),
                            subtitle: Text(
                              termo['conteudo']?.toString().substring(
                                      0,
                                      (termo['conteudo']?.toString().length ?? 0) > 100
                                          ? 100
                                          : termo['conteudo']?.toString().length) ??
                                  '',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isAtivo)
                                  const Chip(label: Text('Ativo', style: TextStyle(color: Colors.white, fontSize: 10)), backgroundColor: Colors.green),
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  onPressed: () => _abrirFormularioTermo(termo),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _excluirTermo(termo['id']),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
