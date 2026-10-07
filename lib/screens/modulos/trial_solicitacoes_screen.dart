import 'package:flutter/material.dart';
import '../../config/api_links.dart';
import '../../services/network_caller.dart';
import '../../utils/app_logger.dart';
import '../../utils/snackbar_utils.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/generic_error_widget.dart';
import '../../widgets/licenca_wizard_dialog.dart';
import '../../services/trial_aprovacao_service.dart';

class TrialSolicitacoesScreen extends StatefulWidget {
  const TrialSolicitacoesScreen({super.key, this.networkCaller, this.empresaIdProvider});

  /// Injetaveis para teste.
  final NetworkCaller? networkCaller;
  final int? Function()? empresaIdProvider;

  @override
  State<TrialSolicitacoesScreen> createState() => _TrialSolicitacoesScreenState();
}

class _TrialSolicitacoesScreenState extends State<TrialSolicitacoesScreen> {
  late final NetworkCaller _networkCaller = widget.networkCaller ?? NetworkCaller();
  late final TrialAprovacaoService _service = TrialAprovacaoService(
      caller: _networkCaller, empresaIdProvider: widget.empresaIdProvider);
  bool _isLoading = false;
  List<dynamic> _solicitacoes = [];
  String? _errorMessage;

  /// Id da solicitacao em processo de aprovacao (bloqueia cliques repetidos).
  int? _aprovandoId;

  @override
  void initState() {
    super.initState();
    _fetchSolicitacoes();
  }

  @override
  void dispose() {
    if (widget.networkCaller == null) _networkCaller.close();
    super.dispose();
  }

  static int? _idDe(dynamic bruto) =>
      bruto is int ? bruto : int.tryParse(bruto?.toString() ?? '');

  /// "Aprovar" = mesmo processo de cliente com licenca e modulos: garante o
  /// cliente (parceiro), vincula os modulos pedidos, abre o popup de
  /// Role/Usuario/Finalizar e so' entao marca APROVADO. Cancelar o popup
  /// desfaz o que foi criado e a solicitacao continua PENDENTE.
  Future<void> _aprovar(Map<String, dynamic> item) async {
    final id = _idDe(item['id']);
    if (id == null || _aprovandoId != null) return;
    setState(() => _aprovandoId = id);

    ClienteTrialPreparado? cliente;
    var concedida = false;
    try {
      final catalogo = await _service.carregarCatalogo();
      final mapa = TrialAprovacaoService.mapearModulos(
          TrialAprovacaoService.parseModulosNomes(item['modulos']), catalogo);
      if (!mapa.temCorrespondencia) {
        throw const TrialAprovacaoException(
            'Nenhum dos módulos solicitados existe no catálogo. Cadastre os módulos antes de aprovar.');
      }
      if (mapa.naoEncontrados.isNotEmpty) {
        final continuar = await _confirmarModulosSemCorrespondencia(mapa);
        if (!continuar || !mounted) return;
      }

      cliente = await _service.prepararCliente(item, mapa);
      if (!mounted) {
        await _service.desfazer(cliente);
        return;
      }

      final preparado = cliente;
      final resultado = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => LicencaWizardDialog(
          empresaId: preparado.parceiroId,
          empresaNome: preparado.parceiroNome,
          modulosNomes: preparado.modulosNomes,
          tipoAlvo: 'parceiro',
          empresaMatrizId: preparado.empresaId,
          networkCaller: _networkCaller,
          usuarioSugerido: UsuarioSugerido(
            nome: (item['nome'] ?? '').toString(),
            email: (item['email'] ?? '').toString(),
            cpfCnpj: TrialAprovacaoService.documentoDaSolicitacao(item),
          ),
          onLoginCriado: preparado.loginsCriados.add,
        ),
      );

      if (!TrialAprovacaoService.deveMarcarAprovado(resultado)) {
        final revertido = await _service.desfazer(preparado);
        if (mounted) {
          SnackbarUtils.showWarning(
              context,
              revertido
                  ? 'Aprovação cancelada. A solicitação continua PENDENTE e nada foi criado.'
                  : 'Aprovação cancelada, mas parte do cadastro não pôde ser desfeita. Revise em Atribuição de Módulos.');
        }
        return;
      }

      concedida = true;
      await _service.atualizarStatus(id, 'APROVADO',
          obs: _montarObs(preparado, mapa));
      if (mounted) {
        SnackbarUtils.showSuccess(context,
            'Solicitação aprovada: ${preparado.parceiroNome} agora aparece em Clientes com Licenças & Módulos.');
        _fetchSolicitacoes();
      }
    } on TrialAprovacaoException catch (e) {
      AppLogger.i.warn('Aprovar trial #$id: ${e.mensagem}');
      if (mounted) {
        SnackbarUtils.showError(
            context,
            concedida
                ? 'Licença concedida, mas a solicitação não foi marcada como APROVADA (${e.mensagem}). Clique em Aprovar novamente: o cliente será reaproveitado.'
                : e.mensagem);
      }
    } catch (e, st) {
      AppLogger.i.error('Aprovar trial #$id: $e', st);
      if (cliente != null && !concedida) await _service.desfazer(cliente);
      if (mounted) SnackbarUtils.showError(context, 'Falha ao aprovar: $e');
    } finally {
      if (mounted) setState(() => _aprovandoId = null);
    }
  }

  String _montarObs(ClienteTrialPreparado cliente, ModulosMapeados mapa) {
    final partes = <String>[
      'Cliente ${cliente.parceiroCriado ? 'criado' : 'reaproveitado'}: parceiro #${cliente.parceiroId}',
      'módulos: ${mapa.nomesVinculados.join(', ')}',
      if (mapa.naoEncontrados.isNotEmpty)
        'sem correspondência no catálogo: ${mapa.naoEncontrados.join(', ')}',
    ];
    return partes.join(' | ');
  }

  Future<bool> _confirmarModulosSemCorrespondencia(ModulosMapeados mapa) async {
    final continuar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Módulos sem correspondência'),
        content: Text(
            'Estes módulos da solicitação não existem no catálogo e NÃO serão vinculados: '
            '${mapa.naoEncontrados.join(', ')}.\n\n'
            'Serão vinculados: ${mapa.nomesVinculados.join(', ')}.'),
        actions: [
          TextButton(
            key: const Key('trial_modulos_cancelar_btn'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            key: const Key('trial_modulos_continuar_btn'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    return continuar == true;
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
    try {
      // Corpo simples ({"status": ...}): o backend le o corpo como mapa e o
      // enriquecimento do TenantContext (empresa/aplicativo como objetos) fazia a
      // aprovacao falhar com erro 500/400.
      final response = await _networkCaller.putRequest(
        ApiLinks.trialSolicitacaoStatus(id),
        {'status': newStatus},
        enriquecerCorpo: false,
      );

      if (response.isSuccess && mounted) {
        SnackbarUtils.showSuccess(context, 'Status atualizado com sucesso!');
        _fetchSolicitacoes();
      } else if (mounted) {
        AppLogger.i.warn(
            'Trial #$id -> $newStatus falhou: HTTP ${response.statusCode}');
        SnackbarUtils.showError(
            context, 'Falha ao atualizar status (HTTP ${response.statusCode}).');
      }
    } catch (e, st) {
      AppLogger.i.error('Trial #$id -> $newStatus: $e', st);
      if (mounted) {
        SnackbarUtils.showError(context, 'Falha ao atualizar status: $e');
      }
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
                                  if (item['telefone'] != null &&
                                      item['telefone'].toString().isNotEmpty)
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
                                          key: Key('trial_rejeitar_${item['id']}'),
                                          onPressed: _aprovandoId != null
                                              ? null
                                              : () => _updateStatus(item['id'], 'REJEITADO'),
                                          child: const Text('Rejeitar', style: TextStyle(color: Colors.red)),
                                        ),
                                        const SizedBox(width: AppSpacing.sm),
                                        ElevatedButton(
                                          key: Key('trial_aprovar_${item['id']}'),
                                          onPressed: _aprovandoId != null
                                              ? null
                                              : () => _aprovar(Map<String, dynamic>.from(item)),
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                          child: _aprovandoId == _idDe(item['id'])
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(
                                                      strokeWidth: 2, color: Colors.white),
                                                )
                                              : const Text('Aprovar'),
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
