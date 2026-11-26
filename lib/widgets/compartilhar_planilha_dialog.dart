import 'package:flutter/material.dart';

import '../services/planilha_service.dart';
import '../utils/app_logger.dart';

/// Compartilha uma planilha com todos do mesmo cadastro ou com usuarios escolhidos, cada um so vendo ou editando.
class CompartilharPlanilhaDialog extends StatefulWidget {
  final PlanilhaService servico;
  final int planilhaId;

  const CompartilharPlanilhaDialog({super.key, required this.servico, required this.planilhaId});

  @override
  State<CompartilharPlanilhaDialog> createState() => _CompartilharPlanilhaDialogState();
}

class _CompartilharPlanilhaDialogState extends State<CompartilharPlanilhaDialog> {
  final _busca = TextEditingController();
  List<UsuarioCompartilhar> _usuarios = const [];
  bool? _todos;
  final Map<int, bool> _marcados = {};
  bool _carregado = false;
  bool _ocupado = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _executar(() async {
      _usuarios = await widget.servico.usuarios();
      final atual = await widget.servico.compartilhamento(widget.planilhaId);
      _todos = atual.todos;
      final existentes = _usuarios.map((u) => u.id).toSet();
      // quem foi desativado sai da lista ao salvar, senao o servidor recusaria o pedido inteiro
      _marcados.addEntries(atual.usuarios.entries.where((e) => existentes.contains(e.key)));
      _carregado = true;
    });
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<bool> _executar(Future<void> Function() tarefa) async {
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    var ok = true;
    try {
      await tarefa();
    } catch (e) {
      ok = false;
      AppLogger.i.warn('CompartilharPlanilhaDialog: $e');
      _erro = '$e';
    }
    if (mounted) setState(() => _ocupado = false);
    return ok;
  }

  Future<void> _salvar() async {
    final ok = await _executar(() => widget.servico
        .compartilhar(widget.planilhaId, CompartilhamentoPlanilha(todos: _todos, usuarios: Map.of(_marcados))));
    if (ok && mounted) Navigator.pop(context, true);
  }

  Widget _permissao(bool podeEditar, ValueChanged<bool> mudar) => DropdownButton<bool>(
        value: podeEditar,
        underline: const SizedBox.shrink(),
        items: const [
          DropdownMenuItem(value: false, child: Text('Só ver')),
          DropdownMenuItem(value: true, child: Text('Editar')),
        ],
        onChanged: (v) => mudar(v ?? false),
      );

  @override
  Widget build(BuildContext context) {
    final filtro = _busca.text.trim().toLowerCase();
    final lista = _usuarios
        .where((u) => filtro.isEmpty || u.nome.toLowerCase().contains(filtro) || u.email.toLowerCase().contains(filtro))
        .toList();
    return AlertDialog(
      title: const Text('Compartilhar planilha'),
      content: SizedBox(
        width: 460,
        height: 460,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_ocupado) const LinearProgressIndicator(),
          if (_erro != null) Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_carregado) ...[
            Row(children: [
              Checkbox(value: _todos != null, onChanged: (v) => setState(() => _todos = v == true ? false : null)),
              const Expanded(child: Text('Todos os usuários do meu cadastro')),
              if (_todos != null) _permissao(_todos!, (v) => setState(() => _todos = v)),
            ]),
            const Divider(),
            TextField(
              controller: _busca,
              decoration: const InputDecoration(labelText: 'Buscar usuário', prefixIcon: Icon(Icons.search)),
              onChanged: (_) => setState(() {}),
            ),
            Expanded(
              child: _usuarios.isEmpty
                  ? const Center(child: Text('Não há outros usuários para compartilhar.'))
                  : ListView(children: [
                      for (final u in lista)
                        Row(children: [
                          Checkbox(
                              value: _marcados.containsKey(u.id),
                              onChanged: (v) => setState(
                                  () => v == true ? _marcados[u.id] = false : _marcados.remove(u.id))),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(u.email.isEmpty || u.email == u.nome ? u.nome : '${u.nome}\n${u.email}'),
                            ),
                          ),
                          if (_marcados.containsKey(u.id))
                            _permissao(_marcados[u.id]!, (v) => setState(() => _marcados[u.id] = v)),
                        ]),
                    ]),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _ocupado || !_carregado ? null : _salvar, child: const Text('Salvar')),
      ],
    );
  }
}
