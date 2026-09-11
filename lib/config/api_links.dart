/// Links de API do Painel do Dono (task_manager_admin_panel).
///
/// Reaproveita o MESMO backend/contrato JWT do app cliente
/// (task_manager_flutter/lib/config/api_links.dart) — mesmo host, mesmo
/// context-path, mesmo endpoint de login.
///
/// ATENCAO (incidente historico documentado no CLAUDE.md do workspace):
/// `_backendUrl`, `_backendContextPath` e `_windowsDownloadUrl` usam
/// `String.fromEnvironment(...)`, que SO funciona como const constructor.
/// Declarar como `final` compila mas quebra em RUNTIME no DDC (flutter run
/// debug web) com "Unsupported operation: String.fromEnvironment can only
/// be used as a const constructor" — isso ja quebrou login em producao por
/// 8 dias no app cliente (2026-08-13/21). Antes de qualquer find-replace de
/// modificador `const`->`final` neste arquivo, rodar
/// `grep -n ".fromEnvironment(" lib/config/api_links.dart` e manter esses
/// 3 campos como `const`.
class ApiLinks {
  ApiLinks._();

  static const String _backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://127.0.0.1:9001',
  );

  static const String _backendContextPath = String.fromEnvironment(
    'BACKEND_CONTEXT_PATH',
    defaultValue: '/boletobancos',
  );

  // URL publica do frontend web no Railway (deixar vazio desabilita o check).
  static const String frontendWebUrl = String.fromEnvironment(
    'FRONTEND_WEB_URL',
    defaultValue: '',
  );

  static final String _baseUrl = '$_backendUrl$_backendContextPath';

  static String get baseUrl => _baseUrl;

  // Endpoint de saude do backend (Spring Boot Actuator — exposto em prod).
  static String get backendHealth => '$_backendUrl/actuator/health';

  // Auth — mesmo endpoint do app cliente.
  static String get login => '$_baseUrl/rest/auth/login';

  // ===========================================================================
  // Fase 2 — Migracao do menu "Sistema" (RESEARCH.md/PLAN.md da fase). Todos os
  // getters abaixo sao declarados de uma vez (Task 01.2) como contrato para os
  // 13 planos seguintes, mesmo que consumidos so nas waves 2-4.
  // ===========================================================================


  // File operations
  static String uploadFile = '$_baseUrl/api/upload';
  static String downloadFile(String id) => '$_baseUrl/api/download/$id';

  // Sistema Logs e Monitoramento
  static String get sistemaLogs => '$_baseUrl/api/sistema-logs';
  static String get sistemaLogsMetricas => '$_baseUrl/api/sistema-logs/metricas';
  static String expurgarSistemaLogs(int dias) => '$_baseUrl/api/sistema-logs/expurgar?dias=$dias';

  // Tela Ajuda
  static String telaAjudaPorTela(String tela) => '$_baseUrl/api/tela-ajuda/tela/$tela';
  // SIS-01 Aplicativo
  static String get allAplicativos => '$_baseUrl/api/aplicativo';
  static String get allEmpresas => '$_baseUrl/api/empresa';
  static String get allParceiros => '$_baseUrl/api/parceiro';
  static String get allSetores => '$_baseUrl/api/setor';
  static String get createAplicativo => '$_baseUrl/api/aplicativo';
  static String updateAplicativo(String id) => '$_baseUrl/api/aplicativo/$id';
  static String deleteAplicativo(String id) => '$_baseUrl/api/aplicativo/$id';

  // SIS-02 Cadastro Empresa (wizard, sequencia empresa -> logins -> clientes ->
  // contas -> nfe -> chamados -> chat -> funcionarios; rollback LIFO via delete).
  static String get createEmpresa => '$_baseUrl/api/empresa';
  static String deleteEmpresa(String id) => '$_baseUrl/api/empresa/$id';
  static String get createLogin => '$_baseUrl/api/login';
  static String deleteLogin(String id) => '$_baseUrl/api/login/$id';
  static String get createParceiro => '$_baseUrl/api/parceiro';
  static String deleteParceiro(String id) => '$_baseUrl/api/parceiro/$id';
  static String get createContaPagar => '$_baseUrl/api/conta_pagar';
  static String deleteContaPagar(String id) => '$_baseUrl/api/conta_pagar/$id';
  static String get createContaReceber => '$_baseUrl/api/conta_receber';
  static String deleteContaReceber(String id) =>
      '$_baseUrl/api/conta_receber/$id';
  static String get createNfe => '$_baseUrl/api/nfe';
  static String deleteNfe(String id) => '$_baseUrl/api/nfe/$id';
  static String get createChamado => '$_baseUrl/api/chamados';
  static String deleteChamado(String id) => '$_baseUrl/api/chamados/$id';
  static String get createChat => '$_baseUrl/api/chat';
  static String deleteChat(String id) => '$_baseUrl/api/chat/$id';

  // Card cUlANCTt - importacao de arquivo SINTEGRA/SPED (EFD ICMS/IPI).
  static String get nfeImportacaoSintegra =>
      '$_baseUrl/api/nfe-import/importacao-sintegra';
  static String get nfeImportacaoSped =>
      '$_baseUrl/api/nfe-import/importacao-sped';
  // Pedido explicito do usuario: identificar o parceiro do arquivo (pelo
  // CNPJ) ANTES de processar, pra filtrar os combos de conta bancaria pelo
  // parceiro certo (nao todos da empresa).
  static String get nfeImportacaoSintegraIdentificarParceiro =>
      '$_baseUrl/api/nfe-import/importacao-sintegra/identificar-parceiro';
  static String get nfeImportacaoSpedIdentificarParceiro =>
      '$_baseUrl/api/nfe-import/importacao-sped/identificar-parceiro';

  // SIS-04 Importacao Cadastros (_ImportacaoCadastrosSection — contrato
  // DISTINTO do de SIS-02 acima: endpoints/verbos diferentes, nao reutilizar).
  static String allEmpresasByAplicativo(String codApp) =>
      '$_baseUrl/api/empresa?codApp=$codApp';
  static String parceirosByEmpresa(String empresaId) =>
      '$_baseUrl/api/parceiro/empresa/$empresaId';
  static String updateEmpresa(String id) => '$_baseUrl/api/empresa/update/$id';
  static String get insertParceiro => '$_baseUrl/api/parceiro/insert';
  static String updateParceiro(String id) =>
      '$_baseUrl/api/parceiro/update/$id';
  static String loginsByEmpresa(String empId) =>
      '$_baseUrl/api/logins?empId=$empId';
  static String get createLoginCadastro => '$_baseUrl/api/logins';

  // Controle de Sessao (bug de producao 2026-09-11): App do Dono >
  // Sistema > Sessoes -- listar/matar sessoes ativas.
  static String get sessoesAtivas => '$_baseUrl/api/sessoes';
  static String matarSessao(int loginId) => '$_baseUrl/api/sessoes/$loginId/matar';
  static String get matarTodasAsSessoes => '$_baseUrl/api/sessoes/matar-todas';
  static String get matarSessoesOciosas => '$_baseUrl/api/sessoes/matar-ociosas';
  static String updateLoginCadastro(String id) => '$_baseUrl/api/logins/$id';
  static String funcionariosByEmpresa(String empId) =>
      '$_baseUrl/api/funcionario?empId=$empId';
  static String get createFuncionario => '$_baseUrl/api/funcionario';
  static String updateFuncionario(String id) =>
      '$_baseUrl/api/funcionario/$id';
  static String get allPlanos => '$_baseUrl/api/planos';
  static String get allPlanosAcademia => '$_baseUrl/api/planos_academia';
  static String get createPlano => '$_baseUrl/api/planos';
  static String updatePlano(String id) => '$_baseUrl/api/planos/$id';
  static String get createPlanoAcademia => '$_baseUrl/api/planos_academia';
  static String updatePlanoAcademia(String id) =>
      '$_baseUrl/api/planos_academia/$id';
  static String get servicosContratados =>
      '$_baseUrl/api/servico-contratado?tamanho=10000';
  static String get createServicoContratado =>
      '$_baseUrl/api/servico-contratado';
  static String updateServicoContratado(String id) =>
      '$_baseUrl/api/servico-contratado/$id';

  // SIS-03 Configuracoes Admin (6 sub-CRUDs)
  static String get allCargos => '$_baseUrl/api/cargo';
  static String get createCargo => '$_baseUrl/api/cargo';
  static String updateCargo(String id) => '$_baseUrl/api/cargo/$id';
  static String deleteCargo(String id) => '$_baseUrl/api/cargo/$id';

  static String get allCentroCusto => '$_baseUrl/api/centro-custo';
  static String get createCentroCusto => '$_baseUrl/api/centro-custo';
  static String updateCentroCusto(String id) =>
      '$_baseUrl/api/centro-custo/$id';
  static String deleteCentroCusto(String id) =>
      '$_baseUrl/api/centro-custo/$id';

  static String get allDepartamento => '$_baseUrl/api/departamento';
  static String get createDepartamento => '$_baseUrl/api/departamento';
  static String updateDepartamento(String id) =>
      '$_baseUrl/api/departamento/$id';
  static String deleteDepartamento(String id) =>
      '$_baseUrl/api/departamento/$id';

  static String get allFeriado => '$_baseUrl/api/feriado';
  static String get createFeriado => '$_baseUrl/api/feriado';
  static String updateFeriado(String id) => '$_baseUrl/api/feriado/$id';
  static String deleteFeriado(String id) => '$_baseUrl/api/feriado/$id';

  static String get allHorarioFunc => '$_baseUrl/api/horarioFunc';
  static String get createHorarioFunc => '$_baseUrl/api/horarioFunc';
  static String updateHorarioFunc(String id) =>
      '$_baseUrl/api/horarioFunc/$id';
  static String deleteHorarioFunc(String id) =>
      '$_baseUrl/api/horarioFunc/$id';

  static String get allTipoProduto => '$_baseUrl/api/tipoProdutos';
  static String get createTipoProduto => '$_baseUrl/api/tipoProdutos';
  static String updateTipoProduto(String id) =>
      '$_baseUrl/api/tipoProdutos/$id';
  static String deleteTipoProduto(String id) =>
      '$_baseUrl/api/tipoProdutos/$id';

  // SIS-04 Config. Sistema (acoes simples, jobs, importacao, banco)
  static String gerarTelas({bool forceUpdate = false, bool fullReset = false}) =>
      '$_baseUrl/api/telas/generate?forceUpdate=$forceUpdate&fullReset=$fullReset';
  static String get regenerarTelas =>
      '$_baseUrl/api/admin/regenerar-telas';
  static String get seedMock => '$_baseUrl/api/admin/seed';
  static String deleteSeedMock(String empresaId) =>
      '$_baseUrl/api/admin/seed?empresaId=$empresaId';
  static String get noticiasLimparEBaixar =>
      '$_baseUrl/api/admin/jobs/noticias-limpar-e-baixar';
  static String get noticiasApagar =>
      '$_baseUrl/api/admin/jobs/noticias-apagar';
  static String get dbStatus => '$_baseUrl/api/admin/db-status';
  static String get fixDb => '$_baseUrl/api/admin/fix-db';
  static String get resetDatabase => '$_baseUrl/api/admin/reset-database';
  static String get allJobs => '$_baseUrl/api/admin/jobs';
  static String executarJob(String nome, {bool forcar = false}) =>
      '$_baseUrl/api/admin/jobs/$nome/executar?forcar=$forcar';
  static String historicoJob(String nome) =>
      '$_baseUrl/api/admin/jobs/$nome/historico';
  static String get importacaoPreview => '$_baseUrl/api/importacao/preview';
  static String get importacaoContaPagar =>
      '$_baseUrl/api/importacao/conta-pagar';
  static String get importacaoContaReceber =>
      '$_baseUrl/api/importacao/conta-receber';

  // SIS-05 Editor de Telas
  static String get allTelas => '$_baseUrl/api/telas?tamanho=500';
  static String telaByNome(String nome) => '$_baseUrl/api/telas/$nome';
  static String reorderTelaFields(String telaId) =>
      '$_baseUrl/api/telas/$telaId/fields/reorder';
  static String updateTelaField(String telaId, String fieldId) =>
      '$_baseUrl/api/telas/$telaId/fields/$fieldId';

  // SIS-06 Permissoes
  static String get allRolePermissoes => '$_baseUrl/api/role-permissao/all';
  static String get allRoles => '$_baseUrl/api/role';
  static String updateRolePermissao(String roleId, String telaNomeEncoded) =>
      '$_baseUrl/api/role-permissao/$roleId/$telaNomeEncoded';
  static String get batchRolePermissao =>
      '$_baseUrl/api/role-permissao/batch';

  // SIS-07 Teste de Endpoints
  static String get adminEndpointsReflection => '$_baseUrl/api/admin/endpoints';

  // SIS-08 Query Builder
  static String get queryBuilderSchemas =>
      '$_baseUrl/api/ferramentas/query-builder/schemas';
  static String get queryBuilderTabelas =>
      '$_baseUrl/api/ferramentas/query-builder/tabelas';
  static String queryBuilderColunas(String schema, String tabela) =>
      '$_baseUrl/api/ferramentas/query-builder/tabelas/$schema/$tabela/colunas';
  static String get queryBuilderExecutar =>
      '$_baseUrl/api/ferramentas/query-builder/executar';

  // ===========================================================================
  // Fase 3 — Licenca, Contatos, Ordem de Servico, Modulos Contratados +
  // Dashboard de Crescimento. Todos os getters abaixo sao declarados de uma
  // vez (P03/Task 03.1) como contrato para os planos das waves 2-3 seguintes.
  // ===========================================================================

  // Fase 3 - LIC-01 (sem deleteLicenca: backend nao expoe DELETE, ativo=false)
  static String get allLicencas => '$_baseUrl/api/licencas';
  static String get createLicenca => '$_baseUrl/api/licencas';
  static String updateLicenca(String id) => '$_baseUrl/api/licencas/$id';

  // Fase 3 - CONT-01 (dominio novo ContatoComercial, NAO e /api/contatos)
  static String get allContatosComerciais =>
      '$_baseUrl/api/contato-comercial';
  static String get createContatoComercial =>
      '$_baseUrl/api/contato-comercial';
  static String updateContatoComercial(String id) =>
      '$_baseUrl/api/contato-comercial/$id';
  static String deleteContatoComercial(String id) =>
      '$_baseUrl/api/contato-comercial/$id';

  // Fase 3 - OS-01 (via dominio Chamado ja existente; createChamado/
  // deleteChamado ja existem na secao Fase 2 SIS-02, reusados aqui)
  static String get allChamadosOS => '$_baseUrl/api/chamados?tamanho=200';
  static String updateChamadoOS(String id) => '$_baseUrl/api/chamados/$id';

  // Fase 3 - MOD-01 (catalogo ModuloServico + atribuicao Parceiro/Empresa)
  static String get allModulosServico =>
      '$_baseUrl/api/modulo-servico?tamanho=1000';
  static String get createModuloServico => '$_baseUrl/api/modulo-servico';
  static String updateModuloServico(String id) =>
      '$_baseUrl/api/modulo-servico/$id';
  static String deleteModuloServico(String id) =>
      '$_baseUrl/api/modulo-servico/$id';
  static String parceiroModulos(String parceiroId) =>
      '$_baseUrl/api/parceiro-modulo?parceiroId=$parceiroId';
  static String get vincularParceiroModulos =>
      '$_baseUrl/api/parceiro-modulo';
  static String empresaModulos(String empresaId) =>
      '$_baseUrl/api/empresa-modulo?empresaId=$empresaId';
  static String get vincularEmpresaModulos => '$_baseUrl/api/empresa-modulo';

  // Fase 3 - DASH-01 (agregacoes MASTER-only, contagem por mes)
  static String parceirosPorMes({int meses = 12}) =>
      '$_baseUrl/api/dashboard/crescimento/parceiros-por-mes?meses=$meses';
  static String empresasPorMes({int meses = 12}) =>
      '$_baseUrl/api/dashboard/crescimento/empresas-por-mes?meses=$meses';
  static String modulosPorMes({int meses = 12}) =>
      '$_baseUrl/api/dashboard/crescimento/modulos-por-mes?meses=$meses';

  // Fase 3 - dropdowns de FK (fonte de opcoes, carregadas 1x). allAplicativos
  // ja existe na secao Fase 2 SIS-01, reusado para o dropdown de Licenca.
  static String get dropdownParceiros => '$_baseUrl/api/parceiro?tamanho=500';
  static String get dropdownEmpresas => '$_baseUrl/api/empresa?tamanho=500';
  static String get dropdownSetores => '$_baseUrl/api/setor?tamanho=500';
}
