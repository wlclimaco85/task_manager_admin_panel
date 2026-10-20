import 'package:flutter/material.dart';

import '../../services/acessos_service.dart';
import '../../services/auth_utility.dart';

/// Painel do dono: quem acessou, em qual aplicacao, plataforma e versao, e acessos por dia.
class AcessosScreen extends StatefulWidget {
  const AcessosScreen({super.key, this.service});

  final AcessosService? service;

  @override
  State<AcessosScreen> createState() => _AcessosScreenState();
}

class _AcessosScreenState extends State<AcessosScreen> {
  late final AcessosService _service = widget.service ?? AcessosService();
  List<Map<String, dynamic>> _usuarios = const [];
  List<Map<String, dynamic>> _diario = const [];
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
    final token = AuthUtility.userInfo?.token ?? '';
    try {
      final usuarios = await _service.usuarios(token);
      final diario = await _service.diario(token);
      if (!mounted) return;
      setState(() {
        _usuarios = usuarios;
        _diario = diario;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar os acessos: $e';
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Acessos'),
          actions: [
            IconButton(
              tooltip: 'Atualizar',
              onPressed: _carregando ? null : _carregar,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Usuários'),
            Tab(text: 'Por dia'),
          ]),
        ),
        body: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_erro!)))
                : TabBarView(children: [
                    _listaUsuarios(),
                    _listaDiario(),
                  ]),
      ),
    );
  }

  Widget _listaUsuarios() {
    if (_usuarios.isEmpty) return const Center(child: Text('Nenhum acesso registrado ainda.'));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _usuarios.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final u = _usuarios[i];
        return Card(
          child: ListTile(
            title: Text('${u['nome'] ?? u['email'] ?? '—'}'),
            subtitle: Text('${u['aplicacao']} • ${u['plataforma']} • ${u['versao']}\n'
                'Último acesso: ${u['ultimoAcessoEm']} • Total: ${u['totalAcessos']}'),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  Widget _listaDiario() {
    if (_diario.isEmpty) return const Center(child: Text('Nenhum acesso nos últimos dias.'));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _diario.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final d = _diario[i];
        return Card(
          child: ListTile(
            title: Text('${d['dia']} • ${d['acessos']} acessos'),
            subtitle: Text('${d['aplicacao']} • ${d['plataforma']} • ${d['versao']}'),
          ),
        );
      },
    );
  }
}
