import 'package:flutter/material.dart';

import '../../config/api_links.dart';
import '../../services/network_caller.dart';
import '../../utils/app_logger.dart';
import '../../utils/grid_colors.dart';

/// App do Dono > Sistema > Sessoes (bug de producao 2026-09-11): sessoes
/// zumbis (JWT valido por 10h sem revogacao server-side) causavam rajadas
/// de requisicoes acumuladas toda manha e erro 429 (rate limit). Esta tela
/// permite matar a sessao de um usuario manualmente e mostra as 2 regras
/// automaticas ja ativas no backend (meia-noite mata todas, hora em hora
/// mata quem esta ocioso ha mais de 1h).
class SessoesScreen extends StatefulWidget {
  const SessoesScreen({super.key, this.networkCaller});

  final NetworkCaller? networkCaller;

  @override
  State<SessoesScreen> createState() => _SessoesScreenState();
}

class _SessoesScreenState extends State<SessoesScreen> {
  late final NetworkCaller _caller = widget.networkCaller ?? NetworkCaller();

  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _sessoes = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final res = await _caller.getRequest(ApiLinks.sessoesAtivas);
      if (!mounted) return;
      final lista = res.body?['data'];
      if (res.isSuccess && lista is List) {
        setState(() {
          _sessoes = List<Map<String, dynamic>>.from(lista);
          _carregando = false;
        });
      } else {
        setState(() {
          _erro = 'Não foi possível carregar as sessões (status ${res.statusCode}).';
          _carregando = false;
        });
        AppLogger.i.warn('SessoesScreen: falha ao carregar sessões (status ${res.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao carregar sessões: $e';
        _carregando = false;
      });
      AppLogger.i.error('SessoesScreen: erro ao carregar sessões: $e');
    }
  }

  Future<void> _matarSessao(Map<String, dynamic> sessao) async {
    final loginId = sessao['loginId'];
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Matar sessão'),
        content: Text(
            'Encerrar a sessão de "${sessao['nome'] ?? sessao['email'] ?? loginId}"? '
            'O usuário precisará fazer login novamente.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Matar sessão')),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      final res = await _caller.postRequest(ApiLinks.matarSessao(loginId as int), {});
      if (!mounted) return;
      if (res.isSuccess) {
        _mostrarSnack('Sessão encerrada.', erro: false);
        _carregar();
      } else {
        _mostrarSnack('Falha ao encerrar sessão (status ${res.statusCode}).', erro: true);
        AppLogger.i.warn('SessoesScreen: falha ao matar sessão $loginId (status ${res.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      _mostrarSnack('Erro ao encerrar sessão: $e', erro: true);
      AppLogger.i.error('SessoesScreen: erro ao matar sessão $loginId: $e');
    }
  }

  Future<void> _matarTodas() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Matar TODAS as sessões'),
        content: const Text(
            'Isso vai desconectar TODOS os usuários do sistema agora, forçando '
            'novo login para todos. Confirma?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: GridColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Matar todas'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      final res = await _caller.postRequest(ApiLinks.matarTodasAsSessoes, {});
      if (!mounted) return;
      if (res.isSuccess) {
        final total = (res.body?['totalInvalidadas'] ?? '?').toString();
        _mostrarSnack('$total sessões encerradas.', erro: false);
        _carregar();
      } else {
        _mostrarSnack('Falha ao encerrar sessões (status ${res.statusCode}).', erro: true);
        AppLogger.i.warn('SessoesScreen: falha ao matar todas (status ${res.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      _mostrarSnack('Erro ao encerrar sessões: $e', erro: true);
      AppLogger.i.error('SessoesScreen: erro ao matar todas as sessões: $e');
    }
  }

  void _mostrarSnack(String msg, {required bool erro}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: erro ? GridColors.error : GridColors.success,
        behavior: SnackBarBehavior.floating,
        content: Text(msg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GridColors.pageBackground,
      appBar: AppBar(
        title: const Text('Sessões'),
        backgroundColor: GridColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _carregar,
          ),
          TextButton.icon(
            onPressed: _matarTodas,
            icon: const Icon(Icons.power_settings_new, color: Colors.white),
            label: const Text('Matar todas', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: GridColors.primarySoft,
            child: const Text(
              'Regras automáticas ativas: à meia-noite todas as sessões são encerradas; '
              'de hora em hora, sessões ociosas há mais de 1h (sem nenhuma requisição) são encerradas.',
              style: TextStyle(fontSize: 12.5, color: GridColors.textSecondary),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erro != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: GridColors.error, size: 40),
            const SizedBox(height: 8),
            Text(_erro!, style: const TextStyle(color: GridColors.error)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _carregar, child: const Text('Tentar novamente')),
          ],
        ),
      );
    }
    if (_sessoes.isEmpty) {
      return const Center(child: Text('Nenhuma sessão ativa no momento.'));
    }
    return ListView.separated(
      itemCount: _sessoes.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final s = _sessoes[index];
        final ociosa = s['ociosa'] == true;
        return ListTile(
          leading: Icon(
            Icons.circle,
            size: 12,
            color: ociosa ? GridColors.error : GridColors.success,
          ),
          title: Text('${s['nome'] ?? '(sem nome)'} — ${s['email'] ?? ''}'),
          subtitle: Text(
              '${s['empresaNome'] ?? 'Empresa não identificada'} · Último acesso: ${s['ultimoAcesso'] ?? '-'}'
              '${ociosa ? ' · OCIOSA' : ''}'),
          trailing: TextButton(
            onPressed: () => _matarSessao(s),
            child: const Text('Matar sessão'),
          ),
        );
      },
    );
  }
}
