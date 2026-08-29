import 'package:flutter/material.dart';

import '../../config/api_links.dart';
import '../../services/network_caller.dart';
import '../../widgets/generic/generic_grid_screen.dart';

/// MOD-01 Modulos Contratados — tela de atribuicao de modulos a um Parceiro
/// OU Empresa. NAO usa o par generico (GenericGridScreen/
/// GenericDetailFormScreen): e edicao de um CONJUNTO inteiro (substituicao
/// total via DELETE+INSERT no backend), analoga em espirito a
/// RolePermissaoScreen (Fase 2), mas em 1 dimensao (so modulos, sem matriz
/// de campos por tela).
///
/// Fluxo: (1) escolhe Parceiro ou Empresa; (2) busca por ID (nao carrega a
/// lista inteira em memoria — volume real de producao pode ser grande); (3)
/// carrega em paralelo o catalogo completo de ModuloServico e os modulos ja
/// vinculados; (4) apresenta checkboxes pre-marcados; (5) ao salvar, exige
/// confirmacao explicita (a substituicao e destrutiva: modulo desmarcado e
/// desvinculado) antes de disparar o POST.
class ModuloAtribuicaoScreen extends StatefulWidget {
  const ModuloAtribuicaoScreen({super.key, this.networkCaller});

  final NetworkCaller? networkCaller;

  @override
  State<ModuloAtribuicaoScreen> createState() =>
      ModuloAtribuicaoScreenState();
}

class ModuloAtribuicaoScreenState extends State<ModuloAtribuicaoScreen> {
  late final NetworkCaller _caller = widget.networkCaller ?? NetworkCaller();
  bool get _ownsCaller => widget.networkCaller == null;

  final TextEditingController _idCtrl = TextEditingController();

  /// 'parceiro' ou 'empresa'.
  String _tipo = 'parceiro';

  bool _carregando = false;
  bool _salvando = false;
  String? _erro;

  int? _idCarregado;
  String? _nomeEncontrado;
  List<Map<String, dynamic>> _catalogo = [];
  final Set<int> _moduloIdsMarcados = <int>{};

  @override
  void dispose() {
    _idCtrl.dispose();
    if (_ownsCaller) _caller.close();
    super.dispose();
  }

  bool get _temSelecao => _idCarregado != null && !_carregando;

  int? _extractId(Map<String, dynamic> row) {
    final raw = row['id'] ?? row['moduloId'];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  String _labelDoRegistro(Map<String, dynamic>? row) {
    if (row == null) return '';
    return (row['nome'] ?? row['razaoSocial'] ?? row['nomeFantasia'] ?? '')
        .toString();
  }

  Future<void> _carregar() async {
    final idTexto = _idCtrl.text.trim();
    final id = int.tryParse(idTexto);
    if (id == null) {
      setState(() => _erro = 'Informe um ID numerico valido.');
      return;
    }

    setState(() {
      _carregando = true;
      _erro = null;
      _idCarregado = null;
      _nomeEncontrado = null;
      _catalogo = [];
      _moduloIdsMarcados.clear();
    });

    final urlRegistro = _tipo == 'parceiro'
        ? '${ApiLinks.baseUrl}/api/parceiro/$id'
        : '${ApiLinks.baseUrl}/api/empresa/$id';

    final resRegistro = await _caller.getRequest(urlRegistro);
    if (!mounted) return;

    if (!resRegistro.isSuccess) {
      setState(() {
        _carregando = false;
        _erro = _tipo == 'parceiro'
            ? 'Parceiro nao encontrado para o ID informado.'
            : 'Empresa nao encontrada para o ID informado.';
      });
      return;
    }

    final registro = _extractRecord(resRegistro.body);
    if (registro == null) {
      setState(() {
        _carregando = false;
        _erro = 'Resposta inesperada do servidor ao buscar o registro.';
      });
      return;
    }

    final urlCatalogo = ApiLinks.allModulosServico;
    final urlVinculados = _tipo == 'parceiro'
        ? ApiLinks.parceiroModulos(id.toString())
        : ApiLinks.empresaModulos(id.toString());

    final resultados = await Future.wait([
      _caller.getRequest(urlCatalogo),
      _caller.getRequest(urlVinculados),
    ]);
    if (!mounted) return;

    final resCatalogo = resultados[0];
    final resVinculados = resultados[1];

    if (!resCatalogo.isSuccess || !resVinculados.isSuccess) {
      setState(() {
        _carregando = false;
        _erro = 'Nao foi possivel carregar o catalogo/modulos vinculados.';
      });
      return;
    }

    final catalogo = GenericGridScreen.extractRows(resCatalogo.body);
    final vinculados = GenericGridScreen.extractRows(resVinculados.body);
    final idsVinculados = vinculados
        .map(_extractId)
        .whereType<int>()
        .toSet();

    setState(() {
      _carregando = false;
      _idCarregado = id;
      _nomeEncontrado = _labelDoRegistro(registro);
      _catalogo = catalogo;
      _moduloIdsMarcados
        ..clear()
        ..addAll(idsVinculados);
    });
  }

  Map<String, dynamic>? _extractRecord(Map<String, dynamic>? body) {
    if (body == null) return null;
    final data = body['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    if (body.containsKey('id')) return Map<String, dynamic>.from(body);
    return null;
  }

  Future<bool> _confirmarSubstituicao() async {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar substituicao de modulos'),
        content: const Text(
          'Isto substitui TODO o conjunto de modulos deste Parceiro/Empresa — '
          'modulos nao marcados serao desvinculados.',
        ),
        actions: [
          TextButton(
            key: const Key('modulo_atribuicao_cancelar_btn'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            key: const Key('modulo_atribuicao_confirmar_btn'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return resultado ?? false;
  }

  Future<void> _salvar() async {
    if (_idCarregado == null) return;
    final id = _idCarregado!;

    final confirmado = await _confirmarSubstituicao();
    if (!mounted || !confirmado) return;

    setState(() => _salvando = true);

    final url = _tipo == 'parceiro'
        ? ApiLinks.vincularParceiroModulos
        : ApiLinks.vincularEmpresaModulos;
    final body = <String, dynamic>{
      _tipo == 'parceiro' ? 'parceiroId' : 'empresaId': id,
      'moduloIds': _moduloIdsMarcados.toList(),
    };

    final response = await _caller.postRequest(url, body);
    if (!mounted) return;

    setState(() => _salvando = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(response.isSuccess
            ? 'Modulos salvos com sucesso.'
            : 'Erro ao salvar modulos: ${response.statusCode}'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Atribuicao de Modulos')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<String>(
              key: const Key('modulo_atribuicao_tipo_seletor'),
              segments: const [
                ButtonSegment(value: 'parceiro', label: Text('Parceiro')),
                ButtonSegment(value: 'empresa', label: Text('Empresa')),
              ],
              selected: {_tipo},
              onSelectionChanged: (selecao) {
                setState(() {
                  _tipo = selecao.first;
                  _idCarregado = null;
                  _nomeEncontrado = null;
                  _catalogo = [];
                  _moduloIdsMarcados.clear();
                  _erro = null;
                });
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('modulo_atribuicao_id_field'),
                    controller: _idCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _tipo == 'parceiro'
                          ? 'ID do Parceiro'
                          : 'ID da Empresa',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  key: const Key('modulo_atribuicao_carregar_btn'),
                  onPressed: _carregando ? null : _carregar,
                  child: const Text('Carregar'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_erro != null)
              Text(
                _erro!,
                key: const Key('modulo_atribuicao_erro'),
                style: const TextStyle(color: Colors.red),
              ),
            if (_nomeEncontrado != null)
              Text(
                'Encontrado: $_nomeEncontrado',
                key: const Key('modulo_atribuicao_nome_encontrado'),
              ),
            const SizedBox(height: 8),
            if (_carregando)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_temSelecao)
              Expanded(
                child: _catalogo.isEmpty
                    ? const Center(
                        child: Text('Nenhum modulo cadastrado no catalogo.'),
                      )
                    : ListView.builder(
                        key: const Key('modulo_atribuicao_lista'),
                        itemCount: _catalogo.length,
                        itemBuilder: (context, index) {
                          final modulo = _catalogo[index];
                          final id = _extractId(modulo);
                          final marcado =
                              id != null && _moduloIdsMarcados.contains(id);
                          return CheckboxListTile(
                            key: Key('modulo_atribuicao_checkbox_$id'),
                            title: Text(modulo['nome']?.toString() ?? ''),
                            subtitle: modulo['descricao'] != null
                                ? Text(modulo['descricao'].toString())
                                : null,
                            value: marcado,
                            onChanged: id == null
                                ? null
                                : (checked) {
                                    setState(() {
                                      if (checked == true) {
                                        _moduloIdsMarcados.add(id);
                                      } else {
                                        _moduloIdsMarcados.remove(id);
                                      }
                                    });
                                  },
                          );
                        },
                      ),
              ),
            if (_temSelecao) ...[
              const SizedBox(height: 8),
              ElevatedButton(
                key: const Key('modulo_atribuicao_salvar_btn'),
                onPressed: _salvando ? null : _salvar,
                child: Text(_salvando ? 'Salvando...' : 'Salvar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
