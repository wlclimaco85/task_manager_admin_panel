import 'package:flutter/material.dart';

import '../services/construtor_telas_service.dart';
import '../utils/app_logger.dart';

/// Abre a tela construida para o usuario ver como ela ficou (cada plataforma passa o seu construtor de grid).
typedef AbrirTelaConstruida = void Function(BuildContext context, TelaConstruida tela);

/// Construtor de Telas (plataforma low-code, F5): cria uma tela sobre uma tabela da empresa. A tela nasce com os
/// campos das colunas (rótulo, tipo e ordem derivados) e passa a funcionar na hora, com CRUD genérico, pelo
/// menu "Telas Personalizadas". Rótulos e ligações (FK) são ajustados depois no Dicionário de Dados.
/// Somente MASTER (o servidor também exige).
class ConstrutorTelasView extends StatefulWidget {
  final ConstrutorTelasService? servico;
  final AbrirTelaConstruida? abrir;

  const ConstrutorTelasView({super.key, this.servico, this.abrir});

  @override
  State<ConstrutorTelasView> createState() => _ConstrutorTelasViewState();
}

class _ConstrutorTelasViewState extends State<ConstrutorTelasView> {
  late final ConstrutorTelasService _svc = widget.servico ?? ConstrutorTelasService();

  List<TelaConstruida> _telas = const [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  void _aviso(String t, {bool erro = false}) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(t), backgroundColor: erro ? Colors.red.shade700 : null));
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final lista = await _svc.todas();
      if (mounted) setState(() => _telas = lista);
    } catch (e) {
      AppLogger.i.warn('ConstrutorTelasView: erro ao listar: $e');
      if (mounted) setState(() => _erro = '$e');
    }
    if (mounted) setState(() => _carregando = false);
  }

  Future<void> _nova() async {
    List<TabelaDisponivel> tabelas;
    try {
      tabelas = await _svc.tabelas();
    } catch (e) {
      AppLogger.i.warn('ConstrutorTelasView: erro ao listar tabelas: $e');
      _aviso('$e', erro: true);
      return;
    }
    if (!mounted) return;
    final r = await showDialog<List<String>>(
      context: context,
      builder: (_) => _NovaTelaDialog(tabelas: tabelas),
    );
    if (r == null) return;
    try {
      await _svc.criar(r[0], r[1]);
      _aviso('Tela criada. Ela já aparece em Telas Personalizadas.');
      await _carregar();
    } catch (e) {
      AppLogger.i.warn('ConstrutorTelasView: erro ao criar tela: $e');
      _aviso('$e', erro: true);
    }
  }

  Future<void> _alternar(TelaConstruida t, bool ativo) async {
    try {
      await _svc.atualizar(t.id, ativo: ativo);
      await _carregar();
    } catch (e) {
      AppLogger.i.warn('ConstrutorTelasView: erro ao ativar/desativar: $e');
      _aviso('$e', erro: true);
    }
  }

  Future<void> _excluir(TelaConstruida t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir tela'),
        content: Text('Excluir a tela "${t.titulo}"? Os dados da tabela ${t.tabelaNome} não são apagados.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _svc.excluir(t.id);
      await _carregar();
    } catch (e) {
      AppLogger.i.warn('ConstrutorTelasView: erro ao excluir: $e');
      _aviso('$e', erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Expanded(
              child: Text('Construtor de Telas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          IconButton(tooltip: 'Atualizar', onPressed: _carregar, icon: const Icon(Icons.refresh)),
          FilledButton.icon(onPressed: _nova, icon: const Icon(Icons.add), label: const Text('Nova tela')),
        ]),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Escolha uma tabela da empresa: a tela é criada com os campos das colunas e já funciona (listar, incluir, '
            'editar e excluir). Ajuste rótulos e ligações no Dicionário de Dados.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ),
      Expanded(
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
                ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_erro!)))
                : _telas.isEmpty
                    ? const Center(child: Text('Nenhuma tela criada ainda.'))
                    : ListView.separated(
                        itemCount: _telas.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final t = _telas[i];
                          return ListTile(
                            minVerticalPadding: 10,
                            leading: const Icon(Icons.table_chart_outlined),
                            title: Text(t.titulo),
                            subtitle: Text('Tabela ${t.tabelaNome}${t.ativo ? '' : ' · desativada'}'),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              if (widget.abrir != null && t.ativo)
                                IconButton(
                                    tooltip: 'Abrir',
                                    onPressed: () => widget.abrir!(context, t),
                                    icon: const Icon(Icons.open_in_new)),
                              Switch(value: t.ativo, onChanged: (v) => _alternar(t, v)),
                              IconButton(
                                  tooltip: 'Excluir',
                                  onPressed: () => _excluir(t),
                                  icon: const Icon(Icons.delete_outline)),
                            ]),
                          );
                        }),
      ),
    ]);
  }
}

class _NovaTelaDialog extends StatefulWidget {
  final List<TabelaDisponivel> tabelas;

  const _NovaTelaDialog({required this.tabelas});

  @override
  State<_NovaTelaDialog> createState() => _NovaTelaDialogState();
}

class _NovaTelaDialogState extends State<_NovaTelaDialog> {
  final _titulo = TextEditingController();
  final _busca = TextEditingController();
  String? _tabela;
  String? _erro;

  @override
  void dispose() {
    _titulo.dispose();
    _busca.dispose();
    super.dispose();
  }

  String _tituloSugerido(String tabela) {
    final s = tabela.replaceAll('_', ' ');
    return s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final filtro = _busca.text.trim().toLowerCase();
    final lista = widget.tabelas.where((t) => filtro.isEmpty || t.nome.contains(filtro)).toList();
    return AlertDialog(
      title: const Text('Nova tela'),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _busca,
            decoration: const InputDecoration(labelText: 'Buscar tabela', prefixIcon: Icon(Icons.search)),
            onChanged: (_) => setState(() {}),
          ),
          Expanded(
            child: lista.isEmpty
                ? const Center(child: Text('Nenhuma tabela disponível.'))
                : ListView(children: [
                    for (final t in lista)
                      ListTile(
                        dense: true,
                        selected: t.nome == _tabela,
                        title: Text(t.nome),
                        subtitle: Text('${t.colunas} coluna(s)'),
                        onTap: () => setState(() {
                          _tabela = t.nome;
                          _erro = null;
                          if (_titulo.text.trim().isEmpty) _titulo.text = _tituloSugerido(t.nome);
                        }),
                      ),
                  ]),
          ),
          TextField(
            controller: _titulo,
            maxLength: 150,
            decoration: const InputDecoration(labelText: 'Título da tela *'),
          ),
          if (_erro != null) Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (_tabela == null) {
              setState(() => _erro = 'Escolha a tabela.');
              return;
            }
            if (_titulo.text.trim().isEmpty) {
              setState(() => _erro = 'Informe o título da tela.');
              return;
            }
            Navigator.pop(context, [_tabela!, _titulo.text.trim()]);
          },
          child: const Text('Criar'),
        ),
      ],
    );
  }
}

/// Telas Personalizadas: lista as telas criadas no Construtor (ativas) e abre a escolhida.
class TelasPersonalizadasView extends StatefulWidget {
  final ConstrutorTelasService? servico;
  final AbrirTelaConstruida abrir;

  const TelasPersonalizadasView({super.key, this.servico, required this.abrir});

  @override
  State<TelasPersonalizadasView> createState() => _TelasPersonalizadasViewState();
}

class _TelasPersonalizadasViewState extends State<TelasPersonalizadasView> {
  late final ConstrutorTelasService _svc = widget.servico ?? ConstrutorTelasService();
  List<TelaConstruida> _telas = const [];
  bool _carregando = true;
  String? _erro;

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
      final lista = await _svc.ativas();
      if (mounted) setState(() => _telas = lista);
    } catch (e) {
      AppLogger.i.warn('TelasPersonalizadasView: erro ao listar: $e');
      if (mounted) setState(() => _erro = '$e');
    }
    if (mounted) setState(() => _carregando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Expanded(
              child: Text('Telas Personalizadas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          IconButton(tooltip: 'Atualizar', onPressed: _carregar, icon: const Icon(Icons.refresh)),
        ]),
      ),
      Expanded(
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
                ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_erro!)))
                : _telas.isEmpty
                    ? const Center(child: Text('Nenhuma tela personalizada disponível.'))
                    : ListView.separated(
                        itemCount: _telas.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) => ListTile(
                          minVerticalPadding: 12,
                          leading: const Icon(Icons.table_chart_outlined),
                          title: Text(_telas[i].titulo),
                          subtitle: Text(_telas[i].tabelaNome),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => widget.abrir(context, _telas[i]),
                        ),
                      ),
      ),
    ]);
  }
}
