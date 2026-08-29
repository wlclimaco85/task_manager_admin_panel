import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../config/api_links.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/network_caller.dart';

/// SIS-04 Config. Sistema — secao "Controle de Jobs" (Fase 2, Task 06.1).
///
/// Lista os ~18 jobs cron do backend (`GET /api/admin/jobs`: scrapers,
/// cotacoes, alertas, certificados NFC-e etc.), permite disparo manual
/// (`POST /api/admin/jobs/{nome}/executar[?forcar=true]`) e exibe o
/// historico de execucoes (`GET /api/admin/jobs/{nome}/historico`) em um
/// dialog. Execucao com `forcar=true` fica atras de confirmacao explicita
/// (job forcado pode reprocessar dados ja processados).
///
/// Port de `configuracoes_sistema_screen.dart` (`_JobsSection`, cliente),
/// adaptado ao padrao de tela embutida (sem `Scaffold` proprio, consumida
/// dentro do container de abas de `ConfiguracoesSistemaScreen` em P13).
class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key, this.networkCaller});

  final NetworkCaller? networkCaller;

  @override
  State<JobsScreen> createState() => JobsScreenState();
}

/// Representacao tolerante de um job retornado pelo backend. Os nomes de
/// campo exatos do `JobMonitorController` nao foram confirmados linha a
/// linha nesta sessao — aceita as variantes mais prováveis (`nome`/`name`,
/// `status`/`ativo`, `ultimaExecucao`/`lastExecution`/`lastRun`) para nao
/// quebrar silenciosamente se o backend usar uma nomenclatura diferente da
/// assumida.
class _JobInfo {
  _JobInfo({
    required this.nome,
    required this.status,
    required this.ultimaExecucao,
    required this.descricao,
    required this.raw,
  });

  factory _JobInfo.fromMap(Map<String, dynamic> map) {
    return _JobInfo(
      nome: (map['nome'] ?? map['name'] ?? map['jobName'] ?? '—').toString(),
      status: (map['status'] ?? map['ativo'] ?? '').toString(),
      ultimaExecucao: (map['ultimaExecucao'] ??
              map['lastExecution'] ??
              map['lastRun'] ??
              map['ultimoExecucao'])
          ?.toString(),
      descricao: (map['descricao'] ?? map['description'])?.toString(),
      raw: map,
    );
  }

  final String nome;
  final String status;
  final String? ultimaExecucao;
  final String? descricao;
  final Map<String, dynamic> raw;
}

class JobsScreenState extends State<JobsScreen> {
  late final NetworkCaller _caller = widget.networkCaller ?? NetworkCaller();
  bool get _ownsCaller => widget.networkCaller == null;

  bool _loading = true;
  String? _error;
  List<_JobInfo> _jobs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (_ownsCaller) _caller.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final body = await _get(ApiLinks.allJobs);
      final jobs = _extractJobs(body);
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Aceita `data: [...]` (lista direta) ou `data: {dados|content: [...]}`
  /// (formato paginado aninhado — mesmo problema tolerado pelo parser de
  /// `GenericGridScreen`, ver Task 01.1 do PLAN.md desta fase).
  List<_JobInfo> _extractJobs(Map<String, dynamic> body) {
    final rawData = body['data'];
    List<dynamic> list;
    if (rawData is List) {
      list = rawData;
    } else if (rawData is Map) {
      final inner = rawData['dados'] ?? rawData['content'];
      list = inner is List ? inner : const [];
    } else {
      list = const [];
    }
    return list
        .whereType<Map>()
        .map((m) => _JobInfo.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<Map<String, dynamic>> _get(String url) async {
    final resp = await _caller.getRequest(url);
    if (!resp.isSuccess) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
    return resp.body ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _post(String url) async {
    final resp = await _caller.postRequest(url, const {});
    if (!resp.isSuccess) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
    return resp.body ?? <String, dynamic>{};
  }

  /// Confirmacao simples (yes/no) para execucao com `forcar=true` — job
  /// forcado pode reprocessar dados ja processados (T-02-01 nao se aplica
  /// aqui, mas o mesmo padrao de defesa em profundidade de `acoes_screen.dart`
  /// e reaplicado por consistencia de UX).
  Future<bool> _confirmForcar(String nomeJob) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forçar execução do job'),
        content: Text(
            'O job "$nomeJob" sera executado com forcar=true, podendo reprocessar dados ja processados anteriormente. Deseja continuar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            key: const Key('confirm_forcar_button'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _executar(_JobInfo job, {required bool forcar}) async {
    if (forcar) {
      final confirmed = await _confirmForcar(job.nome);
      if (!confirmed) return;
      if (!mounted) return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await _post(ApiLinks.executarJob(job.nome, forcar: forcar));
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Job "${job.nome}" executado: '
            '${result['mensagem'] ?? result['message'] ?? 'OK'}'),
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Erro ao executar: $e')));
    }
  }

  Future<void> _abrirHistorico(_JobInfo job) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _HistoricoDialog(
        nomeJob: job.nome,
        load: () => _get(ApiLinks.historicoJob(job.nome)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        key: Key('jobs_screen_loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_error != null) {
      final colors = Theme.of(context).appColors;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Erro ao carregar jobs: $_error',
                key: const Key('jobs_screen_error'),
                style: TextStyle(color: colors.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              ElevatedButton(
                key: const Key('jobs_screen_retry_button'),
                onPressed: _load,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }
    if (_jobs.isEmpty) {
      return const Center(
        key: Key('jobs_screen_empty'),
        child: Text('Nenhum job encontrado.'),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        key: const Key('jobs_screen_list'),
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: _jobs.length,
        itemBuilder: (context, index) => _JobRow(
          job: _jobs[index],
          onExecutar: (forcar) => _executar(_jobs[index], forcar: forcar),
          onHistorico: () => _abrirHistorico(_jobs[index]),
        ),
      ),
    );
  }
}

class _JobRow extends StatefulWidget {
  const _JobRow({
    required this.job,
    required this.onExecutar,
    required this.onHistorico,
  });

  final _JobInfo job;
  final void Function(bool forcar) onExecutar;
  final VoidCallback onHistorico;

  @override
  State<_JobRow> createState() => _JobRowState();
}

class _JobRowState extends State<_JobRow> {
  bool _forcar = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;
    final job = widget.job;
    return Card(
      key: Key('job_row_${job.nome}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule, color: colors.primary, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(job.nome,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      if (job.descricao != null)
                        Text(job.descricao!,
                            style: TextStyle(
                                fontSize: 11, color: colors.onSurfaceMuted)),
                      if (job.status.isNotEmpty || job.ultimaExecucao != null)
                        Text(
                          [
                            if (job.status.isNotEmpty) 'status: ${job.status}',
                            if (job.ultimaExecucao != null)
                              'última execução: ${job.ultimaExecucao}',
                          ].join(' · '),
                          style: TextStyle(
                              fontSize: 11, color: colors.onSurfaceMuted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Switch(
                  key: Key('job_row_${job.nome}_forcar_switch'),
                  value: _forcar,
                  onChanged: (v) => setState(() => _forcar = v),
                ),
                const Text('Forçar'),
                const Spacer(),
                TextButton.icon(
                  key: Key('job_row_${job.nome}_historico_button'),
                  onPressed: widget.onHistorico,
                  icon: const Icon(Icons.history, size: 18),
                  label: const Text('Histórico'),
                ),
                const SizedBox(width: AppSpacing.sm),
                ElevatedButton.icon(
                  key: Key('job_row_${job.nome}_executar_button'),
                  onPressed: () => widget.onExecutar(_forcar),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Executar agora'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoricoDialog extends StatefulWidget {
  const _HistoricoDialog({required this.nomeJob, required this.load});

  final String nomeJob;
  final Future<Map<String, dynamic>> Function() load;

  @override
  State<_HistoricoDialog> createState() => _HistoricoDialogState();
}

class _HistoricoDialogState extends State<_HistoricoDialog> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Histórico — ${widget.nomeJob}'),
      content: SizedBox(
        width: 480,
        height: 320,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                key: Key('historico_dialog_loading'),
                child: CircularProgressIndicator(),
              );
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  key: const Key('historico_dialog_error'),
                  'Erro ao carregar histórico: ${snapshot.error}',
                ),
              );
            }
            final text = const JsonEncoder.withIndent('  ')
                .convert(snapshot.data ?? <String, dynamic>{});
            return SingleChildScrollView(
              child: SelectableText(
                text,
                key: const Key('historico_dialog_content'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
