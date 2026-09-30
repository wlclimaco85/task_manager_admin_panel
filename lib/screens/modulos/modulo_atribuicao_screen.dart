import 'package:flutter/material.dart';

import '../../config/api_links.dart';
import '../../services/network_caller.dart';
import '../../utils/app_logger.dart';
import '../../utils/dropdown_helpers.dart';
import '../../utils/grid_colors.dart';
import '../../widgets/generic_grid_windows_screen.dart';
import '../../widgets/licenca_wizard_dialog.dart';
import '../../widgets/searchable_dropdown.dart';

/// MOD-01 Modulos Contratados — tela de atribuicao de modulos a um Parceiro
/// OU Empresa com UI/UX Pro Max (design system, busca inteligente com
/// autocomplete, visualizacao em cards com iconografia, status visual,
/// selecao rapida e feedback rico).
class ModuloAtribuicaoScreen extends StatefulWidget {
  const ModuloAtribuicaoScreen({
    super.key,
    this.networkCaller,
    this.initialTipo,
    this.initialId,
    this.initialNome,
  });

  final NetworkCaller? networkCaller;
  final String? initialTipo;
  final int? initialId;
  final String? initialNome;

  @override
  State<ModuloAtribuicaoScreen> createState() =>
      ModuloAtribuicaoScreenState();
}

class ModuloAtribuicaoScreenState extends State<ModuloAtribuicaoScreen> {
  late final NetworkCaller _caller = widget.networkCaller ?? NetworkCaller();
  bool get _ownsCaller => widget.networkCaller == null;

  final TextEditingController _idCtrl = TextEditingController();
  final TextEditingController _filtroModuloCtrl = TextEditingController();
  final TextEditingController _buscaGradeCtrl = TextEditingController();

  /// Controle de exibicao: false = Grade Inicial, true = Formulario de Atribuicao
  bool _exibindoFormulario = false;
  List<Map<String, dynamic>> _gradeResumo = [];
  bool _carregandoGrade = false;
  String? _erroGrade;

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
    _carregarCatalogoInicial();
    _carregarOpcoesDropdown();
    if (widget.initialId != null) {
      _exibindoFormulario = true;
      if (widget.initialTipo != null && widget.initialTipo!.isNotEmpty) {
        _tipo = widget.initialTipo!.toLowerCase();
      }
      _carregar(widget.initialId);
    } else {
      _carregarGradeResumo();
    }
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _filtroModuloCtrl.dispose();
    _buscaGradeCtrl.dispose();
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

  Future<void> _carregarGradeResumo() async {
    if (!mounted) return;
    setState(() {
      _carregandoGrade = true;
      _erroGrade = null;
    });

    try {
      final res = await _caller.getRequest(ApiLinks.modulosAtribuidosResumo);
      if (!mounted) return;
      if (res.isSuccess) {
        final rows = GenericGridWindowsScreen.extractRows(res.body);
        setState(() {
          _gradeResumo = rows.map((r) => Map<String, dynamic>.from(r)).toList();
          _carregandoGrade = false;
        });
      } else if (res.statusCode == 404) {
        // Fallback gracioso: se o endpoint de resumo consolidado nao responder (404),
        // consulta os parceiros diretamente para permitir visualizacao e selecao sem bloquear o usuario.
        await _carregarGradeResumoFallback();
      } else {
        setState(() {
          _erroGrade = 'Falha ao carregar listagem de licencas (${res.statusCode})';
          _carregandoGrade = false;
        });
      }
    } catch (e) {
      if (mounted) {
        await _carregarGradeResumoFallback();
      }
    }
  }

  Future<void> _carregarGradeResumoFallback() async {
    try {
      final res = await _caller.getRequest(ApiLinks.dropdownParceiros);
      if (!mounted) return;
      if (res.isSuccess) {
        final rows = GenericGridWindowsScreen.extractRows(res.body);
        final lista = rows.map((r) {
          final id = _extractId(r);
          final nome = _labelDoRegistro(r);
          final doc = (r['cnpj'] ?? r['cpf'] ?? '').toString();
          return <String, dynamic>{
            'tipo': 'parceiro',
            'id': id,
            'nome': nome,
            'documento': doc,
            'quantidadeModulos': 0,
            'modulos': 'Clique para gerenciar',
          };
        }).toList();
        setState(() {
          _gradeResumo = lista;
          _carregandoGrade = false;
          _erroGrade = null;
        });
        return;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _erroGrade = 'Listagem de licencas indisponivel no momento. Clique em "Novo" para vincular modulos.';
        _carregandoGrade = false;
      });
    }
  }

  void _abrirFormularioNovo() {
    setState(() {
      _exibindoFormulario = true;
      _idCarregado = null;
      _nomeEncontrado = null;
      _moduloIdsMarcados.clear();
      _erro = null;
      _idCtrl.clear();
      _filtroModuloCtrl.clear();
    });
    _carregarOpcoesDropdown();
  }

  void _abrirFormularioEditar(Map<String, dynamic> item) {
    final tipo = (item['tipo'] ?? 'parceiro').toString().toLowerCase();
    final id = _extractId(item);
    if (id == null) return;

    setState(() {
      _exibindoFormulario = true;
      _tipo = tipo;
      _erro = null;
      _idCtrl.text = id.toString();
    });
    _carregarOpcoesDropdown();
    _carregar(id);
  }

  void _voltarParaGrade() {
    setState(() {
      _exibindoFormulario = false;
      _idCarregado = null;
      _nomeEncontrado = null;
      _moduloIdsMarcados.clear();
      _erro = null;
      _idCtrl.clear();
      _filtroModuloCtrl.clear();
    });
    _carregarGradeResumo();
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
              'nome': nome,
              'cnpj': cnpj,
              'documento': cnpj,
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

  Future<void> _carregarCatalogoInicial() async {
    try {
      final res = await _caller.getRequest(ApiLinks.allModulosServico);
      if (!mounted) return;
      if (res.isSuccess) {
        final rows = GenericGridWindowsScreen.extractRows(res.body);
        setState(() {
          _catalogo = rows.map((r) => Map<String, dynamic>.from(r)).toList();
        });
      }
    } catch (_) {}
  }

  /// Cada módulo possui um valor cadastrado ou default (R$ 49,90)
  double _getValorModulo(Map<String, dynamic> modulo) {
    final raw = modulo['valor'] ?? modulo['preco'] ?? modulo['valorMensal'];
    if (raw is num) return raw.toDouble();
    if (raw is String) {
      final parsed = double.tryParse(raw.replaceAll(',', '.'));
      if (parsed != null) return parsed;
    }
    return 49.90;
  }

  /// Regra Comercial Solicitada:
  /// - 1º Mês Grátis
  /// - Se selecionar mais de 3 módulos (> 3), o valor total do pacote é fixo em R$ 129,90
  /// - Caso contrário (1 a 3), é a soma dos valores individuais de cada módulo.
  double _calcularSubtotal() {
    final marcados = _catalogo.where((m) {
      final id = _extractId(m);
      return id != null && _moduloIdsMarcados.contains(id);
    }).toList();

    if (marcados.isEmpty) return 0.0;
    if (marcados.length > 3) {
      return 129.90;
    }
    return marcados.fold<double>(0.0, (acc, m) => acc + _getValorModulo(m));
  }

  Future<void> _abrirWizardLicenca() async {
    if (_idCarregado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Selecione ${_tipo == 'parceiro' ? "o parceiro" : "a empresa"} antes de conceder a licença.'),
          backgroundColor: GridColors.warning,
        ),
      );
      return;
    }

    final modulosNomes = _catalogo
        .where((m) {
          final id = _extractId(m);
          return id != null && _moduloIdsMarcados.contains(id);
        })
        .map((m) => (m['nome'] ?? '').toString())
        .where((nome) => nome.isNotEmpty)
        .toList();

    final empresaId = _idCarregado!;
    final empresaNome = _nomeEncontrado ?? 'Beneficiário #$empresaId';

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => LicencaWizardDialog(
        empresaId: empresaId,
        empresaNome: empresaNome,
        modulosNomes: modulosNomes,
        tipoAlvo: _tipo,
        networkCaller: _caller,
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
      if (widget.initialId == null) {
        _voltarParaGrade();
      }
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
        title: Text(_exibindoFormulario
            ? 'Atribuicao de Modulos'
            : 'Clientes com Licencas & Modulos'),
        leading: _exibindoFormulario && widget.initialId == null
            ? IconButton(
                key: const Key('modulo_atribuicao_voltar_btn'),
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Voltar para listagem',
                onPressed: _voltarParaGrade,
              )
            : null,
        elevation: 0,
        backgroundColor: GridColors.primary,
        foregroundColor: GridColors.textPrimary,
        actions: [
          if (_exibindoFormulario && _temSelecao)
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
      body: _exibindoFormulario
          ? _buildFormularioBody(modulosFiltrados)
          : _buildGradeView(),
    );
  }

  Widget _buildFormularioBody(List<Map<String, dynamic>> modulosFiltrados) {
    return Center(
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
                            if (isCompact) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SearchableDropdownField(
                                    key: ValueKey('modulo_busca_alvo_$_tipo'),
                                    label: _tipo == 'parceiro'
                                        ? 'Buscar Parceiro (Nome, Razão Social ou CNPJ)'
                                        : 'Buscar Empresa (Nome, Razão Social ou CNPJ)',
                                    hintText: 'Clique para pesquisar ou selecionar...',
                                    items: _opcoesLista,
                                    valueField: 'id',
                                    displayField: 'nome',
                                    value: _idCarregado?.toString(),
                                    prefixIcon: _tipo == 'parceiro'
                                        ? Icons.person_search
                                        : Icons.domain_verification,
                                    loadPage: _tipo == 'parceiro'
                                        ? ({String? busca, required int pagina}) =>
                                            DropdownHelpers.parceirosBusca(
                                              busca: busca,
                                              pagina: pagina,
                                              tamanho: 20,
                                            )
                                        : ({String? busca, required int pagina}) =>
                                            DropdownHelpers.empresasBusca(
                                              busca: busca,
                                              pagina: pagina,
                                              tamanho: 20,
                                            ),
                                    labelResolver: _tipo == 'parceiro'
                                        ? DropdownHelpers.parceiroLabelPorId
                                        : DropdownHelpers.empresaLabelPorId,
                                    onChanged: (novoId) {
                                      if (novoId != null) {
                                        final parsed = int.tryParse(novoId);
                                        if (parsed != null) {
                                          _carregar(parsed);
                                        }
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          key: const Key('modulo_atribuicao_id_field'),
                                          controller: _idCtrl,
                                          keyboardType: TextInputType.number,
                                          decoration: InputDecoration(
                                            isDense: true,
                                            labelText: _tipo == 'parceiro'
                                                ? 'ID Parceiro'
                                                : 'ID Empresa',
                                            floatingLabelBehavior: FloatingLabelBehavior.always,
                                            hintText: 'Ex: 42',
                                            contentPadding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 13,
                                            ),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                          ),
                                          onSubmitted: (_) => _carregar(),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        height: 44,
                                        child: ElevatedButton(
                                          key: const Key('modulo_atribuicao_carregar_btn'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: GridColors.primary,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                          ),
                                          onPressed: _carregando ? null : () => _carregar(),
                                          child: const Text('Carregar'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            }

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: SearchableDropdownField(
                                    key: ValueKey('modulo_busca_alvo_$_tipo'),
                                    label: _tipo == 'parceiro'
                                        ? 'Buscar Parceiro (Nome, Razão Social ou CNPJ)'
                                        : 'Buscar Empresa (Nome, Razão Social ou CNPJ)',
                                    hintText: 'Clique para pesquisar ou selecionar...',
                                    items: _opcoesLista,
                                    valueField: 'id',
                                    displayField: 'nome',
                                    value: _idCarregado?.toString(),
                                    prefixIcon: _tipo == 'parceiro'
                                        ? Icons.person_search
                                        : Icons.domain_verification,
                                    loadPage: _tipo == 'parceiro'
                                        ? ({String? busca, required int pagina}) =>
                                            DropdownHelpers.parceirosBusca(
                                              busca: busca,
                                              pagina: pagina,
                                              tamanho: 20,
                                            )
                                        : ({String? busca, required int pagina}) =>
                                            DropdownHelpers.empresasBusca(
                                              busca: busca,
                                              pagina: pagina,
                                              tamanho: 20,
                                            ),
                                    labelResolver: _tipo == 'parceiro'
                                        ? DropdownHelpers.parceiroLabelPorId
                                        : DropdownHelpers.empresaLabelPorId,
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
                                const SizedBox(width: 16),
                                SizedBox(
                                  width: 240,
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          key: const Key('modulo_atribuicao_id_field'),
                                          controller: _idCtrl,
                                          keyboardType: TextInputType.number,
                                          decoration: InputDecoration(
                                            isDense: true,
                                            labelText: _tipo == 'parceiro'
                                                ? 'ID Parceiro'
                                                : 'ID Empresa',
                                            floatingLabelBehavior: FloatingLabelBehavior.always,
                                            hintText: 'Ex: 42',
                                            contentPadding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 13,
                                            ),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                          ),
                                          onSubmitted: (_) => _carregar(),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        height: 44,
                                        child: ElevatedButton(
                                          key: const Key('modulo_atribuicao_carregar_btn'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: GridColors.primary,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                          ),
                                          onPressed: _carregando ? null : () => _carregar(),
                                          child: const Text('Carregar'),
                                        ),
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

                // Lista e Gestao de Modulos com Painel Lateral de Subtotal
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
                else
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isDesktop = constraints.maxWidth >= 780;
                        final subtotal = _calcularSubtotal();
                        final qtdMarcados = _moduloIdsMarcados.length;
                        final ehPacotePromocional = qtdMarcados > 3;

                        final painelLateral = Card(
                          key: const Key('modulo_atribuicao_painel_subtotal'),
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: GridColors.divider),
                          ),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.shopping_bag_outlined,
                                        color: GridColors.primary, size: 20),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'Resumo do Pacote',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 20),

                                // Badge 1º Mês Grátis
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: GridColors.successLight,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: GridColors.success.withOpacity(0.3),
                                    ),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.card_giftcard,
                                          color: GridColors.successDark, size: 18),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '1º Mês Grátis de Avaliação!',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: GridColors.successDark,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // Detalhes de itens e regra de preço
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Módulos selecionados:',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: GridColors.textMuted,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '$qtdMarcados módulo(s)',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),

                                if (ehPacotePromocional)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: GridColors.primarySoft.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'Pacote Ilimitado (> 3 módulos): valor especial fixo de R\$ 129,90/mês!',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: GridColors.primaryDark,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),

                                const Divider(height: 16),

                                // Subtotal
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Subtotal:',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      'R\$ ${subtotal.toStringAsFixed(2).replaceAll('.', ',')}/mês',
                                      key: const Key('modulo_atribuicao_subtotal_valor'),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: GridColors.primaryDark,
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 16),

                                // Botão para abrir o Wizard de Concessão de Licença
                                ElevatedButton.icon(
                                  key: const Key('modulo_atribuicao_conceder_licenca_btn'),
                                  icon: const Icon(Icons.verified_user_outlined, size: 18),
                                  label: const Text(
                                    'Conceder Licença',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: GridColors.success,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: _idCarregado == null ? null : _abrirWizardLicenca,
                                ),
                              ],
                            ),
                          ),
                        );

                        final listaModulosWidget = Column(
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
                                        final valorMod = _getValorModulo(modulo);

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
                                                        Wrap(
                                                          spacing: 8,
                                                          runSpacing: 4,
                                                          crossAxisAlignment: WrapCrossAlignment.center,
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
                                                            Text(
                                                              'R\$ ${valorMod.toStringAsFixed(2).replaceAll('.', ',')}',
                                                              style: const TextStyle(
                                                                fontSize: 12,
                                                                fontWeight: FontWeight.w600,
                                                                color: GridColors.neutral,
                                                              ),
                                                            ),
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
                                      Text(
                                        _idCarregado == null
                                            ? 'Selecione Parceiro/Empresa acima para salvar'
                                            : 'Clique em salvar para vincular ao destinatário',
                                        style: const TextStyle(
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
                                    onPressed: (_salvando || _idCarregado == null) ? null : _salvar,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );

                        if (constraints.maxWidth >= 650) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: listaModulosWidget),
                              const SizedBox(width: 16),
                              SizedBox(
                                width: 300,
                                child: painelLateral,
                              ),
                            ],
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            painelLateral,
                            const SizedBox(height: 12),
                            Expanded(child: listaModulosWidget),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
  }

  Widget _buildGradeView() {
    final filtro = _buscaGradeCtrl.text.trim().toLowerCase();
    final itensFiltrados = _gradeResumo.where((item) {
      if (filtro.isEmpty) return true;
      final nome = (item['nome'] ?? '').toString().toLowerCase();
      final modulos = (item['modulos'] ?? '').toString().toLowerCase();
      final doc = (item['documento'] ?? '').toString().toLowerCase();
      final tipo = (item['tipo'] ?? '').toString().toLowerCase();
      return nome.contains(filtro) ||
          modulos.contains(filtro) ||
          doc.contains(filtro) ||
          tipo.contains(filtro);
    }).toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Barra superior com busca, recarregar e botao Novo
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: GridColors.divider),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('modulo_atribuicao_grade_busca_field'),
                          controller: _buscaGradeCtrl,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search, color: GridColors.primary),
                            hintText: 'Filtrar por nome, documento ou modulo...',
                            suffixIcon: _buscaGradeCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _buscaGradeCtrl.clear();
                                      setState(() {});
                                    },
                                  )
                                : null,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: GridColors.divider),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: GridColors.divider),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        key: const Key('modulo_atribuicao_grade_recarregar_btn'),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Recarregar'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: GridColors.textPrimary,
                          side: const BorderSide(color: GridColors.divider),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _carregandoGrade ? null : _carregarGradeResumo,
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        key: const Key('modulo_atribuicao_novo_btn'),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Novo'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: GridColors.primary,
                          foregroundColor: GridColors.textPrimary,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 1,
                        ),
                        onPressed: _abrirFormularioNovo,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Grade de Licenças / Clientes
              Expanded(
                child: Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: GridColors.divider),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _buildGradeConteudo(itensFiltrados),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGradeConteudo(List<Map<String, dynamic>> itens) {
    if (_carregandoGrade) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_erroGrade != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: GridColors.error),
              const SizedBox(height: 12),
              Text(
                _erroGrade!,
                style: const TextStyle(color: GridColors.error, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _carregarGradeResumo,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar novamente'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: GridColors.textPrimary,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _abrirFormularioNovo,
                    icon: const Icon(Icons.add),
                    label: const Text('Atribuir Módulos (Novo)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GridColors.primary,
                      foregroundColor: GridColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (itens.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.layers_clear_outlined,
                  size: 56, color: GridColors.textSecondary.withOpacity(0.4)),
              const SizedBox(height: 12),
              const Text(
                'Nenhum cliente ou empresa com modulos vinculados encontrado.',
                style: TextStyle(fontSize: 16, color: GridColors.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                key: const Key('modulo_atribuicao_grade_vazia_novo_btn'),
                onPressed: _abrirFormularioNovo,
                icon: const Icon(Icons.add),
                label: const Text('Atribuir Modulos a um Cliente'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GridColors.primary,
                  foregroundColor: GridColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: itens.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: GridColors.divider),
      itemBuilder: (context, index) {
        final item = itens[index];
        final tipo = (item['tipo'] ?? 'parceiro').toString().toLowerCase();
        final isParceiro = tipo == 'parceiro';
        final nome = (item['nome'] ?? 'Sem nome').toString();
        final doc = (item['documento'] ?? '').toString();
        final qtd = item['quantidadeModulos'] ?? 0;
        final modulos = (item['modulos'] ?? '').toString();
        final id = item['id'];

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar do Tipo
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isParceiro
                      ? Colors.blueGrey.withOpacity(0.12)
                      : GridColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isParceiro ? Icons.person_outline : Icons.business_outlined,
                  color: isParceiro ? Colors.blueGrey.shade800 : GridColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),

              // Dados do Beneficiário
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            nome,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: GridColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (doc.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            '($doc)',
                            style: const TextStyle(fontSize: 12, color: GridColors.textSecondary),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        // Badge Tipo
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isParceiro
                                ? Colors.blue.withOpacity(0.1)
                                : Colors.teal.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isParceiro
                                  ? Colors.blue.withOpacity(0.3)
                                  : Colors.teal.withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            isParceiro ? 'Parceiro' : 'Empresa',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isParceiro ? Colors.blue.shade900 : Colors.teal.shade900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Badge Quantidade
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: GridColors.primarySoft,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$qtd ${qtd == 1 ? "modulo" : "modulos"}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: GridColors.primaryDark,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Lista resumida de módulos
                        Expanded(
                          child: Text(
                            modulos,
                            style: const TextStyle(fontSize: 12, color: GridColors.textSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 16),

              // Botão Editar
              ElevatedButton.icon(
                key: Key('modulo_atribuicao_editar_$id'),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Editar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GridColors.primary,
                  foregroundColor: GridColors.textPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                onPressed: () => _abrirFormularioEditar(item),
              ),
            ],
          ),
        );
      },
    );
  }
}
