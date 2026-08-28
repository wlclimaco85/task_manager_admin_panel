import '../config/api_links.dart';
import '../models/network_response.dart';
import '../utils/tenant_context.dart';
import 'network_caller.dart';

/// Logica de negocio de "Importacao de Cadastros" (SIS-04, `_ImportacaoCadastrosSection`
/// em `task_manager_flutter/lib/web/screens/configuracoes_sistema_screen.dart`), portada
/// como servico puro para o admin panel (Task 08a.1, PLAN.md da Fase 2).
///
/// Nao existe endpoint de importacao em lote no backend para estes cadastros — toda a
/// logica roda no cliente, disparando ~10 endpoints REST individuais por linha do CSV:
/// para cada linha, decide create-vs-update via `GET` + filtro em memoria (dedup por
/// chave natural: CNPJ/nome para empresa, CPF/nome para parceiro, e-mail para login),
/// resolve FK de empresa/parceiro quando o CSV nao traz o ID, e aplica a heuristica
/// `_isFaturamentoServico` (portada verbatim) para decidir se uma linha de "planos" na
/// verdade representa um servico contratado de faturamento avulso.
///
/// Diferente de `CadastroEmpresaService` (P03): aqui uma falha em uma linha NAO
/// interrompe o processamento das linhas seguintes — cada linha e' independente,
/// erro e sucesso sao registrados por linha e o processamento continua.
///
/// Entrada: `rows` ja parseadas (cabecalho -> valor por coluna) e um mapeamento
/// opcional `campo -> nome da coluna do CSV` (equivalente ao `_ctrl[tipo][campo].text`
/// do arquivo original, escolhido pelo usuario na tela de mapeamento, P08b). Quando o
/// mapeamento nao traz uma coluna para um campo (ou a linha nao tem aquela coluna), cai
/// para deteccao automatica por sinonimo (mesma logica de `_autoMapear`/`_valor`
/// originais), usando os `sinonimos` declarados em [CadastroImportConfig].

/// Os 5 tipos de cadastro importaveis via CSV.
enum ImportacaoCadastroTipo { empresa, parceiros, funcionarios, loginsClientes, planos }

/// Um campo importavel de um tipo de cadastro: chave interna (`key`, usada nos
/// payloads dos endpoints), rotulo de exibicao e lista de sinonimos de nome de coluna
/// aceitos para deteccao automatica (ex.: campo `cnpj` aceita colunas `cnpj`,
/// `cpf_cnpj`, `documento`).
class CadastroImportField {
  final String key;
  final String label;
  final List<String> sinonimos;
  const CadastroImportField(this.key, this.label, this.sinonimos);
}

/// Configuracao de um tipo de cadastro importavel: titulo/subtitulo (uso da UI, P08b)
/// e a lista de campos com seus sinonimos (usados por este servico para resolver o
/// valor de cada campo a partir da linha do CSV).
class CadastroImportConfig {
  final ImportacaoCadastroTipo tipo;
  final String title;
  final String subtitle;
  final List<CadastroImportField> campos;
  const CadastroImportConfig({
    required this.tipo,
    required this.title,
    required this.subtitle,
    required this.campos,
  });
}

/// Resultado do processamento de uma linha do CSV.
class ImportacaoLogEntry {
  final int linha;

  /// `sucesso` | `erro` | `ignorado`.
  final String status;
  final String mensagem;
  const ImportacaoLogEntry({
    required this.linha,
    required this.status,
    required this.mensagem,
  });
}

/// Resumo agregado de uma execucao de `importar(...)`.
class ImportacaoResultado {
  final int total;
  final int sucesso;
  final int erros;
  final int ignorados;
  final List<ImportacaoLogEntry> detalhes;
  const ImportacaoResultado({
    required this.total,
    required this.sucesso,
    required this.erros,
    required this.ignorados,
    required this.detalhes,
  });
}

/// Callback de progresso incremental (mesmo padrao de `CadastroEmpresaService`, P03),
/// para a UI (P08b) plotar log/barra de progresso linha a linha sem acoplar a um
/// `StatefulWidget`.
typedef ImportacaoProgressCallback = void Function(
    int linhaAtual, int total, ImportacaoLogEntry entry);

/// Excecao de negocio lancada durante o processamento de uma linha (validacao
/// obrigatoria ausente, FK nao resolvida, HTTP com erro etc.). Capturada por linha em
/// `importar(...)` — nao interrompe as linhas seguintes.
class ImportacaoCadastroException implements Exception {
  final String mensagem;
  const ImportacaoCadastroException(this.mensagem);
  @override
  String toString() => mensagem;
}

class ImportacaoCadastrosService {
  // Nome publico do parametro (`networkCaller`) precisa divergir do campo
  // privado (`_networkCaller`) — initializing formal nao se aplica aqui.
  ImportacaoCadastrosService({required NetworkCaller networkCaller})
      : _networkCaller = networkCaller; // ignore: prefer_initializing_formals

  final NetworkCaller _networkCaller;

  /// Configuracao dos 5 tipos importaveis, portada verbatim (campos + sinonimos) de
  /// `_ImportacaoCadastrosSectionState._configs` no arquivo original.
  static const List<CadastroImportConfig> configs = [
    CadastroImportConfig(
      tipo: ImportacaoCadastroTipo.empresa,
      title: 'Importar Empresas',
      subtitle: 'Cria ou atualiza empresas a partir do CSV.',
      campos: [
        CadastroImportField(
            'external_id', 'External ID', ['external_id', 'codigo', 'cod_empresa']),
        CadastroImportField(
            'nome', 'Nome Fantasia *', ['nome', 'nome_fantasia', 'fantasia', 'empresa']),
        CadastroImportField(
            'razaoSocial', 'Razao Social', ['razao_social', 'razaosocial', 'razo_social']),
        CadastroImportField('cnpj', 'CNPJ', ['cnpj', 'cpf_cnpj', 'documento']),
        CadastroImportField('email', 'Email', ['email', 'e_mail']),
        CadastroImportField('telefone', 'Telefone', ['telefone', 'fone', 'celular']),
        CadastroImportField('rua', 'Rua', ['rua', 'logradouro', 'endereco']),
        CadastroImportField('numero', 'Numero', ['numero', 'nro', 'num']),
        CadastroImportField('bairro', 'Bairro', ['bairro']),
        CadastroImportField('cidade', 'Cidade', ['cidade', 'municipio']),
        CadastroImportField('estado', 'Estado', ['estado', 'uf']),
        CadastroImportField('cep', 'CEP', ['cep']),
        CadastroImportField('regime_codigo', 'Regime',
            ['regime_codigo', 'regime', 'regime_tributario', 'tributacao']),
        CadastroImportField('ambiente', 'Ambiente', ['ambiente', 'sefaz_ambiente']),
        CadastroImportField(
            'app_id', 'App ID', ['app_id', 'aplicativo_id', 'aplicativo']),
      ],
    ),
    CadastroImportConfig(
      tipo: ImportacaoCadastroTipo.parceiros,
      title: 'Importar Parceiros',
      subtitle:
          'Importa clientes, fornecedores ou parceiros vinculados a empresa selecionada.',
      campos: [
        CadastroImportField(
            'external_id', 'External ID', ['external_id', 'codigo', 'cod_parceiro']),
        CadastroImportField('empresa_id', 'Empresa ID',
            ['empresa_id', 'empresa_external_id', 'cod_empresa', 'id_empresa']),
        CadastroImportField(
            'nome', 'Nome *', ['nome', 'cliente', 'parceiro', 'nome_fantasia']),
        CadastroImportField(
            'razaoSocial', 'Razao Social', ['razao_social', 'razaosocial', 'razo_social']),
        CadastroImportField(
            'cpf', 'CPF/CNPJ', ['cpf', 'cnpj', 'cpf_cnpj', 'documento']),
        CadastroImportField('codProdutor', 'Codigo Produtor',
            ['cod_produtor', 'codprodutor', 'codigo_produtor']),
        CadastroImportField('email', 'Email', ['email', 'e_mail']),
        CadastroImportField(
            'telefone1', 'Telefone', ['telefone', 'telefone1', 'fone', 'celular']),
        CadastroImportField('rua', 'Rua', ['rua', 'logradouro', 'endereco']),
        CadastroImportField('bairro', 'Bairro', ['bairro']),
        CadastroImportField('cidade', 'Cidade', ['cidade', 'municipio']),
        CadastroImportField('estado', 'Estado', ['estado', 'uf']),
        CadastroImportField('cep', 'CEP', ['cep']),
        CadastroImportField('numero', 'Numero', ['numero', 'nro', 'num']),
        CadastroImportField('ie', 'IE', ['ie', 'inscricao_estadual']),
        CadastroImportField(
            'incrMun', 'Insc. Municipal', ['incr_mun', 'inscricao_municipal', 'im']),
        CadastroImportField('regime_codigo', 'Regime',
            ['regime_codigo', 'regime', 'regime_tributario', 'tributacao']),
        CadastroImportField('status', 'Status', ['status', 'situacao']),
        CadastroImportField(
            'tipoCliente', 'Tipo Cliente', ['tipo_cliente', 'tipo', 'classificacao']),
        CadastroImportField('tipo_parceiro_id', 'Tipo Parceiro ID',
            ['tipo_parceiro_id', 'tipo_parceiro', 'tipoParceiro', 'perfil']),
        CadastroImportField(
            'valorMensal', 'Valor Mensal', ['valor_mensal', 'mensalidade', 'valor']),
      ],
    ),
    CadastroImportConfig(
      tipo: ImportacaoCadastroTipo.funcionarios,
      title: 'Importar Funcionarios e Logins',
      subtitle: 'Cria login, funcionario e vincula o funcionario ao login criado.',
      campos: [
        CadastroImportField('empresa_id', 'Empresa ID',
            ['empresa_id', 'empresa_external_id', 'cod_empresa', 'id_empresa']),
        CadastroImportField('nome', 'Nome *', ['nome', 'funcionario', 'colaborador']),
        CadastroImportField('cpf', 'CPF *', ['cpf', 'cpf_cnpj', 'documento']),
        CadastroImportField(
            'email', 'Email/Login *', ['email', 'login', 'usuario', 'e_mail']),
        CadastroImportField('setor', 'Setor', ['setor', 'departamento', 'area']),
        CadastroImportField(
            'tipoLogin', 'Tipo Login', ['tipo_login', 'tipologin', 'perfil']),
        CadastroImportField(
            'senha', 'Senha Padrao', ['senha', 'senha_padrao', 'password']),
        CadastroImportField('ativo', 'Ativo', ['ativo', 'status', 'situacao']),
      ],
    ),
    CadastroImportConfig(
      tipo: ImportacaoCadastroTipo.loginsClientes,
      title: 'Importar Logins de Clientes',
      subtitle: 'Cria ou atualiza logins de clientes vinculando pelo CNPJ do parceiro.',
      campos: [
        CadastroImportField(
            'external_id', 'External ID', ['external_id', 'codigo', 'cod_parceiro']),
        CadastroImportField('empresa_id', 'Empresa ID',
            ['empresa_id', 'empresa_external_id', 'cod_empresa', 'id_empresa']),
        CadastroImportField('parceiro_cnpj', 'CNPJ Cliente *',
            ['parceiro_cnpj', 'codigo_cliente', 'cnpj', 'cpf', 'documento']),
        CadastroImportField('codigo_faturamento', 'Codigo Faturamento',
            ['codigo_faturamento', 'cod_faturamento']),
        CadastroImportField(
            'nome', 'Nome *', ['nome', 'cliente', 'parceiro', 'razao_social']),
        CadastroImportField(
            'email', 'Email/Login *', ['email', 'login', 'usuario', 'e_mail']),
        CadastroImportField(
            'senha', 'Senha Padrao', ['senha', 'senha_padrao', 'password']),
        CadastroImportField(
            'tipoLogin', 'Tipo Login', ['tipo_login', 'tipologin', 'perfil']),
        CadastroImportField(
            'app_id', 'App ID', ['app_id', 'aplicativo_id', 'aplicativo']),
      ],
    ),
    CadastroImportConfig(
      tipo: ImportacaoCadastroTipo.planos,
      title: 'Importar Planos',
      subtitle: 'Importa planos comuns ou planos da academia conforme a coluna tipo_plano.',
      campos: [
        CadastroImportField('empresa_id', 'Empresa ID',
            ['empresa_id', 'empresa_external_id', 'cod_empresa', 'id_empresa']),
        CadastroImportField(
            'parceiro_id', 'Parceiro ID', ['parceiro_id', 'cliente_id']),
        CadastroImportField('cnpj', 'CNPJ Cliente',
            ['cnpj', 'cpf_cnpj', 'documento', 'cpf', 'cod_produtor']),
        CadastroImportField('codigo_faturamento', 'Codigo Faturamento',
            ['codigo_faturamento', 'cod_faturamento', 'codigo']),
        CadastroImportField('nome_cliente', 'Cliente',
            ['nome_faturamento', 'cliente', 'parceiro', 'razao_social']),
        CadastroImportField('nome', 'Nome *',
            ['nome', 'plano', 'nome_plano', 'servico', 'nome_faturamento']),
        CadastroImportField('descricao', 'Descricao', ['descricao', 'description']),
        CadastroImportField(
            'valor', 'Valor', ['valor', 'valor_mensal', 'preco', 'mensalidade']),
        CadastroImportField(
            'dt_inicio', 'Data Inicio', ['dt_inicio', 'data_inicio', 'inicio']),
        CadastroImportField('dt_final', 'Data Final', ['dt_final', 'data_final', 'fim']),
        CadastroImportField(
            'qtd_aula', 'Qtd. Aula', ['qtd_aula', 'qtd_aulas', 'aulas']),
        CadastroImportField(
            'cod_personal', 'Cod. Personal', ['cod_personal', 'personal_id']),
        CadastroImportField(
            'cod_academia', 'Cod. Academia', ['cod_academia', 'academia_id']),
        CadastroImportField(
            'tipo_plano', 'Tipo Plano', ['tipo_plano', 'tipo', 'origem']),
      ],
    ),
  ];

  static CadastroImportConfig _config(ImportacaoCadastroTipo tipo) =>
      configs.firstWhere((c) => c.tipo == tipo);

  /// Processa todas as linhas do CSV para o [tipo] informado. Cada linha e'
  /// processada de forma independente: uma falha e' registrada como `erro` no
  /// resultado, sem interromper as linhas seguintes. Linhas totalmente vazias sao
  /// registradas como `ignorado`.
  Future<ImportacaoResultado> importar({
    required ImportacaoCadastroTipo tipo,
    required List<Map<String, String>> rows,
    Map<String, String> mapeamentoColunas = const {},
    String? empresaIdSelecionada,
    String? parceiroIdSelecionado,
    bool atualizar = false,
    ImportacaoProgressCallback? onProgress,
  }) async {
    final total = rows.length;
    var sucesso = 0;
    var erros = 0;
    var ignorados = 0;
    final detalhes = <ImportacaoLogEntry>[];

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      // Linha 1 do arquivo e' o cabecalho — linha de dados N corresponde a (N+2)
      // na numeracao "humana" do arquivo original (mesma convencao do port).
      final linha = i + 2;
      ImportacaoLogEntry entry;
      try {
        if (_linhaVazia(row)) {
          ignorados++;
          entry = ImportacaoLogEntry(linha: linha, status: 'ignorado', mensagem: 'Linha vazia');
        } else {
          final id = await _importarLinha(
            tipo,
            row,
            mapeamentoColunas: mapeamentoColunas,
            empresaIdSelecionada: empresaIdSelecionada,
            parceiroIdSelecionado: parceiroIdSelecionado,
            atualizar: atualizar,
          );
          sucesso++;
          entry = ImportacaoLogEntry(
            linha: linha,
            status: 'sucesso',
            mensagem: id != null ? 'Registro salvo com ID $id' : 'Registro salvo',
          );
        }
      } catch (e) {
        erros++;
        entry = ImportacaoLogEntry(linha: linha, status: 'erro', mensagem: e.toString());
      }
      detalhes.add(entry);
      onProgress?.call(i + 1, total, entry);
    }

    return ImportacaoResultado(
      total: total,
      sucesso: sucesso,
      erros: erros,
      ignorados: ignorados,
      detalhes: detalhes,
    );
  }

  Future<int?> _importarLinha(
    ImportacaoCadastroTipo tipo,
    Map<String, String> row, {
    required Map<String, String> mapeamentoColunas,
    required String? empresaIdSelecionada,
    required String? parceiroIdSelecionado,
    required bool atualizar,
  }) {
    switch (tipo) {
      case ImportacaoCadastroTipo.empresa:
        return _importarEmpresa(row, mapeamentoColunas, atualizar);
      case ImportacaoCadastroTipo.parceiros:
        return _importarParceiro(row, mapeamentoColunas, empresaIdSelecionada, atualizar);
      case ImportacaoCadastroTipo.funcionarios:
        return _importarFuncionarioLogin(
            row, mapeamentoColunas, empresaIdSelecionada, atualizar);
      case ImportacaoCadastroTipo.loginsClientes:
        return _importarLoginCliente(
            row, mapeamentoColunas, empresaIdSelecionada, parceiroIdSelecionado, atualizar);
      case ImportacaoCadastroTipo.planos:
        return _importarPlano(
            row, mapeamentoColunas, empresaIdSelecionada, parceiroIdSelecionado, atualizar);
    }
  }

  // ---------------------------------------------------------------------------
  // Empresa — dedup por CNPJ (ou nome, se "Atualizar" ligado e sem CNPJ na linha).
  // ---------------------------------------------------------------------------

  Future<int?> _importarEmpresa(
      Map<String, String> row, Map<String, String> mapeamento, bool atualizar) async {
    const tipo = ImportacaoCadastroTipo.empresa;
    final nome = _valor(row, tipo, 'nome', mapeamento);
    if (nome.isEmpty) throw const ImportacaoCadastroException('Nome fantasia obrigatorio');

    final cnpj = _digits(_valor(row, tipo, 'cnpj', mapeamento));
    final regimeId = _regimeId(_valor(row, tipo, 'regime_codigo', mapeamento));
    final appId = _toInt(_valor(row, tipo, 'app_id', mapeamento)) ?? 1;

    final createPayload = _compact({
      'nome': nome,
      'razaoSocial': _valor(row, tipo, 'razaoSocial', mapeamento),
      'email': _valor(row, tipo, 'email', mapeamento),
      'telefone': _valor(row, tipo, 'telefone', mapeamento),
      'rua': _valor(row, tipo, 'rua', mapeamento),
      'numero': _valor(row, tipo, 'numero', mapeamento),
      'cep': _digits(_valor(row, tipo, 'cep', mapeamento)),
      'centroCustoObrigatorio': false,
    });

    final updatePayload = _compact({
      'nome': nome,
      'razaoSocial': _valor(row, tipo, 'razaoSocial', mapeamento),
      'cnpj': cnpj,
      'email': _valor(row, tipo, 'email', mapeamento),
      'telefone': _valor(row, tipo, 'telefone', mapeamento),
      'rua': _valor(row, tipo, 'rua', mapeamento),
      'numero': _valor(row, tipo, 'numero', mapeamento),
      'bairro': _valor(row, tipo, 'bairro', mapeamento),
      'cep': _digits(_valor(row, tipo, 'cep', mapeamento)),
      'ambiente': _ambiente(_valor(row, tipo, 'ambiente', mapeamento)),
      'regime': regimeId != null ? {'id': regimeId} : null,
      'aplicativo': {'id': appId},
      'centroCustoObrigatorio': false,
    });

    final buscaUrl = ApiLinks.allEmpresasByAplicativo(appId.toString());
    final existentePorCnpj =
        cnpj.isNotEmpty ? await _buscarExistente(buscaUrl, 'cnpj', cnpj) : null;
    if (existentePorCnpj != null && !atualizar) {
      throw ImportacaoCadastroException(
          'CNPJ $cnpj ja existe no cadastro de empresas. Ative "Atualizar se existir" para atualizar.');
    }
    final existente = existentePorCnpj ??
        (atualizar ? await _buscarExistente(buscaUrl, 'nome', nome) : null);

    if (existente != null) {
      await _put(ApiLinks.updateEmpresa(existente.toString()), {'id': existente, ...updatePayload});
      return existente;
    }

    final body = await _post(ApiLinks.createEmpresa, createPayload);
    final id = _extractId(body);
    if (id == null) {
      throw const ImportacaoCadastroException(
          'Empresa salva, mas a API nao retornou o ID para atualizar e selecionar o destino.');
    }
    await _put(ApiLinks.updateEmpresa(id.toString()), {'id': id, ...updatePayload});
    return id;
  }

  // ---------------------------------------------------------------------------
  // Parceiro — dedup por CPF/CNPJ (ou codProdutor), depois nome, dentro da empresa.
  // ---------------------------------------------------------------------------

  Future<int?> _importarParceiro(Map<String, String> row, Map<String, String> mapeamento,
      String? empresaIdSelecionada, bool atualizar) async {
    const tipo = ImportacaoCadastroTipo.parceiros;
    final nome = _valor(row, tipo, 'nome', mapeamento);
    if (nome.isEmpty) throw const ImportacaoCadastroException('Nome do parceiro obrigatorio');

    final empresaId = _empresaId(row, tipo, mapeamento, empresaIdSelecionada);
    if (empresaId == null) {
      throw const ImportacaoCadastroException(
          'Selecione a empresa destino ou informe empresa_id no CSV');
    }

    final documento = _digits(_valor(row, tipo, 'cpf', mapeamento));
    final codProdutor = _valor(row, tipo, 'codProdutor', mapeamento);
    final documentoDuplicidade = documento.isNotEmpty ? documento : _digits(codProdutor);
    final tipoParceiroId = _toInt(_valor(row, tipo, 'tipo_parceiro_id', mapeamento)) ?? 1;
    final regimeId = _regimeId(_valor(row, tipo, 'regime_codigo', mapeamento));
    final status = _status(_valor(row, tipo, 'status', mapeamento));

    final payload = _compact({
      'nome': nome,
      'cpf': documento,
      'codProdutor': codProdutor,
      'email': _valor(row, tipo, 'email', mapeamento),
      'telefone1': _valor(row, tipo, 'telefone1', mapeamento),
      'razao_social': _valor(row, tipo, 'razaoSocial', mapeamento),
      'incr_mun': _valor(row, tipo, 'incrMun', mapeamento),
      'ie': _valor(row, tipo, 'ie', mapeamento),
      'rua': _valor(row, tipo, 'rua', mapeamento),
      'bairro': _valor(row, tipo, 'bairro', mapeamento),
      'cidade': _valor(row, tipo, 'cidade', mapeamento),
      'estado': _valor(row, tipo, 'estado', mapeamento),
      'cep': _digits(_valor(row, tipo, 'cep', mapeamento)),
      'numero': _valor(row, tipo, 'numero', mapeamento),
      'status': status,
      'tipo_cliente': _valor(row, tipo, 'tipoCliente', mapeamento).isNotEmpty
          ? _valor(row, tipo, 'tipoCliente', mapeamento)
          : 'CLIENTE',
      'empresa': {'id': empresaId},
      'regime': regimeId != null ? {'id': regimeId} : null,
      'tipos_parceiro': [
        {'id': tipoParceiroId}
      ],
      'valor_mensal': _money(_valor(row, tipo, 'valorMensal', mapeamento)),
    });

    final buscaUrl = ApiLinks.parceirosByEmpresa(empresaId.toString());
    final existentePorDocumento = documentoDuplicidade.isNotEmpty
        ? await _buscarExistente(
            buscaUrl, documento.isNotEmpty ? 'cpf' : 'codProdutor', documentoDuplicidade)
        : null;
    if (existentePorDocumento != null && !atualizar) {
      throw ImportacaoCadastroException(
          'CPF/CNPJ $documentoDuplicidade ja existe para a empresa destino. Ative "Atualizar se existir" para atualizar.');
    }
    final existente = existentePorDocumento ??
        (atualizar ? await _buscarExistente(buscaUrl, 'nome', nome) : null);

    if (existente != null) {
      await _put(ApiLinks.updateParceiro(existente.toString()), {'id': existente, ...payload});
      return existente;
    }

    final body = await _post(ApiLinks.insertParceiro, payload);
    return _extractId(body);
  }

  // ---------------------------------------------------------------------------
  // Funcionario + Login — dedup de login por e-mail, funcionario por CPF.
  // ---------------------------------------------------------------------------

  Future<int?> _importarFuncionarioLogin(Map<String, String> row, Map<String, String> mapeamento,
      String? empresaIdSelecionada, bool atualizar) async {
    const tipo = ImportacaoCadastroTipo.funcionarios;
    final nome = _valor(row, tipo, 'nome', mapeamento);
    final email = _valor(row, tipo, 'email', mapeamento);
    final cpf = _digits(_valor(row, tipo, 'cpf', mapeamento));
    if (nome.isEmpty) throw const ImportacaoCadastroException('Nome do funcionario obrigatorio');
    if (email.isEmpty) throw const ImportacaoCadastroException('Email/login obrigatorio');
    if (cpf.isEmpty) throw const ImportacaoCadastroException('CPF obrigatorio');

    final empresaId = _empresaId(row, tipo, mapeamento, empresaIdSelecionada);
    if (empresaId == null) {
      throw const ImportacaoCadastroException(
          'Selecione a empresa destino ou informe empresa_id no CSV');
    }

    final tipoLogin = _valor(row, tipo, 'tipoLogin', mapeamento).isNotEmpty
        ? _valor(row, tipo, 'tipoLogin', mapeamento)
        : 'APP_ABRACO';
    final senha = _valor(row, tipo, 'senha', mapeamento).isNotEmpty
        ? _valor(row, tipo, 'senha', mapeamento)
        : '123456';
    final ativo = _boolOrNull(_valor(row, tipo, 'ativo', mapeamento)) ?? true;

    final loginPayload = _compact({
      'email': email,
      'senha': senha,
      'nome': nome,
      'cpfCnpj': cpf,
      'tipoLogin': tipoLogin,
      'empresa': {'id': empresaId},
      'aplicativo': {'id': 1},
    });

    var loginId = atualizar
        ? await _buscarExistente(ApiLinks.loginsByEmpresa(empresaId.toString()), 'email', email)
        : null;
    if (loginId != null) {
      await _put(ApiLinks.updateLoginCadastro(loginId.toString()), loginPayload);
    } else {
      loginId = _extractId(await _post(ApiLinks.createLoginCadastro, loginPayload));
    }

    final funcionarioPayload = _compact({
      'nome': nome,
      'cpf': cpf,
      'email': email,
      'status': 'A',
      'tipoCliente': 'FUNCIONARIO',
      'ativo': ativo,
      'observacao': _valor(row, tipo, 'setor', mapeamento),
      'empresa': {'id': empresaId},
      'login': loginId != null ? {'id': loginId} : null,
    });

    var funcionarioId = atualizar
        ? await _buscarExistente(
            ApiLinks.funcionariosByEmpresa(empresaId.toString()), 'cpf', cpf)
        : null;
    if (funcionarioId != null) {
      await _put(ApiLinks.updateFuncionario(funcionarioId.toString()),
          {'id': funcionarioId, ...funcionarioPayload});
    } else {
      funcionarioId = _extractId(await _post(ApiLinks.createFuncionario, funcionarioPayload));
    }

    return funcionarioId ?? loginId;
  }

  // ---------------------------------------------------------------------------
  // Login de cliente — vincula pelo CNPJ/CPF do parceiro ja existente na empresa.
  // ---------------------------------------------------------------------------

  Future<int?> _importarLoginCliente(
      Map<String, String> row,
      Map<String, String> mapeamento,
      String? empresaIdSelecionada,
      String? parceiroIdSelecionado,
      bool atualizar) async {
    const tipo = ImportacaoCadastroTipo.loginsClientes;
    final nome = _valor(row, tipo, 'nome', mapeamento);
    final email = _valor(row, tipo, 'email', mapeamento).trim().toLowerCase();
    final documento = _digits(_valor(row, tipo, 'parceiro_cnpj', mapeamento));
    if (nome.isEmpty) throw const ImportacaoCadastroException('Nome do cliente obrigatorio');
    if (email.isEmpty) throw const ImportacaoCadastroException('Email/login obrigatorio');
    if (documento.isEmpty) {
      throw const ImportacaoCadastroException('CNPJ/CPF do cliente obrigatorio');
    }

    final empresaId = _empresaId(row, tipo, mapeamento, empresaIdSelecionada);
    if (empresaId == null) {
      throw const ImportacaoCadastroException(
          'Selecione a empresa destino ou informe empresa_id no CSV');
    }

    final parceiros = await _listarParceirosEmpresa(empresaId);
    final parceiro = _buscarParceiroNaLista(parceiros, documento: documento);
    if (parceiro == null) {
      final codigo = _valor(row, tipo, 'codigo_faturamento', mapeamento);
      throw ImportacaoCadastroException(codigo.isNotEmpty
          ? 'Cliente CNPJ $documento nao encontrado para codigo $codigo'
          : 'Cliente CNPJ $documento nao encontrado na empresa destino');
    }

    final senha = _valor(row, tipo, 'senha', mapeamento).isNotEmpty
        ? _valor(row, tipo, 'senha', mapeamento)
        : '123456';
    final tipoLogin = _valor(row, tipo, 'tipoLogin', mapeamento).isNotEmpty
        ? _valor(row, tipo, 'tipoLogin', mapeamento)
        : 'APP_ABRACO';
    final appId = _toInt(_valor(row, tipo, 'app_id', mapeamento)) ?? 1;

    final payload = _compact({
      'email': email,
      'senha': senha,
      'nome': nome,
      'cpfCnpj': documento,
      'tipoLogin': tipoLogin,
      'empresa': {'id': empresaId},
      'parceiro': {'id': _extractId(parceiro)},
      'aplicativo': {'id': appId},
      'ativo': true,
      'trocarSenhaProximoLogin': false,
    });

    final loginExistente =
        await _buscarExistente(ApiLinks.loginsByEmpresa(empresaId.toString()), 'email', email);
    if (loginExistente != null && !atualizar) {
      throw ImportacaoCadastroException(
          'Email $email ja existe. Ative "Atualizar se existir" para atualizar.');
    }
    if (loginExistente != null) {
      await _put(ApiLinks.updateLoginCadastro(loginExistente.toString()), payload);
      return loginExistente;
    }

    final body = await _post(ApiLinks.createLoginCadastro, payload);
    return _extractId(body);
  }

  // ---------------------------------------------------------------------------
  // Plano — ou plano comum/academia, ou (heuristica _isFaturamentoServico) um
  // servico contratado de faturamento avulso vinculado a um parceiro existente.
  // ---------------------------------------------------------------------------

  Future<int?> _importarPlano(
      Map<String, String> row,
      Map<String, String> mapeamento,
      String? empresaIdSelecionada,
      String? parceiroIdSelecionado,
      bool atualizar) async {
    if (_isFaturamentoServico(row)) {
      return _importarServicoContratadoFaturamento(
          row, mapeamento, empresaIdSelecionada, parceiroIdSelecionado, atualizar);
    }

    const tipo = ImportacaoCadastroTipo.planos;
    final nome = _valor(row, tipo, 'nome', mapeamento);
    if (nome.isEmpty) throw const ImportacaoCadastroException('Nome do plano obrigatorio');

    final academia = _isPlanoAcademia(row, mapeamento);
    final allEndpoint = academia ? ApiLinks.allPlanosAcademia : ApiLinks.allPlanos;
    final createEndpoint = academia ? ApiLinks.createPlanoAcademia : ApiLinks.createPlano;
    final updateEndpoint = academia ? ApiLinks.updatePlanoAcademia : ApiLinks.updatePlano;

    final payload = _compact({
      'nome': nome,
      'descricao': _valor(row, tipo, 'descricao', mapeamento),
      'valor': _money(_valor(row, tipo, 'valor', mapeamento)),
      'dt_inicio': _dateOrNull(_valor(row, tipo, 'dt_inicio', mapeamento)),
      'dt_final': _dateOrNull(_valor(row, tipo, 'dt_final', mapeamento)),
      'qtd_aula': academia ? null : _toInt(_valor(row, tipo, 'qtd_aula', mapeamento)),
      'cod_personal': academia ? null : _toInt(_valor(row, tipo, 'cod_personal', mapeamento)),
      'cod_academia': academia ? _toInt(_valor(row, tipo, 'cod_academia', mapeamento)) : null,
    });

    final existente = atualizar ? await _buscarExistente(allEndpoint, 'nome', nome) : null;
    if (existente != null) {
      await _put(updateEndpoint(existente.toString()), {'id': existente, ...payload});
      return existente;
    }

    final body = await _post(createEndpoint, payload);
    return _extractId(body);
  }

  Future<int?> _importarServicoContratadoFaturamento(
      Map<String, String> row,
      Map<String, String> mapeamento,
      String? empresaIdSelecionada,
      String? parceiroIdSelecionado,
      bool atualizar) async {
    const tipo = ImportacaoCadastroTipo.planos;
    final empresaId = _empresaId(row, tipo, mapeamento, empresaIdSelecionada);
    if (empresaId == null) throw const ImportacaoCadastroException('Empresa destino obrigatoria');

    final parceiro = await _resolverParceiroFaturamento(
        row, mapeamento, empresaId, parceiroIdSelecionado);
    final parceiroId = _extractId(parceiro);
    if (parceiroId == null) {
      throw const ImportacaoCadastroException('Cliente/parceiro do faturamento nao encontrado');
    }

    final cliente = _nomeClienteFaturamento(row, mapeamento, parceiro);
    final nome = _nomeServicoFaturamento(row, mapeamento, cliente);
    final valor = _money(_valor(row, tipo, 'valor', mapeamento));
    final descricao = _valor(row, tipo, 'descricao', mapeamento);
    final codigoFaturamento = _valor(row, tipo, 'codigo_faturamento', mapeamento);
    final documento = _documentoParceiro(parceiro);

    final payload = _compact({
      'nome': nome,
      'descricao': descricao.isNotEmpty
          ? descricao
          : [
              if (codigoFaturamento.isNotEmpty) 'Codigo faturamento $codigoFaturamento',
              if (documento.isNotEmpty) 'CNPJ/CPF $documento',
            ].join(' - '),
      'valor': valor,
      'empresa': {'id': empresaId},
      'parceiro': {'id': parceiroId},
    });

    final existente = await _buscarServicoContratadoExistente(empresaId, parceiroId);
    if (existente != null) {
      if (!atualizar) {
        throw const ImportacaoCadastroException(
            'Plano/servico ja existe para este cliente nesta empresa');
      }
      await _put(
          ApiLinks.updateServicoContratado(existente.toString()), {'id': existente, ...payload});
      return existente;
    }

    final body = await _post(ApiLinks.createServicoContratado, payload);
    return _extractId(body);
  }

  bool _isFaturamentoServico(Map<String, String> row) =>
      _temColuna(row, 'codigo_faturamento') ||
      _temColuna(row, 'nome_faturamento') ||
      _temColuna(row, 'valor_mensal');

  bool _temColuna(Map<String, String> row, String coluna) {
    final alvo = _normalizar(coluna);
    return row.keys.any((key) => _normalizar(key) == alvo);
  }

  Future<Map<String, dynamic>?> _resolverParceiroFaturamento(Map<String, String> row,
      Map<String, String> mapeamento, int empresaId, String? parceiroIdSelecionado) async {
    const tipo = ImportacaoCadastroTipo.planos;
    final parceiroId = _toInt(_valor(row, tipo, 'parceiro_id', mapeamento)) ??
        _toInt(parceiroIdSelecionado ?? '');
    final documento = _digits(_valor(row, tipo, 'cnpj', mapeamento));
    final nomeCliente = _valor(row, tipo, 'nome_cliente', mapeamento);
    final parceiros = await _listarParceirosEmpresa(empresaId);

    if (parceiroId != null) {
      final porId = _buscarParceiroNaLista(parceiros, id: parceiroId);
      if (porId != null) return porId;
    }
    if (documento.isNotEmpty) {
      final porDocumento = _buscarParceiroNaLista(parceiros, documento: documento);
      if (porDocumento != null) return porDocumento;
      throw ImportacaoCadastroException(
          'Cliente/parceiro com CNPJ/CPF $documento nao encontrado na empresa destino');
    }
    if (nomeCliente.isNotEmpty) {
      final porNome = _buscarParceiroNaLista(parceiros, nome: nomeCliente);
      if (porNome != null) return porNome;
    }

    final codigo = _valor(row, tipo, 'codigo_faturamento', mapeamento);
    throw ImportacaoCadastroException(codigo.isNotEmpty
        ? 'Faturamento $codigo sem CNPJ no CSV e cliente nao localizado por nome'
        : 'Informe CNPJ/CPF, Parceiro ID ou nome do cliente para vincular o plano');
  }

  Future<List<Map<String, dynamic>>> _listarParceirosEmpresa(int empresaId) async {
    final body = await _get(ApiLinks.parceirosByEmpresa(empresaId.toString()));
    if (body == null) return [];
    return _extractList(body);
  }

  Map<String, dynamic>? _buscarParceiroNaLista(
    List<Map<String, dynamic>> parceiros, {
    int? id,
    String? documento,
    String? nome,
  }) {
    final documentoDigits = _digits(documento ?? '');
    final nomeNorm = _normalizar(nome ?? '');
    for (final parceiro in parceiros) {
      if (id != null && _extractId(parceiro) == id) return parceiro;
      if (documentoDigits.isNotEmpty) {
        final cpf = _digits(parceiro['cpf']?.toString() ?? '');
        final codProdutor = _digits(parceiro['codProdutor']?.toString() ?? '');
        if (cpf == documentoDigits || codProdutor == documentoDigits) return parceiro;
      }
      if (nomeNorm.isNotEmpty) {
        final nomes = [
          parceiro['nome']?.toString() ?? '',
          parceiro['razaoSocial']?.toString() ?? '',
        ].map(_normalizar);
        if (nomes.any((n) => n == nomeNorm)) return parceiro;
      }
    }
    return null;
  }

  Future<int?> _buscarServicoContratadoExistente(int empresaId, int parceiroId) async {
    final body = await _get(ApiLinks.servicosContratados);
    if (body == null) return null;
    final lista = _extractList(body);
    for (final item in lista) {
      final itemEmpresaId = _extractRelatedId(item['empresa']);
      final itemParceiroId = _extractRelatedId(item['parceiro']);
      if (itemEmpresaId == empresaId && itemParceiroId == parceiroId) {
        return _extractId(item);
      }
    }
    return null;
  }

  int? _extractRelatedId(dynamic value) {
    if (value is Map) return _extractId(Map<String, dynamic>.from(value));
    return _toInt(value?.toString() ?? '');
  }

  String _nomeClienteFaturamento(
      Map<String, String> row, Map<String, String> mapeamento, Map<String, dynamic>? parceiro) {
    final csv = _valor(row, ImportacaoCadastroTipo.planos, 'nome_cliente', mapeamento);
    if (csv.isNotEmpty) return csv;
    return parceiro?['nome']?.toString() ?? parceiro?['razaoSocial']?.toString() ?? '';
  }

  String _nomeServicoFaturamento(
      Map<String, String> row, Map<String, String> mapeamento, String cliente) {
    final nome = _valor(row, ImportacaoCadastroTipo.planos, 'nome', mapeamento);
    if (nome.isNotEmpty && !_temColuna(row, 'nome_faturamento')) return nome;
    if (cliente.isNotEmpty) return 'Mensalidade - $cliente';
    final codigo = _valor(row, ImportacaoCadastroTipo.planos, 'codigo_faturamento', mapeamento);
    if (codigo.isNotEmpty) return 'Mensalidade - $codigo';
    throw const ImportacaoCadastroException('Nome do plano/servico obrigatorio');
  }

  String _documentoParceiro(Map<String, dynamic>? parceiro) {
    if (parceiro == null) return '';
    final cpf = _digits(parceiro['cpf']?.toString() ?? '');
    if (cpf.isNotEmpty) return cpf;
    return _digits(parceiro['codProdutor']?.toString() ?? '');
  }

  bool _isPlanoAcademia(Map<String, String> row, Map<String, String> mapeamento) {
    final tipoPlano =
        _normalizar(_valor(row, ImportacaoCadastroTipo.planos, 'tipo_plano', mapeamento));
    final codAcademia = _valor(row, ImportacaoCadastroTipo.planos, 'cod_academia', mapeamento);
    return tipoPlano.contains('academia') || codAcademia.trim().isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // Helpers de rede (via NetworkCaller — nunca `http` cru).
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>?> _get(String url) async {
    try {
      final resp = await _networkCaller.getRequest(url);
      if (!resp.isSuccess) return null;
      return resp.body;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _post(String url, Map<String, dynamic> body) async {
    final resp = await _networkCaller.postRequest(url, _compact(body));
    _ensureOk(resp, url);
    return resp.body;
  }

  Future<Map<String, dynamic>?> _put(String url, Map<String, dynamic> body) async {
    final resp = await _networkCaller.putRequest(url, _compact(body));
    _ensureOk(resp, url);
    return resp.body;
  }

  void _ensureOk(NetworkResponse resp, String url) {
    if (!resp.isSuccess) {
      throw ImportacaoCadastroException('HTTP ${resp.statusCode} em $url');
    }
  }

  Future<int?> _buscarExistente(String url, String campo, String valor) async {
    if (valor.trim().isEmpty) return null;
    final body = await _get(url);
    if (body == null) return null;
    final lista = _extractList(body);
    final valorDigits = _digits(valor);
    final valorNorm = _normalizar(valor);
    for (final item in lista) {
      final itemValor = item[campo]?.toString() ?? '';
      if (valorDigits.isNotEmpty && _digits(itemValor) == valorDigits) return _extractId(item);
      if (valorNorm.isNotEmpty && _normalizar(itemValor) == valorNorm) return _extractId(item);
    }
    return null;
  }

  List<Map<String, dynamic>> _extractList(Map<String, dynamic>? body) {
    dynamic data = body;
    if (data is Map && data['data'] != null) data = data['data'];
    if (data is Map && data['dados'] != null) data = data['dados'];
    if (data is Map && data['content'] != null) data = data['content'];
    if (data is List) {
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  int? _extractId(Map<String, dynamic>? body) {
    if (body == null) return null;
    for (final key in ['id', 'codigo', 'cod']) {
      final id = _toInt(body[key]?.toString() ?? '');
      if (id != null) return id;
    }
    for (final key in ['data', 'dados', 'login', 'parceiro']) {
      final nested = body[key];
      if (nested is Map) {
        final id = _extractId(Map<String, dynamic>.from(nested));
        if (id != null) return id;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Resolucao de valor de campo (mapeamento explicito -> sinonimo -> vazio) e
  // demais helpers puros, portados de `_ImportacaoCadastrosSectionState`.
  // ---------------------------------------------------------------------------

  String _valor(Map<String, String> row, ImportacaoCadastroTipo tipo, String campo,
      Map<String, String> mapeamento) {
    final coluna = mapeamento[campo]?.trim() ?? '';
    if (coluna.isNotEmpty && row.containsKey(coluna)) {
      return row[coluna]?.trim() ?? '';
    }

    final candidatos = <String>{coluna.isNotEmpty ? coluna : campo};
    final config = _config(tipo);
    for (final field in config.campos) {
      if (field.key == campo) {
        candidatos
          ..add(field.key)
          ..addAll(field.sinonimos);
        break;
      }
    }
    final alvos = candidatos.map(_normalizar).where((c) => c.isNotEmpty).toSet();
    for (final entry in row.entries) {
      if (alvos.contains(_normalizar(entry.key))) return entry.value.trim();
    }
    return '';
  }

  int? _empresaId(Map<String, String> row, ImportacaoCadastroTipo tipo,
      Map<String, String> mapeamento, String? empresaIdSelecionada) {
    return _toInt(_valor(row, tipo, 'empresa_id', mapeamento)) ??
        _toInt(empresaIdSelecionada ?? '') ??
        TenantContext.empresaId;
  }

  bool _linhaVazia(Map<String, String> row) => row.values.every((v) => v.trim().isEmpty);

  /// Remove chaves com valor `null`/vazio de um payload, recursivamente (incluindo
  /// Maps/Lists aninhados) — evita enviar campos em branco que sobrescreveriam dados
  /// existentes num update parcial.
  Map<String, dynamic> _compact(Map<String, dynamic> value) {
    final out = <String, dynamic>{};
    value.forEach((key, raw) {
      dynamic v = raw;
      if (v is Map<String, dynamic>) v = _compact(v);
      if (v is List) {
        v = v.map((e) => e is Map<String, dynamic> ? _compact(e) : e).where((e) {
          if (e == null) return false;
          if (e is String) return e.trim().isNotEmpty;
          if (e is Map) return e.isNotEmpty;
          return true;
        }).toList();
      }
      if (v == null) return;
      if (v is String && v.trim().isEmpty) return;
      if (v is Map && v.isEmpty) return;
      if (v is List && v.isEmpty) return;
      out[key] = v;
    });
    return out;
  }

  String _digits(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

  int? _toInt(String value) {
    final digits = _digits(value);
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  double? _money(String value) {
    var clean = value.trim();
    if (clean.isEmpty) return null;
    clean = clean.replaceAll(RegExp(r'[^0-9,.-]'), '');
    if (clean.contains(',') && clean.contains('.')) {
      clean = clean.replaceAll('.', '').replaceAll(',', '.');
    } else {
      clean = clean.replaceAll(',', '.');
    }
    return double.tryParse(clean);
  }

  bool? _boolOrNull(String value) {
    final v = _normalizar(value);
    if (['s', 'sim', 'true', '1', 'ativo', 'a'].contains(v)) return true;
    if (['n', 'nao', 'false', '0', 'inativo', 'i'].contains(v)) return false;
    return null;
  }

  String? _dateOrNull(String value) {
    final v = value.trim();
    if (v.isEmpty) return null;
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) return v;
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(v);
    if (m == null) return v;
    final d = m.group(1)!.padLeft(2, '0');
    final month = m.group(2)!.padLeft(2, '0');
    final y = m.group(3)!;
    return '$y-$month-$d';
  }

  int? _regimeId(String value) {
    final v = _normalizar(value);
    if (v.isEmpty) return null;
    if (v == '1' || v.contains('simples') || v == 'sn') return 1;
    if (v == '2' || v.contains('presumido') || v == 'lp') return 2;
    if (v == '3' || v.contains('real') || v == 'lr') return 3;
    return _toInt(value);
  }

  String? _status(String value) {
    final v = _normalizar(value);
    if (v.isEmpty) return null;
    if (['i', 'inativo', 'inativa', 'baixada'].contains(v)) return 'I';
    return 'A';
  }

  String? _ambiente(String value) {
    final v = _normalizar(value);
    if (v.isEmpty) return null;
    if (v.contains('prod')) return 'PRODUCAO';
    return 'HOMOLOGACAO';
  }

  /// Normalizacao de texto (minusculas, sem acento, sem espaco) usada para
  /// deteccao de sinonimo de coluna e comparacao de valores no dedup. Reescrita a
  /// partir do original com a tabela de acentos corrigida (o arquivo-fonte tinha um
  /// mapa de acentuacao corrompido por encoding — bug de origem, nao replicado
  /// aqui; ver Deviations do SUMMARY).
  String _normalizar(String value) {
    var r = value.toLowerCase().trim();
    const mapa = {
      'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    mapa.forEach((a, b) => r = r.replaceAll(a, b));
    return r.replaceAll(RegExp(r'\s+'), '_').replaceAll(RegExp(r'[^a-z0-9_]'), '');
  }
}
