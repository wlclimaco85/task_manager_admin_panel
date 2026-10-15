import 'package:flutter/material.dart';
import '../../models/modulo_servico_tela_model.dart';
import '../../models/network_response.dart';
import '../../services/network_caller.dart';
import '../../utils/grid_colors.dart';

class WebModuloTelaGridScreen extends StatefulWidget {
  final bool isMobile;
  const WebModuloTelaGridScreen({super.key, this.isMobile = false});

  @override
  State<WebModuloTelaGridScreen> createState() => _WebModuloTelaGridScreenState();
}

class _WebModuloTelaGridScreenState extends State<WebModuloTelaGridScreen> {
  final NetworkCaller _networkCaller = NetworkCaller();
  final TextEditingController _buscaController = TextEditingController();

  List<ModuloServicoTelaModel> _itens = [];
  List<Map<String, dynamic>> _modulosDisponiveis = [];
  int? _moduloFiltroId;
  bool _isLoading = false;
  bool _isRecarregandoCache = false;
  int _paginaAtual = 0;
  int _tamanhoPagina = 25;
  int _totalElementos = 0;
  int _totalPaginas = 1;

  @override
  void initState() {
    super.initState();
    _carregarModulosResumo();
    _carregarDados();
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  Future<void> _carregarModulosResumo() async {
    try {
      final NetworkResponse response =
          await _networkCaller.getRequest('/api/modulo-servico-tela/modulos-resumo');
      if (response.isSuccess && response.body != null) {
        final raw = response.body!['data'] ?? response.body!['dados'];
        if (raw is List && mounted) {
          setState(() {
            _modulosDisponiveis =
                raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _carregarDados() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    String url = '/api/modulo-servico-tela?pagina=$_paginaAtual&tamanho=$_tamanhoPagina';
    if (_moduloFiltroId != null) {
      url += '&moduloId=$_moduloFiltroId';
    }
    if (_buscaController.text.trim().isNotEmpty) {
      url += '&busca=${Uri.encodeComponent(_buscaController.text.trim())}';
    }

    try {
      final NetworkResponse response = await _networkCaller.getRequest(url);
      if (response.isSuccess && response.body != null) {
        final data = response.body!['data'];
        final List<dynamic> lista = data is Map
            ? (data['dados'] ?? data['content'] ?? [])
            : (data is List ? data : []);
        final total = data is Map
            ? (data['totalItens'] ?? data['totalElements'] ?? 0)
            : lista.length;
        final totalPags = data is Map
            ? (data['totalPaginas'] ?? data['totalPages'] ?? 1)
            : 1;

        if (mounted) {
          setState(() {
            _itens = lista.map((j) => ModuloServicoTelaModel.fromJson(j)).toList();
            _totalElementos = total is int ? total : int.tryParse(total.toString()) ?? 0;
            _totalPaginas = totalPags is int ? totalPags : int.tryParse(totalPags.toString()) ?? 1;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Falha ao carregar dados: ${response.statusCode}'),
              backgroundColor: GridColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro de conexao: $e'),
            backgroundColor: GridColors.error,
          ),
        );
      }
    }
  }

  Future<void> _recarregarCache() async {
    setState(() => _isRecarregandoCache = true);
    try {
      final NetworkResponse response =
          await _networkCaller.postRequest('/api/modulo-servico-tela/recarregar-cache', {});
      if (mounted) {
        setState(() => _isRecarregandoCache = false);
        if (response.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cache de modulos e telas sincronizado com sucesso no backend.'),
              backgroundColor: GridColors.success,
            ),
          );
          _carregarDados();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Falha ao sincronizar cache: ${response.statusCode}'),
              backgroundColor: GridColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRecarregandoCache = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao sincronizar: $e'),
            backgroundColor: GridColors.error,
          ),
        );
      }
    }
  }

  void _abrirModalFormulario({ModuloServicoTelaModel? item}) {
    int? moduloSelecionadoId = item?.moduloId ?? (_moduloFiltroId ?? (_modulosDisponiveis.isNotEmpty ? _modulosDisponiveis.first['id'] as int? : null));
    final telaCtrl = TextEditingController(text: item?.telaNome ?? '');
    final rotaCtrl = TextEditingController(text: item?.rotaApi ?? '');
    final descCtrl = TextEditingController(text: item?.descricao ?? '');
    bool ativo = item?.ativo ?? true;
    bool salvando = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            title: Row(
              children: [
                Icon(
                  item == null ? Icons.add_circle_outline : Icons.edit_outlined,
                  color: GridColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  item == null ? 'Nova Associação Tela x Módulo' : 'Editar Associação',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Selecione o módulo contratado e informe o identificador da tela ou rota de API correspondente.',
                      style: TextStyle(fontSize: 13, color: GridColors.textMuted),
                    ),
                    const SizedBox(height: 16),
                    // Dropdown de Modulo
                    const Text('Módulo Contratado *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      value: moduloSelecionadoId,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: _modulosDisponiveis.map((m) {
                        return DropdownMenuItem<int>(
                          value: m['id'] as int,
                          child: Text('${m['nome']} (ID: ${m['id']})'),
                        );
                      }).toList(),
                      onChanged: (val) => setDialogState(() => moduloSelecionadoId = val),
                    ),
                    const SizedBox(height: 16),
                    // Nome da Tela
                    const Text('Nome da Tela (Identificador interno) *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: telaCtrl,
                      decoration: const InputDecoration(
                        hintText: 'ex: nfce_screen, nfe_screen, conta_pagar_screen',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Identificador snake_case utilizado no Flutter e nas regras de permissão.',
                      style: TextStyle(fontSize: 11, color: GridColors.textMuted),
                    ),
                    const SizedBox(height: 16),
                    // Rota de API
                    const Text('Rota da API (Endpoint REST protegido)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: rotaCtrl,
                      decoration: const InputDecoration(
                        hintText: 'ex: /api/nfce, /api/pedido, /api/conta-pagar',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Prefixo da rota no backend que será protegido e liberado apenas para clientes deste módulo.',
                      style: TextStyle(fontSize: 11, color: GridColors.textMuted),
                    ),
                    const SizedBox(height: 16),
                    // Descrição
                    const Text('Descrição Amigável', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(
                        hintText: 'ex: Emissão e Consulta de Cupons Fiscais (NFC-e)',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Switch Ativo
                    Row(
                      children: [
                        Switch(
                          value: ativo,
                          activeColor: GridColors.success,
                          onChanged: (v) => setDialogState(() => ativo = v),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          ativo ? 'Associação Ativa' : 'Associação Inativa',
                          style: TextStyle(
                            color: ativo ? GridColors.success : GridColors.neutral,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: salvando ? null : () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                icon: salvando
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check, size: 18),
                label: Text(item == null ? 'Cadastrar' : 'Salvar Alterações'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GridColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: salvando
                    ? null
                    : () async {
                        if (moduloSelecionadoId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Selecione um módulo.'), backgroundColor: GridColors.error),
                          );
                          return;
                        }
                        if (telaCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Informe o nome da tela.'), backgroundColor: GridColors.error),
                          );
                          return;
                        }

                        setDialogState(() => salvando = true);
                        final payload = {
                          if (item != null) 'id': item.id,
                          'modulo': {'id': moduloSelecionadoId},
                          'telaNome': telaCtrl.text.trim().toLowerCase(),
                          'rotaApi': rotaCtrl.text.trim().isNotEmpty ? rotaCtrl.text.trim() : null,
                          'descricao': descCtrl.text.trim().isNotEmpty ? descCtrl.text.trim() : null,
                          'ativo': ativo,
                        };

                        try {
                          final NetworkResponse response = item == null
                              ? await _networkCaller.postRequest('/api/modulo-servico-tela', payload)
                              : await _networkCaller.putRequest('/api/modulo-servico-tela/${item.id}', payload);

                          if (response.isSuccess) {
                            if (mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(item == null ? 'Tela associada com sucesso!' : 'Associação atualizada!'),
                                  backgroundColor: GridColors.success,
                                ),
                              );
                              _carregarModulosResumo();
                              _carregarDados();
                            }
                          } else {
                            setDialogState(() => salvando = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Erro ao salvar: ${response.body?['message'] ?? response.statusCode}'),
                                  backgroundColor: GridColors.error,
                                ),
                              );
                            }
                          }
                        } catch (e) {
                          setDialogState(() => salvando = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Erro: $e'), backgroundColor: GridColors.error),
                            );
                          }
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmarExclusao(ModuloServicoTelaModel item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Associação'),
        content: Text(
          'Deseja realmente remover a tela "${item.telaNome}" do módulo "${item.moduloNome}"?\n\n'
          'Clientes que contratam este módulo deixarão de ter acesso a esta tela no backend.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: GridColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final response = await _networkCaller.deleteRequest('/api/modulo-servico-tela/${item.id}');
                if (response.isSuccess) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Associação removida com sucesso.'), backgroundColor: GridColors.success),
                    );
                    _carregarModulosResumo();
                    _carregarDados();
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Falha ao excluir: ${response.statusCode}'), backgroundColor: GridColors.error),
                    );
                  }
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erro: $e'), backgroundColor: GridColors.error),
                  );
                }
              }
            },
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  Color _corDoModulo(String nome) {
    final n = nome.toLowerCase();
    if (n.contains('comercial')) return Colors.blue.shade700;
    if (n.contains('financeiro')) return GridColors.secondary;
    if (n.contains('pessoal') || n.contains('dp')) return Colors.orange.shade800;
    if (n.contains('nfc')) return GridColors.primary;
    if (n.contains('nfs')) return Colors.purple.shade700;
    if (n.contains('service') || n.contains('chamado')) return Colors.teal.shade700;
    if (n.contains('projeto')) return Colors.indigo.shade700;
    if (n.contains('precifica')) return Colors.brown.shade700;
    return Colors.blueGrey;
  }

  Widget _buildHeader() {
    return Container(
      height: 56,
      color: GridColors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          if (Navigator.canPop(context))
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                tooltip: 'Voltar',
                onPressed: () => Navigator.pop(context),
              ),
            ),
          const Icon(Icons.layers_outlined, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Telas por Módulo do Sistema',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          OutlinedButton.icon(
            icon: _isRecarregandoCache
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.sync, color: Colors.white, size: 16),
            label: const Text('Recarregar Cache', style: TextStyle(color: Colors.white, fontSize: 13)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            onPressed: _isRecarregandoCache ? null : _recarregarCache,
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Nova Associação', style: TextStyle(fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: GridColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onPressed: () => _abrirModalFormulario(),
          ),
        ],
      ),
    );
  }

  Widget _buildBannerInformativo() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GridColors.secondarySoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GridColors.secondary.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: GridColors.secondary, size: 22),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Mapeamento dinâmico via Banco de Dados: Define quais telas e rotas de API pertencem a cada módulo de serviço. '
              'Os filtros de segurança e licenças no backend Spring Boot utilizam este catálogo para validar o acesso dos usuários em tempo real.',
              style: TextStyle(fontSize: 13, color: GridColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarraFiltros() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GridColors.divider),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Filtro por Modulo
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<int?>(
              value: _moduloFiltroId,
              decoration: const InputDecoration(
                labelText: 'Filtrar por Módulo',
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Todos os Módulos'),
                ),
                ..._modulosDisponiveis.map((m) {
                  final qtd = m['totalTelas'] ?? 0;
                  return DropdownMenuItem<int?>(
                    value: m['id'] as int?,
                    child: Text('${m['nome']} ($qtd)'),
                  );
                }),
              ],
              onChanged: (val) {
                setState(() {
                  _moduloFiltroId = val;
                  _paginaAtual = 0;
                });
                _carregarDados();
              },
            ),
          ),
          // Campo de busca
          SizedBox(
            width: 280,
            child: TextField(
              controller: _buscaController,
              decoration: InputDecoration(
                hintText: 'Buscar tela, rota ou descrição...',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _buscaController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _buscaController.clear();
                          _carregarDados();
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              onSubmitted: (_) {
                setState(() => _paginaAtual = 0);
                _carregarDados();
              },
            ),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.filter_list, size: 16),
            label: const Text('Filtrar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: GridColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onPressed: () {
              setState(() => _paginaAtual = 0);
              _carregarDados();
            },
          ),
          Text(
            'Total: $_totalElementos tela(s)',
            style: const TextStyle(fontWeight: FontWeight.bold, color: GridColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildTabela() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_itens.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.layers_clear_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text(
                'Nenhuma associação de tela encontrada.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              const Text(
                'Cadastre uma nova associação ou limpe os filtros de busca.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Associar Tela'),
                style: ElevatedButton.styleFrom(backgroundColor: GridColors.primary, foregroundColor: Colors.white),
                onPressed: () => _abrirModalFormulario(),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GridColors.divider),
      ),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: MaterialStateProperty.all(GridColors.gridHeader),
                  headingRowHeight: 44,
                  dataRowHeight: 48,
                  columns: const [
                    DataColumn(label: Text('Id', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Módulo', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Nome da Tela', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Rota de API', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Descrição', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Ações', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: _itens.map((item) {
                    final corMod = _corDoModulo(item.moduloNome);
                    return DataRow(
                      cells: [
                        DataCell(Text(item.id.toString())),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: corMod.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: corMod.withOpacity(0.4)),
                            ),
                            child: Text(
                              item.moduloNome,
                              style: TextStyle(color: corMod, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            item.telaNome,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                          ),
                        ),
                        DataCell(
                          Text(
                            item.rotaApi ?? '—',
                            style: TextStyle(
                              color: item.rotaApi != null ? Colors.blue.shade900 : Colors.grey,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            item.descricao ?? '—',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: item.ativo ? GridColors.success : GridColors.error,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(item.ativo ? 'Ativo' : 'Inativo', style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.blue),
                                tooltip: 'Editar',
                                onPressed: () => _abrirModalFormulario(item: item),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: GridColors.error),
                                tooltip: 'Remover',
                                onPressed: () => _confirmarExclusao(item),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          // Barra de paginacao
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: GridColors.divider)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Página ${_paginaAtual + 1} de $_totalPaginas ($_totalElementos itens)',
                  style: const TextStyle(fontSize: 12, color: GridColors.textMuted),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      tooltip: 'Página anterior',
                      onPressed: _paginaAtual > 0
                          ? () {
                              setState(() => _paginaAtual--);
                              _carregarDados();
                            }
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      tooltip: 'Próxima página',
                      onPressed: (_paginaAtual + 1) < _totalPaginas
                          ? () {
                              setState(() => _paginaAtual++);
                              _carregarDados();
                            }
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildHeader(),
        _buildBannerInformativo(),
        _buildBarraFiltros(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _itens.isEmpty
                  ? const Center(child: Text('Nenhuma tela cadastrada.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _itens.length,
                      itemBuilder: (ctx, i) {
                        final item = _itens[i];
                        final cor = _corDoModulo(item.moduloNome);
                        return Card(
                          elevation: 1,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: cor.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(item.moduloNome, style: TextStyle(color: cor, fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.blue),
                                          onPressed: () => _abrirModalFormulario(item: item),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, size: 20, color: GridColors.error),
                                          onPressed: () => _confirmarExclusao(item),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(item.telaNome, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'monospace')),
                                if (item.rotaApi != null) ...[
                                  const SizedBox(height: 2),
                                  Text(item.rotaApi!, style: TextStyle(color: Colors.blue.shade900, fontSize: 13, fontFamily: 'monospace')),
                                ],
                                if (item.descricao != null) ...[
                                  const SizedBox(height: 4),
                                  Text(item.descricao!, style: const TextStyle(fontSize: 12, color: GridColors.textMuted)),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isMobile) {
      return Scaffold(
        backgroundColor: GridColors.background,
        body: SafeArea(child: _buildMobileLayout()),
        floatingActionButton: FloatingActionButton(
          backgroundColor: GridColors.primary,
          foregroundColor: Colors.white,
          onPressed: () => _abrirModalFormulario(),
          child: const Icon(Icons.add),
        ),
      );
    }

    return Scaffold(
      backgroundColor: GridColors.background,
      body: Column(
        children: [
          _buildHeader(),
          _buildBannerInformativo(),
          _buildBarraFiltros(),
          Expanded(child: _buildTabela()),
        ],
      ),
    );
  }
}
