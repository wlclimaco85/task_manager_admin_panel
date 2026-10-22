import 'package:flutter/material.dart';

import '../../services/acessos_service.dart';
import '../../services/auth_utility.dart';

/// Painel do dono: dashboard de usuarios (total, ultimos 7 dias, hoje, por aplicacao)
/// e a grade com login, data logada, modulo, versao e aplicacao.
class AcessosScreen extends StatefulWidget {
  const AcessosScreen({super.key, this.service});

  final AcessosService? service;

  @override
  State<AcessosScreen> createState() => _AcessosScreenState();
}

class _AcessosScreenState extends State<AcessosScreen> {
  late final AcessosService _service = widget.service ?? AcessosService();
  Map<String, dynamic> _resumo = const {};
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
      final resumo = await _service.resumo(token);
      final usuarios = await _service.usuarios(token);
      final diario = await _service.diario(token);
      if (!mounted) return;
      setState(() {
        _resumo = resumo;
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
            Tab(text: 'Visão geral'),
            Tab(text: 'Por dia'),
          ]),
        ),
        body: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_erro!)))
                : TabBarView(children: [
                    _visaoGeral(),
                    _listaDiario(),
                  ]),
      ),
    );
  }

  Widget _visaoGeral() {
    final totais = (_resumo['totais'] as Map?) ?? const {};
    final porApp = (_resumo['porAplicacao'] as List?) ?? const [];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          _cardTotal('Usuários', totais['total']),
          const SizedBox(width: 8),
          _cardTotal('Últimos 7 dias', totais['semana']),
          const SizedBox(width: 8),
          _cardTotal('Hoje', totais['hoje']),
        ]),
        const SizedBox(height: 16),
        const Text('Por aplicação', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (porApp.isEmpty)
          const Text('Nenhum acesso registrado ainda.')
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Aplicação')),
                DataColumn(label: Text('Total'), numeric: true),
                DataColumn(label: Text('7 dias'), numeric: true),
                DataColumn(label: Text('Hoje'), numeric: true),
              ],
              rows: [
                for (final a in porApp.whereType<Map>())
                  DataRow(cells: [
                    DataCell(Text('${a['aplicacao']}')),
                    DataCell(Text('${a['total']}')),
                    DataCell(Text('${a['semana']}')),
                    DataCell(Text('${a['hoje']}')),
                  ]),
              ],
            ),
          ),
        const SizedBox(height: 16),
        const Text('Usuários e últimos acessos', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _gradeUsuarios(),
      ],
    );
  }

  Widget _cardTotal(String titulo, Object? valor) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Text(titulo, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Text('${valor ?? 0}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    );
  }

  Widget _gradeUsuarios() {
    if (_usuarios.isEmpty) return const Text('Nenhum acesso registrado ainda.');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Login')),
          DataColumn(label: Text('Data logada')),
          DataColumn(label: Text('Módulo')),
          DataColumn(label: Text('Versão')),
          DataColumn(label: Text('Aplicação')),
        ],
        rows: [
          for (final u in _usuarios)
            DataRow(cells: [
              DataCell(Text('${u['email'] ?? u['nome'] ?? '—'}')),
              DataCell(Text(_formatarData(u['ultimoAcessoEm']))),
              DataCell(Text(_rotuloModulo(u['plataforma']))),
              DataCell(Text('${u['versao'] ?? ''}')),
              DataCell(Text('${u['aplicacao'] ?? ''}')),
            ]),
        ],
      ),
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
            subtitle: Text('${d['aplicacao']} • ${_rotuloModulo(d['plataforma'])} • ${d['versao']}'),
          ),
        );
      },
    );
  }

  /// Modulo como o usuario entende: WEB, Windows ou App (MOBILE).
  static String _rotuloModulo(Object? plataforma) {
    return switch ('$plataforma') {
      'WEB' => 'Web',
      'WINDOWS' => 'Windows',
      'MOBILE' => 'App',
      _ => 'Desconhecido',
    };
  }

  /// Data do ultimo acesso no formato dd/MM/aaaa HH:mm (vem do backend como ISO local).
  static String _formatarData(Object? iso) {
    final data = DateTime.tryParse('$iso');
    if (data == null) return '${iso ?? ''}';
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(data.day)}/${dois(data.month)}/${data.year} ${dois(data.hour)}:${dois(data.minute)}';
  }
}
