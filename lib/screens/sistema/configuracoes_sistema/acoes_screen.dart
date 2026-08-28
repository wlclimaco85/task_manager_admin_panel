import 'package:flutter/material.dart';

import '../../../config/api_links.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/network_caller.dart';
import '../../../widgets/admin/admin_action_card.dart';

/// SIS-04 Config. Sistema — secao "Acoes simples" (Geracao de Telas, Dados
/// de Teste/Mock, Noticias, Banco de Dados). Port de
/// `configuracoes_sistema_screen.dart` (cliente), Fase 2 Task 05.2.
///
/// As demais secoes de Config. Sistema (Controle de Jobs, Importacao de
/// Contas, Importacao de Cadastros) sao planos separados (P06/P07/P08b) e
/// entram no container final em P13 — esta tela cobre so as 4 secoes
/// "simples" do escopo desta task.
///
/// Nota de seguranca (Task 05.1 — verificacao no backend, nao bloqueante):
/// `POST /api/admin/reset-database` tem `@tenantSecurity.isMaster()`
/// confirmado. `POST /api/admin/fix-db` e `DELETE /api/admin/seed` (usado
/// por "Apagar Dados Mock" abaixo) NAO tem `@PreAuthorize` equivalente no
/// backend hoje (`AdminFixController`/`MockDataController`,
/// `AppAcademia/src/main/java/br/com/appAcademia/controller/`) —
/// TODO-SEGURANCA: pedir ao dono do backend para adicionar
/// `@PreAuthorize("@tenantSecurity.isMaster()")` nesses dois endpoints. A
/// confirmacao explicita no cliente abaixo (dialogs "digite RESET"/"digite
/// APAGAR"/confirmacao simples) e mantida mesmo assim, como defesa em
/// profundidade — nao substitui a correcao no backend.
class ConfiguracoesSistemaAcoesScreen extends StatefulWidget {
  const ConfiguracoesSistemaAcoesScreen({super.key, this.networkCaller});

  final NetworkCaller? networkCaller;

  @override
  State<ConfiguracoesSistemaAcoesScreen> createState() =>
      ConfiguracoesSistemaAcoesScreenState();
}

class ConfiguracoesSistemaAcoesScreenState
    extends State<ConfiguracoesSistemaAcoesScreen> {
  late final NetworkCaller _caller = widget.networkCaller ?? NetworkCaller();
  bool get _ownsCaller => widget.networkCaller == null;

  bool _forceUpdate = false;
  bool _fullReset = false;

  final _quantidadeController = TextEditingController(text: '20');
  final _mesesController = TextEditingController(text: '6');
  final _seedEmpresaIdController = TextEditingController();
  final _deleteEmpresaIdController = TextEditingController();

  @override
  void dispose() {
    if (_ownsCaller) _caller.close();
    _quantidadeController.dispose();
    _mesesController.dispose();
    _seedEmpresaIdController.dispose();
    _deleteEmpresaIdController.dispose();
    super.dispose();
  }

  // ── Chamadas de rede (converte NetworkResponse em Map ou lanca excecao) ──

  Future<Map<String, dynamic>> _get(String url) async {
    final resp = await _caller.getRequest(url);
    if (!resp.isSuccess) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
    return resp.body ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _post(String url,
      [Map<String, dynamic> body = const {}]) async {
    final resp = await _caller.postRequest(url, body);
    if (!resp.isSuccess) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
    return resp.body ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _delete(String url) async {
    final resp = await _caller.deleteRequest(url);
    if (!resp.isSuccess) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
    return resp.body ?? <String, dynamic>{};
  }

  // ── Dialogs de confirmacao ──

  /// Confirmacao simples (yes/no), usada por acoes sensiveis porem nao
  /// destrutivas em massa (ex.: `fix-db`).
  Future<bool> _confirmSimple({
    required String title,
    required String message,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            key: const Key('confirm_simple_button'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// Confirmacao "digite X para confirmar" — reusa/adapta o padrao do
  /// arquivo original (dialog "digite RESET" para `reset-database`),
  /// aplicado tambem a "Apagar Dados Mock" (digite "APAGAR"). Diferente do
  /// original: aqui o botao de confirmar so habilita quando o texto digitado
  /// bate exatamente com [requiredText] (achado do plan-phase — o original
  /// exibia a instrucao mas nao chegava a bloquear o botao).
  Future<bool> _confirmTyped({
    required String title,
    required String message,
    required String requiredText,
  }) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final matches = controller.text.trim() == requiredText;
          return AlertDialog(
            title: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(title)),
            ]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                const SizedBox(height: AppSpacing.md),
                Text('Digite "$requiredText" no campo abaixo para confirmar:'),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  key: const Key('confirm_typed_field'),
                  controller: controller,
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                key: const Key('confirm_typed_button'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red, foregroundColor: Colors.white),
                onPressed: matches ? () => Navigator.of(ctx).pop(true) : null,
                child: const Text('Confirmar'),
              ),
            ],
          );
        },
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Geração de Telas', Icons.table_chart_outlined),
          _gerarTelasCard(),
          _actionCard(
            key: const Key('acao_regenerar_telas'),
            title: 'Regenerar Telas (Admin)',
            subtitle:
                'Limpa o controle de versao e regenera todas as telas com dropdowns FK/Enum. POST /api/admin/regenerar-telas',
            icon: Icons.auto_fix_high,
            color: Colors.blue.shade700,
            buttonKey: const Key('acao_regenerar_telas_button'),
            onExecute: () => _post(ApiLinks.regenerarTelas),
          ),
          const SizedBox(height: AppSpacing.lg),
          _sectionTitle('Dados de Teste (Mock)', Icons.data_array),
          _gerarSeedCard(),
          _apagarSeedCard(),
          const SizedBox(height: AppSpacing.lg),
          _sectionTitle('Notícias', Icons.newspaper),
          _actionCard(
            key: const Key('acao_noticias_limpar_baixar'),
            title: 'Limpar e Baixar Notícias',
            subtitle:
                'Apaga todas as noticias e baixa novamente de todas as fontes. POST /api/admin/jobs/noticias-limpar-e-baixar',
            icon: Icons.refresh,
            color: Colors.blue.shade700,
            buttonKey: const Key('acao_noticias_limpar_baixar_button'),
            onExecute: () => _post(ApiLinks.noticiasLimparEBaixar),
          ),
          _actionCard(
            key: const Key('acao_noticias_apagar'),
            title: 'Apagar Todas as Notícias',
            subtitle:
                'Remove todas as noticias e imagens do banco (sem baixar novamente). DELETE /api/admin/jobs/noticias-apagar',
            icon: Icons.delete_forever,
            color: Colors.red.shade700,
            buttonKey: const Key('acao_noticias_apagar_button'),
            onExecute: () => _delete(ApiLinks.noticiasApagar),
          ),
          const SizedBox(height: AppSpacing.lg),
          _sectionTitle('Banco de Dados', Icons.storage_outlined),
          _actionCard(
            key: const Key('acao_db_status'),
            title: 'Status do Banco',
            subtitle:
                'Verifica estado das colunas e sequencias. GET /api/admin/db-status',
            icon: Icons.health_and_safety_outlined,
            color: Colors.green.shade700,
            buttonKey: const Key('acao_db_status_button'),
            onExecute: () => _get(ApiLinks.dbStatus),
          ),
          _actionCard(
            key: const Key('acao_fix_db'),
            title: 'Corrigir Banco (Fix DB)',
            subtitle:
                'Aplica correcoes de colunas, FKs e sequencias. POST /api/admin/fix-db',
            icon: Icons.build_outlined,
            color: Colors.purple.shade700,
            buttonKey: const Key('acao_fix_db_button'),
            onExecute: () async {
              final confirmed = await _confirmSimple(
                title: 'Corrigir Banco de Dados',
                message:
                    'Esta acao aplica correcoes estruturais (colunas, FKs, sequencias) diretamente no banco. Deseja continuar?',
              );
              if (!confirmed) return null;
              return _post(ApiLinks.fixDb);
            },
          ),
          _actionCard(
            key: const Key('acao_reset_database'),
            title: 'Resetar Banco de Dados (Zerar Tudo)',
            subtitle:
                'TRUNCA TODAS as tabelas da aplicacao. Todos os dados serao PERMANENTEMENTE EXCLUIDOS. POST /api/admin/reset-database',
            icon: Icons.delete_sweep,
            color: Colors.red.shade900,
            buttonKey: const Key('acao_reset_database_button'),
            onExecute: () async {
              final confirmed = await _confirmTyped(
                title: 'Resetar Banco de Dados',
                message:
                    'ATENCAO: Esta operacao e IRREVERSIVEL! Todos os dados (empresas, parceiros, logins, contas, NF-e, chamados etc.) serao PERMANENTEMENTE EXCLUIDOS. As tabelas de controle (Flyway, Telas) serao preservadas.',
                requiredText: 'RESET',
              );
              if (!confirmed) return null;
              return _post(ApiLinks.resetDatabase);
            },
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    final colors = Theme.of(context).appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, color: colors.primary, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Text(
            title,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: colors.primary),
          ),
        ],
      ),
    );
  }

  Widget _actionCard({
    required Key key,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Key buttonKey,
    required Future<Map<String, dynamic>?> Function() onExecute,
  }) {
    return AdminActionCard(
      key: key,
      title: title,
      subtitle: subtitle,
      icon: icon,
      color: color,
      buttonKey: buttonKey,
      onExecute: onExecute,
    );
  }

  Widget _gerarTelasCard() {
    return StatefulBuilder(
      builder: (context, setLocalState) {
        return AdminActionCard(
          key: const Key('acao_gerar_telas'),
          title: 'Gerar Telas',
          subtitle:
              'Gera/atualiza as telas dinamicas a partir dos metadados. POST /api/telas/generate',
          icon: Icons.refresh,
          color: Theme.of(context).appColors.primary,
          buttonKey: const Key('acao_gerar_telas_button'),
          content: Row(
            children: [
              Checkbox(
                key: const Key('acao_gerar_telas_force_update'),
                value: _forceUpdate,
                onChanged: (v) =>
                    setLocalState(() => _forceUpdate = v ?? false),
              ),
              const Text('forceUpdate'),
              const SizedBox(width: AppSpacing.md),
              Checkbox(
                key: const Key('acao_gerar_telas_full_reset'),
                value: _fullReset,
                onChanged: (v) => setLocalState(() => _fullReset = v ?? false),
              ),
              const Text('fullReset'),
            ],
          ),
          onExecute: () => _post(
              ApiLinks.gerarTelas(forceUpdate: _forceUpdate, fullReset: _fullReset)),
        );
      },
    );
  }

  Widget _gerarSeedCard() {
    return AdminActionCard(
      key: const Key('acao_seed_gerar'),
      title: 'Gerar Dados Mock',
      subtitle:
          'Historico integrado: Comercial, Financeiro, Produtos, DP, Chat, OS, NFC-e/NFS-e. POST /api/admin/seed',
      icon: Icons.science_outlined,
      color: Colors.teal,
      buttonLabel: 'Gerar',
      buttonKey: const Key('acao_seed_gerar_button'),
      content: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('acao_seed_empresa_id_field'),
              controller: _seedEmpresaIdController,
              decoration: const InputDecoration(
                  labelText: 'Empresa ID (vazio = criar nova)'),
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              key: const Key('acao_seed_quantidade_field'),
              controller: _quantidadeController,
              decoration: const InputDecoration(labelText: 'Quantidade base'),
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              key: const Key('acao_seed_meses_field'),
              controller: _mesesController,
              decoration: const InputDecoration(labelText: 'Meses de historico'),
              keyboardType: TextInputType.number,
            ),
          ),
        ],
      ),
      onExecute: () {
        final empresaId = _seedEmpresaIdController.text.trim();
        final quantidade = int.tryParse(_quantidadeController.text.trim()) ?? 20;
        final meses = int.tryParse(_mesesController.text.trim()) ?? 6;
        final uri = Uri.parse(ApiLinks.seedMock).replace(queryParameters: {
          'quantidade': '$quantidade',
          'meses': '$meses',
          if (empresaId.isNotEmpty) 'empresaId': empresaId,
        });
        return _post(uri.toString());
      },
    );
  }

  Widget _apagarSeedCard() {
    return AdminActionCard(
      key: const Key('acao_seed_apagar'),
      title: 'Apagar Dados Mock (Empresa)',
      subtitle:
          'Remove TODOS os dados de uma empresa (parceiros, logins, NF-e, chamados, contas etc). DELETE /api/admin/seed',
      icon: Icons.delete_forever,
      color: Colors.red.shade700,
      buttonLabel: 'Apagar',
      buttonKey: const Key('acao_seed_apagar_button'),
      content: TextField(
        key: const Key('acao_seed_apagar_empresa_id_field'),
        controller: _deleteEmpresaIdController,
        decoration: const InputDecoration(labelText: 'ID da Empresa para apagar'),
        keyboardType: TextInputType.number,
      ),
      onExecute: () async {
        final empresaId = _deleteEmpresaIdController.text.trim();
        if (empresaId.isEmpty) {
          throw Exception('Informe o ID da empresa antes de apagar.');
        }
        final confirmed = await _confirmTyped(
          title: 'Apagar Dados Mock',
          message:
              'ATENCAO: Esta operacao remove PERMANENTEMENTE todos os dados da empresa $empresaId (parceiros, logins, contas, NF-e, chamados etc).',
          requiredText: 'APAGAR',
        );
        if (!confirmed) return null;
        return _delete(ApiLinks.deleteSeedMock(empresaId));
      },
    );
  }
}
