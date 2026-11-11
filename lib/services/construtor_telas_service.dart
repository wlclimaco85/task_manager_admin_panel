import '../models/network_response.dart';
import '../config/api_links.dart';
import 'modulo_java_service.dart';
import 'network_caller.dart';

/// Tabela da empresa que pode virar tela no Construtor de Telas.
class TabelaDisponivel {
  final String nome;
  final int colunas;

  const TabelaDisponivel(this.nome, this.colunas);

  factory TabelaDisponivel.fromJson(Map<String, dynamic> j) =>
      TabelaDisponivel(j['nome']?.toString() ?? '', (j['colunas'] as num?)?.toInt() ?? 0);
}

/// Tela criada pelo Construtor de Telas sobre uma tabela (CRUD generico em /api/dados/{tabela}).
class TelaConstruida {
  final int id;
  final String telaNome;
  final String tabelaNome;
  final String titulo;
  final bool ativo;

  const TelaConstruida({
    required this.id,
    required this.telaNome,
    required this.tabelaNome,
    required this.titulo,
    this.ativo = true,
  });

  factory TelaConstruida.fromJson(Map<String, dynamic> j) => TelaConstruida(
        id: (j['id'] as num?)?.toInt() ?? 0,
        telaNome: j['telaNome']?.toString() ?? '',
        tabelaNome: j['tabelaNome']?.toString() ?? '',
        titulo: j['titulo']?.toString() ?? '',
        ativo: j['ativo'] != false,
      );
}

/// Construtor de Telas (plataforma low-code, F5).
class ConstrutorTelasService {
  final NetworkCaller _rede;

  ConstrutorTelasService({NetworkCaller? rede}) : _rede = rede ?? NetworkCaller();

  Future<List<TabelaDisponivel>> tabelas() async {
    final r = await _rede.getRequest(ApiLinks.construtorTabelas);
    _exigir(r, 'listar as tabelas');
    return listaDeResposta(r).map(TabelaDisponivel.fromJson).toList();
  }

  /// Telas ativas da empresa (qualquer usuario logado; alimenta o menu "Telas Personalizadas").
  Future<List<TelaConstruida>> ativas() async {
    final r = await _rede.getRequest(ApiLinks.construtorTelas);
    _exigir(r, 'listar as telas');
    return listaDeResposta(r).map(TelaConstruida.fromJson).toList();
  }

  Future<List<TelaConstruida>> todas() async {
    final r = await _rede.getRequest(ApiLinks.construtorTelasTodas);
    _exigir(r, 'listar as telas');
    return listaDeResposta(r).map(TelaConstruida.fromJson).toList();
  }

  Future<TelaConstruida> criar(String tabela, String titulo) async {
    final r = await _rede.postRequest(ApiLinks.construtorTelas, {'tabela': tabela, 'titulo': titulo});
    _exigir(r, 'criar a tela');
    return TelaConstruida.fromJson(r.body!);
  }

  Future<TelaConstruida> atualizar(int id, {String? titulo, bool? ativo}) async {
    final r = await _rede.putRequest(ApiLinks.construtorTela('$id'), {
      if (titulo != null) 'titulo': titulo,
      if (ativo != null) 'ativo': ativo,
    });
    _exigir(r, 'atualizar a tela');
    return TelaConstruida.fromJson(r.body!);
  }

  Future<void> excluir(int id) async {
    final r = await _rede.deleteRequest(ApiLinks.construtorTela('$id'));
    _exigir(r, 'excluir a tela');
  }

  void _exigir(NetworkResponse r, String acao) {
    if (r.isSuccess) return;
    if (r.statusCode == 403) {
      throw const ModuloJavaException('Somente o usuário MASTER pode usar o Construtor de Telas.');
    }
    throw ModuloJavaException(mensagemDeResposta(r) ?? 'Não foi possível $acao (HTTP ${r.statusCode}).');
  }
}
