import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/importacao_cadastros_service.dart';
import '../../../services/network_caller.dart';
import '../../../utils/csv_parser.dart';

/// SIS-04 Config. Sistema — Importação CSV de Cadastros (Empresas,
/// Parceiros, Funcionários, Logins de Clientes, Planos).
///
/// Porta `_ImportacaoCadastrosSection` de
/// `task_manager_flutter/lib/web/screens/configuracoes_sistema_screen.dart`
/// (ver RESEARCH.md, Item 4) como camada de UI sobre
/// [ImportacaoCadastrosService] (Task 08a.1, já pronta) — esta task (08b.1)
/// só cobre seleção de tipo, seleção de arquivo (`file_picker`, mesmo
/// padrão de P07), preview das primeiras linhas do CSV, mapeamento de
/// colunas configurável (auto-mapeado por sinônimo, editável) e execução
/// linha-a-linha com barra de progresso e log por linha.
///
/// Igual à `ImportacaoContasScreen` (P07), o `file_picker` é injetável via
/// [pickFileOverride] para permitir testes de widget sem depender de
/// seleção real de arquivo pelo SO.
class ImportacaoCadastrosScreen extends StatefulWidget {
  // ignore: prefer_const_constructors_in_immutables
  ImportacaoCadastrosScreen({
    super.key,
    this.networkCaller,
    Future<FilePickerResult?> Function()? pickFileOverride,
  }) : pickFileOverride = pickFileOverride ?? _pickFileReal;

  final NetworkCaller? networkCaller;
  final Future<FilePickerResult?> Function() pickFileOverride;

  static Future<FilePickerResult?> _pickFileReal() {
    return FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
  }

  @override
  State<ImportacaoCadastrosScreen> createState() =>
      ImportacaoCadastrosScreenState();
}

/// Normaliza uma string do mesmo jeito que o serviço (minúsculo, sem
/// acentos, espaços viram `_`) — usado só para o auto-mapeamento de colunas
/// nesta tela; a lógica de dedup/normalização definitiva vive no serviço.
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
/// conhecidos de [config] por dicionário de sinônimos — preenche
/// [controllers] (um `TextEditingController` por campo) só quando encontra
/// correspondência; campos sem correspondência ficam vazios (o serviço cai
/// de volta para o mesmo dicionário de sinônimos internamente quando o
/// mapeamento explícito não bate com nenhuma coluna real da linha).
void _autoMapear(
  CadastroImportConfig config,
  Map<String, TextEditingController> controllers,
  List<String> colunas,
) {
  final colunasNorm = colunas.map(_normalizar).toList();
  for (final campo in config.campos) {
    final candidatos = [campo.key, ...campo.sinonimos].map(_normalizar);
    for (final candidato in candidatos) {
      final idx = colunasNorm.indexWhere(
        (cn) => cn == candidato || cn.contains(candidato) || candidato.contains(cn),
      );
      if (idx >= 0) {
        controllers[campo.key]?.text = colunas[idx];
        break;
      }
    }
  }
}

/// Converte a matriz `linhas` (retorno de [parseCsv], 1ª linha = cabeçalho)
/// em uma lista de `Map<coluna, valor>` — mesmo contrato de `rows` esperado
/// por `ImportacaoCadastrosService.importar`.
List<Map<String, String>> _linhasParaMapas(List<List<String>> linhas) {
  if (linhas.length < 2) return const [];
  final header = linhas.first.map((c) => c.trim()).toList();
  return linhas.skip(1).map((linha) {
    final map = <String, String>{};
    for (var i = 0; i < header.length; i++) {
      map[header[i]] = i < linha.length ? linha[i].trim() : '';
    }
    return map;
  }).toList();
}

class ImportacaoCadastrosScreenState extends State<ImportacaoCadastrosScreen> {
  late final NetworkCaller _caller = widget.networkCaller ?? NetworkCaller();
  bool get _ownsCaller => widget.networkCaller == null;
  late final ImportacaoCadastrosService _service =
      ImportacaoCadastrosService(networkCaller: _caller);

  final _empresaIdController = TextEditingController();
  final _parceiroIdController = TextEditingController();

  ImportacaoCadastroTipo _tipo = ImportacaoCadastroTipo.empresa;
  Map<String, TextEditingController> _mapControllers = _controllersPara(
      ImportacaoCadastrosService.configs.first);

  PlatformFile? _arquivo;
  List<List<String>> _linhasCsv = const [];
  List<String> _colunas = const [];
  bool _mapeamentoExpandido = false;

  bool _importando = false;
  int _linhaAtual = 0;
  int _totalLinhas = 0;
  ImportacaoResultado? _resultado;
  String? _erro;
  bool _atualizar = false;

  static Map<String, TextEditingController> _controllersPara(
      CadastroImportConfig config) {
    return {
      for (final campo in config.campos) campo.key: TextEditingController(),
    };
  }

  CadastroImportConfig get _config =>
      ImportacaoCadastrosService.configs.firstWhere((c) => c.tipo == _tipo);

  @override
  void dispose() {
    if (_ownsCaller) _caller.close();
    _empresaIdController.dispose();
    _parceiroIdController.dispose();
    for (final c in _mapControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _trocarTipo(ImportacaoCadastroTipo? novo) {
    if (novo == null || novo == _tipo) return;
    for (final c in _mapControllers.values) {
      c.dispose();
    }
    setState(() {
      _tipo = novo;
      _mapControllers = _controllersPara(_config);
      _arquivo = null;
      _linhasCsv = const [];
      _colunas = const [];
      _resultado = null;
      _erro = null;
    });
  }

  Future<void> _selecionarArquivo() async {
    final result = await widget.pickFileOverride();
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    final linhas = _parseArquivo(bytes);
    final colunas =
        linhas.isNotEmpty ? linhas.first.map((c) => c.trim()).toList() : const <String>[];

    setState(() {
      _arquivo = file;
      _linhasCsv = linhas;
      _colunas = colunas;
      _resultado = null;
      _erro = null;
      _autoMapear(_config, _mapControllers, colunas);
    });
  }

  List<List<String>> _parseArquivo(Uint8List bytes) {
    try {
      final texto = utf8.decode(bytes, allowMalformed: true).replaceAll('﻿', '');
      return parseCsv(texto);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _importar() async {
    final rows = _linhasParaMapas(_linhasCsv);
    if (rows.isEmpty) return;

    setState(() {
      _importando = true;
      _linhaAtual = 0;
      _totalLinhas = rows.length;
      _resultado = null;
      _erro = null;
    });

    final mapeamento = <String, String>{
      for (final entry in _mapControllers.entries)
        if (entry.value.text.trim().isNotEmpty) entry.key: entry.value.text.trim(),
    };

    try {
      final resultado = await _service.importar(
        tipo: _tipo,
        rows: rows,
        mapeamentoColunas: mapeamento,
        empresaIdSelecionada: _empresaIdController.text.trim().isEmpty
            ? null
            : _empresaIdController.text.trim(),
        parceiroIdSelecionado: _parceiroIdController.text.trim().isEmpty
            ? null
            : _parceiroIdController.text.trim(),
        atualizar: _atualizar,
        onProgress: (linhaAtual, total, entry) {
          if (!mounted) return;
          setState(() {
            _linhaAtual = linhaAtual;
            _totalLinhas = total;
          });
        },
      );
      if (!mounted) return;
      setState(() => _resultado = resultado);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _importando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final podeImportar =
        _arquivo != null && _linhasCsv.length > 1 && !_importando;

    // Achado do code-review da Fase 2 (WR-01, mesmo padrao encontrado em
    // ImportacaoContasScreen): esta tela e' instanciada so' embutida como
    // aba de ConfiguracoesSistemaScreen (TabBarView), que ja tem seu
    // proprio Scaffold/AppBar/TabBar -- Scaffold/AppBar aqui duplicava o
    // chrome dentro da area de conteudo da aba. Sem Scaffold proprio.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTipoCard(),
          const SizedBox(height: AppSpacing.md),
          _buildArquivoCard(podeImportar: podeImportar),
          if (_linhasCsv.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _buildPreviewCard(),
          ],
          if (_importando || _resultado != null) ...[
            const SizedBox(height: AppSpacing.md),
            _buildProgressoCard(),
          ],
          if (_erro != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              key: const Key('importacao_cadastros_erro_text'),
              _erro!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTipoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tipo de Cadastro', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<ImportacaoCadastroTipo>(
              key: const Key('importacao_cadastros_tipo_dropdown'),
              initialValue: _tipo,
              items: [
                for (final config in ImportacaoCadastrosService.configs)
                  DropdownMenuItem(value: config.tipo, child: Text(config.title)),
              ],
              onChanged: _importando ? null : _trocarTipo,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(_config.subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('importacao_cadastros_empresa_field'),
                    controller: _empresaIdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'ID da Empresa'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    key: const Key('importacao_cadastros_parceiro_field'),
                    controller: _parceiroIdController,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'ID do Parceiro (opcional)'),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  key: const Key('importacao_cadastros_atualizar_checkbox'),
                  value: _atualizar,
                  onChanged: _importando
                      ? null
                      : (v) => setState(() => _atualizar = v ?? false),
                ),
                const Text('Atualizar se existir'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArquivoCard({required bool podeImportar}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Arquivo CSV', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              key: const Key('importacao_cadastros_pick_file_button'),
              onPressed: _importando ? null : _selecionarArquivo,
              icon: const Icon(Icons.attach_file),
              label: Text(_arquivo?.name ?? 'Selecionar arquivo CSV'),
            ),
            const SizedBox(height: AppSpacing.sm),
            ExpansionTile(
              key: const Key('importacao_cadastros_mapeamento_expansion'),
              initiallyExpanded: _mapeamentoExpandido,
              onExpansionChanged: (v) => setState(() => _mapeamentoExpandido = v),
              title: const Text('Mapeamento de colunas'),
              children: [
                for (final campo in _config.campos)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: TextField(
                      key: Key('importacao_cadastros_map_${campo.key}'),
                      controller: _mapControllers[campo.key],
                      decoration: InputDecoration(labelText: campo.label),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const Key('importacao_cadastros_import_button'),
                onPressed: podeImportar ? _importar : null,
                child: _importando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Importar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard() {
    final linhasPreview = _linhasCsv.skip(1).take(3).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Preview (${linhasPreview.length} de ${_linhasCsv.length - 1} linhas)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            SingleChildScrollView(
              key: const Key('importacao_cadastros_preview_table'),
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [for (final coluna in _colunas) DataColumn(label: Text(coluna))],
                rows: [
                  for (final linha in linhasPreview)
                    DataRow(cells: [
                      for (var i = 0; i < _colunas.length; i++)
                        DataCell(Text(i < linha.length ? linha[i] : '')),
                    ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressoCard() {
    final resultado = _resultado;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Progresso', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (_importando) ...[
              LinearProgressIndicator(
                key: const Key('importacao_cadastros_progress_bar'),
                value: _totalLinhas > 0 ? _linhaAtual / _totalLinhas : null,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text('Linha $_linhaAtual de $_totalLinhas'),
            ],
            if (resultado != null) ...[
              Text(
                key: const Key('importacao_cadastros_resultado_text'),
                'Sucesso: ${resultado.sucesso} · Erros: ${resultado.erros} · '
                'Ignorados: ${resultado.ignorados} · Total: ${resultado.total}',
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  key: const Key('importacao_cadastros_log_list'),
                  itemCount: resultado.detalhes.length,
                  itemBuilder: (context, index) {
                    final entry = resultado.detalhes[index];
                    final cor = switch (entry.status) {
                      'sucesso' => Colors.green,
                      'erro' => Theme.of(context).colorScheme.error,
                      _ => Theme.of(context).colorScheme.outline,
                    };
                    return Text(
                      'Linha ${entry.linha}: ${entry.mensagem}',
                      style: TextStyle(color: cor),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
