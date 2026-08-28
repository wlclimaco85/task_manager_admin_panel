import '../models/cadastro_empresa_models.dart';
import 'network_caller.dart';

class EmpresaData {
  final String nome;
  final String razaoSocial;
  final String email;
  final String telefone;
  final String cnpj;
  final int? aplicativoId;

  const EmpresaData({
    required this.nome,
    this.razaoSocial = '',
    this.email = '',
    this.telefone = '',
    this.cnpj = '',
    this.aplicativoId,
  });
}

class UsuarioData {
  final String nome;
  final String email;
  final String senha;
  final String cpfCnpj;
  final List<int> roleIds;
  final String tipo;

  const UsuarioData({
    required this.nome,
    required this.email,
    required this.senha,
    this.cpfCnpj = '',
    this.roleIds = const [],
    this.tipo = '',
  });
}

class ClienteData {
  final String nome;
  final String email;
  final String cpf;
  final String telefone;
  final int? roleAdminId;

  const ClienteData({
    required this.nome,
    required this.email,
    this.cpf = '',
    this.telefone = '',
    this.roleAdminId,
  });
}

class ContaData {
  final String descricao;
  final double valor;

  const ContaData({required this.descricao, required this.valor});
}

class ChamadoData {
  final String titulo;
  final String descricao;
  final String prioridade;

  const ChamadoData({
    required this.titulo,
    this.descricao = '',
    this.prioridade = 'MEDIA',
  });
}

class FuncionarioData {
  final String nome;
  final String email;
  final String cpf;

  const FuncionarioData({
    required this.nome,
    required this.email,
    this.cpf = '',
  });
}

// STUB TEMPORARIO (fase RED do TDD) — implementacao real na task 03.2,
// commit seguinte.
class CadastroEmpresaService {
  CadastroEmpresaService({required NetworkCaller networkCaller});

  Future<void> execute({
    required EmpresaData empresa,
    required List<UsuarioData> usuarios,
    required List<ClienteData> clientes,
    required List<ContaData> contas,
    required List<ChamadoData> chamados,
    required List<FuncionarioData> funcionarios,
    void Function(LogEntry)? onLog,
  }) async {
    throw UnimplementedError();
  }
}
