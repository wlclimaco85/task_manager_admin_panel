// lib/utils/app_logger.dart
// AppLogger + Console Overlay (com filtro, copiar e exportar .txt)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import '../utils/grid_colors.dart';
import 'package:flutter/services.dart';

// ====== Dependências opcionais p/ exportar & abrir/compartilhar ======
// Adicione ao pubspec.yaml se quiser habilitar os botões de exportar/abrir/compartilhar.
// Caso não estejam presentes, o código faz fallback e mostra aviso.
import 'package:path_provider/path_provider.dart' as pp;
import 'package:url_launcher/url_launcher.dart' as launcher;
import 'package:share_plus/share_plus.dart' as share;

// ------------------------------- MODELOS -------------------------------

enum LogLevel { info, debug, success, warning, error }

extension on LogLevel {
  String get label {
    switch (this) {
      case LogLevel.info:
        return 'INFO';
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.success:
        return 'SUCCESS';
      case LogLevel.warning:
        return 'WARN';
      case LogLevel.error:
        return 'ERROR';
    }
  }

  IconData get icon {
    switch (this) {
      case LogLevel.info:
        return Icons.info_outline;
      case LogLevel.debug:
        return Icons.bug_report_outlined;
      case LogLevel.success:
        return Icons.check_circle_outline;
      case LogLevel.warning:
        return Icons.warning_amber_outlined;
      case LogLevel.error:
        return Icons.error_outline;
    }
  }

  Color color(Brightness b) {
    final dark = b == Brightness.dark;
    switch (this) {
      case LogLevel.info:
        return dark ? const Color(0xFFB3E5FC) : const Color(0xFF1565C0);
      case LogLevel.debug:
        return dark ? const Color(0xFFC5CAE9) : const Color(0xFF5E35B1);
      case LogLevel.success:
        return dark ? const Color(0xFFA5D6A7) : GridColors.success;
      case LogLevel.warning:
        return dark ? const Color(0xFFFFE082) : const Color(0xFFF57F17);
      case LogLevel.error:
        return dark ? const Color(0xFFFFAB91) : GridColors.error;
    }
  }
}

class AppLogEntry {
  final DateTime ts;
  final String message;
  final LogLevel level;
  final StackTrace? stack;

  AppLogEntry({
    required this.ts,
    required this.message,
    required this.level,
    this.stack,
  });

  String toLine() {
    final t = ts.toIso8601String();
    final head = '[$t] [${level.label}] ';
    if (stack != null) {
      return '$head$message\n$stack';
    }
    return '$head$message';
  }
}

// ------------------------------- LOGGER -------------------------------

class AppLogger {
  AppLogger._();
  static final AppLogger i = AppLogger._();

  final _logs = <AppLogEntry>[];
  final _stream = StreamController<List<AppLogEntry>>.broadcast();

  /// Tamanho máximo do buffer em memória.
  int maxEntries = 2000;

  /// Quando true, a UI (overlay) autoscrola quando chegam logs.
  bool autoScroll = true;

  bool _initialized = false;

  Stream<List<AppLogEntry>> get stream => _stream.stream;
  List<AppLogEntry> get current => List.unmodifiable(_logs);

  /// Chame uma única vez no início do app (ex.: no main ou na tela root)
  /// para capturar print/debugPrint, FlutterError e erros globais.
  void initCapture() {
    if (_initialized) return;
    _initialized = true;

    // Captura debugPrint/print
    final originalDebugPrint = debugPrint;
    debugPrint = (String? msg, {int? wrapWidth}) {
      if (msg != null) {
        add(AppLogEntry(
            ts: DateTime.now(), message: msg, level: LogLevel.debug));
      }
      originalDebugPrint.call(msg, wrapWidth: wrapWidth);
    };

    // Captura FlutterError
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      add(AppLogEntry(
        ts: DateTime.now(),
        message: details.exceptionAsString(),
        level: LogLevel.error,
        stack: details.stack,
      ));
      originalOnError?.call(details);
    };

    // Captura erros globais do engine (forma compatível com Flutter estável)
    try {
      WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
        add(AppLogEntry(
          ts: DateTime.now(),
          message: error.toString(),
          level: LogLevel.error,
          stack: stack,
        ));
        return false; // mantém comportamento padrão (report/crashlytics, etc.)
      };
    } catch (_) {
      // Em versões antigas, platformDispatcher pode não estar disponível; ignorar.
      info('AppLogger: platformDispatcher.onError indisponível (ok).');
    }

    // Mensagem de boas-vindas
    info('AppLogger inicializado ✅');
  }

  void add(AppLogEntry log) {
    _logs.add(log);
    if (_logs.length > maxEntries) {
      _logs.removeRange(0, _logs.length - maxEntries);
    }
    _stream.add(List.unmodifiable(_logs));
  }

  void info(String msg) =>
      add(AppLogEntry(ts: DateTime.now(), message: msg, level: LogLevel.info));
  void debug(String msg) =>
      add(AppLogEntry(ts: DateTime.now(), message: msg, level: LogLevel.debug));
  void success(String msg) => add(
      AppLogEntry(ts: DateTime.now(), message: msg, level: LogLevel.success));
  void warn(String msg) => add(
      AppLogEntry(ts: DateTime.now(), message: msg, level: LogLevel.warning));
  void error(String msg, [StackTrace? st]) => add(AppLogEntry(
      ts: DateTime.now(), message: msg, level: LogLevel.error, stack: st));

  void clear() {
    _logs.clear();
    _stream.add(List.unmodifiable(_logs));
  }

  Future<void> copyAllToClipboard(BuildContext context,
      {List<AppLogEntry>? list}) async {
    final data = (list ?? _logs).map((e) => e.toLine()).join('\n');
    await Clipboard.setData(ClipboardData(text: data));
    _snack(context, 'Logs copiados para a área de transferência');
  }

  Future<void> exportToTxt(BuildContext context,
      {List<AppLogEntry>? list}) async {
    try {
      final logs = (list ?? _logs).map((e) => e.toLine()).join('\n');
      final dir = await _safeDocsDir();
      final file = File(
          '${dir.path}/console_logs_${DateTime.now().millisecondsSinceEpoch}.txt');
      await file.writeAsString(logs, encoding: const Utf8Codec(), flush: true);

      // Tenta abrir; se não der, oferece compartilhar.
      try {
        final uri = Uri.file(file.path);
        if (await launcher.canLaunchUrl(uri)) {
          await launcher.launchUrl(uri,
              mode: launcher.LaunchMode.externalApplication);
        } else {
          throw Exception('canLaunchUrl returned false');
        }
      } catch (_) {
        try {
          await share.Share.shareXFiles([share.XFile(file.path)],
              text: 'Logs do console');
        } catch (_) {}
      }

      _snack(context, 'Arquivo exportado em: ${file.path}');
    } catch (e) {
      _snack(context,
          'Falha ao exportar: $e\nDica: adicione path_provider e share_plus ao pubspec para habilitar totalmente.');
    }
  }

  static void _snack(BuildContext ctx, String msg) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<Directory> _safeDocsDir() async {
    try {
      final d = await pp.getApplicationDocumentsDirectory();
      return d;
    } catch (_) {
      // fallback se path_provider não estiver instalado
      final tmp = Directory.systemTemp.createTempSync('app_logger_');
      return tmp;
    }
  }
}

// ----------------------------- OVERLAY UI -----------------------------

/// Botão flutuante + painel de console.
/// Se preferir só o serviço, não use este widget.
class AppLoggerOverlay extends StatefulWidget {
  const AppLoggerOverlay({super.key});

  @override
  State<AppLoggerOverlay> createState() => _AppLoggerOverlayState();
}

class _AppLoggerOverlayState extends State<AppLoggerOverlay> {
  OverlayEntry? _fabEntry;
  OverlayEntry? _panelEntry;
  bool _panelOpen = false;

  Offset _fabPos =
      const Offset(16, 100); // deslocamento a partir do canto direito

  @override
  void initState() {
    super.initState();
    AppLogger.i.initCapture();
    WidgetsBinding.instance.addPostFrameCallback((_) => _insertFab());
  }

  @override
  void dispose() {
    _removePanel();
    _removeFab();
    super.dispose();
  }

  void _insertFab() {
    _fabEntry ??= OverlayEntry(
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        final dx = size.width - 72 - _fabPos.dx;
        final dy = _fabPos.dy.clamp(16, size.height - 120);
        return Positioned(
          right: dx,
          top: dy.toDouble(),
          child: Draggable(
            feedback: _fabButton(ctx, dragging: true),
            childWhenDragging: const SizedBox.shrink(),
            onDragEnd: (details) {
              setState(() {
                _fabPos = Offset(
                    size.width - details.offset.dx - 56, details.offset.dy);
                _fabEntry?.markNeedsBuild();
              });
            },
            child: _fabButton(ctx),
          ),
        );
      },
    );
    Overlay.of(context).insert(_fabEntry!);
  }

  void _removeFab() {
    _fabEntry?.remove();
    _fabEntry = null;
  }

  Widget _fabButton(BuildContext ctx, {bool dragging = false}) {
    return Material(
      color: Colors.transparent,
      child: FloatingActionButton.small(
        heroTag: 'app_logger_fab',
        onPressed: dragging ? null : _togglePanel,
        tooltip: _panelOpen ? 'Fechar console' : 'Abrir console',
        child: Icon(_panelOpen ? Icons.close_fullscreen : Icons.terminal),
      ),
    );
  }

  void _togglePanel() {
    if (_panelOpen) {
      _removePanel();
    } else {
      _showPanel();
    }
    setState(() => _panelOpen = !_panelOpen);
    _fabEntry?.markNeedsBuild();
  }

  void _showPanel() {
    _panelEntry ??= OverlayEntry(builder: (ctx) {
      return _ConsolePanel(onClose: _togglePanel);
    });
    Overlay.of(context).insert(_panelEntry!);
  }

  void _removePanel() {
    _panelEntry?.remove();
    _panelEntry = null;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _ConsolePanel extends StatefulWidget {
  final VoidCallback onClose;
  const _ConsolePanel({required this.onClose});

  @override
  State<_ConsolePanel> createState() => _ConsolePanelState();
}

class _ConsolePanelState extends State<_ConsolePanel> {
  final _log = AppLogger.i;
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  LogLevel? _levelFilter;

  @override
  void initState() {
    super.initState();
    _log.stream.listen((_) {
      if (!mounted) return;
      if (_log.autoScroll && _scrollCtrl.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.animateTo(
              _scrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<AppLogEntry> _applyFilters(List<AppLogEntry> logs) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final l = _levelFilter;
    return logs.where((e) {
      final okLevel = l == null || e.level == l;
      final okQuery = q.isEmpty ||
          e.message.toLowerCase().contains(q) ||
          (e.stack?.toString().toLowerCase().contains(q) ?? false);
      return okLevel && okQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.35),
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: LayoutBuilder(
              builder: (_, constraints) {
                final maxW = constraints.maxWidth;
                final panelW = maxW < 720 ? maxW : 680.0;
                return Container(
                  width: panelW,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: GridColors.background,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 18,
                        color: Colors.black.withValues(alpha: 0.25),
                        spreadRadius: 2,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    border: Border.all(
                        color: theme.dividerColor.withValues(alpha: 0.2)),
                  ),
                  child: DraggableScrollableSheet(
                    expand: false,
                    initialChildSize: 0.65,
                    minChildSize: 0.35,
                    maxChildSize: 0.9,
                    builder: (ctx, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Column(
                        children: [
                          _buildHeader(theme),
                          _buildToolbar(theme),
                          const Divider(height: 1),
                          Expanded(
                            child: StreamBuilder<List<AppLogEntry>>(
                              stream: _log.stream,
                              initialData: _log.current,
                              builder: (context, snapshot) {
                                final logs = _applyFilters(snapshot.data ?? []);
                                return Scrollbar(
                                  controller: _scrollCtrl,
                                  child: ListView.builder(
                                    controller: _scrollCtrl,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    itemCount: logs.length,
                                    itemBuilder: (ctx, i) =>
                                        _LogTile(log: logs[i]),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.08)),
      child: Row(
        children: [
          const Icon(Icons.terminal, size: 18),
          const SizedBox(width: 8),
          Text('Console de Logs',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const Spacer(),
          IconButton(
            tooltip:
                _log.autoScroll ? 'Pausar autoscroll' : 'Retomar autoscroll',
            onPressed: () => setState(() => _log.autoScroll = !_log.autoScroll),
            icon: Icon(_log.autoScroll ? Icons.playlist_play : Icons.pause),
          ),
          IconButton(
            tooltip: 'Fechar',
            onPressed: widget.onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Busca por palavra-chave
          SizedBox(
            width: 220,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: 'Filtrar (ex.: erro)',
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        tooltip: 'Limpar filtro',
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear, size: 18),
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
          ),

          DropdownButton<LogLevel?>(
            value: _levelFilter,
            hint: const Text('Nível: todos'),
            onChanged: (v) => setState(() => _levelFilter = v),
            items: [
              const DropdownMenuItem<LogLevel?>(
                value: null,
                child: Text('Todos'),
              ),
              ...LogLevel.values.map(
                (e) => DropdownMenuItem<LogLevel?>(
                  value: e,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(e.icon, size: 18, color: e.color(theme.brightness)),
                      const SizedBox(width: 6),
                      Text(e.label),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(width: 8),

          FilledButton.tonalIcon(
            onPressed: () => setState(() => _log.clear()),
            icon: const Icon(Icons.delete_sweep),
            label: const Text('Limpar'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => _log.copyAllToClipboard(context,
                list: _applyFilters(_log.current)),
            icon: const Icon(Icons.content_copy),
            label: const Text('Copiar'),
          ),
          FilledButton.icon(
            onPressed: () =>
                _log.exportToTxt(context, list: _applyFilters(_log.current)),
            icon: const Icon(Icons.save_alt),
            label: const Text('Exportar .txt'),
          ),
        ],
      ),
    );
  }
}

// ------------------------------- LOG TILE -------------------------------

class _LogTile extends StatelessWidget {
  final AppLogEntry log;
  const _LogTile({required this.log});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = log.level.color(theme.brightness);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(log.level.icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                '[${log.ts.toIso8601String()}] ${log.level.label}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Mensagem — Selectable, com quebra natural
          SelectionArea(
            child: Text(
              log.message,
              softWrap: true,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.25),
            ),
          ),

          if (log.stack != null) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectionArea(
                child: Text(
                  log.stack.toString(),
                  softWrap: true,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------- HELPERS PÚBLICOS -------------------------------
/// Azucar sintático, se você quiser logar rápido sem importar o singleton:
class L {
  static String _text(Object? msg) => msg?.toString() ?? 'null';
  static void i(Object? msg) => AppLogger.i.info(_text(msg));
  static void d(Object? msg) => AppLogger.i.debug(_text(msg));
  static void s(Object? msg) => AppLogger.i.success(_text(msg));
  static void w(Object? msg) => AppLogger.i.warn(_text(msg));
  static void e(Object? msg, [StackTrace? st]) =>
      AppLogger.i.error(_text(msg), st);
}
