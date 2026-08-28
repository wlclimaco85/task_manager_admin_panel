import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../config/api_links.dart';
import '../../core/theme/app_theme.dart';
import '../../models/role_permission_catalog.dart';
import '../../services/network_caller.dart';
import '../../utils/role_permissao_normalizacao.dart';
import '../../utils/tenant_context.dart';

/// SIS-06 Permissoes. Matriz de permissoes Role x Tela x Campo (checkboxes).
/// Portado de `task_manager_flutter/lib/web/screens/role_permissao_screen.dart`
/// (503 linhas) -- ver PLAN.md/RESEARCH.md da Fase 2, Item 6 / Task 10.2.
/// Nao e' um CRUD de registro unico (nao usa `GenericGridScreen`): carrega
/// TODAS as permissoes (`GET .../role-permissao/all`) e roles (`GET
/// .../role`), filtra por role selecionada em memoria, salva individual via
/// `PUT .../role-permissao/{roleId}/{telaNome}` e em lote (checkbox de
/// grupo) via `POST .../role-permissao/batch`.
class RolePermissaoScreen extends StatefulWidget {
  const RolePermissaoScreen({super.key, this.networkCaller, this.httpClient});

  /// Usado para os `GET`s e o `PUT` individual (contrato padrao do app,
  /// injeta tenant/auth automaticamente).
  final NetworkCaller? networkCaller;

  /// Usado SOMENTE para `POST .../role-permissao/batch`. Achado de
  /// deviation (Rule 1/3): `RolePermissaoController.batch` (backend) espera
  /// uma LISTA JSON na raiz do body (`@RequestBody List<Map<String,Object>>`),
  /// mas `NetworkCaller.postRequest` so aceita `Map<String,dynamic>` e
  /// sempre serializa um objeto JSON -- nao ha como enviar um array puro
  /// por ele sem alterar `network_caller.dart` (fora do escopo deste plano,
  /// que restringe os arquivos tocados). Por isso este unico endpoint usa
  /// `package:http` diretamente, com os mesmos headers de
  /// `TenantContext.jsonHeaders` (leitura, sem alterar o utilitario).
  final http.Client? httpClient;

  @override
  State<RolePermissaoScreen> createState() => RolePermissaoScreenState();
}

class RolePermissaoScreenState extends State<RolePermissaoScreen> {
  late final NetworkCaller _caller = widget.networkCaller ?? NetworkCaller();
  late final http.Client _httpClient = widget.httpClient ?? http.Client();

  bool get _ownsCaller => widget.networkCaller == null;
  bool get _ownsHttpClient => widget.httpClient == null;

  List<RolePermissao> _permissoes = [];
  List<Map<String, dynamic>> _roles = [];
  final TextEditingController _buscaCtrl = TextEditingController();
  int? _roleId;
  String _busca = '';
  bool _carregando = true;
  String? _erro;
  final Set<String> _gruposSalvando = <String>{};

  @override
  void initState() {
    super.initState();
    _buscaCtrl.addListener(() => setState(() => _busca = _buscaCtrl.text));
    _carregarDados();
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    if (_ownsCaller) _caller.close();
    if (_ownsHttpClient) _httpClient.close();
    super.dispose();
  }

  List<dynamic> _extrairLista(Map<String, dynamic>? body) {
    dynamic data = body?['data'] ?? body?['dados'] ?? [];
    // Mesmo formato aninhado tratado em `GenericGridScreen` (Fase 2 Task
    // 01.1): alguns endpoints retornam `data: {dados: [...]}`.
    if (data is Map) {
      data = data['dados'] ?? data['content'] ?? [];
    }
    return data is List ? data : <dynamic>[];
  }

  Future<void> _carregarDados() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    final resPermissoes = await _caller.getRequest(ApiLinks.allRolePermissoes);
    final resRoles = await _caller.getRequest(ApiLinks.allRoles);

    if (!mounted) return;

    if (!resPermissoes.isSuccess || !resRoles.isSuccess) {
      setState(() {
        _carregando = false;
        _erro = 'Nao foi possivel carregar permissoes/roles.';
      });
      return;
    }

    final permissoesRaw = _extrairLista(resPermissoes.body);
    final rolesRaw = _extrairLista(resRoles.body);

    setState(() {
      _permissoes = permissoesRaw
          .whereType<Map>()
          .map((j) => RolePermissao.fromJson(Map<String, dynamic>.from(j)))
          .toList();
      _roles = rolesRaw
          .whereType<Map>()
          .map((r) => {'id': r['id'], 'description': r['description']})
          .toList();
      if (_roles.isNotEmpty) _roleId = _roles.first['id'] as int?;
      _carregando = false;
    });
  }

  // Fix (card #460, sintoma 3): apos o PUT bem-sucedido, atualiza
  // _permissoes localmente (upsert do registro alterado) e chama setState,
  // em vez de deixar o estado antigo intocado.
  Future<void> _salvar(String telaNome, String campo, bool valor) async {
    if (_roleId == null) return;
    final roleId = _roleId!;

    // CR-05 (portado): Uri.encodeComponent() no telaNome evita caracteres
    // especiais malformarem a URL.
    final url = ApiLinks.updateRolePermissao(
      roleId.toString(),
      Uri.encodeComponent(telaNome),
    );

    final response = await _caller.putRequest(url, {campo: valor});

    if (!mounted) return;

    if (!response.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: ${response.statusCode}')),
      );
      return;
    }

    setState(() {
      final index = _permissoes.indexWhere(
        (p) =>
            p.roleId == roleId &&
            normalizeTelaNome(p.telaNome) == normalizeTelaNome(telaNome),
      );
      if (index >= 0) {
        final atual = _permissoes[index];
        _permissoes[index] = atual.copyWith(
          podeVer: campo == 'podeVer' ? valor : null,
          podeInserir: campo == 'podeInserir' ? valor : null,
          podeEditar: campo == 'podeEditar' ? valor : null,
          podeDeletar: campo == 'podeDeletar' ? valor : null,
          podeBaixar: campo == 'podeBaixar' ? valor : null,
        );
      } else {
        _permissoes.add(RolePermissao(
          id: 0,
          roleId: roleId,
          roleKey: '',
          roleDescription: '',
          telaNome: telaNome,
          podeVer: campo == 'podeVer' ? valor : false,
          podeInserir: campo == 'podeInserir' ? valor : false,
          podeEditar: campo == 'podeEditar' ? valor : false,
          podeDeletar: campo == 'podeDeletar' ? valor : false,
          podeBaixar: campo == 'podeBaixar' ? valor : false,
        ));
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Salvo'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _salvarGrupo(RolePermissionGroup grupo, bool marcar) async {
    if (_roleId == null || grupo.entries.isEmpty) return;
    final roleId = _roleId!;
    final grupoKey = grupo.id;
    if (_gruposSalvando.contains(grupoKey)) return;
    setState(() => _gruposSalvando.add(grupoKey));

    try {
      final response = await _httpClient.post(
        Uri.parse(ApiLinks.batchRolePermissao),
        headers: TenantContext.jsonHeaders,
        body: jsonEncode(
          buildRolePermissionGroupBatch(roleId: roleId, grupo: grupo, marcar: marcar),
        ),
      );

      if (!mounted) return;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar grupo: ${response.statusCode}')),
        );
        return;
      }

      setState(() => _atualizarGrupoLocal(roleId, grupo, marcar));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(marcar ? 'Permissoes liberadas' : 'Permissoes bloqueadas'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _gruposSalvando.remove(grupoKey));
      }
    }
  }

  void _atualizarGrupoLocal(int roleId, RolePermissionGroup grupo, bool marcar) {
    for (final tela in grupo.entries) {
      final index = _permissoes.indexWhere(
        (p) =>
            p.roleId == roleId &&
            normalizeTelaNome(p.telaNome) == normalizeTelaNome(tela.telaNome),
      );
      if (index >= 0) {
        _permissoes[index] = rolePermissionWithAllFields(_permissoes[index], valor: marcar);
      } else {
        _permissoes.add(RolePermissao(
          id: 0,
          roleId: roleId,
          roleKey: '',
          roleDescription: '',
          telaNome: tela.telaNome,
          podeVer: marcar,
          podeInserir: marcar,
          podeEditar: marcar,
          podeDeletar: marcar,
          podeBaixar: marcar,
        ));
      }
    }
  }

  RolePermissao _permissaoDe(RolePermissionMenuEntry tela) {
    final telaNomeNormalizado = normalizeTelaNome(tela.telaNome);
    return _permissoes.firstWhere(
      (p) => p.roleId == _roleId && normalizeTelaNome(p.telaNome) == telaNomeNormalizado,
      orElse: () => RolePermissao(
        id: 0,
        roleId: _roleId!,
        roleKey: '',
        roleDescription: '',
        telaNome: tela.telaNome,
        podeVer: false,
        podeInserir: false,
        podeEditar: false,
        podeDeletar: false,
        podeBaixar: false,
      ),
    );
  }

  List<String> get _telaNomesConhecidos =>
      _permissoes.map((p) => p.telaNome).where((t) => t.isNotEmpty).toSet().toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Permissoes')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(key: Key('permissoes_loading')))
          : _erro != null
              ? Center(child: Text(_erro!, key: const Key('permissoes_erro')))
              : _roles.isEmpty
                  ? const Center(child: Text('Nenhuma role', key: Key('permissoes_sem_roles')))
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: DropdownButton<int>(
                            key: const Key('permissoes_role_dropdown'),
                            value: _roleId,
                            isExpanded: true,
                            items: _roles
                                .map((r) => DropdownMenuItem<int>(
                                      value: r['id'] as int?,
                                      child: Text(r['description'] ?? ''),
                                    ))
                                .toList(),
                            onChanged: (v) => setState(() => _roleId = v),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                          child: TextField(
                            key: const Key('permissoes_busca_field'),
                            controller: _buscaCtrl,
                            decoration: InputDecoration(
                              labelText: 'Buscar tela',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _busca.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Limpar busca',
                                      icon: const Icon(Icons.clear),
                                      onPressed: _buscaCtrl.clear,
                                    ),
                            ),
                          ),
                        ),
                        Expanded(child: _buildTabela()),
                      ],
                    ),
    );
  }

  Widget _buildTabela() {
    if (_roleId == null) return const SizedBox();

    final grupos = RolePermissionCatalog.groups(_telaNomesConhecidos, query: _busca);
    final headerColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.1);
    final groupColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.06);

    final rows = <TableRow>[
      TableRow(
        decoration: BoxDecoration(color: headerColor),
        children: [
          _cell('Tela', bold: true),
          _cell('Ver', bold: true),
          _cell('Inserir', bold: true),
          _cell('Editar', bold: true),
          _cell('Deletar', bold: true),
          _cell('Baixar', bold: true),
        ],
      ),
    ];

    for (final grupo in grupos) {
      rows.add(TableRow(
        decoration: BoxDecoration(color: groupColor),
        children: [
          _groupCell(grupo),
          const SizedBox(),
          const SizedBox(),
          const SizedBox(),
          const SizedBox(),
          const SizedBox(),
        ],
      ));

      for (final tela in grupo.entries) {
        final p = _permissaoDe(tela);
        rows.add(TableRow(
          children: [
            _cell(tela.label),
            _check(p.podeVer, () => _salvar(tela.telaNome, 'podeVer', !p.podeVer)),
            _check(
                p.podeInserir, () => _salvar(tela.telaNome, 'podeInserir', !p.podeInserir)),
            _check(p.podeEditar, () => _salvar(tela.telaNome, 'podeEditar', !p.podeEditar)),
            _check(
                p.podeDeletar, () => _salvar(tela.telaNome, 'podeDeletar', !p.podeDeletar)),
            _check(p.podeBaixar, () => _salvar(tela.telaNome, 'podeBaixar', !p.podeBaixar)),
          ],
        ));
      }
    }

    if (grupos.isEmpty) {
      rows.add(TableRow(
        children: [
          _cell('Nenhuma tela encontrada', key: const Key('permissoes_tabela_vazia')),
          const SizedBox(),
          const SizedBox(),
          const SizedBox(),
          const SizedBox(),
          const SizedBox(),
        ],
      ));
    }

    return SingleChildScrollView(
      child: Table(
        key: const Key('permissoes_tabela'),
        columnWidths: const {
          0: FlexColumnWidth(2),
          1: FixedColumnWidth(60),
          2: FixedColumnWidth(60),
          3: FixedColumnWidth(60),
          4: FixedColumnWidth(60),
          5: FixedColumnWidth(60),
        },
        border: TableBorder.all(color: Theme.of(context).colorScheme.outline),
        children: rows,
      ),
    );
  }

  Widget _cell(String text, {bool bold = false, Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Text(
        text,
        style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal),
      ),
    );
  }

  Widget _groupCell(RolePermissionGroup grupo) {
    final value = rolePermissionGroupCheckboxValue(grupo: grupo, permissaoDe: _permissaoDe);
    final salvando = _gruposSalvando.contains(grupo.id);
    final tooltip = salvando
        ? 'Salvando permissoes de ${grupo.label}'
        : 'Marcar ou desmarcar todas as permissoes de ${grupo.label}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          Tooltip(
            message: tooltip,
            child: Checkbox(
              key: Key('permissoes_grupo_checkbox_${grupo.id}'),
              value: value,
              tristate: true,
              semanticLabel: tooltip,
              onChanged: salvando ? null : (_) => _salvarGrupo(grupo, value != true),
            ),
          ),
          Expanded(
            child: Text(
              grupo.label,
              style: const TextStyle(fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _check(bool valor, VoidCallback onTap) {
    return Center(
      child: Checkbox(value: valor, onChanged: (_) => onTap()),
    );
  }
}
