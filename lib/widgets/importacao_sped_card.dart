// Card cUlANCTt - Importar arquivo SPED (EFD ICMS/IPI) em
// Sistema > Config de Sistemas. Clone adaptado de ImportacaoSintegraCard
// (mesmo padrao de dropdown de empresa + upload + resumo) porque e o mesmo
// fluxo de UI para outro formato de arquivo fiscal.
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:http/http.dart' as http;

import '../config/api_links.dart';
import '../utils/grid_colors.dart';
import '../utils/tenant_context.dart';
import 'searchable_dropdown.dart';

typedef ImportacaoSpedLoader = Future<List<Map<String, dynamic>>>
    Function();
typedef ImportacaoSpedSubmit = Future<Map<String, dynamic>> Function(
  String empresaId,
  PlatformFile arquivo,
);
// Pedido explicito do usuario: combos de conta bancaria/centro de custo
// escopados pela empresa selecionada -- injetavel pra permitir teste de
// regressao sem depender do TenantContext/HTTP reais.
typedef ImportacaoFinanceiroLoader = Future<List<Map<String, dynamic>>>
    Function(String? empresaId);
// Ver comentario completo em ImportacaoSintegraCard.
typedef ImportacaoContasBancariasLoader = Future<List<Map<String, dynamic>>>
    Function(String? empresaId, String? parceiroId);
typedef ImportacaoIdentificarParceiroLoader
    = Future<Map<String, dynamic>?> Function(
        String empresaId, PlatformFile arquivo);

class ImportacaoSpedCard extends StatefulWidget {
  final String baseUrl;
  final ImportacaoSpedLoader? carregarEmpresas;
  final ImportacaoSpedSubmit? importar;
  final ImportacaoContasBancariasLoader? carregarContasBancarias;
  final ImportacaoFinanceiroLoader? carregarCentrosCusto;
  final ImportacaoIdentificarParceiroLoader? identificarParceiro;
  final PlatformFile? arquivoInicial;
  final String? empresaIdInicial;

  const ImportacaoSpedCard({
    super.key,
    required this.baseUrl,
    this.carregarEmpresas,
    this.importar,
    this.carregarContasBancarias,
    this.carregarCentrosCusto,
    this.identificarParceiro,
    this.arquivoInicial,
    this.empresaIdInicial,
  });

  @override
  State<ImportacaoSpedCard> createState() => _ImportacaoSpedCardState();
}

class _ImportacaoSpedCardState extends State<ImportacaoSpedCard> {
  List<Map<String, dynamic>> _empresas = [];
  String? _empresaId;
  PlatformFile? _arquivo;
  Map<String, dynamic>? _resultado;
  String? _erro;
  // Pedido explicito do usuario: erro inesperado deve trazer o stack trace
  // completo (campo "trace" da resposta) com opcao de copiar, pra facilitar
  // o diagnostico sem precisar olhar log de servidor.
  String? _trace;
  bool _loadingEmpresas = false;
  bool _importando = false;

  List<Map<String, dynamic>> _contasBancarias = [];
  List<Map<String, dynamic>> _centrosCusto = [];
  String? _contaBancariaId;
  String? _centroCustoId;
  bool _loadingFinanceiro = false;

  // Ver comentario completo em ImportacaoSintegraCard.
  String? _parceiroIdentificadoId;
  String? _parceiroIdentificadoNome;
  bool _identificandoParceiro = false;

  @override
  void initState() {
    super.initState();
    _arquivo = widget.arquivoInicial;
    _empresaId = widget.empresaIdInicial;
    _carregarEmpresas();
    // Ver comentario completo em ImportacaoSintegraCard: so' carrega aqui se
    // a empresa ja veio definida (empresaIdInicial); senao _carregarEmpresas
    // dispara depois de resolver via TenantContext, evitando a corrida que
    // trazia conta/centro de custo de TODAS as empresas.
    if (_empresaId != null && _empresaId!.isNotEmpty) {
      _carregarOpcoesFinanceiro();
      _identificarParceiroSeNecessario();
    }
  }

  Future<void> _carregarOpcoesFinanceiro() async {
    setState(() => _loadingFinanceiro = true);
    try {
      final resultados = await Future.wait([
        widget.carregarContasBancarias != null
            ? widget.carregarContasBancarias!(_empresaId, _parceiroIdentificadoId)
            : _carregarContasBancariasApi(),
        widget.carregarCentrosCusto != null
            ? widget.carregarCentrosCusto!(_empresaId)
            : _carregarCentrosCustoApi(),
      ]);
      if (!mounted) return;
      setState(() {
        _contasBancarias = resultados[0];
        _centrosCusto = resultados[1];
        if (_contaBancariaId != null &&
            !_contasBancarias.any((c) => c['id'] == _contaBancariaId)) {
          _contaBancariaId = null;
        }
      });
    } catch (_) {
      // Campos opcionais -- falha ao carregar nao bloqueia a importacao.
    } finally {
      if (mounted) setState(() => _loadingFinanceiro = false);
    }
  }

  // Ver comentario completo em ImportacaoSintegraCard.
  Future<void> _identificarParceiroSeNecessario() async {
    final empresaId = _empresaId;
    final arquivo = _arquivo;
    if (empresaId == null || empresaId.isEmpty || arquivo == null) return;
    setState(() => _identificandoParceiro = true);
    try {
      final identificado = widget.identificarParceiro != null
          ? await widget.identificarParceiro!(empresaId, arquivo)
          : await _identificarParceiroApi(empresaId, arquivo);
      if (!mounted) return;
      setState(() {
        _parceiroIdentificadoId = identificado?['parceiroId']?.toString();
        _parceiroIdentificadoNome = identificado?['parceiroNome']?.toString();
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _parceiroIdentificadoId = null;
          _parceiroIdentificadoNome = null;
        });
      }
    } finally {
      if (mounted) setState(() => _identificandoParceiro = false);
    }
    if (mounted) _carregarOpcoesFinanceiro();
  }

  Future<Map<String, dynamic>?> _identificarParceiroApi(
    String empresaId,
    PlatformFile arquivo,
  ) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(ApiLinks.nfeImportacaoSpedIdentificarParceiro),
    );
    request.headers.addAll(TenantContext.headers);
    request.headers.removeWhere(
      (key, _) => key.toLowerCase() == 'content-type',
    );
    request.fields['empId'] = empresaId;
    if (arquivo.bytes != null) {
      request.files.add(http.MultipartFile.fromBytes(
        'arquivo',
        arquivo.bytes!,
        filename: arquivo.name,
      ));
    } else if (arquivo.path != null) {
      request.files.add(await http.MultipartFile.fromPath(
        'arquivo',
        arquivo.path!,
        filename: arquivo.name,
      ));
    } else {
      return null;
    }
    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    final decoded = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  Future<List<Map<String, dynamic>>> _carregarContasBancariasApi() async {
    final query = StringBuffer('?tamanho=200');
    if (_empresaId != null && _empresaId!.isNotEmpty) {
      query.write('&empresa=$_empresaId');
    }
    if (_parceiroIdentificadoId != null && _parceiroIdentificadoId!.isNotEmpty) {
      query.write('&parceiro=$_parceiroIdentificadoId');
    }
    final url = '${widget.baseUrl}/api/contas-bancaria$query';
    final resp = await http.get(Uri.parse(url), headers: TenantContext.headers);
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    return _extractList(jsonDecode(resp.body)).map<Map<String, dynamic>>((item) {
      final descricao = item['descricao']?.toString().trim() ?? '';
      final banco = item['banco']?.toString().trim() ?? '';
      final numero = item['numero']?.toString().trim() ?? '';
      final bancoNumero = [
        if (banco.isNotEmpty) banco,
        if (numero.isNotEmpty) numero,
      ].join(' - ');
      final nome = [
        if (descricao.isNotEmpty) descricao,
        if (bancoNumero.isNotEmpty) bancoNumero,
      ].join(' • ');
      return {
        'id': item['id']?.toString() ?? '',
        'nome': nome.isNotEmpty ? nome : (item['nome']?.toString() ?? ''),
      };
    }).where((item) => item['id']!.isNotEmpty).toList();
  }

  Future<List<Map<String, dynamic>>> _carregarCentrosCustoApi() async {
    final query = StringBuffer('?tamanho=200');
    if (_empresaId != null && _empresaId!.isNotEmpty) {
      query.write('&empId=$_empresaId');
    }
    final url = '${ApiLinks.allCentroCusto}$query';
    final resp = await http.get(Uri.parse(url), headers: TenantContext.headers);
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    return _extractList(jsonDecode(resp.body))
        .map<Map<String, dynamic>>(
          (item) => {
            'id': item['id']?.toString() ?? '',
            'nome': item['nome']?.toString() ?? '',
          },
        )
        .where((item) => item['id']!.isNotEmpty)
        .toList();
  }

  Future<void> _carregarEmpresas() async {
    setState(() => _loadingEmpresas = true);
    try {
      final empresas = widget.carregarEmpresas != null
          ? await widget.carregarEmpresas!()
          : await _carregarEmpresasApi();
      if (!mounted) return;
      final empresaJaEscolhida = _empresaId != null && _empresaId!.isNotEmpty;
      setState(() {
        _empresas = empresas;
        final contexto = TenantContext.empresaId?.toString();
        if (_empresaId == null &&
            contexto != null &&
            _empresas.any((empresa) => empresa['id']?.toString() == contexto)) {
          _empresaId = contexto;
        }
      });
      if (!empresaJaEscolhida && _empresaId != null && _empresaId!.isNotEmpty) {
        _carregarOpcoesFinanceiro();
        _identificarParceiroSeNecessario();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _erro = 'Nao foi possivel carregar as empresas.');
      }
    } finally {
      if (mounted) setState(() => _loadingEmpresas = false);
    }
  }

  Future<List<Map<String, dynamic>>> _carregarEmpresasApi() async {
    final url = '${widget.baseUrl}/api/empresa';
    final resp = await http.get(Uri.parse(url), headers: TenantContext.headers);
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    return _extractList(jsonDecode(resp.body))
        .map<Map<String, dynamic>>(
          (empresa) => {
            'id': empresa['id']?.toString() ?? '',
            'nome': empresa['nome']?.toString() ??
                empresa['razaoSocial']?.toString() ??
                '',
          },
        )
        .where((empresa) => empresa['id']!.isNotEmpty)
        .toList();
  }

  Future<void> _selecionarArquivo() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: kIsWeb,
      type: FileType.custom,
      allowedExtensions: const ['txt'],
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      _arquivo = result.files.first;
      _erro = null;
      _trace = null;
      _resultado = null;
      _parceiroIdentificadoId = null;
      _parceiroIdentificadoNome = null;
    });
    _identificarParceiroSeNecessario();
  }

  Future<void> _importar() async {
    final empresaId = _empresaId;
    final arquivo = _arquivo;
    if (empresaId == null || empresaId.isBlank) {
      setState(() => _erro = 'Selecione a empresa antes de importar.');
      return;
    }
    if (arquivo == null) {
      setState(() => _erro = 'Selecione um arquivo SPED.');
      return;
    }

    setState(() {
      _importando = true;
      _erro = null;
      _trace = null;
      _resultado = null;
    });
    try {
      final resultado = widget.importar != null
          ? await widget.importar!(empresaId, arquivo)
          : await _importarApi(empresaId, arquivo);
      if (!mounted) return;
      setState(() => _resultado = resultado);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Arquivo SPED importado.')),
      );
    } on ErroImportacaoComTrace catch (e) {
      if (mounted) setState(() {
        _erro = e.message;
        _trace = e.trace;
      });
    } catch (e) {
      if (mounted)
        setState(() => _erro = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _importando = false);
    }
  }

  Future<Map<String, dynamic>> _importarApi(
    String empresaId,
    PlatformFile arquivo,
  ) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(ApiLinks.nfeImportacaoSped),
    );
    request.headers.addAll(TenantContext.headers);
    request.headers.removeWhere(
      (key, _) => key.toLowerCase() == 'content-type',
    );
    request.fields['empId'] = empresaId;
    if (_contaBancariaId != null && _contaBancariaId!.isNotEmpty) {
      request.fields['contaBancariaId'] = _contaBancariaId!;
    }
    if (_centroCustoId != null && _centroCustoId!.isNotEmpty) {
      request.fields['centroCustoId'] = _centroCustoId!;
    }
    if (arquivo.bytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'arquivo',
          arquivo.bytes!,
          filename: arquivo.name,
        ),
      );
    } else if (arquivo.path != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'arquivo',
          arquivo.path!,
          filename: arquivo.name,
        ),
      );
    } else {
      throw Exception('Arquivo selecionado sem conteudo.');
    }

    final response = await request.send();
    final body = await response.stream.bytesToString();
    final decoded = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final trace = decoded is Map ? decoded['trace']?.toString() : null;
      if (trace != null && trace.isNotEmpty) {
        throw ErroImportacaoComTrace(_mensagemErro(decoded), trace);
      }
      throw Exception(_mensagemErro(decoded));
    }
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('importacao-sped-card'),
      elevation: 0,
      color: GridColors.info.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: GridColors.info.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: GridColors.info.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.receipt_long_outlined,
                    color: GridColors.info,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Importar SPED',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Importa notas de entrada/saida, itens, produtos, parceiros e tributacao fiscal disponivel no arquivo SPED (EFD ICMS/IPI).',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  key: const Key('importacao-sped-selecionar'),
                  onPressed: _importando ? null : _selecionarArquivo,
                  icon: const Icon(Icons.folder_open, size: 15),
                  label: const Text(
                    'Selecionar arquivo',
                    style: TextStyle(fontSize: 11),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: GridColors.info,
                    side: const BorderSide(color: GridColors.info),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final compacto = constraints.maxWidth < 760;
                final dropdown = SearchableDropdownField(
                  key: const Key('importacao-sped-empresa'),
                  label: 'Empresa',
                  value: _empresaId,
                  items: _empresas,
                  valueField: 'id',
                  displayField: 'nome',
                  hintText: _loadingEmpresas
                      ? 'Carregando empresas...'
                      : 'Selecione a empresa',
                  enabled: !_loadingEmpresas && !_importando,
                  isRequired: true,
                  onChanged: (value) {
                    setState(() {
                      _empresaId = value;
                      _parceiroIdentificadoId = null;
                      _parceiroIdentificadoNome = null;
                    });
                    _carregarOpcoesFinanceiro();
                    _identificarParceiroSeNecessario();
                  },
                );
                final arquivo = _arquivoResumo();
                final importar = _botaoImportar();
                if (compacto) {
                  return Column(
                    children: [
                      dropdown,
                      const SizedBox(height: 8),
                      arquivo,
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerRight, child: importar),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(flex: 2, child: dropdown),
                    const SizedBox(width: 12),
                    Expanded(flex: 3, child: arquivo),
                    const SizedBox(width: 12),
                    importar,
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            _camposFinanceiro(),
            if (_erro != null) ...[
              const SizedBox(height: 10),
              _feedback(_erro!, GridColors.error, Icons.error_outline),
            ],
            if (_trace != null) ...[
              const SizedBox(height: 8),
              _blocoTrace(_trace!),
            ],
            if (_resultado != null) ...[
              const SizedBox(height: 10),
              _resumo(_resultado!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _arquivoResumo() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFDDDDDD)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            size: 16,
            color: Colors.grey.shade600,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _arquivo?.name ?? 'Nenhum arquivo selecionado',
              style: TextStyle(
                fontSize: 12,
                color: _arquivo == null
                    ? Colors.grey.shade500
                    : Colors.grey.shade800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _camposFinanceiro() {
    final contaDropdown = SearchableDropdownField(
      key: const Key('importacao-sped-conta-bancaria'),
      label: 'Conta bancaria/caixa (opcional)',
      value: _contaBancariaId,
      items: _contasBancarias,
      valueField: 'id',
      displayField: 'nome',
      hintText: _loadingFinanceiro || _identificandoParceiro
          ? 'Carregando contas...'
          : 'Usar default da empresa',
      enabled: !_loadingFinanceiro && !_identificandoParceiro && !_importando,
      onChanged: (value) => setState(() => _contaBancariaId = value),
    );
    final centroCustoDropdown = SearchableDropdownField(
      key: const Key('importacao-sped-centro-custo'),
      label: 'Centro de custo (opcional)',
      value: _centroCustoId,
      items: _centrosCusto,
      valueField: 'id',
      displayField: 'nome',
      hintText: _loadingFinanceiro
          ? 'Carregando centros de custo...'
          : 'Usar default da empresa',
      enabled: !_loadingFinanceiro && !_importando,
      onChanged: (value) => setState(() => _centroCustoId = value),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 760;
        final campos = compacto
            ? Column(
                children: [
                  contaDropdown,
                  const SizedBox(height: 8),
                  centroCustoDropdown,
                ],
              )
            : Row(
                children: [
                  Expanded(child: contaDropdown),
                  const SizedBox(width: 12),
                  Expanded(child: centroCustoDropdown),
                ],
              );
        if (_parceiroIdentificadoNome == null) return campos;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            campos,
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.link, size: 12, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Conta bancaria filtrada pelo parceiro do arquivo: $_parceiroIdentificadoNome',
                    key: const Key('importacao-sped-parceiro-identificado'),
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _botaoImportar() {
    return ElevatedButton.icon(
      key: const Key('importacao-sped-importar'),
      onPressed: _importando ? null : _importar,
      icon: _importando
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.upload_file, size: 15),
      label: Text(
        _importando ? 'Importando...' : 'Importar',
        style: const TextStyle(fontSize: 12),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: GridColors.secondary,
        foregroundColor: Colors.white,
        minimumSize: const Size(118, 40),
      ),
    );
  }

  Widget _resumo(Map<String, dynamic> resultado) {
    final itens = <_ResumoItem>[
      _ResumoItem('Entradas', resultado['notasEntrada']),
      _ResumoItem('Saidas', resultado['notasSaida']),
      _ResumoItem('Itens', resultado['itens']),
      _ResumoItem('Produtos novos', resultado['produtosCriados']),
      _ResumoItem('Produtos atualizados', resultado['produtosAtualizados']),
      _ResumoItem('Parceiros novos', resultado['parceirosCriados']),
      _ResumoItem('Parceiros atualizados', resultado['parceirosAtualizados']),
      _ResumoItem('Tributacoes', resultado['tributacoes']),
      _ResumoItem('Financeiro gerado', resultado['financeirosGerados']),
      _ResumoItem('Financeiro pendente', resultado['financeirosPendentes']),
    ];
    return Container(
      key: const Key('importacao-sped-resumo'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: GridColors.secondary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: GridColors.secondary.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in itens)
                Chip(
                  label: Text(
                    '${item.label}: ${item.valor ?? 0}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          ..._listaMensagens(
            resultado['avisos'],
            Icons.info_outline,
            GridColors.info,
          ),
          ..._listaMensagens(
            resultado['ignorados'],
            Icons.block_outlined,
            Colors.orange.shade800,
          ),
        ],
      ),
    );
  }

  Widget _feedback(String mensagem, Color color, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(mensagem, style: TextStyle(color: color, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // Pedido explicito do usuario: erro inesperado na importacao mostra o
  // stack trace completo (rolavel) com botao pra copiar, sem precisar
  // acessar log de servidor.
  Widget _blocoTrace(String trace) {
    return Container(
      key: const Key('importacao-sped-trace'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Detalhes do erro',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade300,
                ),
              ),
              TextButton.icon(
                key: const Key('importacao-sped-copiar-erro'),
                onPressed: () => _copiarErro(trace),
                icon: const Icon(Icons.copy, size: 13, color: Colors.white70),
                label: const Text(
                  'Copiar erro',
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: SelectableText(
                trace,
                style: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: Colors.white70,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _copiarErro(String trace) {
    Clipboard.setData(ClipboardData(text: '${_erro ?? ''}\n\n$trace'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Erro copiado.')),
    );
  }

  List<Widget> _listaMensagens(dynamic valores, IconData icon, Color color) {
    final lista = valores is List ? valores : const [];
    return [
      for (final valor in lista) ...[
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                valor.toString(),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
            ),
          ],
        ),
      ],
    ];
  }

  static List<Map<String, dynamic>> _extractList(dynamic body) {
    if (body is List) return List<Map<String, dynamic>>.from(body);
    if (body is Map && body['data'] is List) {
      return List<Map<String, dynamic>>.from(body['data'] as List);
    }
    if (body is Map && body['data'] is Map && body['data']['dados'] is List) {
      return List<Map<String, dynamic>>.from(body['data']['dados'] as List);
    }
    if (body is Map && body['content'] is List) {
      return List<Map<String, dynamic>>.from(body['content'] as List);
    }
    return const [];
  }

  static String _mensagemErro(dynamic decoded) {
    if (decoded is Map) {
      final message = decoded['message'] ?? decoded['causa'];
      if (message != null) return message.toString();
      if (decoded['response'] is Map &&
          decoded['response']['message'] != null) {
        return decoded['response']['message'].toString();
      }
    }
    return 'Nao foi possivel importar o arquivo SPED.';
  }
}

class _ResumoItem {
  final String label;
  final dynamic valor;

  _ResumoItem(this.label, this.valor);
}

// Pedido explicito do usuario: erro inesperado na importacao carrega o
// stack trace completo (campo "trace" da resposta) pra exibir na tela com
// opcao de copiar, alem da mensagem resumida.
class ErroImportacaoComTrace implements Exception {
  final String message;
  final String trace;

  ErroImportacaoComTrace(this.message, this.trace);

  @override
  String toString() => message;
}

extension on String {
  bool get isBlank => trim().isEmpty;
}
