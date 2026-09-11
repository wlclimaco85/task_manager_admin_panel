import 'package:flutter/material.dart';

import '../../config/api_links.dart';
import '../../services/network_caller.dart';
import '../../utils/app_logger.dart';
import '../../utils/grid_colors.dart';
import '../../widgets/generic_grid_windows_screen.dart';
import '../../widgets/searchable_dropdown.dart';

/// MOD-01 Modulos Contratados — tela de atribuicao de modulos a um Parceiro
/// OU Empresa com UI/UX Pro Max (design system, busca inteligente com
/// autocomplete, visualizacao em cards com iconografia, status visual,
/// selecao rapida e feedback rico).
class ModuloAtribuicaoScreen extends StatefulWidget {
  const ModuloAtribuicaoScreen({super.key, this.networkCaller});

  final NetworkCaller? networkCaller;

  @override
  State<ModuloAtribuicaoScreen> createState() =>
      ModuloAtribuicaoScreenState();
}

class ModuloAtribuicaoScreenState extends State<ModuloAtribuicaoScreen> {
  late final NetworkCaller _caller = widget.networkCaller ?? NetworkCaller();
  bool get _ownsCaller => widget.networkCaller == null;

  final TextEditingController _idCtrl = TextEditingController();
  final TextEditingController _filtroModuloCtrl = TextEditingController();

  /// 'parceiro' ou 'empresa'.
  String _tipo = 'parceiro';

  bool _carregando = false;
  bool _salvando = false;
  String? _erro;

  int? _idCarregado;
  String? _nomeEncontrado;
  List<Map<String, dynamic>> _catalogo = [];
  final Set<int> _moduloIdsMarcados = <int>{};

  // Dropdown options
  List<Map<String, dynamic>> _opcoesLista = [];
  bool _carregandoOpcoes = false;

  @override
  void initState() {
    super.initState();
    _carregarOpcoesDropdown();
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _filtroModuloCtrl.dispose();
    if (_ownsCaller) _caller.close();
    super.dispose();
  }

  bool get _temSelecao => _idCarregado != null && !_carregando;

  int? _extractId(Map<String, dynamic> row) {
    final raw = row['id'] ?? row['moduloId'];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  String _labelDoRegistro(Map<String, dynamic>? row) {
    if (row == null) return '';
    final nome = (row['nome'] ?? row['razaoSocial'] ?? row['nomeFantasia'] ?? '')
        .toString()
        .trim();
    if (nome.isNotEmpty) return nome;
    return 'Registro #${row['id'] ?? ''}';
  }

  Future<void> _carregarOpcoesDropdown() async {
    if (!mounted) return;
    setState(() {
      _carregandoOpcoes = true;
      _opcoesLista = [];
    });

    final url = _tipo == 'parceiro'
        ? ApiLinks.dropdownParceiros
        : ApiLinks.dropdownEmpresas;

    try {
      final res = await _caller.getRequest(url);
      if (!mounted) return;
      if (res.isSuccess) {
        final rows = GenericGridWindowsScreen.extractRows(res.body);
        setState(() {
          _opcoesLista = rows.map((r) {
            final id = _extractId(r);
            final nome = _labelDoRegistro(r);
            final cnpj = (r['cnpj'] ?? r['cpf'] ?? '').toString();
            final labelCompleto = cnpj.isNotEmpty ? '$nome ($cnpj)' : nome;
            return {
              'id': id.toString(),
              'nome': labelCompleto,
              'raw': r,
            };
          }).toList();
          _carregandoOpcoes = false;
        });
      } else {
        setState(() => _carregandoOpcoes = false);
        AppLogger.i.warn(
            'ModuloAtribuicaoScreen: falha ao carregar opcoes de $_tipo (status ${res.statusCode})');
        _mostrarErroCarregarOpcoes();
      }
    } catch (e) {
      if (mounted) setState(() => _carregandoOpcoes = false);
      AppLogger.i.warn(
          'ModuloAtribuicaoScreen: erro ao carregar opcoes de $_tipo: $e');
      _mostrarErroCarregarOpcoes();
    }
  }

  void _mostrarErroCarregarOpcoes() {
    if (!mounted) return;
    final tipoLabel = _tipo == 'parceiro' ? 'parceiros' : 'empresas';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: GridColors.error,
        behavior: SnackBarBehavior.floating,
        content: Text('Nao foi possivel carregar a lista de $tipoLabel. Tente novamente.'),
      ),
    );
  }

  Future<void> _carregar([int? idManual]) async {
    final idParaCarregar = idManual ?? int.tryParse(_idCtrl.text.trim());
    if (idParaCarregar == null) {
      setState(() => _erro = 'Informe um ID numerico valido.');
      return;
    }

    _idCtrl.text = idParaCarregar.toString();

    setState(() {
      _carregando = true;
      _erro = null;
      _idCarregado = null;
      _nomeEncontrado = null;
      _catalogo = [];
      _moduloIdsMarcados.clear();
      _filtroModuloCtrl.clear();
    });

    final urlRegistro = _tipo == 'parceiro'
        ? '${ApiLinks.baseUrl}/api/parceiro/$idParaCarregar'
        : '${ApiLinks.baseUrl}/api/empresa/$idParaCarregar';

    final resRegistro = await _caller.getRequest(urlRegistro);
    if (!mounted) return;

    if (!resRegistro.isSuccess) {
      setState(() {
        _carregando = false;
        _erro = _tipo == 'parceiro'
            ? 'Parceiro nao encontrado para o ID informado.'
            : 'Empresa nao encontrada para o ID informado.';
      });
      return;
    }

    final registro = _extractRecord(resRegistro.body);
    if (registro == null) {
      setState(() {
        _carregando = false;
        _erro = 'Resposta inesperada do servidor ao buscar o registro.';
      });
      return;
    }

    final urlCatalogo = ApiLinks.allModulosServico;
    final urlVinculados = _tipo == 'parceiro'
        ? ApiLinks.parceiroModulos(idParaCarregar.toString())
        : ApiLinks.empresaModulos(idParaCarregar.toString());

    final resultados = await Future.wait([
      _caller.getRequest(urlCatalogo),
      _caller.getRequest(urlVinculados),
    ]);
    if (!mounted) return;

    final resCatalogo = resultados[0];
    final resVinculados = resultados[1];

    if (!resCatalogo.isSuccess || !resVinculados.isSuccess) {
      setState(() {
        _carregando = false;
        _erro = 'Nao foi possivel carregar o catalogo/modulos vinculados.';
      });
      return;
    }

    final catalogo = GenericGridWindowsScreen.extractRows(resCatalogo.body);
    final vinculados = GenericGridWindowsScreen.extractRows(resVinculados.body);
    final idsVinculados = vinculados
        .map(_extractId)
        .whereType<int>()
        .toSet();

    setState(() {
      _carregando = false;
      _idCarregado = idParaCarregar;
      _nomeEncontrado = _labelDoRegistro(registro);
      _catalogo = catalogo;
      _moduloIdsMarcados
        ..clear()
        ..addAll(idsVinculados);
    });
  }

  Map<String, dynamic>? _extractRecord(Map<String, dynamic>? body) {
    if (body == null) return null;
    final data = body['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    if (body.containsKey('id')) return Map<String, dynamic>.from(body);
    return null;
  }

  Future<bool> _confirmarSubstituicao() async {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: GridColors.warning.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  color: GridColors.warning, size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Confirmar substituicao de modulos',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Isto substitui TODO o conjunto de modulos deste Parceiro/Empresa — '
              'modulos nao marcados serao desvinculados.',
              style: const TextStyle(fontSize: 14),
            ),
            if (_nomeEncontrado != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: GridColors.primarySoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_nomeEncontrado (ID: $_idCarregado)',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: GridColors.primaryDark,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            key: const Key('modulo_atribuicao_cancelar_btn'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            key: const Key('modulo_atribuicao_confirmar_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: GridColors.primary,
              foregroundColor: GridColors.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return resultado ?? false;
  }

  Future<void> _salvar() async {
    if (_idCarregado == null) return;
    final id = _idCarregado!;

    final confirmado = await _confirmarSubstituicao();
    if (!mounted || !confirmado) return;

    setState(() => _salvando = true);

    final url = _tipo == 'parceiro'
        ? ApiLinks.vincularParceiroModulos
        : ApiLinks.vincularEmpresaModulos;
    final body = <String, dynamic>{
      _tipo == 'parceiro' ? 'parceiroId' : 'empresaId': id,
      'moduloIds': _moduloIdsMarcados.toList(),
    };

    final response = await _caller.postRequest(url, body);
    if (!mounted) return;

    setState(() => _salvando = false);

    if (response.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: GridColors.success,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Modulos salvos com sucesso. (${_moduloIdsMarcados.length} ativos)',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: GridColors.error,
          behavior: SnackBarBehavior.floating,
          content: Text('Erro ao salvar modulos: ${response.statusCode}'),
        ),
      );
    }
  }

  IconData _getIconParaModulo(String nome) {
    final lower = nome.toLowerCase();
    if (lower.contains('financeiro') || lower.contains('caixa') || lower.contains('banc')) {
      return Icons.account_balance_wallet_outlined;
    }
    if (lower.contains('fiscal') || lower.contains('nota') || lower.contains('nfe') || lower.contains('sped')) {
      return Icons.receipt_long_outlined;
    }
    if (lower.contains('estoque') || lower.contains('produto') || lower.contains('giro')) {
      return Icons.inventory_2_outlined;
    }
    if (lower.contains('chamado') || lower.contains('suporte') || lower.contains('os') || lower.contains('atend')) {
      return Icons.support_agent_outlined;
    }
    if (lower.contains('chat') || lower.contains('conversa') || lower.contains('mensag')) {
      return Icons.forum_outlined;
    }
    if (lower.contains('pessoal') || lower.contains('func') || lower.contains('rh')) {
      return Icons.badge_outlined;
    }
    if (lower.contains('dre') || lower.contains('relat') || lower.contains('indicador')) {
      return Icons.insights_outlined;
    }
    if (lower.contains('projeto') || lower.contains('tarefa')) {
      return Icons.assignment_outlined;
    }
    return Icons.widgets_outlined;
  }

  void _selecionarTodos() {
    setState(() {
      for (final mod in _catalogo) {
        final id = _extractId(mod);
        if (id != null) _moduloIdsMarcados.add(id);
      }
    });
  }

  void _desmarcarTodos() {
    setState(() {
      _moduloIdsMarcados.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final modulosFiltrados = _catalogo.where((modulo) {
      final filtro = _filtroModuloCtrl.text.trim().toLowerCase();
      if (filtro.isEmpty) return true;
      final nome = (modulo['nome'] ?? '').toString().toLowerCase();
      final desc = (modulo['descricao'] ?? '').toString().toLowerCase();
      return nome.contains(filtro) || desc.contains(filtro);
    }).toList();

    return Scaffold(
      backgroundColor: GridColors.background,
      appBar: AppBar(
        title: const Text('Atribuicao de Modulos'),
        elevation: 0,
        backgroundColor: GridColors.primary,
        foregroundColor: GridColors.textPrimary,
        actions: [
          if (_temSelecao)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_moduloIdsMarcados.length} de ${_catalogo.length} ativos',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Card de selecao do Alvo (Parceiro / Empresa)
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: GridColors.divider),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.tune, color: GridColors.primary, size: 22),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Destinatario do Modulo',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: GridColors.textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Spacer(),
                            SegmentedButton<String>(
                              key: const Key('modulo_atribuicao_tipo_seletor'),
                              style: ButtonStyle(
                                visualDensity: VisualDensity.compact,
                                shape: WidgetStateProperty.all(
                                  RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              segments: const [
                                ButtonSegment(
                                  value: 'parceiro',
                                  label: Text('Parceiro'),
                                  icon: Icon(Icons.person_outline, size: 16),
                                ),
                                ButtonSegment(
                                  value: 'empresa',
                                  label: Text('Empresa'),
                                  icon: Icon(Icons.business_outlined, size: 16),
                                ),
                              ],
                              selected: {_tipo},
                              onSelectionChanged: (selecao) {
                                setState(() {
                                  _tipo = selecao.first;
                                  _idCarregado = null;
                                  _nomeEncontrado = null;
                                  _catalogo = [];
                                  _moduloIdsMarcados.clear();
                                  _erro = null;
                                  _idCtrl.clear();
                                });
                                _carregarOpcoesDropdown();
                              },
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        // Barra de busca: Dropdown pesquisavel + campo ID direto
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isCompact = constraints.maxWidth < 650;
                            return Flex(
                              direction: isCompact ? Axis.vertical : Axis.horizontal,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Busca inteligente com autocomplete
                                Expanded(
                                  flex: isCompact ? 0 : 3,
                                  child: SearchableDropdownField(
                                    label: _tipo == 'parceiro'
                                        ? 'Buscar Parceiro (Nome ou CNPJ)'
                                        : 'Buscar Empresa',
                                    hintText: _carregandoOpcoes
                                        ? 'Carregando lista...'
                                        : 'Clique para selecionar ou pesquisar...',
                                    items: _opcoesLista,
                                    valueField: 'id',
                                    displayField: 'nome',
                                    value: _idCarregado?.toString(),
                                    prefixIcon: _tipo == 'parceiro'
                                        ? Icons.person_search
                                        : Icons.domain_verification,
                                    onChanged: (novoId) {
                                      if (novoId != null) {
                                        final parsed = int.tryParse(novoId);
                                        if (parsed != null) {
                                          _carregar(parsed);
                                        }
                                      }
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: isCompact ? 0 : 16,
                                  height: isCompact ? 12 : 0,
                                ),
                                // Ou ID direto com botao Carregar
                                SizedBox(
                                  width: isCompact ? double.infinity : 240,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          key: const Key('modulo_atribuicao_id_field'),
                                          controller: _idCtrl,
                                          keyboardType: TextInputType.number,
                                          decoration: InputDecoration(
                                            isDense: true,
                                            labelText: _tipo == 'parceiro'
                                                ? 'ID do Parceiro'
                                                : 'ID da Empresa',
                                            hintText: 'Ex: 42',
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                          ),
                                          onSubmitted: (_) => _carregar(),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        key: const Key('modulo_atribuicao_carregar_btn'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: GridColors.primary,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 14,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        onPressed: _carregando ? null : () => _carregar(),
                                        child: const Text('Carregar'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        // Mensagem de Erro
                        if (_erro != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: GridColors.errorLight,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: GridColors.error),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: GridColors.error, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _erro!,
                                    key: const Key('modulo_atribuicao_erro'),
                                    style: const TextStyle(
                                      color: GridColors.errorDark,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        // Registro Encontrado
                        if (_nomeEncontrado != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: GridColors.successLight,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: GridColors.success.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle, color: GridColors.success, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Encontrado: $_nomeEncontrado',
                                    key: const Key('modulo_atribuicao_nome_encontrado'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: GridColors.successDark,
                                    ),
                                  ),
                                ),
                                Text(
                                  'ID: $_idCarregado',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: GridColors.neutral,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Lista e Gestao de Modulos
                if (_carregando)
                  const Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text(
                            'Carregando catalogo e modulos vinculados...',
                            style: TextStyle(color: GridColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (!_temSelecao)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _tipo == 'parceiro'
                                ? Icons.person_search_outlined
                                : Icons.domain_outlined,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _tipo == 'parceiro'
                                ? 'Selecione ou informe o Parceiro acima para gerenciar os modulos.'
                                : 'Selecione ou informe a Empresa acima para gerenciar os modulos.',
                            style: const TextStyle(
                              fontSize: 15,
                              color: GridColors.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Barra de Acoes Rapidas da Lista de Modulos
                        Row(
                          children: [
                            // Campo de Filtro rapido de modulos
                            Expanded(
                              child: TextField(
                                controller: _filtroModuloCtrl,
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: 'Filtrar modulos nesta tela...',
                                  prefixIcon: const Icon(Icons.search, size: 20),
                                  suffixIcon: _filtroModuloCtrl.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear, size: 18),
                                          onPressed: () => setState(() => _filtroModuloCtrl.clear()),
                                        )
                                      : null,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              key: const Key('modulo_atribuicao_selecionar_todos_btn'),
                              icon: const Icon(Icons.select_all, size: 18),
                              label: const Text('Marcar Todos'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: GridColors.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: _selecionarTodos,
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              key: const Key('modulo_atribuicao_limpar_btn'),
                              icon: const Icon(Icons.deselect, size: 18),
                              label: const Text('Limpar'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: GridColors.textMuted,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: _desmarcarTodos,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Lista de Modulos em Cards
                        Expanded(
                          child: _catalogo.isEmpty
                              ? const Center(
                                  child: Text('Nenhum modulo cadastrado no catalogo.'),
                                )
                              : ListView.builder(
                                  key: const Key('modulo_atribuicao_lista'),
                                  itemCount: modulosFiltrados.length,
                                  itemBuilder: (context, index) {
                                    final modulo = modulosFiltrados[index];
                                    final id = _extractId(modulo);
                                    final marcado =
                                        id != null && _moduloIdsMarcados.contains(id);
                                    final nome = modulo['nome']?.toString() ?? '';
                                    final desc = modulo['descricao']?.toString() ?? '';
                                    final icon = _getIconParaModulo(nome);

                                    return Card(
                                      key: ValueKey('modulo_card_$id'),
                                      elevation: marcado ? 2 : 0,
                                      margin: const EdgeInsets.only(bottom: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        side: BorderSide(
                                          color: marcado
                                              ? GridColors.primary
                                              : GridColors.divider,
                                          width: marcado ? 1.5 : 1.0,
                                        ),
                                      ),
                                      color: marcado
                                          ? GridColors.primarySoft.withOpacity(0.4)
                                          : Colors.white,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: id == null
                                            ? null
                                            : () {
                                                setState(() {
                                                  if (marcado) {
                                                    _moduloIdsMarcados.remove(id);
                                                  } else {
                                                    _moduloIdsMarcados.add(id);
                                                  }
                                                });
                                              },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(10),
                                                decoration: BoxDecoration(
                                                  color: marcado
                                                      ? GridColors.primary
                                                      : Colors.grey.shade100,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Icon(
                                                  icon,
                                                  color: marcado
                                                      ? Colors.white
                                                      : Colors.grey.shade600,
                                                  size: 24,
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Text(
                                                          nome,
                                                          style: TextStyle(
                                                            fontSize: 15,
                                                            fontWeight: FontWeight.bold,
                                                            color: marcado
                                                                ? GridColors.primaryDark
                                                                : GridColors.textSecondary,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        if (marcado)
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 2,
                                                            ),
                                                            decoration: BoxDecoration(
                                                              color: GridColors.successLight,
                                                              borderRadius: BorderRadius.circular(12),
                                                            ),
                                                            child: const Text(
                                                              'CONTRATADO',
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                fontWeight: FontWeight.bold,
                                                                color: GridColors.successDark,
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                    if (desc.isNotEmpty) ...[
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        desc,
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: GridColors.textMuted,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              Checkbox(
                                                key: Key('modulo_atribuicao_checkbox_$id'),
                                                value: marcado,
                                                activeColor: GridColors.primary,
                                                onChanged: id == null
                                                    ? null
                                                    : (checked) {
                                                        setState(() {
                                                          if (checked == true) {
                                                            _moduloIdsMarcados.add(id);
                                                          } else {
                                                            _moduloIdsMarcados.remove(id);
                                                          }
                                                        });
                                                      },
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),

                        // Barra inferior de Salvar
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                                offset: Offset(0, -2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${_moduloIdsMarcados.length} modulos selecionados',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: GridColors.textSecondary,
                                    ),
                                  ),
                                  const Text(
                                    'Clique em salvar para aplicar as alteracoes',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: GridColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              ElevatedButton.icon(
                                key: const Key('modulo_atribuicao_salvar_btn'),
                                icon: _salvando
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.save_outlined),
                                label: Text(
                                  _salvando ? 'Salvando...' : 'Salvar',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: GridColors.primary,
                                  foregroundColor: GridColors.textPrimary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: _salvando ? null : _salvar,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
