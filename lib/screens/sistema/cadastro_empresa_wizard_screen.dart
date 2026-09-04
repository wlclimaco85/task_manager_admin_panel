import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/api_links.dart';
import '../../core/theme/app_theme.dart';
import '../../models/cadastro_empresa_models.dart';
import '../../services/cadastro_empresa_service.dart';
import '../../services/network_caller.dart';

/// SIS-02 Cadastro Empresa — wizard de 7 passos (`Empresa`, `Usuários`,
/// `Clientes`, `Contas`, `Chamados`, `Funcionários`, `Executar`). Port de
/// `task_manager_flutter/lib/web/screens/cadastro_empresa_wizard.dart`
/// (Fase 2, Task 04.1/04.2), coletando os mesmos dados pré-preenchidos do
/// arquivo original e delegando toda a orquestração de rede para
/// [CadastroEmpresaService] (Task 03.2) — esta tela não duplica lógica de
/// negócio, só coleta dados e plota o log incremental via `onLog`.
class CadastroEmpresaWizardScreen extends StatefulWidget {
  const CadastroEmpresaWizardScreen({super.key, this.networkCaller});

  final NetworkCaller? networkCaller;

  @override
  State<CadastroEmpresaWizardScreen> createState() =>
      CadastroEmpresaWizardScreenState();
}

class CadastroEmpresaWizardScreenState
    extends State<CadastroEmpresaWizardScreen> {
  late final NetworkCaller _caller = widget.networkCaller ?? NetworkCaller();
  bool get _ownsCaller => widget.networkCaller == null;
  late final CadastroEmpresaService _service =
      CadastroEmpresaService(networkCaller: _caller);

  static const _steps = [
    'Empresa',
    'Usuários',
    'Clientes',
    'Contas',
    'Chamados',
    'Funcionários',
    'Executar',
  ];

  int _step = 0;
  final _pageController = PageController();
  final _formKeys = List.generate(6, (_) => GlobalKey<FormState>());

  // ── dados coletados (mesmos defaults do arquivo original) ──
  final _empresaNome = TextEditingController();
  final _empresaRazaoSocial = TextEditingController();
  final _empresaEmail = TextEditingController();
  final _empresaTelefone = TextEditingController();
  final _empresaCnpj = TextEditingController();
  int? _empresaAplicativoId;

  final _usuarios = [
    _UsuarioForm(tipo: 'ADMIN', nome: 'Admin Principal', email: 'admin@empresa.com'),
    _UsuarioForm(tipo: 'FINANCEIRO', nome: 'Financeiro', email: 'financeiro@empresa.com'),
  ];

  final _clientes = List.generate(
    5,
    (i) => _ClienteForm(
      nome: 'Cliente ${i + 1}',
      email: 'cliente${i + 1}@empresa.com',
      cpf: '000.000.000-0$i',
    ),
  );

  final _contas = [
    ...List.generate(
      5,
      (i) => _ContaForm(descricao: 'Conta Pagar ${i + 1}', isPagar: true),
    ),
    ...List.generate(
      5,
      (i) => _ContaForm(descricao: 'Conta Receber ${i + 1}', isPagar: false),
    ),
  ];

  final _chamados = List.generate(
    3,
    (i) => _ChamadoForm(
      titulo: 'Chamado ${i + 1}',
      descricao: 'Descrição do chamado ${i + 1}',
    ),
  );

  final _funcionarios = List.generate(
    5,
    (i) => _FuncionarioForm(
      nome: 'Funcionário ${i + 1}',
      email: 'func${i + 1}@empresa.com',
    ),
  );

  // ── dropdowns ──
  List<Map<String, dynamic>> _aplicativos = [];
  List<Map<String, dynamic>> _roles = [];

  // ── execução ──
  bool _running = false;
  bool _done = false;
  bool _failed = false;
  final List<LogEntry> _logs = [];

  @override
  void initState() {
    super.initState();
    _loadDropdowns();
  }

  Future<void> _loadDropdowns() async {
    final aps = await _fetchList(ApiLinks.allAplicativos);
    final rls = await _fetchList(ApiLinks.allRoles);
    if (!mounted) return;
    setState(() {
      _aplicativos = aps;
      _roles = rls;
    });
  }

  /// Parser tolerante a `{data:[...]}`, `{data:{dados:[...]}}`,
  /// `{dados:[...]}` — mesma heurística de `GenericGridScreen._load()`
  /// (Task 01.1), reaplicada aqui pois esta tela é bespoke.
  Future<List<Map<String, dynamic>>> _fetchList(String url) async {
    final response = await _caller.getRequest(url);
    if (!response.isSuccess) return [];
    dynamic data = response.body?['data'] ?? response.body?['dados'] ?? [];
    if (data is Map) {
      data = data['dados'] ?? data['content'] ?? [];
    }
    if (data is! List) return [];
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  @override
  void dispose() {
    if (_ownsCaller) _caller.close();
    _pageController.dispose();
    _empresaNome.dispose();
    _empresaRazaoSocial.dispose();
    _empresaEmail.dispose();
    _empresaTelefone.dispose();
    _empresaCnpj.dispose();
    for (final u in _usuarios) {
      u.dispose();
    }
    for (final c in _clientes) {
      c.dispose();
    }
    for (final c in _contas) {
      c.dispose();
    }
    for (final ch in _chamados) {
      ch.dispose();
    }
    for (final f in _funcionarios) {
      f.dispose();
    }
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────
  // NAVEGAÇÃO
  // ─────────────────────────────────────────────────────────────────────

  void _next() {
    if (_step < _formKeys.length) {
      if (_formKeys[_step].currentState?.validate() == false) return;
    }
    if (_step < _steps.length - 1) {
      setState(() => _step++);
      _pageController.animateToPage(_step,
          duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
      _pageController.animateToPage(_step,
          duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
    }
  }

  void _jumpTo(int i) {
    if (i < _step) {
      setState(() => _step = i);
      _pageController.jumpToPage(i);
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // EXECUÇÃO
  // ─────────────────────────────────────────────────────────────────────

  Future<void> _execute() async {
    setState(() {
      _running = true;
      _done = false;
      _failed = false;
      _logs.clear();
    });

    final empresa = EmpresaData(
      nome: _empresaNome.text,
      razaoSocial: _empresaRazaoSocial.text,
      email: _empresaEmail.text,
      telefone: _empresaTelefone.text,
      cnpj: _empresaCnpj.text,
      aplicativoId: _empresaAplicativoId,
    );
    final usuarios = _usuarios.map((u) => u.toData()).toList();
    final clientes = _clientes.map((c) => c.toData()).toList();
    final contas = _contas.map((c) => c.toData()).toList();
    final chamados = _chamados.map((c) => c.toData()).toList();
    final funcionarios = _funcionarios.map((f) => f.toData()).toList();

    try {
      await _service.execute(
        empresa: empresa,
        usuarios: usuarios,
        clientes: clientes,
        contas: contas,
        chamados: chamados,
        funcionarios: funcionarios,
        onLog: (entry) {
          if (!mounted) return;
          setState(() => _logs.add(entry));
        },
      );
      if (!mounted) return;
      setState(() {
        _running = false;
        _done = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _failed = true;
      });
    }
  }

  void _reset() {
    setState(() {
      _running = false;
      _done = false;
      _failed = false;
      _logs.clear();
    });
  }

  // ─────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cadastro de Empresa')),
      body: Column(
        children: [
          _buildStepIndicator(context),
          const Divider(height: 1),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildEmpresaStep(context),
                _buildUsuariosStep(context),
                _buildClientesStep(context),
                _buildContasStep(context),
                _buildChamadosStep(context),
                _buildFuncionariosStep(context),
                _buildExecutarStep(context),
              ],
            ),
          ),
          const Divider(height: 1),
          _buildNavButtons(context),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(BuildContext context) {
    final colors = Theme.of(context).appColors;
    return Container(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm, horizontal: AppSpacing.md),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(_steps.length, (i) {
            final active = i == _step;
            final done = i < _step;
            return Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: GestureDetector(
                key: Key('wizard_step_$i'),
                onTap: () => _jumpTo(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: active || done
                        ? colors.primary
                        : colors.surfaceVariant,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${i + 1}. ${_steps[i]}',
                    style: TextStyle(
                      color: active || done ? colors.onPrimary : colors.onSurfaceMuted,
                      fontSize: 12,
                      fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildNavButtons(BuildContext context) {
    final isLast = _step == _steps.length - 1;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_step > 0)
            OutlinedButton.icon(
              key: const Key('wizard_back_button'),
              onPressed: _running ? null : _back,
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Voltar'),
            )
          else
            const SizedBox(),
          if (!isLast)
            ElevatedButton.icon(
              key: const Key('wizard_next_button'),
              onPressed: _next,
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('Próximo'),
            ),
        ],
      ),
    );
  }

  // ── Passo 1: Empresa ──

  Widget _buildEmpresaStep(BuildContext context) {
    return _stepScaffold(
      context,
      title: 'Dados da Empresa',
      icon: Icons.business,
      formKey: _formKeys[0],
      child: Column(
        children: [
          _textField('Nome *', _empresaNome, required: true),
          _textField('Razão Social', _empresaRazaoSocial),
          _textField('E-mail', _empresaEmail, keyboard: TextInputType.emailAddress),
          _textField('Telefone', _empresaTelefone, keyboard: TextInputType.phone),
          _textField('CNPJ', _empresaCnpj),
          const SizedBox(height: AppSpacing.sm),
          _dropdown(
            label: 'Aplicativo',
            items: _aplicativos,
            displayField: 'nome',
            valueField: 'id',
            value: _empresaAplicativoId,
            onChanged: (v) => setState(() => _empresaAplicativoId = v as int?),
          ),
        ],
      ),
    );
  }

  // ── Passo 2: Usuários ──

  Widget _buildUsuariosStep(BuildContext context) {
    return _stepScaffold(
      context,
      title: '2 Usuários (Admin + Financeiro)',
      icon: Icons.people,
      formKey: _formKeys[1],
      child: Column(
        children: _usuarios.asMap().entries.map((entry) {
          final i = entry.key;
          final u = entry.value;
          return _card(
            context,
            title: 'Usuário ${i + 1} — ${u.tipo}',
            child: Column(
              children: [
                _textField('Nome *', u.nome, required: true),
                _textField('E-mail *', u.email,
                    required: true, keyboard: TextInputType.emailAddress),
                _textField('Senha', u.senha),
                _textField('CPF/CNPJ', u.cpfCnpj),
                const SizedBox(height: AppSpacing.xs),
                _multiSelectRoles(key: 'roles_${i}',
                  selected: u.roleIds,
                  onChanged: (ids) => setState(() => u.roleIds = ids),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Passo 3: Clientes ──

  Widget _buildClientesStep(BuildContext context) {
    return _stepScaffold(
      context,
      title: '5 Clientes',
      icon: Icons.group,
      formKey: _formKeys[2],
      child: Column(
        children: _clientes.asMap().entries.map((entry) {
          final i = entry.key;
          final c = entry.value;
          return _card(
            context,
            title: 'Cliente ${i + 1}',
            child: Column(
              children: [
                _textField('Nome *', c.nome, required: true),
                _textField('E-mail', c.email, keyboard: TextInputType.emailAddress),
                _textField('CPF', c.cpf),
                _textField('Telefone', c.telefone),
                const SizedBox(height: AppSpacing.xs),
                _dropdown(
                  label: 'Role Admin',
                  items: _roles,
                  displayField: 'description',
                  valueField: 'id',
                  value: c.roleAdminId,
                  onChanged: (v) => setState(() => c.roleAdminId = v as int?),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Passo 4: Contas ──

  Widget _buildContasStep(BuildContext context) {
    final colors = Theme.of(context).appColors;
    return _stepScaffold(
      context,
      title: '5 Contas a Pagar + 5 a Receber',
      icon: Icons.account_balance_wallet,
      formKey: _formKeys[3],
      child: Column(
        children: _contas.asMap().entries.map((entry) {
          final i = entry.key;
          final c = entry.value;
          return _card(
            context,
            title: c.isPagar ? 'Pagar ${i + 1}' : 'Receber ${i - 4}',
            color: c.isPagar ? colors.error : colors.success,
            child: Row(
              children: [
                Expanded(child: _textField('Descrição', c.descricao)),
                const SizedBox(width: AppSpacing.md),
                SizedBox(
                  width: 120,
                  child: _textField('Valor', c.valor, keyboard: TextInputType.number),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Passo 5: Chamados ──

  Widget _buildChamadosStep(BuildContext context) {
    final colors = Theme.of(context).appColors;
    return _stepScaffold(
      context,
      title: 'Chamados + Chat',
      icon: Icons.support_agent,
      formKey: _formKeys[4],
      child: Column(
        children: [
          ..._chamados.asMap().entries.map((entry) {
            final i = entry.key;
            final ch = entry.value;
            return _card(
              context,
              title: 'Chamado ${i + 1}',
              child: Column(
                children: [
                  _textField('Título *', ch.titulo, required: true),
                  _textField('Descrição', ch.descricao, maxLines: 2),
                  const SizedBox(height: AppSpacing.xs),
                  _dropdown(
                    label: 'Prioridade',
                    items: const [
                      {'id': 'BAIXA', 'nome': 'Baixa'},
                      {'id': 'MEDIA', 'nome': 'Média'},
                      {'id': 'ALTA', 'nome': 'Alta'},
                      {'id': 'URGENTE', 'nome': 'Urgente'},
                    ],
                    displayField: 'nome',
                    valueField: 'id',
                    value: ch.prioridade,
                    onChanged: (v) =>
                        setState(() => ch.prioridade = v?.toString() ?? 'MEDIA'),
                  ),
                ],
              ),
            );
          }),
          _card(
            context,
            title: 'Chat',
            color: colors.info,
            child: Row(
              children: [
                Icon(Icons.chat, color: colors.onSurfaceMuted, size: 20),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(
                  child: Text(
                    'Um chat será iniciado com o primeiro cliente cadastrado.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Passo 6: Funcionários ──

  Widget _buildFuncionariosStep(BuildContext context) {
    return _stepScaffold(
      context,
      title: '5 Funcionários',
      icon: Icons.badge,
      formKey: _formKeys[5],
      child: Column(
        children: _funcionarios.asMap().entries.map((entry) {
          final i = entry.key;
          final f = entry.value;
          return _card(
            context,
            title: 'Funcionário ${i + 1}',
            child: Column(
              children: [
                _textField('Nome *', f.nome, required: true),
                _textField('E-mail', f.email, keyboard: TextInputType.emailAddress),
                _textField('CPF', f.cpf),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Passo 7: Executar ──

  Widget _buildExecutarStep(BuildContext context) {
    final colors = Theme.of(context).appColors;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _card(
            context,
            title: 'Resumo',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryRow(Icons.business, 'Empresa',
                    _empresaNome.text.isNotEmpty ? _empresaNome.text : '(não preenchido)'),
                _summaryRow(Icons.people, 'Usuários', '${_usuarios.length} (Admin + Financeiro)'),
                _summaryRow(Icons.group, 'Clientes', '${_clientes.length} parceiros com login'),
                const _SummaryStaticRow(icon: Icons.account_balance_wallet, label: 'Contas', value: '5 a pagar + 5 a receber'),
                const _SummaryStaticRow(icon: Icons.receipt, label: 'Nota Fiscal', value: '1 nota fiscal de entrada'),
                _summaryRow(Icons.support_agent, 'Chamados', '${_chamados.length} chamados + 1 chat'),
                _summaryRow(Icons.badge, 'Funcionários', '${_funcionarios.length} funcionários com login'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (!_running && !_done && !_failed)
            Center(
              child: ElevatedButton.icon(
                key: const Key('wizard_execute_button'),
                onPressed: _execute,
                icon: const Icon(Icons.rocket_launch),
                label: const Text('Executar Cadastro Completo'),
              ),
            ),
          if (_running)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  key: const Key('wizard_running_indicator'),
                  children: const [
                    CircularProgressIndicator(),
                    SizedBox(height: AppSpacing.sm),
                    Text('Executando...'),
                  ],
                ),
              ),
            ),
          if (_done)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Row(
                  key: const Key('wizard_done_indicator'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: colors.success, size: 28),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Concluído!',
                        style: TextStyle(
                            color: colors.success,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          if (_failed)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Row(
                  key: const Key('wizard_failed_indicator'),
                  children: [
                    Icon(Icons.error, color: colors.error, size: 28),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text('Falha na execução! Dados já criados foram revertidos.',
                          style: TextStyle(
                              color: colors.error,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          if ((_done || _failed) && !_running)
            Center(
              child: TextButton.icon(
                key: const Key('wizard_reset_button'),
                onPressed: _reset,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Executar Novamente'),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          if (_logs.isNotEmpty) ...[
            Row(
              children: [
                const Text('Log de Execução',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const Spacer(),
                if (_logs.any((l) => !l.sucesso))
                  TextButton.icon(
                    onPressed: () {
                      final errorText = _logs
                          .where((l) => !l.sucesso)
                          .map((l) => l.mensagem)
                          .join('\n');
                      Clipboard.setData(ClipboardData(text: errorText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Erros copiados para a área de transferência'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('Copiar Erros'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Container(
              key: const Key('wizard_log_list'),
              height: 280,
              decoration: BoxDecoration(
                color: colors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppSpacing.radiusDefault),
                border: Border.all(color: colors.outline),
              ),
              child: ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.sm),
                itemCount: _logs.length,
                itemBuilder: (_, i) {
                  final log = _logs[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text(
                      log.mensagem,
                      style: TextStyle(
                        color: log.sucesso ? colors.success : colors.error,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return _SummaryStaticRow(icon: icon, label: label, value: value);
  }

  // ─────────────────────────────────────────────────────────────────────
  // WIDGETS AUXILIARES
  // ─────────────────────────────────────────────────────────────────────

  Widget _stepScaffold(
    BuildContext context, {
    required String title,
    required IconData icon,
    required GlobalKey<FormState> formKey,
    required Widget child,
  }) {
    final colors = Theme.of(context).appColors;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colors.primary, size: 22),
                const SizedBox(width: AppSpacing.sm),
                Text(title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            child,
          ],
        ),
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required String title,
    required Widget child,
    Color? color,
  }) {
    final colors = Theme.of(context).appColors;
    final accent = color ?? colors.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppSpacing.radiusDefault),
                topRight: Radius.circular(AppSpacing.radiusDefault),
              ),
            ),
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          Padding(padding: const EdgeInsets.all(AppSpacing.md), child: child),
        ],
      ),
    );
  }

  Widget _textField(
    String label,
    TextEditingController controller, {
    bool required = false,
    TextInputType keyboard = TextInputType.text,
    int maxLines = 1,
    String? key,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: TextFormField(
        key: key != null ? Key(key) : null,
        controller: controller,
        keyboardType: keyboard,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? '$label é obrigatório' : null
            : null,
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required List<Map<String, dynamic>> items,
    required String displayField,
    required String valueField,
    required dynamic value,
    required void Function(dynamic) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: DropdownButtonFormField<dynamic>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem(value: null, child: Text('— Selecione —')),
          ...items.map((item) => DropdownMenuItem(
                value: item[valueField],
                child: Text(item[displayField]?.toString() ?? ''),
              )),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _multiSelectRoles({
    required String key,
    required List<int> selected,
    required void Function(List<int>) onChanged,
  }) {
    return InkWell(
      key: Key(key),
      onTap: () async {
        final result = await showDialog<List<int>>(
          context: context,
          builder: (_) => _RolesDialog(roles: _roles, selected: selected),
        );
        if (result != null) onChanged(result);
      },
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Roles'),
        child: Text(
          selected.isEmpty ? 'Nenhuma role selecionada' : '${selected.length} role(s) selecionada(s)',
        ),
      ),
    );
  }
}

class _SummaryStaticRow extends StatelessWidget {
  const _SummaryStaticRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colors.onSurfaceMuted),
          const SizedBox(width: AppSpacing.sm),
          Text('$label: ', style: TextStyle(color: colors.onSurfaceMuted, fontSize: 13)),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _RolesDialog extends StatefulWidget {
  const _RolesDialog({required this.roles, required this.selected});

  final List<Map<String, dynamic>> roles;
  final List<int> selected;

  @override
  State<_RolesDialog> createState() => _RolesDialogState();
}

class _RolesDialogState extends State<_RolesDialog> {
  late final Set<int> _selected = Set.from(widget.selected);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Selecionar Roles'),
      content: SizedBox(
        width: 400,
        height: 400,
        child: ListView(
          children: widget.roles.map((item) {
            final id = item['id'] as int?;
            if (id == null) return const SizedBox();
            return CheckboxListTile(
              value: _selected.contains(id),
              title: Text(item['description']?.toString() ?? ''),
              onChanged: (v) => setState(() => v == true ? _selected.add(id) : _selected.remove(id)),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_selected.toList()),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// MODELOS DE FORMULÁRIO (mutáveis, só desta tela — convertidos para os
// modelos imutáveis de `cadastro_empresa_models.dart`/`cadastro_empresa_
// service.dart` no momento de `_execute()`).
// ─────────────────────────────────────────────────────────────────────────

class _UsuarioForm {
  _UsuarioForm({required this.tipo, String nome = '', String email = ''})
      : nome = TextEditingController(text: nome),
        email = TextEditingController(text: email),
        senha = TextEditingController(text: 'Senha@123'),
        cpfCnpj = TextEditingController();

  final String tipo;
  final TextEditingController nome;
  final TextEditingController email;
  final TextEditingController senha;
  final TextEditingController cpfCnpj;
  List<int> roleIds = [];

  UsuarioData toData() => UsuarioData(
        nome: nome.text,
        email: email.text,
        senha: senha.text.isNotEmpty ? senha.text : 'Senha@123',
        cpfCnpj: cpfCnpj.text,
        roleIds: roleIds,
        tipo: tipo,
      );

  void dispose() {
    nome.dispose();
    email.dispose();
    senha.dispose();
    cpfCnpj.dispose();
  }
}

class _ClienteForm {
  _ClienteForm({String nome = '', String email = '', String cpf = ''})
      : nome = TextEditingController(text: nome),
        email = TextEditingController(text: email),
        cpf = TextEditingController(text: cpf),
        telefone = TextEditingController();

  final TextEditingController nome;
  final TextEditingController email;
  final TextEditingController cpf;
  final TextEditingController telefone;
  int? roleAdminId;

  ClienteData toData() => ClienteData(
        nome: nome.text,
        email: email.text,
        cpf: cpf.text,
        telefone: telefone.text,
        roleAdminId: roleAdminId,
      );

  void dispose() {
    nome.dispose();
    email.dispose();
    cpf.dispose();
    telefone.dispose();
  }
}

class _ContaForm {
  _ContaForm({required String descricao, required this.isPagar})
      : descricao = TextEditingController(text: descricao),
        valor = TextEditingController(text: '100.0');

  final TextEditingController descricao;
  final TextEditingController valor;
  final bool isPagar;

  ContaData toData() => ContaData(
        descricao: descricao.text,
        valor: double.tryParse(valor.text.replaceAll(',', '.')) ?? 100.0,
      );

  void dispose() {
    descricao.dispose();
    valor.dispose();
  }
}

class _ChamadoForm {
  _ChamadoForm({String titulo = '', String descricao = ''})
      : titulo = TextEditingController(text: titulo),
        descricao = TextEditingController(text: descricao);

  final TextEditingController titulo;
  final TextEditingController descricao;
  String prioridade = 'MEDIA';

  ChamadoData toData() => ChamadoData(
        titulo: titulo.text,
        descricao: descricao.text,
        prioridade: prioridade,
      );

  void dispose() {
    titulo.dispose();
    descricao.dispose();
  }
}

class _FuncionarioForm {
  _FuncionarioForm({String nome = '', String email = ''})
      : nome = TextEditingController(text: nome),
        email = TextEditingController(text: email),
        cpf = TextEditingController();

  final TextEditingController nome;
  final TextEditingController email;
  final TextEditingController cpf;

  FuncionarioData toData() => FuncionarioData(
        nome: nome.text,
        email: email.text,
        cpf: cpf.text,
      );

  void dispose() {
    nome.dispose();
    email.dispose();
    cpf.dispose();
  }
}
