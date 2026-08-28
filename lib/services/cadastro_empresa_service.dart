import '../config/api_links.dart';
import '../models/cadastro_empresa_models.dart';
import 'network_caller.dart';

// Orquestra a criacao completa de uma empresa de demonstracao (SIS-02,
// wizard "Cadastro Empresa"), portado de
// task_manager_flutter/lib/web/screens/cadastro_empresa_wizard.dart
// (`_execute`/`_post`/`_delete`/`_rollback`), trocando `http` cru por
// `NetworkCaller` (achado do RESEARCH.md desta fase). Logica pura, sem
// dependencia de widget — a UI (P04) injeta os dados coletados no wizard e
// consome o progresso via `onLog`.
//
// Sequencia (replica fielmente o arquivo original, incluindo a assimetria
// de campo `parceiro` (contas a pagar) vs `cliente` (contas a receber)):
// empresa -> 2 logins fixos (ADMIN/FINANCEIRO, tipoLogin:1) -> N clientes
// (parceiro + login tipoLogin:2) -> 5 contas a pagar -> 5 contas a receber
// -> 1 nota fiscal -> N chamados -> 1 chat (condicional a existir cliente)
// -> N funcionarios (parceiro tipoAluno:'FUNCIONARIO' + login tipoLogin:3).
//
// Paths confirmados contra os controllers reais do backend
// (AppAcademia/src/main/java/br/com/appAcademia/controller/) nesta sessao:
// EmpresaController(/api/empresa), LoginController(/api/login,/api/logins),
// ParceiroController(/api/parceiro), ContaPagarController(/api/conta_pagar),
// ContaReceberController(/api/conta_receber), NfeController(/api/nfe),
// ChamadoController(/api/chamados,/api/chamado),
// ChatController(/api/chat,/api/chat_message) — todos com
// `@DeleteMapping("/{id}")` equivalente, usado pelo rollback LIFO.

/// Dados de entrada da etapa "Empresa" do wizard.
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

/// Dados de entrada de um usuario fixo (ADMIN ou FINANCEIRO) da etapa
/// "Usuarios". `tipo` e apenas descritivo (rotulo de log), o backend
/// recebe sempre `tipoLogin: 1` para ambos, conforme o arquivo original.
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

/// Dados de entrada de um cliente da etapa "Clientes" (gera 1 parceiro +
/// 1 login vinculado, `tipoLogin: 2`).
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

/// Dados de entrada de uma conta (Pagar ou Receber) da etapa "Contas".
class ContaData {
  final String descricao;
  final double valor;

  const ContaData({required this.descricao, required this.valor});
}

/// Dados de entrada de um chamado da etapa "Chamados".
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

/// Dados de entrada de um funcionario da etapa "Funcionarios" (gera 1
/// parceiro com `tipoAluno: 'FUNCIONARIO'` + 1 login `tipoLogin: 3`).
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

class CadastroEmpresaService {
  CadastroEmpresaService({required NetworkCaller networkCaller})
      : _nc = networkCaller;

  final NetworkCaller _nc;
  final List<CreatedEntity> _createdEntities = [];

  /// Executa a sequencia completa de criacao. `contas` deve conter os 5
  /// itens de "Contas a Pagar" seguidos dos 5 itens de "Contas a Receber"
  /// (mesma ordem posicional do arquivo original: indices 0-4 -> pagar,
  /// 5-9 -> receber). Lanca [CadastroException] na primeira falha e
  /// dispara rollback LIFO das entidades ja criadas antes de repropagar o
  /// erro (a UI decide como exibir).
  Future<void> execute({
    required EmpresaData empresa,
    required List<UsuarioData> usuarios,
    required List<ClienteData> clientes,
    required List<ContaData> contas,
    required List<ChamadoData> chamados,
    required List<FuncionarioData> funcionarios,
    void Function(LogEntry)? onLog,
  }) async {
    _createdEntities.clear();
    final clienteIds = <int>[];

    try {
      final now = DateTime.now().toIso8601String();
      final aplicativoPayload =
          empresa.aplicativoId != null ? {'id': empresa.aplicativoId} : null;

      // ── 1. EMPRESA ─────────────────────────────────────────────────────
      final empresaId = await _post(
        ApiLinks.createEmpresa,
        {
          'nome': empresa.nome,
          'razaoSocial': empresa.razaoSocial.isNotEmpty
              ? empresa.razaoSocial
              : empresa.nome,
          'email': empresa.email,
          'telefone': empresa.telefone,
          'cnpj': empresa.cnpj,
          'aplicativo': ?aplicativoPayload,
        },
        'Empresa: ${empresa.nome}',
        onLog,
      );
      if (empresaId == null) {
        throw const CadastroException('Falha ao criar empresa');
      }
      _createdEntities.add(CreatedEntity(
          tipo: 'Empresa', id: empresaId, deleteUrl: ApiLinks.deleteEmpresa));

      final empresaRef = {'id': empresaId};

      // ── 2. USUARIOS ────────────────────────────────────────────────────
      for (final u in usuarios) {
        final roles = u.roleIds.map((id) => {'id': id}).toList();
        final id = await _post(
          ApiLinks.createLogin,
          {
            'nome': u.nome,
            'email': u.email,
            'senha': u.senha,
            'cpfCnpj': u.cpfCnpj.isNotEmpty ? u.cpfCnpj : null,
            'empresa': empresaRef,
            'aplicativo': ?aplicativoPayload,
            if (roles.isNotEmpty) 'roles': roles,
            'tipoLogin': 1,
          },
          'Usuario: ${u.nome} (${u.tipo})',
          onLog,
        );
        if (id == null) {
          throw CadastroException('Falha ao criar usuario ${u.nome}');
        }
        _createdEntities.add(CreatedEntity(
            tipo: 'Usuario ${u.nome}', id: id, deleteUrl: ApiLinks.deleteLogin));
      }

      // ── 3. CLIENTES (PARCEIROS) ───────────────────────────────────────
      for (final c in clientes) {
        final id = await _post(
          ApiLinks.createParceiro,
          {
            'nome': c.nome,
            'email': c.email,
            'cpf': c.cpf.isNotEmpty ? c.cpf : null,
            'telefone': c.telefone.isNotEmpty ? c.telefone : null,
            'empresa': empresaRef,
            'aplicativo': ?aplicativoPayload,
          },
          'Cliente: ${c.nome}',
          onLog,
        );
        if (id == null) {
          throw CadastroException('Falha ao criar cliente ${c.nome}');
        }
        clienteIds.add(id);
        _createdEntities.add(CreatedEntity(
            tipo: 'Cliente ${c.nome}',
            id: id,
            deleteUrl: ApiLinks.deleteParceiro));

        final rolePayload = c.roleAdminId != null
            ? [
                {'id': c.roleAdminId}
              ]
            : <Map<String, dynamic>>[];
        final loginId = await _post(
          ApiLinks.createLogin,
          {
            'nome': c.nome,
            'email': c.email,
            'senha': 'Senha@123',
            'empresa': empresaRef,
            'parceiro': {'id': id},
            'aplicativo': ?aplicativoPayload,
            if (rolePayload.isNotEmpty) 'roles': rolePayload,
            'tipoLogin': 2,
          },
          'Login cliente: ${c.nome}',
          onLog,
        );
        if (loginId == null) {
          throw CadastroException(
              'Falha ao criar login do cliente ${c.nome}');
        }
        _createdEntities.add(CreatedEntity(
            tipo: 'Login cliente ${c.nome}',
            id: loginId,
            deleteUrl: ApiLinks.deleteLogin));
      }

      final parceiroRef =
          clienteIds.isNotEmpty ? {'id': clienteIds.first} : null;

      // ── 4. CONTAS A PAGAR (posicoes 0-4) ──────────────────────────────
      for (int i = 0; i < contas.length && i < 5; i++) {
        final c = contas[i];
        final id = await _post(
          ApiLinks.createContaPagar,
          {
            'descricao': c.descricao,
            'valor': c.valor,
            'dataVencimento':
                DateTime.now().add(Duration(days: 30 + i * 7)).toIso8601String(),
            'status': 'ABERTA',
            'empresa': empresaRef,
            'parceiro': ?parceiroRef,
          },
          'Conta Pagar: ${c.descricao}',
          onLog,
        );
        if (id == null) {
          throw CadastroException(
              'Falha ao criar conta a pagar ${c.descricao}');
        }
        _createdEntities.add(CreatedEntity(
            tipo: 'Conta Pagar ${c.descricao}',
            id: id,
            deleteUrl: ApiLinks.deleteContaPagar));
      }

      // ── 5. CONTAS A RECEBER (posicoes 5-9) ────────────────────────────
      // Atencao (assimetria confirmada no backend): o payload usa a chave
      // `cliente`, NAO `parceiro` como em contas a pagar.
      for (int i = 5; i < contas.length; i++) {
        final c = contas[i];
        final id = await _post(
          ApiLinks.createContaReceber,
          {
            'descricao': c.descricao,
            'valor': c.valor,
            'dataVencimento': DateTime.now()
                .add(Duration(days: 30 + (i - 5) * 7))
                .toIso8601String(),
            'status': 'ABERTA',
            'empresa': empresaRef,
            'cliente': ?parceiroRef,
          },
          'Conta Receber: ${c.descricao}',
          onLog,
        );
        if (id == null) {
          throw CadastroException(
              'Falha ao criar conta a receber ${c.descricao}');
        }
        _createdEntities.add(CreatedEntity(
            tipo: 'Conta Receber ${c.descricao}',
            id: id,
            deleteUrl: ApiLinks.deleteContaReceber));
      }

      // ── 6. NOTA FISCAL ─────────────────────────────────────────────────
      final nfId = await _post(
        ApiLinks.createNfe,
        {
          'numero': 'NF-$empresaId-001',
          'dhEmi': now,
          'valorTotal': 1000.0,
          'status': 'CRIADA',
          'empresa': empresaRef,
        },
        'Nota Fiscal Entrada',
        onLog,
      );
      if (nfId == null) {
        throw const CadastroException('Falha ao criar nota fiscal');
      }
      _createdEntities.add(CreatedEntity(
          tipo: 'Nota Fiscal', id: nfId, deleteUrl: ApiLinks.deleteNfe));

      // ── 7. CHAMADOS ────────────────────────────────────────────────────
      for (final ch in chamados) {
        final id = await _post(
          ApiLinks.createChamado,
          {
            'titulo': ch.titulo,
            'descricao': ch.descricao,
            'status': 'ABERTO',
            'prioridade': ch.prioridade,
            'empresa': empresaRef,
            'parceiro': ?parceiroRef,
            'dataAbertura': now,
          },
          'Chamado: ${ch.titulo}',
          onLog,
        );
        if (id == null) {
          throw CadastroException('Falha ao criar chamado ${ch.titulo}');
        }
        _createdEntities.add(CreatedEntity(
            tipo: 'Chamado ${ch.titulo}',
            id: id,
            deleteUrl: ApiLinks.deleteChamado));
      }

      // ── 8. CHAT (condicional a existir cliente) ───────────────────────
      if (clienteIds.isNotEmpty) {
        final clienteId = clienteIds.first;
        final chatId = await _post(
          ApiLinks.createChat,
          {
            'empId': empresaId,
            'empresaId': empresaId,
            'parceiroId': clienteId,
            'chatId': 'empresa-$empresaId-parceiro-$clienteId',
            'sector': 'Abertura Firma',
            'status': 'ABERTO',
            'text':
                'Chat inicial criado automaticamente para ${empresa.nome}.',
            'titulo': 'Chat inicial - ${empresa.nome}',
          },
          'Chat inicial',
          onLog,
        );
        if (chatId == null) {
          throw const CadastroException('Falha ao criar chat inicial');
        }
        _createdEntities.add(CreatedEntity(
            tipo: 'Chat inicial', id: chatId, deleteUrl: ApiLinks.deleteChat));
      }

      // ── 9. FUNCIONARIOS ────────────────────────────────────────────────
      for (final f in funcionarios) {
        final id = await _post(
          ApiLinks.createParceiro,
          {
            'nome': f.nome,
            'email': f.email,
            'cpf': f.cpf.isNotEmpty ? f.cpf : null,
            'empresa': empresaRef,
            'aplicativo': ?aplicativoPayload,
            'tipoAluno': 'FUNCIONARIO',
          },
          'Funcionario: ${f.nome}',
          onLog,
        );
        if (id == null) {
          throw CadastroException('Falha ao criar funcionario ${f.nome}');
        }
        _createdEntities.add(CreatedEntity(
            tipo: 'Funcionario ${f.nome}',
            id: id,
            deleteUrl: ApiLinks.deleteParceiro));

        final loginId = await _post(
          ApiLinks.createLogin,
          {
            'nome': f.nome,
            'email': f.email,
            'senha': 'Senha@123',
            'empresa': empresaRef,
            'parceiro': {'id': id},
            'aplicativo': ?aplicativoPayload,
            'tipoLogin': 3,
          },
          'Login funcionario: ${f.nome}',
          onLog,
        );
        if (loginId == null) {
          throw CadastroException(
              'Falha ao criar login do funcionario ${f.nome}');
        }
        _createdEntities.add(CreatedEntity(
            tipo: 'Login funcionario ${f.nome}',
            id: loginId,
            deleteUrl: ApiLinks.deleteLogin));
      }
    } catch (e) {
      await _rollback(onLog);
      rethrow;
    }
  }

  Future<int?> _post(String url, Map<String, dynamic> body, String label,
      void Function(LogEntry)? onLog) async {
    final response = await _nc.postRequest(url, body);
    if (response.isSuccess) {
      final id = _extractId(response.body);
      onLog?.call(LogEntry(mensagem: '$label -> id=$id', sucesso: true));
      return id;
    }
    onLog?.call(LogEntry(
        mensagem: '$label -> HTTP ${response.statusCode}', sucesso: false));
    return null;
  }

  /// Tenta 4 formatos de resposta conhecidos, mesma heuristica do arquivo
  /// original: `body.id`, `body.data.id`, `body.data.parceiro.id`,
  /// `body.data.login.id` — cada endpoint devolve um formato diferente.
  int? _extractId(dynamic body) {
    if (body is! Map) return null;
    final direct = body['id'];
    if (direct is int) return direct;

    final data = body['data'];
    if (data is Map) {
      final fromData = data['id'];
      if (fromData is int) return fromData;

      final parceiro = data['parceiro'];
      if (parceiro is Map && parceiro['id'] is int) {
        return parceiro['id'] as int;
      }

      final login = data['login'];
      if (login is Map && login['id'] is int) {
        return login['id'] as int;
      }
    }
    return null;
  }

  Future<void> _rollback(void Function(LogEntry)? onLog) async {
    for (final entity in _createdEntities.reversed) {
      final response =
          await _nc.deleteRequest(entity.deleteUrl(entity.id.toString()));
      onLog?.call(LogEntry(
        mensagem: 'Rollback: ${entity.tipo} (id=${entity.id})',
        sucesso: response.isSuccess,
      ));
    }
    _createdEntities.clear();
  }
}
