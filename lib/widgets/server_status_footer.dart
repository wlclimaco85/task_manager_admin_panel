import 'dart:async';

import 'package:flutter/material.dart';

import '../config/api_links.dart';
import '../screens/monitoramento/sistema_logs_screen.dart';
import '../services/server_status_service.dart';
import '../utils/grid_colors.dart';

/// Footer permanente do Painel do Dono que exibe saude dos servidores Railway.
///
/// Atualiza automaticamente a cada 60 segundos e permite refresh manual.
/// Clicando no badge de excecoes abre [SistemaLogsScreen] filtrado por ERROR.
class ServerStatusFooter extends StatefulWidget {
  const ServerStatusFooter({super.key, ServerStatusService? service})
      : _service = service;

  final ServerStatusService? _service;

  @override
  State<ServerStatusFooter> createState() => _ServerStatusFooterState();
}

class _ServerStatusFooterState extends State<ServerStatusFooter> {
  late final ServerStatusService _service;
  Timer? _timer;
  ServerStatusResult _result = ServerStatusResult.checking();
  bool _carregando = false;

  @override
  void initState() {
    super.initState();
    _service = widget._service ?? ServerStatusService();
    _verificar();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _verificar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _verificar() async {
    if (_carregando) return;
    setState(() => _carregando = true);
    try {
      final result = await _service.checkAll();
      if (mounted) setState(() => _result = result);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _abrirLogs(BuildContext ctx) {
    Navigator.of(ctx).push(
      MaterialPageRoute(builder: (_) => const SistemaLogsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final horario = _formatarHorario(_result.verificadoEm);
    final webConfigurada = ApiLinks.frontendWebUrl.isNotEmpty;

    return Container(
      color: GridColors.shellBackground,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // --- dots de status ---
            _StatusDot(
              label: 'Backend',
              status: _result.backend,
              carregando: _carregando,
            ),
            const SizedBox(width: 10),
            _StatusDot(
              label: 'Web',
              status: webConfigurada
                  ? _result.frontendWeb
                  : ServerStatus.offline,
              carregando: _carregando,
              tooltip: webConfigurada
                  ? null
                  : 'Configure FRONTEND_WEB_URL para monitorar',
              inativo: !webConfigurada,
            ),
            const SizedBox(width: 10),
            // Windows e app local — sem URL de servidor
            const _StatusDot(
              label: 'Windows',
              status: ServerStatus.online,
              carregando: false,
              tooltip: 'App desktop local — sem monitoramento remoto',
              inativo: true,
            ),
            const Spacer(),
            // --- badge de excecoes ---
            GestureDetector(
              onTap: () => _abrirLogs(context),
              child: _BadgeExcecoes(
                count: _result.totalExcecoes,
                carregando: _carregando,
              ),
            ),
            const SizedBox(width: 8),
            // --- horario ---
            Text(
              horario,
              style: const TextStyle(
                color: GridColors.textPrimaryMuted,
                fontSize: 10,
              ),
            ),
            const SizedBox(width: 4),
            // --- botao refresh ---
            SizedBox(
              width: 28,
              height: 28,
              child: _carregando
                  ? const Padding(
                      padding: EdgeInsets.all(6),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: GridColors.textPrimaryMuted,
                      ),
                    )
                  : IconButton(
                      key: const Key('server_status_refresh_btn'),
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.refresh,
                        size: 18,
                        color: GridColors.textPrimaryMuted,
                      ),
                      tooltip: 'Atualizar status',
                      onPressed: _verificar,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatarHorario(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

// ---------------------------------------------------------------------------

class _StatusDot extends StatelessWidget {
  const _StatusDot({
    required this.label,
    required this.status,
    required this.carregando,
    this.tooltip,
    this.inativo = false,
  });

  final String label;
  final ServerStatus status;
  final bool carregando;
  final String? tooltip;
  final bool inativo;

  Color get _cor {
    if (inativo) return GridColors.textPrimaryMuted;
    if (carregando || status == ServerStatus.checking) return GridColors.warning;
    if (status == ServerStatus.online) return GridColors.success;
    return GridColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final dot = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: _cor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: inativo
                ? GridColors.textPrimaryMuted
                : GridColors.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: dot);
    }
    return dot;
  }
}

// ---------------------------------------------------------------------------

class _BadgeExcecoes extends StatelessWidget {
  const _BadgeExcecoes({required this.count, required this.carregando});

  final int count;
  final bool carregando;

  @override
  Widget build(BuildContext context) {
    final temErros = !carregando && count > 0;
    final cor = temErros ? GridColors.error : GridColors.textPrimaryMuted;
    final bgCor = temErros
        ? GridColors.error.withAlpha(30)
        : Colors.transparent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgCor,
        borderRadius: BorderRadius.circular(10),
        border: temErros
            ? Border.all(color: GridColors.error.withAlpha(100), width: 1)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            temErros ? Icons.warning_amber_rounded : Icons.check_circle_outline,
            size: 12,
            color: cor,
          ),
          const SizedBox(width: 4),
          Text(
            carregando ? '–' : '$count excecoes',
            style: TextStyle(
              color: cor,
              fontSize: 11,
              fontWeight: temErros ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
