import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_utility.dart';
import '../models/system_test_run_model.dart';
import '../services/system_test_run_service.dart';

class SystemTestRunPanel extends StatefulWidget {
  final SystemTestRunService? service;
  final String? token;
  const SystemTestRunPanel({super.key, this.service, this.token});
  @override
  State<SystemTestRunPanel> createState() => _SystemTestRunPanelState();
}

class _SystemTestRunPanelState extends State<SystemTestRunPanel> {
  static const _groups = <String, String>{
    'FASE_1': 'Fase 1',
    'FASE_2': 'Fase 2',
    'COMERCIAL': 'Comercial',
    'NFE': 'NF-e',
    'NFSE': 'NFS-e',
    'NFCE': 'NFC-e',
    'FINANCEIRO_AVANCADO': 'Financeiro avançado',
    'TRADING': 'Bolsa de valores',
    'GME': 'GME',
    'TODOS': 'Tudo: fases 1 e 2',
  };
  late final SystemTestRunService _service =
      widget.service ?? SystemTestRunService();
  Timer? _poller;
  SystemTestRunModel? _run;
  List<SystemTestEventModel> _events = const [];
  String? _error;
  bool _starting = false;
  String _selectedGroup = 'FASE_1';
  String get _token => widget.token ?? AuthUtility.userInfo?.token ?? '';

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (_token.isEmpty) {
      setState(() => _error = 'Sessão sem token. Entre novamente.');
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
      _events = const [];
    });
    try {
      final run = await _service.start(_token, [_selectedGroup]);
      if (!mounted) return;
      setState(() => _run = run);
      _beginPolling();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _beginPolling() {
    _poller?.cancel();
    _refresh();
    _poller = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  Future<void> _refresh() async {
    final id = _run?.runId;
    if (id == null || id.isEmpty) return;
    try {
      final values = await Future.wait(
          [_service.status(_token, id), _service.events(_token, id)]);
      if (!mounted) return;
      final run = values[0] as SystemTestRunModel;
      setState(() {
        _run = run;
        _events = values[1] as List<SystemTestEventModel>;
        _error = null;
      });
      if (!run.isActive) _poller?.cancel();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _cancel() async {
    await _service.cancel(_token, _run!.runId);
    await _refresh();
  }

  Future<void> _retryCleanup() async {
    try {
      final run = await _service.retryCleanup(_token, _run!.runId);
      if (mounted) setState(() => _run = run);
      _beginPolling();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final run = _run;
    return Column(children: [
      Container(
          color: const Color(0xFF1A1D27),
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(children: [
              const Expanded(
                  child: Text('Homologação · fluxo real com limpeza automática',
                      style: TextStyle(
                          color: Colors.white70, fontWeight: FontWeight.w600))),
              if (run?.isActive != true)
                SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                        key: const Key('system_test_group_selector'),
                        initialValue: _selectedGroup,
                        dropdownColor: const Color(0xFF252936),
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Escopo', isDense: true),
                        items: _groups.entries
                            .map((entry) => DropdownMenuItem(
                                value: entry.key, child: Text(entry.value)))
                            .toList(),
                        onChanged: _starting
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _selectedGroup = value);
                                }
                              })),
              const SizedBox(width: 8),
              if (run?.isActive == true)
                OutlinedButton.icon(
                    onPressed: _cancel,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Cancelar'))
              else
                FilledButton.icon(
                    key: const Key('system_test_start_button'),
                    onPressed: _starting ? null : _start,
                    icon: _starting
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.play_arrow),
                    label: Text('Executar ${_groups[_selectedGroup]}')),
              if (run != null && run.residueCount > 0) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                    onPressed: _retryCleanup,
                    icon: const Icon(Icons.cleaning_services_outlined),
                    label: const Text('Refazer limpeza'))
              ],
            ]),
            if (run != null) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(
                  value: run.progressPercent.clamp(0, 100) / 100),
              const SizedBox(height: 8),
              Wrap(spacing: 18, runSpacing: 6, children: [
                Text(
                    '${run.progressPercent}% · ${run.completedOperations}/${run.totalOperations}',
                    style: const TextStyle(color: Colors.white)),
                Text(run.status,
                    style: const TextStyle(color: Color(0xFF66BB6A))),
                Text('Falhas ${run.failureCount}',
                    style: const TextStyle(color: Color(0xFFEF5350))),
                Text('Limpos ${run.cleanedCount}',
                    style: const TextStyle(color: Colors.white70)),
                Text('Resíduos ${run.residueCount}',
                    style: const TextStyle(color: Color(0xFFFFB74D))),
              ]),
              const SizedBox(height: 6),
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text(run.currentStep ?? run.marker,
                      style: const TextStyle(color: Colors.white54)))
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_error!,
                      style: const TextStyle(color: Color(0xFFEF5350))))
            ],
          ])),
      Expanded(
          child: _events.isEmpty
              ? const Center(
                  child: Text('Nenhuma execução iniciada.',
                      style: TextStyle(color: Colors.white38)))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _events.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Colors.white12, height: 1),
                  itemBuilder: (_, i) {
                    final event = _events[i];
                    final failed = event.level == 'ERROR';
                    return ListTile(
                        dense: true,
                        leading: Icon(
                            failed
                                ? Icons.error_outline
                                : Icons.check_circle_outline,
                            color: failed
                                ? const Color(0xFFEF5350)
                                : const Color(0xFF66BB6A),
                            size: 18),
                        title: Text(event.step,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                        subtitle: Text(event.message,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11)),
                        trailing: Text('#${event.sequence}',
                            style: const TextStyle(color: Colors.white24)));
                  }))
    ]);
  }
}
