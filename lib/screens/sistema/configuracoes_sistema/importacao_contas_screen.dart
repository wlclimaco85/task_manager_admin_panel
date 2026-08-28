import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../config/api_links.dart';
import '../../../core/theme/app_theme.dart';
import '../../../utils/csv_parser.dart';
import '../../../utils/tenant_context.dart';

/// SIS-04 Config. Sistema — Importação CSV de Contas a Pagar/Receber.
///
/// Porta `_ImportacaoSection` de
/// `task_manager_flutter/lib/web/screens/configuracoes_sistema_screen.dart`
/// (ver RESEARCH.md, Item 4). Delega parsing/persistência definitiva ao
/// backend via multipart (`POST /api/importacao/preview` para detectar
/// colunas, `POST /api/importacao/conta-pagar`|`conta-receber` para
/// importar) — `parseCsv` (P01b) é usado só para pré-visualização local
/// (fallback rápido antes da resposta do preview do backend).
///
/// Não existe helper de multipart em [NetworkCaller] (fora de escopo desta
/// task alterar outros arquivos — ver PLAN.md Task 07.1), então as chamadas
/// multipart são montadas aqui diretamente com `http.MultipartRequest`,
/// reaproveitando `TenantContext.headers`/`applyToUrl` (read-only, nenhuma
/// alteração nesse arquivo).
class ImportacaoContasScreen extends StatefulWidget {
  ImportacaoContasScreen({
    super.key,
    http.Client? httpClient,
    Future<FilePickerResult?> Function()? pickFileOverride,
  })  : httpClient = httpClient ?? http.Client(),
        pickFileOverride = pickFileOverride ?? _pickFileReal;

  final http.Client httpClient;
  final Future<FilePickerResult?> Function() pickFileOverride;

  static Future<FilePickerResult?> _pickFileReal() {
    return FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
  }

  @override
  State<ImportacaoContasScreen> createState() =>
      _ImportacaoContasScreenState();
}

/// Definição de um campo de mapeamento coluna-CSV → campo do backend.
class _CampoMapeamento {
  const _CampoMapeamento({
    required this.chave,
    required this.label,
    required this.obrigatorio,
    required this.sinonimos,
    this.valorPadrao = '',
  });

  final String chave;
  final String label;
  final bool obrigatorio;
  final List<String> sinonimos;
  final String valorPadrao;
}

const _camposMapeamento = <_CampoMapeamento>[
  _CampoMapeamento(
    chave: 'colDescricao',
    label: 'Coluna Descrição',
    obrigatorio: true,
    valorPadrao: 'historico',
    sinonimos: [
      'descricao', 'description', 'historico', 'lancamento', 'titulo',
      'nome', 'descricao_tipo_de_titulo', 'descricao_natureza', //
    ],
  ),
  _CampoMapeamento(
    chave: 'colValor',
    label: 'Coluna Valor',
    obrigatorio: true,
    valorPadrao: 'vlr_do_desdobramento',
    sinonimos: [
      'valor', 'value', 'montante', 'total', 'vlr', 'vl', 'valor_liquido',
      'vlr_do_desdobramento', //
    ],
  ),
  _CampoMapeamento(
    chave: 'colVencimento',
    label: 'Coluna Vencimento',
    obrigatorio: true,
    valorPadrao: 'dt_vencimento',
    sinonimos: [
      'vencimento', 'data_vencimento', 'dt_vencimento', 'datavencimento',
      'due_date', 'venc', 'dt_prevista_p_baixa', //
    ],
  ),
  _CampoMapeamento(
    chave: 'colParceiro',
    label: 'Coluna Parceiro',
    obrigatorio: false,
    valorPadrao: 'parceiro',
    sinonimos: [
      'parceiro', 'fornecedor', 'cliente', 'partner', 'vendor', 'supplier',
      'nome_parceiro_parceiro', 'nome_fantasia_empresa', //
    ],
  ),
  _CampoMapeamento(
    chave: 'colFormaPagamento',
    label: 'Coluna Forma Pagamento',
    obrigatorio: false,
    valorPadrao: 'forma_pagamento',
    sinonimos: [
      'forma_pagamento', 'formapagamento', 'payment_method', 'pagamento',
      'forma', 'tipo_operacao', 'descricao_tipo_de_operacao', //
    ],
  ),
  _CampoMapeamento(
    chave: 'colStatus',
    label: 'Coluna Status',
    obrigatorio: false,
    valorPadrao: 'status',
    sinonimos: ['status', 'situacao', 'state', 'tipo_de_movimento'],
  ),
  _CampoMapeamento(
    chave: 'colNumeroNota',
    label: 'Coluna Número Nota',
    obrigatorio: false,
    valorPadrao: 'nro_nota',
    sinonimos: [
      'numero_nota', 'numeronota', 'nota', 'nf', 'nfe', 'invoice',
      'documento', 'nro_nota', 'nro_duplicata', //
    ],
  ),
  _CampoMapeamento(
    chave: 'colObservacao',
    label: 'Coluna Observação',
    obrigatorio: false,
    valorPadrao: 'observacao',
    sinonimos: [
      'observacao', 'obs', 'observation', 'nota', 'comentario',
      'observacao_padrao', //
    ],
  ),
  _CampoMapeamento(
    chave: 'colDataBaixa',
    label: 'Coluna Data Baixa',
    obrigatorio: false,
    sinonimos: [
      'data_baixa', 'dt_baixa', 'databaixa', 'dtbaixa', 'data_pagamento',
      'dt_pagamento', 'data_recebimento', 'dt_recebimento',
      'data_quitacao', //
    ],
  ),
  _CampoMapeamento(
    chave: 'colValorBaixa',
    label: 'Coluna Valor Baixa',
    obrigatorio: false,
    sinonimos: [
      'valor_baixa', 'vlr_baixa', 'valor_pago', 'vlr_pago',
      'valor_recebido', 'vlr_recebido', 'valor_liquido', 'vlr_liquido', //
    ],
  ),
  _CampoMapeamento(
    chave: 'colValorMulta',
    label: 'Coluna Valor Multa',
    obrigatorio: false,
    sinonimos: ['valor_multa', 'vlr_multa', 'multa', 'vl_multa'],
  ),
  _CampoMapeamento(
    chave: 'colValorJuros',
    label: 'Coluna Valor Juros',
    obrigatorio: false,
    sinonimos: ['valor_juros', 'vlr_juros', 'juros', 'vl_juros', 'juro'],
  ),
  _CampoMapeamento(
    chave: 'colValorDesconto',
    label: 'Coluna Valor Desconto',
    obrigatorio: false,
    sinonimos: [
      'valor_desconto', 'vlr_desconto', 'desconto', 'vl_desconto', //
    ],
  ),
  _CampoMapeamento(
    chave: 'colParceiroDev',
    label: 'Coluna Parceiro Dev',
    obrigatorio: false,
    sinonimos: [
      'parceiro_dev', 'parceiro_devedor', 'devedor', 'parceiro_rec',
      'recebedor', 'nome_parceiro_dev', //
    ],
  ),
  _CampoMapeamento(
    chave: 'colContaBancaria',
    label: 'Coluna Conta Bancária',
    obrigatorio: false,
    sinonimos: [
      'conta_bancaria', 'conta', 'banco', 'bank_account', 'conta_id',
      'nome_conta', //
    ],
  ),
];

/// Normaliza uma string do mesmo jeito que o backend: minúsculo, sem
/// acentos, espaços viram `_`. Portado verbatim de `_normalizar`
/// (`_ImportacaoSection`).
String _normalizar(String s) {
  const comAcento = 'àáâãäåèéêëìíîïòóôõöùúûüýÿñçÀÁÂÃÄÅÈÉÊËÌÍÎÏÒÓÔÕÖÙÚÛÜÝÑÇ';
  const semAcento = 'aaaaaaeeeeiiiioooooouuuuyyncAAAAAAEEEEIIIIOOOOOUUUUYNC';
  var r = s.toLowerCase();
  for (var i = 0; i < comAcento.length; i++) {
    r = r.replaceAll(comAcento[i], semAcento[i]);
  }
  return r.replaceAll(RegExp(r'\s+'), '_').replaceAll(RegExp(r'[^a-z0-9_]'), '');
}

/// Tenta mapear automaticamente cada coluna detectada do CSV para os campos
/// conhecidos por dicionário de sinônimos. Portado de `_autoMapear`.
void _autoMapear(
  Map<String, TextEditingController> controllers,
  List<String> colunas,
) {
  final colunasNorm = colunas.map(_normalizar).toList();
  for (final campo in _camposMapeamento) {
    for (final candidato in campo.sinonimos) {
      final idx = colunasNorm.indexWhere(
        (cn) => cn == candidato || cn.contains(candidato) || candidato.contains(cn),
      );
      if (idx >= 0) {
        controllers[campo.chave]?.text = colunas[idx];
        break;
      }
    }
  }
}

/// Estado isolado de uma seção de importação (Contas a Pagar OU Receber) —
/// evita duplicar os dois blocos quase idênticos do arquivo original em
/// dois conjuntos de campos soltos na classe principal.
class _SecaoImportacao {
  _SecaoImportacao();

  PlatformFile? arquivo;
  List<String> colunas = [];
  bool upsert = false;
  bool importando = false;
  bool mapeamentoExpandido = false;
  Map<String, dynamic>? resultado;
  String? erro;

  final Map<String, TextEditingController> controllers = {
    for (final campo in _camposMapeamento)
      campo.chave: TextEditingController(text: campo.valorPadrao),
  };

  bool get temMapeamentoObrigatorio => _camposMapeamento
      .where((c) => c.obrigatorio)
      .every((c) => (controllers[c.chave]?.text.trim() ?? '').isNotEmpty);

  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
  }
}

class _ImportacaoContasScreenState extends State<ImportacaoContasScreen> {
  final _empresaIdController = TextEditingController();
  final _parceiroIdController = TextEditingController();

  final _cp = _SecaoImportacao();
  final _cr = _SecaoImportacao();

  @override
  void dispose() {
    _empresaIdController.dispose();
    _parceiroIdController.dispose();
    _cp.dispose();
    _cr.dispose();
    widget.httpClient.close();
    super.dispose();
  }

  bool get _temEmpresa => _empresaIdController.text.trim().isNotEmpty;

  Future<void> _selecionarArquivo(_SecaoImportacao secao) async {
    final result = await widget.pickFileOverride();
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    final colunasLocal = _detectarColunas(file.bytes!);
    setState(() {
      secao.arquivo = file;
      secao.resultado = null;
      secao.erro = null;
      secao.colunas = colunasLocal;
      _autoMapear(secao.controllers, colunasLocal);
    });

    // Preview server-side (detecta separador/BOM/tab com mais precisão) —
    // best-effort, mantém a detecção local se a chamada falhar.
    try {
      final resp = await _multipartPost(
        ApiLinks.importacaoPreview,
        file.bytes!,
        file.name,
      );
      if (!mounted || resp.statusCode != 200) return;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final colunas = (body['colunas'] as List?)?.cast<String>();
      if (colunas == null || colunas.isEmpty) return;
      setState(() {
        secao.colunas = colunas;
        _autoMapear(secao.controllers, colunas);
      });
    } catch (_) {
      // Mantém detecção local.
    }
  }

  /// Fallback local: usa [parseCsv] (P01b) só para ler o cabeçalho do CSV
  /// antes da resposta do preview do backend chegar.
  List<String> _detectarColunas(List<int> bytes) {
    try {
      final texto = utf8.decode(bytes, allowMalformed: true).replaceAll('﻿', '');
      final linhas = parseCsv(texto);
      if (linhas.isEmpty) return [];
      return linhas.first.map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  Future<http.Response> _multipartPost(
    String url,
    List<int> fileBytes,
    String fileName, {
    Map<String, String>? fields,
  }) async {
    final uri = Uri.parse(TenantContext.applyToUrl(url));
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(TenantContext.headers)
      ..files.add(http.MultipartFile.fromBytes('arquivo', fileBytes, filename: fileName))
      ..fields.addAll(fields ?? {});
    final streamed = await widget.httpClient.send(request);
    return http.Response.fromStream(streamed);
  }

  Future<void> _importar(_SecaoImportacao secao, bool isCP) async {
    final arquivo = secao.arquivo;
    if (arquivo == null || arquivo.bytes == null || !_temEmpresa) return;

    setState(() => secao.importando = true);

    try {
      final empId = _empresaIdController.text.trim();
      final parId = _parceiroIdController.text.trim();
      final endpoint = isCP
          ? ApiLinks.importacaoContaPagar
          : ApiLinks.importacaoContaReceber;

      var url = endpoint;
      {
        final uri = Uri.parse(url);
        final params = Map<String, String>.from(uri.queryParameters);
        params['empId'] = empId;
        if (parId.isNotEmpty) params['parId'] = parId;
        if (secao.upsert) params['upsert'] = 'true';
        url = uri.replace(queryParameters: params).toString();
      }

      final fields = <String, String>{
        for (final campo in _camposMapeamento)
          if ((secao.controllers[campo.chave]?.text.trim() ?? '').isNotEmpty)
            campo.chave: secao.controllers[campo.chave]!.text.trim(),
      };

      final resp = await _multipartPost(url, arquivo.bytes!, arquivo.name, fields: fields);

      if (!mounted) return;
      if (resp.statusCode >= 300) {
        setState(() {
          secao.erro = 'HTTP ${resp.statusCode}: ${resp.body}';
          secao.resultado = null;
        });
        return;
      }

      dynamic body;
      try {
        body = jsonDecode(resp.body);
      } catch (_) {
        body = {'error': resp.body};
      }
      setState(() {
        secao.erro = null;
        secao.resultado = body is Map<String, dynamic> ? body : {'data': body};
        final sucesso = secao.resultado?['sucesso'] as int? ?? 0;
        final erros = secao.resultado?['erros'] as int? ?? 0;
        final ignorados = secao.resultado?['ignorados'] as int? ?? 0;
        if (sucesso == 0 && erros == 0 && ignorados > 0) {
          secao.mapeamentoExpandido = true;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        secao.erro = e.toString();
        secao.resultado = null;
      });
    } finally {
      if (mounted) setState(() => secao.importando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Importação CSV — Contas')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDestinoCard(),
            const SizedBox(height: AppSpacing.md),
            _buildImportCard(
              secao: _cp,
              isCP: true,
              titulo: 'Importar Contas a Pagar',
              subtitulo:
                  'Importa lançamentos de Contas a Pagar a partir de um CSV.',
              prefixo: 'cp',
            ),
            const SizedBox(height: AppSpacing.md),
            _buildImportCard(
              secao: _cr,
              isCP: false,
              titulo: 'Importar Contas a Receber',
              subtitulo:
                  'Importa lançamentos de Contas a Receber a partir de um CSV.',
              prefixo: 'cr',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDestinoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Destino da Importação', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Informe a empresa (obrigatório) e, opcionalmente, o parceiro dos lançamentos importados.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('importacao_empresa_field'),
                    controller: _empresaIdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'ID da Empresa *'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    key: const Key('importacao_parceiro_field'),
                    controller: _parceiroIdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'ID do Parceiro (opcional)'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportCard({
    required _SecaoImportacao secao,
    required bool isCP,
    required String titulo,
    required String subtitulo,
    required String prefixo,
  }) {
    final podeImportar = secao.arquivo != null &&
        _temEmpresa &&
        secao.temMapeamentoObrigatorio &&
        !secao.importando;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: Theme.of(context).textTheme.titleMedium),
            Text(subtitulo, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                OutlinedButton.icon(
                  key: Key('${prefixo}_pick_file_button'),
                  onPressed: () => _selecionarArquivo(secao),
                  icon: const Icon(Icons.attach_file),
                  label: Text(secao.arquivo?.name ?? 'Selecionar arquivo CSV'),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      key: Key('${prefixo}_upsert_checkbox'),
                      value: secao.upsert,
                      onChanged: (v) => setState(() => secao.upsert = v ?? false),
                    ),
                    const Text('Atualizar existentes (upsert)'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ExpansionTile(
              key: Key('${prefixo}_mapeamento_expansion'),
              initiallyExpanded: secao.mapeamentoExpandido,
              title: const Text('Mapeamento de colunas'),
              children: [
                for (final campo in _camposMapeamento)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: TextField(
                      key: Key('${prefixo}_map_${campo.chave}'),
                      controller: secao.controllers[campo.chave],
                      decoration: InputDecoration(
                        labelText: campo.obrigatorio ? '${campo.label} *' : campo.label,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: Key('${prefixo}_import_button'),
                onPressed: podeImportar ? () => _importar(secao, isCP) : null,
                child: secao.importando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Importar'),
              ),
            ),
            if (secao.erro != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                key: Key('${prefixo}_erro_text'),
                secao.erro!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (secao.resultado != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                key: Key('${prefixo}_resultado_text'),
                'Sucesso: ${secao.resultado?['sucesso'] ?? 0} · '
                'Erros: ${secao.resultado?['erros'] ?? 0} · '
                'Ignorados: ${secao.resultado?['ignorados'] ?? 0}',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
