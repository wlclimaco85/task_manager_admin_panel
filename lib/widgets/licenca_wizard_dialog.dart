import 'package:flutter/material.dart';
import '../config/api_links.dart';
import '../services/network_caller.dart';
import '../utils/grid_colors.dart';
import 'generic_grid_windows_screen.dart';

/// Wizard modal progressivo com 3 etapas:
/// 1. Selecionar / verificar Role vinculada às telas dos módulos contratados
/// 2. Selecionar usuários da Empresa com checkbox individual e "Marcar Todos"
/// 3. Finalizar (atribuição da role aos usuários selecionados e confirmação)
class LicencaWizardDialog extends StatefulWidget {
  final int empresaId;
  final String empresaNome;
  final List<String> modulosNomes;
  final NetworkCaller? networkCaller;

  const LicencaWizardDialog({
    super.key,
    required this.empresaId,
    required this.empresaNome,
    required this.modulosNomes,
    this.networkCaller,
  });

  @override
  State<LicencaWizardDialog> createState() => _LicencaWizardDialogState();
}

class _LicencaWizardDialogState extends State<LicencaWizardDialog> {
  late final NetworkCaller _caller = widget.networkCaller ?? NetworkCaller();
  bool get _ownsCaller => widget.networkCaller == null;

  int _etapaAtual = 0; // 0: Role, 1: Usuários, 2: Finalizar
  bool _carregando = false;
  bool _salvando = false;
  String? _erro;

  // Etapa 1 - Roles
  List<Map<String, dynamic>> _rolesDisponiveis = [];
  int? _roleSelecionadaId;
  String? _roleSelecionadaNome;
  bool _roleCompativelEncontrada = false;

  // Etapa 2 - Usuários
  List<Map<String, dynamic>> _usuarios = [];
  final Set<int> _usuariosSelecionadosIds = <int>{};

  @override
  void initState() {
    super.initState();
    _carregarDadosIniciais();
  }

  @override
  void dispose() {
    if (_ownsCaller) _caller.close();
    super.dispose();
  }

  Future<void> _carregarDadosIniciais() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      // 1. Carregar Roles
      final resRoles = await _caller.getRequest(ApiLinks.allRoles);
      // 2. Carregar Usuários da Empresa
      final urlLogins = ApiLinks.loginsByEmpresa(widget.empresaId.toString());
      final resLogins = await _caller.getRequest(urlLogins);

      if (!mounted) return;

      if (!resRoles.isSuccess) {
        setState(() {
          _carregando = false;
          _erro = 'Não foi possível carregar as roles do sistema.';
        });
        return;
      }

      final rolesRaw = GenericGridWindowsScreen.extractRows(resRoles.body);
      final roles = rolesRaw.map((r) => Map<String, dynamic>.from(r)).toList();

      final loginsRaw = resLogins.isSuccess
          ? GenericGridWindowsScreen.extractRows(resLogins.body)
          : <dynamic>[];
      final usuarios = loginsRaw.map((u) => Map<String, dynamic>.from(u)).toList();

      // Procurar se já existe role correspondente aos módulos da licença
      int? roleEncontradaId;
      String? roleEncontradaNome;
      bool compativel = false;

      // Verificar se alguma role tem moduloNecessario ou nome compatível
      for (final r in roles) {
        final id = r['id'] is int ? r['id'] as int : int.tryParse(r['id']?.toString() ?? '');
        final desc = (r['description'] ?? r['key'] ?? r['name'] ?? '').toString();
        final modNec = (r['moduloNecessario'] ?? '').toString().toLowerCase();

        final ehCompativel = widget.modulosNomes.any((m) {
          final modLower = m.toLowerCase();
          return (modNec.isNotEmpty && modNec.contains(modLower)) ||
              desc.toLowerCase().contains(modLower);
        });

        if (ehCompativel && roleEncontradaId == null) {
          roleEncontradaId = id;
          roleEncontradaNome = desc;
          compativel = true;
          break;
        }
      }

      // Se não encontrou específica, seleciona a primeira se houver
      if (roleEncontradaId == null && roles.isNotEmpty) {
        final first = roles.first;
        roleEncontradaId = first['id'] is int ? first['id'] as int : int.tryParse(first['id']?.toString() ?? '');
        roleEncontradaNome = (first['description'] ?? first['name'] ?? '').toString();
      }

      setState(() {
        _carregando = false;
        _rolesDisponiveis = roles;
        _roleSelecionadaId = roleEncontradaId;
        _roleSelecionadaNome = roleEncontradaNome;
        _roleCompativelEncontrada = compativel;
        _usuarios = usuarios;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _carregando = false;
          _erro = 'Erro de comunicação ao carregar dados: $e';
        });
      }
    }
  }

  void _marcarTodosUsuarios(bool marcar) {
    setState(() {
      _usuariosSelecionadosIds.clear();
      if (marcar) {
        for (final u in _usuarios) {
          final id = u['id'] is int ? u['id'] as int : int.tryParse(u['id']?.toString() ?? '');
          if (id != null) _usuariosSelecionadosIds.add(id);
        }
      }
    });
  }

  Future<void> _finalizarConcessao() async {
    if (_roleSelecionadaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione uma role antes de finalizar.'),
          backgroundColor: GridColors.error,
        ),
      );
      return;
    }

    if (_usuariosSelecionadosIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione ao menos um usuário para receber o acesso.'),
          backgroundColor: GridColors.warning,
        ),
      );
      return;
    }

    setState(() {
      _salvando = true;
      _erro = null;
    });

    int atribuidosComSucesso = 0;
    final roleId = _roleSelecionadaId!;

    try {
      // Atribuir role para cada usuário selecionado
      for (final loginId in _usuariosSelecionadosIds) {
        final urlAddRole = '${ApiLinks.baseUrl}/api/login/$loginId/roles/$roleId';
        final res = await _caller.postRequest(urlAddRole, {});
        if (res.isSuccess) {
          atribuidosComSucesso++;
        }
      }

      if (!mounted) return;

      setState(() => _salvando = false);

      Navigator.of(context).pop(true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: GridColors.success,
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Licença concedida! Role atribuída a $atribuidosComSucesso usuário(s).',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _salvando = false;
          _erro = 'Erro ao finalizar atribuição: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: isDark ? const Color(0xFF1E2638) : Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header com Progresso visual (UX-PRO-MAX)
            _buildHeader(isDark),

            // Stepper de etapas
            _buildStepperIndicator(isDark),

            const Divider(height: 1),

            // Conteúdo dinâmico da etapa
            Expanded(
              child: _carregando
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Carregando informações da licença...'),
                        ],
                      ),
                    )
                  : _erro != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline,
                                    color: GridColors.error, size: 48),
                                const SizedBox(height: 16),
                                Text(
                                  _erro!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: GridColors.errorDark,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _carregarDadosIniciais,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Tentar Novamente'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(20),
                          child: _buildEtapaConteudo(isDark),
                        ),
            ),

            const Divider(height: 1),

            // Rodapé com botões de Navegação (Anterior / Próximo / Finalizar)
            _buildRodapeAcoes(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: GridColors.primary,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.admin_panel_settings,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Concessão de Licença & Acessos',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  widget.empresaNome,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('licenca_wizard_fechar_btn'),
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }

  Widget _buildStepperIndicator(bool isDark) {
    final etapas = ['1. Role de Acesso', '2. Usuários', '3. Finalizar'];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: isDark ? const Color(0xFF161C2A) : const Color(0xFFF8FAFC),
      child: Row(
        children: List.generate(etapas.length * 2 - 1, (index) {
          if (index.isOdd) {
            final anteriorConcluida = (index ~/ 2) < _etapaAtual;
            return Expanded(
              child: Container(
                height: 2,
                color: anteriorConcluida
                    ? GridColors.primary
                    : (isDark ? Colors.grey.shade800 : Colors.grey.shade300),
              ),
            );
          }
          final stepIndex = index ~/ 2;
          final ativo = stepIndex == _etapaAtual;
          final concluido = stepIndex < _etapaAtual;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: concluido
                      ? GridColors.success
                      : (ativo ? GridColors.primary : Colors.grey.shade400),
                ),
                child: Center(
                  child: concluido
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : Text(
                          '${stepIndex + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                etapas[stepIndex],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: ativo ? FontWeight.bold : FontWeight.w500,
                  color: ativo
                      ? GridColors.primary
                      : (concluido
                          ? GridColors.success
                          : (isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildEtapaConteudo(bool isDark) {
    switch (_etapaAtual) {
      case 0:
        return _buildEtapaRole(isDark);
      case 1:
        return _buildEtapaUsuarios(isDark);
      case 2:
      default:
        return _buildEtapaFinalizar(isDark);
    }
  }

  Widget _buildEtapaRole(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.security, color: GridColors.primary, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Perfil de Telas (Role)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (_roleCompativelEncontrada)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: GridColors.successLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: GridColors.success.withOpacity(0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, color: GridColors.successDark, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Perfil Detectado',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: GridColors.successDark,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Módulos contratados nesta licença: ${widget.modulosNomes.isEmpty ? "Nenhum" : widget.modulosNomes.join(", ")}.',
          style: const TextStyle(fontSize: 13, color: GridColors.textMuted),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161C2A) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Selecione a Role com acesso às telas dos módulos:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                key: const Key('licenca_wizard_role_dropdown'),
                value: _roleSelecionadaId,
                isExpanded: true,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E2638) : Colors.white,
                ),
                items: _rolesDisponiveis.map((r) {
                  final id = r['id'] is int ? r['id'] as int : int.tryParse(r['id']?.toString() ?? '');
                  final desc = (r['description'] ?? r['name'] ?? 'Role #${r['id']}').toString();
                  return DropdownMenuItem<int>(
                    value: id,
                    child: Text(desc, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (novoId) {
                  setState(() {
                    _roleSelecionadaId = novoId;
                    final roleMatch = _rolesDisponiveis.firstWhere(
                      (r) => (r['id'] is int ? r['id'] : int.tryParse(r['id'].toString())) == novoId,
                      orElse: () => {},
                    );
                    _roleSelecionadaNome = (roleMatch['description'] ?? roleMatch['name'] ?? '').toString();
                  });
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: GridColors.primarySoft.withOpacity(0.4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: GridColors.primary.withOpacity(0.2)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: GridColors.primary, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'A Role selecionada define exatamente quais telas e permissões os usuários selecionados terão acesso no sistema.',
                  style: TextStyle(fontSize: 12, color: GridColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEtapaUsuarios(bool isDark) {
    final todosMarcados = _usuarios.isNotEmpty && _usuariosSelecionadosIds.length == _usuarios.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.people_alt_outlined, color: GridColors.primary, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Usuários da Empresa',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            TextButton.icon(
              key: const Key('licenca_wizard_marcar_todos_btn'),
              icon: Icon(
                todosMarcados ? Icons.deselect : Icons.select_all,
                size: 16,
              ),
              label: Text(todosMarcados ? 'Desmarcar Todos' : 'Marcar Todos'),
              onPressed: () => _marcarTodosUsuarios(!todosMarcados),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Marque os colaboradores que devem receber o perfil "${_roleSelecionadaNome ?? 'selecionado'}":',
          style: const TextStyle(fontSize: 13, color: GridColors.textMuted),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _usuarios.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_off_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text(
                        'Nenhum usuário cadastrado para esta empresa.',
                        style: TextStyle(color: GridColors.textMuted),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  key: const Key('licenca_wizard_usuarios_lista'),
                  itemCount: _usuarios.length,
                  itemBuilder: (context, index) {
                    final u = _usuarios[index];
                    final id = u['id'] is int ? u['id'] as int : int.tryParse(u['id']?.toString() ?? '');
                    final nome = (u['nome'] ?? u['name'] ?? 'Usuário #$id').toString();
                    final email = (u['email'] ?? '').toString();
                    final marcado = id != null && _usuariosSelecionadosIds.contains(id);

                    return Card(
                      key: ValueKey('licenca_usuario_$id'),
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: marcado ? GridColors.primary : (isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                          width: marcado ? 1.5 : 1.0,
                        ),
                      ),
                      color: marcado
                          ? GridColors.primarySoft.withOpacity(0.3)
                          : (isDark ? const Color(0xFF161C2A) : Colors.white),
                      child: CheckboxListTile(
                        value: marcado,
                        activeColor: GridColors.primary,
                        title: Text(
                          nome,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: marcado ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: email.isNotEmpty
                            ? Text(email, style: const TextStyle(fontSize: 12, color: GridColors.textMuted))
                            : null,
                        onChanged: id == null
                            ? null
                            : (checked) {
                                setState(() {
                                  if (checked == true) {
                                    _usuariosSelecionadosIds.add(id);
                                  } else {
                                    _usuariosSelecionadosIds.remove(id);
                                  }
                                });
                              },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEtapaFinalizar(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.verified_outlined, color: GridColors.success, size: 22),
            SizedBox(width: 8),
            Text(
              'Resumo e Confirmação',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161C2A) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _resumoLinha('Empresa Beneficiária:', widget.empresaNome),
              const Divider(height: 20),
              _resumoLinha('Role / Perfil atribuído:', _roleSelecionadaNome ?? 'Nenhuma'),
              const Divider(height: 20),
              _resumoLinha(
                'Módulos inclusos:',
                widget.modulosNomes.isEmpty ? 'Nenhum' : widget.modulosNomes.join(', '),
              ),
              const Divider(height: 20),
              _resumoLinha(
                'Usuários contemplados:',
                '${_usuariosSelecionadosIds.length} selecionado(s)',
                destaque: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: GridColors.successLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: GridColors.success.withOpacity(0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: GridColors.successDark, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ao confirmar, a role será imediatamente vinculada a todos os usuários marcados.',
                  style: TextStyle(fontSize: 12, color: GridColors.successDark, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _resumoLinha(String rotulo, String valor, {bool destaque = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 170,
          child: Text(
            rotulo,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: GridColors.textMuted),
          ),
        ),
        Expanded(
          child: Text(
            valor,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: destaque ? GridColors.primary : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRodapeAcoes() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          if (_etapaAtual > 0)
            OutlinedButton.icon(
              key: const Key('licenca_wizard_anterior_btn'),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Anterior'),
              onPressed: _salvando
                  ? null
                  : () {
                      setState(() => _etapaAtual--);
                    },
            ),
          const Spacer(),
          if (_etapaAtual < 2)
            ElevatedButton.icon(
              key: const Key('licenca_wizard_proximo_btn'),
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('Próximo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: GridColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: () {
                if (_etapaAtual == 0 && _roleSelecionadaId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Selecione uma role antes de avançar.'),
                      backgroundColor: GridColors.error,
                    ),
                  );
                  return;
                }
                setState(() => _etapaAtual++);
              },
            )
          else
            ElevatedButton.icon(
              key: const Key('licenca_wizard_finalizar_btn'),
              icon: _salvando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline, size: 18),
              label: Text(_salvando ? 'Concedendo...' : 'Finalizar e Conceder'),
              style: ElevatedButton.styleFrom(
                backgroundColor: GridColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: _salvando ? null : _finalizarConcessao,
            ),
        ],
      ),
    );
  }
}
