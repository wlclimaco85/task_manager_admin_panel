import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/network_caller.dart';
import '../config/api_links.dart';
import '../utils/app_logger.dart';
import '../utils/grid_colors.dart';
import 'nfce_notice_banner.dart';

/// Rotulo legivel da origem do arquivo (BOLETO/SPED/SINTEGRA), como vem do
/// backend em AutomacaoFiscalLogDTO.origem. Funcao pura (fora da classe)
/// pra ser testavel sem depender de rede -- mesmo padrao ja estabelecido em
/// produto_impostos_tab.dart (ver comentario em
/// test/widgets/produto_impostos_tab_test.dart).
String origemLabel(String? origem) {
  switch (origem) {
    case 'BOLETO':
      return 'Boletos';
    case 'SPED':
      return 'SPED';
    case 'SINTEGRA':
      return 'Sintegra';
    default:
      return origem ?? '-';
  }
}

/// Rotulo legivel do tipo de documento (BoletoTipoDocumento.name() do
/// backend). Funcao pura, mesmo motivo de origemLabel acima.
String tipoDocumentoLabel(String? tipo) {
  switch (tipo) {
    case 'BOLETO_FORNECEDOR':
      return 'Boleto Fornecedor';
    case 'FGTS':
      return 'FGTS';
    case 'DAE_ICMS':
      return 'DAE ICMS';
    case 'DARF_FEDERAL':
      return 'DARF Federal';
    case 'GUIA_ISS_MUNICIPAL':
      return 'Guia ISS';
    case 'COMPROVANTE_PAGAMENTO':
      return 'Comprovante de Pagamento';
    case null:
      return '-';
    default:
      return 'Não identificado';
  }
}

/// Tela Sistema > Automacao Fiscal (card automacao-fiscal-pastas,
/// 2026-09-10). Configura a pasta raiz + intervalo de execucao da
/// automacao que escaneia boletos/speds/sintegra (cada uma com
/// sucesso/erro) e cria titulos a pagar automaticamente.
///
/// Compartilhada entre Web, Windows e Mobile (layout responsivo via
/// LayoutBuilder, mesmo padrao de outras telas em lib/widgets/).
class AutomacaoFiscalScreen extends StatefulWidget {
  /// false quando embutida como aba dentro de outra tela (ex.: Config.
  /// Sistema do admin_panel, que ja tem seu proprio AppBar/TabBar) -- evita
  /// Scaffold/AppBar duplicado.
  final bool showAppBar;

  const AutomacaoFiscalScreen({super.key, this.showAppBar = true});

  @override
  State<AutomacaoFiscalScreen> createState() => _AutomacaoFiscalScreenState();
}

class _AutomacaoFiscalScreenState extends State<AutomacaoFiscalScreen> {
  static const _kCompactoBreakpoint = 760.0;

  final _formKey = GlobalKey<FormState>();
  final _pastaRaizCtrl = TextEditingController();
  final _intervaloValorCtrl = TextEditingController(text: '1');

  String _intervaloUnidade = 'DIAS';
  bool _ativo = true;

  bool _carregando = true;
  bool _salvando = false;
  bool _executando = false;
  String? _erroCarregamento;

  DateTime? _ultimaExecucao;
  String? _ultimoResultado;

  List<Map<String, dynamic>> _logs = [];
  bool _carregandoLogs = false;

  final _dataFmt = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _pastaRaizCtrl.dispose();
    _intervaloValorCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erroCarregamento = null;
    });
    try {
      final resp =
          await NetworkCaller().getRequest('${ApiLinks.baseUrl}/api/automacao-fiscal/config');
      final rawBody = resp.body;
      if (resp.isSuccess && rawBody != null) {
        final body = Map<String, dynamic>.from(rawBody);
        _pastaRaizCtrl.text = (body['pastaRaiz'] ?? '').toString();
        _intervaloValorCtrl.text = (body['intervaloValor'] ?? 1).toString();
        _intervaloUnidade = (body['intervaloUnidade'] ?? 'DIAS').toString();
        _ativo = body['ativo'] == true;
        final ultimaExecucaoStr = body['ultimaExecucao']?.toString();
        _ultimaExecucao =
            ultimaExecucaoStr != null ? DateTime.tryParse(ultimaExecucaoStr) : null;
        _ultimoResultado = body['ultimoResultado']?.toString();
      } else if (!resp.isSuccess && resp.statusCode != 200) {
        _erroCarregamento = 'Erro ao carregar configuração (status ${resp.statusCode}).';
        AppLogger.i.warn(
            '[AutomacaoFiscal] Erro ao carregar config (status ${resp.statusCode})');
      }
    } catch (e, st) {
      _erroCarregamento = 'Erro ao carregar configuração: $e';
      AppLogger.i.error('[AutomacaoFiscal] Erro ao carregar config: $e', st);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
    await _carregarLogs();
  }

  Future<void> _carregarLogs() async {
    setState(() => _carregandoLogs = true);
    try {
      final resp =
          await NetworkCaller().getRequest('${ApiLinks.baseUrl}/api/automacao-fiscal/logs');
      if (resp.isSuccess && resp.body is List) {
        _logs = List<Map<String, dynamic>>.from(
            (resp.body as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
      }
    } catch (e, st) {
      // Historico e' informativo -- nao trava o resto da tela se falhar,
      // mas precisa registrar pro Console de Logs (regra de monitoramento).
      AppLogger.i.error('[AutomacaoFiscal] Erro ao carregar histórico: $e', st);
    } finally {
      if (mounted) setState(() => _carregandoLogs = false);
    }
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _salvando = true);
    try {
      final body = {
        'pastaRaiz': _pastaRaizCtrl.text.trim(),
        'intervaloValor': int.tryParse(_intervaloValorCtrl.text.trim()) ?? 1,
        'intervaloUnidade': _intervaloUnidade,
        'ativo': _ativo,
      };
      final resp = await NetworkCaller()
          .putRequest('${ApiLinks.baseUrl}/api/automacao-fiscal/config', body);

      if (!mounted) return;
      if (resp.isSuccess) {
        _snack('Configuração salva.');
        await _carregar();
      } else {
        _snack('Erro ao salvar (status ${resp.statusCode}).', error: true);
        AppLogger.i.warn('[AutomacaoFiscal] Erro ao salvar config (status ${resp.statusCode})');
      }
    } catch (e, st) {
      if (mounted) _snack('Erro ao salvar: $e', error: true);
      AppLogger.i.error('[AutomacaoFiscal] Erro ao salvar config: $e', st);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _executarAgora() async {
    setState(() => _executando = true);
    try {
      final resp = await NetworkCaller()
          .postRequest('${ApiLinks.baseUrl}/api/automacao-fiscal/executar-agora', {});
      if (!mounted) return;
      if (resp.isSuccess) {
        _snack('Execução concluída.');
        await _carregar();
      } else {
        _snack('Erro ao executar (status ${resp.statusCode}). Salve a configuração primeiro.',
            error: true);
        AppLogger.i.warn('[AutomacaoFiscal] Erro ao executar agora (status ${resp.statusCode})');
      }
    } catch (e, st) {
      if (mounted) _snack('Erro ao executar: $e', error: true);
      AppLogger.i.error('[AutomacaoFiscal] Erro ao executar agora: $e', st);
    } finally {
      if (mounted) setState(() => _executando = false);
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? GridColors.error : GridColors.success,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final corpo = _carregando
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_erroCarregamento != null) _erroBanner(),
                    _configCard(),
                    const SizedBox(height: 16),
                    _statusBanner(),
                    const SizedBox(height: 16),
                    _historicoCard(),
                  ],
                ),
              ),
            ),
          );

    if (!widget.showAppBar) {
      return Container(color: GridColors.pageBackground, child: corpo);
    }

    return Scaffold(
      backgroundColor: GridColors.pageBackground,
      appBar: AppBar(
        title: const Text('Automação Fiscal'),
        backgroundColor: GridColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: corpo,
    );
  }

  Widget _erroBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: NfceNoticeBanner(
        icon: Icons.error_outline,
        backgroundColor: GridColors.errorLight,
        borderColor: GridColors.error,
        textColor: GridColors.errorDark,
        title: 'Erro',
        message: _erroCarregamento!,
      ),
    );
  }

  /// Observação com a hierarquia exata de pastas esperada, pra tirar
  /// qualquer dúvida de nome/estrutura antes de configurar a pasta raiz.
  /// Pedido do usuário (2026-09-10): deixar claro nome e nível de cada
  /// subpasta -- boletos/speds/sintegra são criadas automaticamente pelo
  /// backend, junto com sucesso/erro dentro de cada uma; o usuário só
  /// precisa soltar os arquivos direto em boletos/, speds/ ou sintegra/.
  Widget _hierarquiaObservacao() {
    const monoStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12.5,
      color: GridColors.textSecondary,
      height: 1.5,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GridColors.filterBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GridColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Observação: hierarquia de pastas esperada',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              color: GridColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '<pasta raiz>\n'
            '├── boletos\\      (PDFs: boletos, guias de tributo, comprovantes)\n'
            '│    ├── sucesso\n'
            '│    └── erro\n'
            '├── speds\\        (arquivos .txt de SPED)\n'
            '│    ├── sucesso\n'
            '│    └── erro\n'
            '└── sintegra\\     (arquivos .txt de SINTEGRA)\n'
            '     ├── sucesso\n'
            '     └── erro',
            style: monoStyle,
          ),
          const SizedBox(height: 6),
          const Text(
            'Os nomes "boletos", "speds", "sintegra", "sucesso" e "erro" são fixos '
            '(minúsculo, sem acento) e criados automaticamente pelo sistema dentro da '
            'pasta raiz. Basta colocar os arquivos direto em "boletos", "speds" ou '
            '"sintegra" — as subpastas "sucesso"/"erro" são só de saída, não coloque '
            'arquivos nelas.',
            style: TextStyle(fontSize: 12, color: GridColors.textMuted),
          ),
        ],
      ),
    );
  }

  // ── Card de configuração ─────────────────────────────────────────────

  Widget _configCard() {
    return Card(
      elevation: 0,
      color: GridColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: GridColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Configuração',
                style: TextStyle(
                  color: GridColors.secondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pastaRaizCtrl,
                decoration: const InputDecoration(
                  labelText: 'Pasta raiz',
                  hintText: r'Ex.: C:\AutomacaoFiscal',
                  helperText:
                      'Pasta no servidor onde o backend roda. Dentro dela serão lidas as '
                      'subpastas "boletos", "speds" e "sintegra".',
                  helperMaxLines: 2,
                  prefixIcon: Icon(Icons.folder_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe o caminho da pasta raiz.' : null,
              ),
              const SizedBox(height: 10),
              _hierarquiaObservacao(),
              const SizedBox(height: 16),
              LayoutBuilder(builder: (context, constraints) {
                final compacto = constraints.maxWidth < _kCompactoBreakpoint;
                final campos = [
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      controller: _intervaloValorCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'A cada',
                        helperText: 'Intervalo entre uma varredura e outra.',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        if (n == null || n <= 0) return 'Informe um número maior que zero.';
                        return null;
                      },
                    ),
                  ),
                  SizedBox(width: compacto ? 0 : 12, height: compacto ? 12 : 0),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: _intervaloUnidade,
                      decoration: const InputDecoration(
                        labelText: 'Unidade',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'HORAS', child: Text('Horas')),
                        DropdownMenuItem(value: 'DIAS', child: Text('Dias')),
                        DropdownMenuItem(value: 'MESES', child: Text('Meses')),
                      ],
                      onChanged: (v) => setState(() => _intervaloUnidade = v ?? 'DIAS'),
                    ),
                  ),
                ];
                return compacto
                    ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: campos)
                    : Row(crossAxisAlignment: CrossAxisAlignment.start, children: campos);
              }),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _ativo,
                activeColor: GridColors.secondary,
                title: const Text('Automação ativa'),
                subtitle: Text(_ativo
                    ? 'Ligada — a próxima varredura ocorre conforme o intervalo configurado.'
                    : 'Desligada — a configuração é mantida, mas nenhuma varredura automática '
                        'será executada.'),
                onChanged: (v) => setState(() => _ativo = v),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(builder: (context, constraints) {
                final compacto = constraints.maxWidth < _kCompactoBreakpoint;
                final salvar = ElevatedButton.icon(
                  onPressed: _salvando ? null : _salvar,
                  icon: _salvando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save),
                  label: Text(_salvando ? 'Salvando...' : 'Salvar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GridColors.secondary,
                    foregroundColor: Colors.white,
                  ),
                );
                final executar = OutlinedButton.icon(
                  onPressed: _executando ? null : _executarAgora,
                  icon: _executando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.bolt_outlined),
                  label: Text(_executando ? 'Executando...' : 'Executar agora'),
                  style: OutlinedButton.styleFrom(foregroundColor: GridColors.info),
                );
                return compacto
                    ? Column(children: [
                        SizedBox(width: double.infinity, child: salvar),
                        const SizedBox(height: 8),
                        SizedBox(width: double.infinity, child: executar),
                      ])
                    : Wrap(spacing: 12, children: [salvar, executar]);
              }),
            ],
          ),
        ),
      ),
    );
  }

  // ── Faixa de status ──────────────────────────────────────────────────

  Widget _statusBanner() {
    if (_ultimaExecucao == null) {
      return const NfceNoticeBanner(
        icon: Icons.info_outline,
        backgroundColor: GridColors.filterBackground,
        borderColor: GridColors.divider,
        textColor: GridColors.textSecondary,
        title: 'Última execução',
        message: 'Ainda não houve nenhuma execução. Use "Executar agora" para testar a '
            'configuração.',
      );
    }

    final houveErro = (_ultimoResultado ?? '').contains(RegExp(r'[1-9]\d* erro'));
    return NfceNoticeBanner(
      icon: houveErro ? Icons.error_outline : Icons.check_circle_outline,
      backgroundColor: houveErro ? GridColors.errorLight : GridColors.filterBackground,
      borderColor: houveErro ? GridColors.error : GridColors.divider,
      textColor: houveErro ? GridColors.errorDark : GridColors.textSecondary,
      title: 'Última execução',
      message: '${_dataFmt.format(_ultimaExecucao!)} — ${_ultimoResultado ?? ''}'
          '${houveErro ? '. Verifique o histórico abaixo.' : ''}',
    );
  }

  // ── Histórico ────────────────────────────────────────────────────────

  Widget _historicoCard() {
    return Card(
      elevation: 0,
      color: GridColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: GridColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Histórico de execuções',
              style: TextStyle(
                color: GridColors.secondary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            if (_carregandoLogs)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
            else if (_logs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Text('Nenhuma execução registrada ainda.',
                      style: TextStyle(color: GridColors.textMuted)),
                ),
              )
            else
              LayoutBuilder(builder: (context, constraints) {
                return constraints.maxWidth < _kCompactoBreakpoint
                    ? Column(children: _logs.map(_logCard).toList())
                    : _logTable();
              }),
          ],
        ),
      ),
    );
  }

  Widget _logTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(GridColors.gridHeader),
        columns: const [
          DataColumn(label: Text('Origem')),
          DataColumn(label: Text('Arquivo')),
          DataColumn(label: Text('Tipo')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Mensagem')),
        ],
        rows: _logs.map((log) {
          final sucesso = log['status'] == 'SUCESSO';
          return DataRow(cells: [
            DataCell(Text(origemLabel(log['origem']?.toString()))),
            DataCell(Text(log['arquivo']?.toString() ?? '')),
            DataCell(_tipoChip(log['tipoDocumento']?.toString())),
            DataCell(_statusChip(sucesso)),
            DataCell(SizedBox(
              width: 260,
              child: Text(
                log['mensagem']?.toString() ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: sucesso ? GridColors.textSecondary : GridColors.error, fontSize: 12),
              ),
            )),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _logCard(Map<String, dynamic> log) {
    final sucesso = log['status'] == 'SUCESSO';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GridColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_outlined, size: 18, color: GridColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${origemLabel(log['origem']?.toString())} · ${log['arquivo'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              _statusChip(sucesso),
            ],
          ),
          if (log['tipoDocumento'] != null) ...[
            const SizedBox(height: 6),
            _tipoChip(log['tipoDocumento']?.toString()),
          ],
          if (!sucesso && (log['mensagem'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(log['mensagem'].toString(),
                style: const TextStyle(color: GridColors.error, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(bool sucesso) {
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: sucesso ? GridColors.successLight : GridColors.errorLight,
      label: Text(
        sucesso ? 'Sucesso' : 'Erro',
        style: TextStyle(
          color: sucesso ? GridColors.successDark : GridColors.errorDark,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _tipoChip(String? tipo) {
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: GridColors.surfaceMuted,
      label: Text(
        tipoDocumentoLabel(tipo),
        style: const TextStyle(color: GridColors.textSecondary, fontSize: 11),
      ),
    );
  }

}
