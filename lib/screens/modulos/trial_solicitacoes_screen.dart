import 'package:flutter/material.dart';
import '../../config/api_links.dart';
import '../../services/network_caller.dart';
import '../../utils/snackbar_utils.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/generic_error_widget.dart';

class TrialSolicitacoesScreen extends StatefulWidget {
  const TrialSolicitacoesScreen({super.key});

  @override
  State<TrialSolicitacoesScreen> createState() => _TrialSolicitacoesScreenState();
}

class _TrialSolicitacoesScreenState extends State<TrialSolicitacoesScreen> {
  final NetworkCaller _networkCaller = NetworkCaller();
  bool _isLoading = false;
  List<dynamic> _solicitacoes = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchSolicitacoes();
  }

  @override
  void dispose() {
    _networkCaller.close();
    super.dispose();
  }

  Future<void> _fetchSolicitacoes() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _networkCaller.getRequest(ApiLinks.trialSolicitacoes);
      if (response.isSuccess) {
        setState(() {
          _solicitacoes = response.body?['data'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Falha ao carregar solicitações (${response.statusCode})';
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

  Future<void> _updateStatus(int id, String newStatus) async {
    final response = await _networkCaller.putRequest(
      ApiLinks.trialSolicitacaoStatus(id),
      {'status': newStatus},
    );

    if (response.isSuccess && mounted) {
      SnackbarUtils.showSuccess(context, 'Status atualizado com sucesso!');
      _fetchSolicitacoes();
    } else if (mounted) {
      SnackbarUtils.showError(context, 'Falha ao atualizar status.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Solicitações de Trial'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchSolicitacoes,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? GenericErrorWidget(
                  message: _errorMessage!,
                  onRetry: _fetchSolicitacoes,
                )
              : _solicitacoes.isEmpty
                  ? const Center(child: Text('Nenhuma solicitação encontrada.'))
                  : RefreshIndicator(
                      onRefresh: _fetchSolicitacoes,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        itemCount: _solicitacoes.length,
                        itemBuilder: (context, index) {
                          final item = _solicitacoes[index];
                          final status = item['status'] ?? 'PENDENTE';
                          
                          Color statusColor = Colors.orange;
                          if (status == 'APROVADO') statusColor = Colors.green;
                          if (status == 'REJEITADO') statusColor = Colors.red;

                          return Card(
                            margin: const EdgeInsets.only(bottom: AppSpacing.md),
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item['nome'] ?? 'Sem Nome',
                                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Chip(
                                        label: Text(
                                          status,
                                          style: const TextStyle(color: Colors.white, fontSize: 12),
                                        ),
                                        backgroundColor: statusColor,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text('Email: ${item['email']}'),
                                  Text('Telefone: ${item['telefone']}'),
                                  if (item['cnpj'] != null && item['cnpj'].toString().isNotEmpty)
                                    Text('CNPJ: ${item['cnpj']}'),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text('Módulos: ${item['modulos'] ?? '-'}'),
                                  Text('Valor: R\$ ${item['valorTotal'] ?? '0.0'}'),
                                  if (status == 'PENDENTE') ...[
                                    const Divider(),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton(
                                          onPressed: () => _updateStatus(item['id'], 'REJEITADO'),
                                          child: const Text('Rejeitar', style: TextStyle(color: Colors.red)),
                                        ),
                                        const SizedBox(width: AppSpacing.sm),
                                        ElevatedButton(
                                          onPressed: () => _updateStatus(item['id'], 'APROVADO'),
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                          child: const Text('Aprovar'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
