import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../models/sistema_log_model.dart';
import '../../services/sistema_log_service.dart';

class SistemaLogsScreen extends StatefulWidget {
  const SistemaLogsScreen({super.key, this.service});

  final SistemaLogService? service;

  @override
  State<SistemaLogsScreen> createState() => _SistemaLogsScreenState();
}

class _SistemaLogsScreenState extends State<SistemaLogsScreen> {
  late final SistemaLogService _service = widget.service ?? SistemaLogService();

  bool _loading = false;
  List<SistemaLogModel> _logs = [];
  SistemaLogMetricasModel? _metricas;

  String _filtroNivel = 'TODOS';
  String _filtroOrigem = 'TODOS';
  String _filtroPlataforma = 'TODAS';
  final _buscaController = TextEditingController();
  final _empresaController = TextEditingController();
  final _parceiroController = TextEditingController();
  final _usuarioController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  @override
  void dispose() {
    _buscaController.dispose();
    _empresaController.dispose();
    _parceiroController.dispose();
    _usuarioController.dispose();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    setState(() => _loading = true);
    try {
      final metricas = await _service.obterMetricas();
      final empId = int.tryParse(_empresaController.text.trim());
      final parcId = int.tryParse(_parceiroController.text.trim());
      final usuario = _usuarioController.text.trim();

      final logs = await _service.listarLogs(
        nivel: _filtroNivel,
        origem: _filtroOrigem,
        plataforma: _filtroPlataforma,
        busca: _buscaController.text,
        empresaId: empId,
        parceiroId: parcId,
        usuario: usuario.isNotEmpty ? usuario : null,
      );
      if (mounted) {
        setState(() {
          _metricas = metricas;
          _logs = logs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao carregar logs: $e')),
        );
      }
    }
  }

  Future<void> _copiarErros() async {
    if (_logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum log para copiar.')),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('=== RELATÓRIO DE LOGS / ERROS DO SISTEMA ===');
    buffer.writeln('Total de registros: ${_logs.length}');
    buffer.writeln('Gerado em: ${DateTime.now().toLocal()}');
    buffer.writeln('--------------------------------------------------');

    for (final l in _logs) {
      buffer.writeln('[${l.timestamp ?? 'SEM DATA'}] [${l.nivel}] [${l.origem}]');
      if (l.empresaId != null) buffer.write('Empresa: ${l.empresaId} ');
      if (l.parceiroId != null) buffer.write('Parceiro: ${l.parceiroId} ');
      if (l.usuario != null && l.usuario!.isNotEmpty) buffer.write('Usuário: ${l.usuario} ');
      if (l.versaoApp != null && l.versaoApp!.isNotEmpty) buffer.write('Plataforma: ${l.versaoApp} ');
      if (l.classeOuRota != null && l.classeOuRota!.isNotEmpty) buffer.write('Rota/Classe: ${l.classeOuRota}');
      buffer.writeln();
      buffer.writeln('Mensagem: ${l.mensagem}');
      if (l.detalhes != null && l.detalhes!.isNotEmpty) {
        buffer.writeln('Detalhes/Stacktrace:');
        buffer.writeln(l.detalhes);
      }
      buffer.writeln('--------------------------------------------------');
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_logs.length} logs copiados para a área de transferência!'),
          backgroundColor: Colors.green.shade800,
        ),
      );
    }
  }

  Future<void> _confirmarExpurgo() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Expurgar Logs Antigos'),
        content: const Text(
          'Deseja remover logs anteriores a 7 dias? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Expurgar'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      setState(() => _loading = true);
      final deletados = await _service.expurgarLogs(dias: 7);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$deletados logs anteriores a 7 dias foram expurgados.')),
        );
        _carregarDados();
      }
    }
  }

  void _abrirDetalhes(SistemaLogModel log) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildNivelBadge(log.nivel),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                log.mensagem,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildInfoRow('Origem', log.origem),
              if (log.classeOuRota != null) _buildInfoRow('Rota / Classe', log.classeOuRota!),
              if (log.timestamp != null) _buildInfoRow('Data / Hora', log.timestamp.toString()),
              if (log.usuario != null) _buildInfoRow('Usuário', log.usuario!),
              if (log.empresaId != null) _buildInfoRow('Empresa ID', log.empresaId.toString()),
              if (log.parceiroId != null) _buildInfoRow('Parceiro ID', log.parceiroId.toString()),
              if (log.versaoApp != null) _buildInfoRow('Versão App / Plataforma', log.versaoApp!),
              const SizedBox(height: AppSpacing.md),
              if (log.detalhes != null && log.detalhes!.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Stacktrace / Detalhes:',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: log.detalhes!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Stacktrace copiado para a área de transferência!')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copiar'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    log.detalhes!,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.greenAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(valor, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildNivelBadge(String nivel) {
    Color cor;
    switch (nivel) {
      case 'ERROR':
        cor = Colors.red;
        break;
      case 'WARN':
        cor = Colors.orange;
        break;
      default:
        cor = Colors.blue;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: cor.withValues(alpha: 0.5)),
      ),
      child: Text(
        nivel,
        style: TextStyle(color: cor, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }

  Widget _buildCardMetrica(String titulo, String valor, IconData icone, Color cor) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 220),
      child: Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(icone, size: 18, color: cor),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                valor,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: cor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs & Monitoramento'),
        actions: [
          FilledButton.tonalIcon(
            onPressed: _copiarErros,
            icon: const Icon(Icons.copy_all, size: 18),
            label: const Text('Copiar Erros'),
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            tooltip: 'Expurgar logs > 7 dias',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _confirmarExpurgo,
          ),
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _carregarDados,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_metricas != null)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  _buildCardMetrica(
                    'Erros (24h)',
                    '${_metricas!.totalErros24h}',
                    Icons.error_outline,
                    Colors.red,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _buildCardMetrica(
                    'Warnings (24h)',
                    '${_metricas!.totalWarnings24h}',
                    Icons.warning_amber_outlined,
                    Colors.orange,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _buildCardMetrica(
                    'Erros Backend',
                    '${_metricas!.totalErrosBackend24h}',
                    Icons.dns_outlined,
                    Colors.purple,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _buildCardMetrica(
                    'Erros App Flutter',
                    '${_metricas!.totalErrosApp24h}',
                    Icons.phone_android_outlined,
                    Colors.blue,
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
            child: Column(
              children: [
                // Linha 1: Busca textual + Nível + Origem + Plataforma
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _buscaController,
                        decoration: InputDecoration(
                          hintText: 'Buscar por mensagem, rota ou usuário...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          suffixIcon: _buscaController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _buscaController.clear();
                                    _carregarDados();
                                  },
                                )
                              : null,
                        ),
                        onSubmitted: (_) => _carregarDados(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    DropdownButton<String>(
                      value: _filtroNivel,
                      items: const [
                        DropdownMenuItem(value: 'TODOS', child: Text('Nível: Todos')),
                        DropdownMenuItem(value: 'ERROR', child: Text('ERROR')),
                        DropdownMenuItem(value: 'WARN', child: Text('WARN')),
                        DropdownMenuItem(value: 'INFO', child: Text('INFO')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _filtroNivel = v);
                          _carregarDados();
                        }
                      },
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    DropdownButton<String>(
                      value: _filtroOrigem,
                      items: const [
                        DropdownMenuItem(value: 'TODOS', child: Text('Origem: Todas')),
                        DropdownMenuItem(value: 'BACKEND', child: Text('Backend Java')),
                        DropdownMenuItem(value: 'APP_FLUTTER', child: Text('App Flutter')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _filtroOrigem = v);
                          _carregarDados();
                        }
                      },
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    DropdownButton<String>(
                      value: _filtroPlataforma,
                      items: const [
                        DropdownMenuItem(value: 'TODAS', child: Text('Plataforma: Todas')),
                        DropdownMenuItem(value: 'WEB', child: Text('Web')),
                        DropdownMenuItem(value: 'WINDOWS', child: Text('Windows')),
                        DropdownMenuItem(value: 'MOBILE', child: Text('Mobile')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _filtroPlataforma = v);
                          _carregarDados();
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                // Linha 2: Filtros de Empresa, Parceiro, Usuário + Botão Filtrar / Limpar
                Row(
                  children: [
                    SizedBox(
                      width: 140,
                      child: TextField(
                        controller: _empresaController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Empresa ID',
                          hintText: 'Ex: 1',
                          isDense: true,
                          prefixIcon: const Icon(Icons.business_outlined, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onSubmitted: (_) => _carregarDados(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    SizedBox(
                      width: 140,
                      child: TextField(
                        controller: _parceiroController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Parceiro ID',
                          hintText: 'Ex: 1756',
                          isDense: true,
                          prefixIcon: const Icon(Icons.people_outline, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onSubmitted: (_) => _carregarDados(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        controller: _usuarioController,
                        decoration: InputDecoration(
                          labelText: 'Usuário',
                          hintText: 'Filtrar por login / e-mail...',
                          isDense: true,
                          prefixIcon: const Icon(Icons.person_outline, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onSubmitted: (_) => _carregarDados(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: () {
                        _buscaController.clear();
                        _empresaController.clear();
                        _parceiroController.clear();
                        _usuarioController.clear();
                        setState(() {
                          _filtroNivel = 'TODOS';
                          _filtroOrigem = 'TODOS';
                          _filtroPlataforma = 'TODAS';
                        });
                        _carregarDados();
                      },
                      icon: const Icon(Icons.clear_all, size: 18),
                      label: const Text('Limpar'),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    FilledButton.icon(
                      onPressed: _carregarDados,
                      icon: const Icon(Icons.filter_alt, size: 18),
                      label: const Text('Filtrar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _logs.isEmpty && !_loading
                ? const Center(
                    child: Text(
                      'Nenhum log encontrado para os filtros selecionados.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    itemCount: _logs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, index) {
                      final log = _logs[index];
                      return ListTile(
                        leading: _buildNivelBadge(log.nivel),
                        title: Text(
                          log.mensagem,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${log.origem} • ${log.classeOuRota ?? 'N/A'} • ${log.timestamp ?? ''}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () => _abrirDetalhes(log),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
