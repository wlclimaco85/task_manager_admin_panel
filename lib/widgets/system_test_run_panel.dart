import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  static const _primary = Color(0xFF93070A);
  static const _success = Color(0xFF2E7D32);
  static const _errorColor = Color(0xFFD32F2F);
  static const _warning = Color(0xFFFFA000);
  static const _background = Color(0xFFF6FAF7);
  static const _surface = Colors.white;
  static const _filterBackground = Color(0xFFF3F7F4);
  static const _divider = Color(0xFFD8E0DA);
  static const _text = Color(0xFF17211B);
  static const _muted = Color(0xFF64756A);

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

  Future<void> _copy(String value, {String? feedback}) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(feedback ?? 'Erro copiado para a área de transferência.')),
    );
  }

  Future<void> _copyAllErrors(String fallback) async {
    final errors =
        _events.where((event) => event.level.toUpperCase() == 'ERROR').toList();
    final text = errors.isEmpty
        ? fallback
        : errors
            .map(
                (event) => '#${event.sequence} ${event.step}\n${event.message}')
            .join('\n\n');
    await _copy(text,
        feedback:
            '${errors.isEmpty ? 1 : errors.length} erros copiados para a área de transferência.');
  }

  @override
  Widget build(BuildContext context) {
    final run = _run;
    final visibleError = _error ?? run?.lastError;
    return ColoredBox(
      color: _background,
      child: Column(
        children: [
          _buildHeader(run),
          if (run != null) _buildProgress(run),
          if (visibleError != null && visibleError.isNotEmpty)
            _buildErrorSummary(visibleError, run?.failureCount ?? 1),
          Expanded(child: _buildEvents()),
        ],
      ),
    );
  }

  Widget _buildHeader(SystemTestRunModel? run) {
    final controls = Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (run?.isActive != true) _buildGroupSelector(),
        if (run?.isActive == true)
          OutlinedButton.icon(
            onPressed: _cancel,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Cancelar'),
          )
        else
          FilledButton.icon(
            key: const Key('system_test_start_button'),
            onPressed: _starting ? null : _start,
            style: FilledButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(190, 44),
            ),
            icon: _starting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.play_arrow),
            label: Text('Executar ${_groups[_selectedGroup]}'),
          ),
        if (run != null && run.residueCount > 0)
          OutlinedButton.icon(
            onPressed: _retryCleanup,
            style: OutlinedButton.styleFrom(
              foregroundColor: _errorColor,
              minimumSize: const Size(160, 44),
            ),
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Refazer limpeza'),
          ),
      ],
    );

    return Container(
      width: double.infinity,
      color: _surface,
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(builder: (context, constraints) {
        const heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Testes integrados em homologação',
              style: TextStyle(
                  color: _text, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 4),
            Text(
              'Executa fluxos reais e remove os dados criados ao finalizar.',
              style: TextStyle(color: _muted, fontSize: 13),
            ),
          ],
        );
        if (constraints.maxWidth < 1000) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 14), controls],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Expanded(child: heading),
            const SizedBox(width: 16),
            Flexible(child: controls),
          ],
        );
      }),
    );
  }

  Widget _buildGroupSelector() {
    return SizedBox(
      width: 250,
      child: DropdownButtonFormField<String>(
        key: const Key('system_test_group_selector'),
        initialValue: _selectedGroup,
        dropdownColor: _surface,
        menuMaxHeight: 360,
        isExpanded: true,
        style: const TextStyle(color: _text, fontSize: 14),
        iconEnabledColor: _primary,
        decoration: InputDecoration(
          labelText: 'Escopo do teste',
          labelStyle: const TextStyle(color: _muted),
          filled: true,
          fillColor: _surface,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: _primary),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: _primary, width: 2),
          ),
        ),
        items: _groups.entries
            .map((entry) => DropdownMenuItem(
                  value: entry.key,
                  child:
                      Text(entry.value, style: const TextStyle(color: _text)),
                ))
            .toList(),
        onChanged: _starting
            ? null
            : (value) {
                if (value != null) setState(() => _selectedGroup = value);
              },
      ),
    );
  }

  Widget _buildProgress(SystemTestRunModel run) {
    return Container(
      width: double.infinity,
      color: _filterBackground,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: run.progressPercent.clamp(0, 100) / 100,
            minHeight: 4,
            color: run.failureCount > 0 ? _errorColor : _success,
            backgroundColor: _divider,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metric('${run.progressPercent}%', _text),
              _metric(
                  '${run.completedOperations}/${run.totalOperations}', _text),
              _metric(
                  run.status, run.failureCount > 0 ? _errorColor : _success),
              _metric('Sucessos ${run.successCount}', _success),
              _metric('Falhas ${run.failureCount}', _errorColor),
              if (run.skippedCount > 0)
                _metric('Ignorados ${run.skippedCount}', _warning),
              _metric('Limpos ${run.cleanedCount}', _muted),
              _metric('Resíduos ${run.residueCount}', _warning),
            ],
          ),
          const SizedBox(height: 8),
          Text(run.currentStep ?? run.marker,
              style: const TextStyle(color: _muted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _metric(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildErrorSummary(String message, int failureCount) {
    return Container(
      key: const Key('system_test_error_summary'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F4),
        border: Border.all(color: _errorColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: _errorColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  failureCount == 1
                      ? '1 falha registrada'
                      : '$failureCount falhas registradas',
                  style: const TextStyle(
                      color: _errorColor, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                SelectableText(message,
                    style: const TextStyle(color: _text, fontSize: 12)),
                if (failureCount > 1)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Os demais erros aparecem nas etapas abaixo.',
                      style: TextStyle(color: _muted, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            key: const Key('system_test_error_copy'),
            tooltip: 'Copiar todos os erros',
            onPressed: () => _copyAllErrors(message),
            icon: const Icon(Icons.copy, color: _primary),
          ),
        ],
      ),
    );
  }

  Widget _buildEvents() {
    if (_events.isEmpty) {
      return const Center(
        child:
            Text('Nenhuma execução iniciada.', style: TextStyle(color: _muted)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: _events.length,
      separatorBuilder: (_, __) => const Divider(color: _divider, height: 1),
      itemBuilder: (_, index) {
        final event = _events[index];
        final failed = event.level == 'ERROR';
        return ColoredBox(
          color: failed ? const Color(0xFFFFF4F4) : _surface,
          child: ListTile(
            dense: true,
            leading: Icon(
              failed ? Icons.error_outline : Icons.check_circle_outline,
              color: failed ? _errorColor : _success,
              size: 20,
            ),
            title: Text(event.step,
                style: const TextStyle(
                    color: _text, fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: failed
                ? SelectableText(event.message,
                    style: const TextStyle(color: _text, fontSize: 12))
                : Text(event.message,
                    style: const TextStyle(color: _muted, fontSize: 11)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('#${event.sequence}',
                    style: const TextStyle(color: _muted, fontSize: 11)),
                if (failed)
                  IconButton(
                    tooltip: 'Copiar erro desta etapa',
                    onPressed: () => _copy(event.message),
                    icon: const Icon(Icons.copy, color: _primary, size: 18),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
