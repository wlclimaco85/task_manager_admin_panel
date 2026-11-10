import '../models/network_response.dart';
import '../config/api_links.dart';
import 'modulo_java_service.dart';
import 'network_caller.dart';

/// Ligacao (FK) de um campo de tela: o app mostra o campo como lista de busca no endpoint informado.
class LigacaoCampo {
  final String campo;
  final String tabelaDestino;
  final String endpoint;
  final String campoChave;
  final String campoExibicao;

  const LigacaoCampo({
    required this.campo,
    required this.tabelaDestino,
    required this.endpoint,
    this.campoChave = 'id',
    this.campoExibicao = 'nome',
  });

  factory LigacaoCampo.fromJson(Map<String, dynamic> j) => LigacaoCampo(
        campo: j['campo']?.toString() ?? '',
        tabelaDestino: j['tabelaDestino']?.toString() ?? '',
        endpoint: j['endpoint']?.toString() ?? '',
        campoChave: j['campoChave']?.toString() ?? 'id',
        campoExibicao: j['campoExibicao']?.toString() ?? 'nome',
      );

  Map<String, dynamic> toJson() => {
        'campo': campo,
        'tabelaDestino': tabelaDestino,
        'endpoint': endpoint,
        'campoChave': campoChave,
        'campoExibicao': campoExibicao,
      };
}

/// Campo da tela no Dicionario: do campo so o rotulo muda (tipo e nome sao fixos; campo nunca e excluido).
class CampoDicionario {
  final int? id;
  final String fieldName;
  final String label;
  final String labelOriginal;
  final String fieldType;
  final bool labelPersonalizado;
  final LigacaoCampo? ligacao;

  const CampoDicionario({
    this.id,
    required this.fieldName,
    required this.label,
    required this.labelOriginal,
    required this.fieldType,
    this.labelPersonalizado = false,
    this.ligacao,
  });

  factory CampoDicionario.fromJson(Map<String, dynamic> j) => CampoDicionario(
        id: (j['id'] as num?)?.toInt(),
        fieldName: j['fieldName']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        labelOriginal: j['labelOriginal']?.toString() ?? '',
        fieldType: j['fieldType']?.toString() ?? 'text',
        labelPersonalizado: j['labelPersonalizado'] == true,
        ligacao: j['ligacao'] is Map<String, dynamic>
            ? LigacaoCampo.fromJson(j['ligacao'] as Map<String, dynamic>)
            : null,
      );
}

/// Rotulos e ligacoes que a empresa personalizou para uma tela (o app aplica sobre a tela).
class PersonalizacaoTela {
  final Map<String, String> labels; // fieldName em minusculas -> rotulo
  final List<LigacaoCampo> ligacoes;

  const PersonalizacaoTela({this.labels = const {}, this.ligacoes = const []});

  bool get vazia => labels.isEmpty && ligacoes.isEmpty;

  factory PersonalizacaoTela.fromJson(Map<String, dynamic> j) => PersonalizacaoTela(
        labels: {
          for (final e in ((j['labels'] as Map?) ?? const {}).entries)
            e.key.toString().toLowerCase(): e.value.toString(),
        },
        ligacoes: ((j['ligacoes'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LigacaoCampo.fromJson)
            .toList(),
      );
}

/// Dicionario de Dados (F4): campos (so rotulo) e ligacoes (FK) por tela.
class DicionarioCampoService {
  final NetworkCaller _rede;

  DicionarioCampoService({NetworkCaller? rede}) : _rede = rede ?? NetworkCaller();

  Future<PersonalizacaoTela> personalizacao(String tela) async {
    final r = await _rede.getRequest(ApiLinks.dicionarioPersonalizacao(tela));
    if (!r.isSuccess || r.body == null) return const PersonalizacaoTela();
    return PersonalizacaoTela.fromJson(r.body!);
  }

  Future<List<CampoDicionario>> campos(String tela) async {
    final r = await _rede.getRequest(ApiLinks.dicionarioCampos(tela));
    _exigir(r, 'listar os campos');
    return listaDeResposta(r).map(CampoDicionario.fromJson).toList();
  }

  Future<CampoDicionario> alterarLabel(String tela, String campo, String label) async {
    final r = await _rede.putRequest(ApiLinks.dicionarioLabel(tela, campo), {'label': label});
    _exigir(r, 'alterar o rótulo');
    return CampoDicionario.fromJson(r.body!);
  }

  Future<CampoDicionario> incluirCampo(String tela, String fieldName, String label, String fieldType) async {
    final r = await _rede.postRequest(ApiLinks.dicionarioCampos(tela), {
      'fieldName': fieldName,
      'label': label,
      'fieldType': fieldType,
    });
    _exigir(r, 'incluir o campo');
    return CampoDicionario.fromJson(r.body!);
  }

  Future<LigacaoCampo> salvarLigacao(String tela, LigacaoCampo l) async {
    final r = await _rede.putRequest(ApiLinks.dicionarioLigacao(tela, l.campo), l.toJson());
    _exigir(r, 'salvar a ligação');
    return LigacaoCampo.fromJson(r.body!);
  }

  Future<void> excluirLigacao(String tela, String campo) async {
    final r = await _rede.deleteRequest(ApiLinks.dicionarioLigacao(tela, campo));
    _exigir(r, 'excluir a ligação');
  }

  void _exigir(NetworkResponse r, String acao) {
    if (r.isSuccess) return;
    if (r.statusCode == 403) {
      throw const ModuloJavaException('Somente o usuário MASTER pode alterar o Dicionário de Dados.');
    }
    throw ModuloJavaException(mensagemDeResposta(r) ?? 'Não foi possível $acao (HTTP ${r.statusCode}).');
  }
}
