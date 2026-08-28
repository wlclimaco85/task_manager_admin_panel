# PLAN — Fase 2: Migração do menu "Sistema"

Ver `RESEARCH.md` desta mesma pasta para o racional completo (mapeamento dos 8 itens,
decisões do PO, leitura integral dos 5 arquivos grandes de origem). Este PLAN.md segue o
formato pragmático já usado na Fase 1 (arquivo único, sem plumbing de `gsd-sdk`/`STATE.md`
— este projeto ainda não usa o pipeline completo do GSD).

## Escopo (fechado pelo PO — não renegociar)

Os 8 itens do grupo `sistema` de `menu_config.dart`, **exceto "Empresas"** (fica no
cliente): Aplicativo, Cadastro Empresa, Configurações Admin (6 sub-CRUDs), Config. Sistema
(6 seções), Editor de Telas, Permissões, Teste de Endpoints (só a 3ª aba, reconstruída como
terminal livre), Query Builder. Decisões do PO 1-4 em `RESEARCH.md` já resolvem UX
(Config. Admin fica tab-container único) e confirmam que nenhum item foi cortado.

## Por que 15 sub-planos em 4 waves (não é fase separada — é granularidade de execução)

O volume de origem (~9000 linhas somadas: `configuracoes_sistema_screen.dart` 4569,
`cadastro_empresa_wizard.dart` 1395, `system_test_screen.dart` 1867,
`tela_editor_screen.dart` 658, `role_permissao_screen.dart` 503, mais os 6 sub-CRUDs de
Config. Admin) excede em muito o orçamento de contexto de um único plano (~50%). Cada
sub-plano abaixo é um commit atômico próprio, dimensionado para ~10-40% de contexto,
seguindo `files_modified` disjuntos dentro da mesma wave para permitir execução paralela
onde fizer sentido. Nenhum item foi reduzido de escopo — a divisão é só de sequenciamento.

## Mapeamento de requisitos (IDs internos desta fase, não há REQUIREMENTS.md formal)

| ID | Item do menu | screenIndex |
|----|---|---|
| SIS-01 | Aplicativo | 3 |
| SIS-02 | Cadastro Empresa | 66 |
| SIS-03 | Configurações Admin (6 sub-CRUDs) | 40 |
| SIS-04 | Config. Sistema (6 seções) | 63 |
| SIS-05 | Editor de Telas | 52 |
| SIS-06 | Permissões | 59 |
| SIS-07 | Teste de Endpoints (3ª aba, terminal livre) | 65 |
| SIS-08 | Query Builder | 150 |
| SIS-09 | Fundação/infra compartilhada + menu "Sistema" | — |

## Interfaces herdadas (Fase 1 — ler antes de codar, não reexplorar)

- `lib/widgets/generic/field_config.dart` — `FieldType {text,number,email,boolean,multiline}`,
  `FieldConfig{key,label,type,required,showInGrid,validator}`.
- `lib/widgets/generic/generic_grid_screen.dart` — `GenericGridScreen({title,listUrl,
  createUrl,updateUrl:String Function(id),deleteUrl:String Function(id),fields,networkCaller,
  rowsPerPage})`. Parser atual: `response.body?['data'] ?? response.body?['dados'] ?? []`,
  espera `List` direto — **quebra com o formato paginado real do backend** (ver Task 01.1).
- `lib/widgets/generic/generic_detail_form_screen.dart` — `GenericDetailFormScreen({title,
  fields,createUrl,updateUrl,initialValues,networkCaller})`.
- `lib/services/network_caller.dart` — `NetworkCaller.getRequest/postRequest/putRequest/
  deleteRequest(url,[body])` retornando `NetworkResponse{isSuccess,statusCode,body}`; injeta
  `TenantContext.headers`/`applyToBody`, trata 401 automaticamente. Usar SEMPRE este wrapper
  nos itens bespoke — **nunca `http` cru** (o código-fonte original usa `http` cru em vários
  itens; isso é débito a NÃO replicar).
- `lib/config/api_links.dart` — `ApiLinks._baseUrl` privado; só expõe getters estáticos.
  **Atenção**: `_backendUrl`/`_backendContextPath` são `String.fromEnvironment` const —
  nunca converter para `final` (ver aviso no próprio arquivo e no `CLAUDE.md` do workspace).
- `lib/screens/home_screen.dart` — shell pós-login, hoje um único `ListTile` de demonstração
  (Contatos). Esta fase adiciona um tile "Sistema" navegando para `SistemaMenuScreen` (novo).
- `lib/core/theme/app_theme.dart` — `AppColors`, `AppSpacing`, tema completo. **Não existe
  `GridColors`** no admin panel (existia no cliente) — mapear usos de `GridColors.*` do
  código-fonte original para tokens de `AppColors`/`Theme.of(context).colorScheme` ao portar.

## Confirmações de backend feitas nesta sessão (resolve Assumption A5 / Pitfall 4)

- `QueryBuilderController` (`/api/ferramentas/query-builder`): `GET /schemas`, `GET /tabelas`,
  `GET /tabelas/{schema}/{tabela}/colunas` (sem restrição extra), `POST /executar` **com
  `@PreAuthorize("@tenantSecurity.isMaster()")`** e `QueryBuilderServiceImpl` **valida regex
  que só permite `SELECT`/`WITH`** (bloqueia DDL/DML). Risco de segurança do Pitfall 4 está
  **mitigado no backend já hoje** — Task 12.1 ainda deve fazer um teste de integração leve
  confirmando isso (não assumir sem verificar em runtime), mas não é mais bloqueio de plan-phase.
- `AdminFixController` (`/api/admin`, inclui `reset-database`/`fix-db`) tem
  `@PreAuthorize("@tenantSecurity.isMaster()")` confirmado na ação de reset (linha 200) — Task
  05.1 deve confirmar (grep) que `fix-db` e o `DELETE /api/admin/seed` (mock) têm a mesma
  proteção antes de expor os botões correspondentes; se algum endpoint não tiver, registrar
  achado e envolver o dono do backend antes de liberar o botão (não implementar workaround
  client-side para suprir ausência de `@PreAuthorize`).
- `RolePermissaoController` → `/api/role-permissao`; `TelaController` → `/api/telas` (batem
  com o que `RESEARCH.md` já mapeou).
- Jobs: `JobMonitorController` → `/api/admin/jobs`; Mock: `MockDataController` →
  `/api/admin/seed`.

## Decisão de arquitetura desta fase: `file_picker` em vez do helper web-only do cliente

`RESEARCH.md` recomenda reusar `pickAndReadFile()` (`file_upload_helper_web.dart`, baseado em
`dart:html`) para evitar a dependência `file_picker`. **Esta fase diverge dessa recomendação**
porque o admin panel é Web+Windows+Mobile desde a Fase 1 (decisão já fechada no ROADMAP.md) e
`dart:html` não compila fora da web. `file_picker` (pub.dev, `miguelpruivo`, Flutter Favorite,
já usado pelo próprio `configuracoes_sistema_screen.dart` original na seção de Contas) é a
escolha correta aqui — ver Task 01b.1 para o registro formal desta troca de pacote (não requer
Package Legitimacy Audit adicional: pacote já em uso no ecossistema do cliente do mesmo
workspace, portanto já avaliado como legítimo).

---

## Estrutura de execução: 15 planos em 4 waves

| Wave | Plano | Item(ns) SIS | Depende de | Arquivos principais (novos, salvo indicação) |
|---|---|---|---|---|
| 1 | P01 | SIS-09 (contratos) | — | `generic_grid_screen.dart` (fix + `embedded`), `api_links.dart` (getters), `pubspec.yaml` (`file_picker`) |
| 1 | P01b | SIS-09 (infra) | — | `utils/csv_parser.dart`, `screens/sistema/sistema_menu_screen.dart`, `screens/home_screen.dart` (edit) |
| 2 | P02 | SIS-01, SIS-03 | P01 | `screens/sistema/aplicativo_screen.dart`, `screens/sistema/configuracoes_admin_screen.dart` |
| 2 | P03 | SIS-02 (lógica) | P01 | `models/cadastro_empresa_models.dart`, `services/cadastro_empresa_service.dart` |
| 2 | P05 | SIS-04 (ações simples) | P01 | `widgets/admin/admin_action_card.dart`, `screens/sistema/configuracoes_sistema/acoes_screen.dart` |
| 2 | P07 | SIS-04 (import. contas) | P01, P01b | `screens/sistema/configuracoes_sistema/importacao_contas_screen.dart` |
| 2 | P08a | SIS-04 (import. cadastros, lógica) | P01, P01b | `services/importacao_cadastros_service.dart` |
| 2 | P09 | SIS-05 | P01 | `screens/sistema/tela_editor_screen.dart`, `screens/sistema/tela_field_editor_screen.dart` |
| 2 | P10 | SIS-06 | P01 | `utils/role_permissao_normalizacao.dart`, `models/role_permission_catalog.dart`, `screens/sistema/role_permissao_screen.dart` |
| 2 | P11 | SIS-07 | P01 | `screens/sistema/endpoint_tester_screen.dart` |
| 2 | P12 | SIS-08 | P01 | `services/query_builder_service.dart`, `screens/sistema/query_builder_screen.dart` |
| 3 | P04 | SIS-02 (UI) | P03 | `screens/sistema/cadastro_empresa_wizard_screen.dart` |
| 3 | P06 | SIS-04 (jobs) | P05 | `screens/sistema/configuracoes_sistema/jobs_screen.dart` |
| 3 | P08b | SIS-04 (import. cadastros, UI) | P08a, P07 | `screens/sistema/configuracoes_sistema/importacao_cadastros_screen.dart` |
| 4 | P13 | SIS-04 (container final) + wiring | Todos acima | `screens/sistema/configuracoes_sistema/configuracoes_sistema_screen.dart`, `screens/sistema/sistema_menu_screen.dart` (edit final) |

Todos os planos da wave 2 têm `files_modified` disjuntos entre si (podem ser executados em
qualquer ordem/paralelo). Waves 3 e 4 têm dependência real de arquivo (consomem tipos/serviços
criados na wave anterior) — não são paralelizáveis com suas dependências.

---

## Wave 1

### P01 — Fundação: contrato de parser + ApiLinks + dependência + embedding

**Objetivo:** corrigir o bug de parsing já conhecido (Pitfall 1), declarar TODOS os
endpoints desta fase em `api_links.dart` de uma vez, adicionar a dependência `file_picker`
e habilitar `GenericGridScreen` a ser embutido sem `Scaffold` próprio — tudo como contrato
para os 13 planos seguintes (evita que cada plano precise editar os mesmos arquivos
compartilhados; achados 1 e 3 do `gsd-plan-checker` incorporados aqui).

1. **Task 01.1 — Corrigir parser do `GenericGridScreen` para respostas paginadas aninhadas.**
   `lib/widgets/generic/generic_grid_screen.dart`: em `_load()`, o parser hoje só aceita
   `data`/`dados` como `List` direto. Ajustar para também reconhecer
   `data: {dados: [...], total: N}` (formato real de `AplicativoController` e
   provavelmente Cargo/Feriado/etc. — ver Pitfall 1 do `RESEARCH.md`): se `data` for `Map`,
   tentar `data['dados'] ?? data['content'] ?? []` antes de desistir. Não alterar a
   paginação client-side existente (fora de escopo desta fase — débito já registrado).
   Adicionar teste cobrindo os 3 formatos (`{data:[...]}`, `{data:{dados:[...]}}`,
   `{dados:[...]}`) em `test/widgets/generic_grid_screen_test.dart`.
   `tdd="true"`.
   - Behavior: dado `data: {dados: [{...}], total: 1}`, o grid deve popular 1 linha (hoje
     retorna 0). Dado `data: [{...}]` (formato já suportado), continuar funcionando.
   - Verify: `flutter test test/widgets/generic_grid_screen_test.dart`

2. **Task 01.2 — `ApiLinks`: adicionar getters para os 8 itens desta fase.**
   `lib/config/api_links.dart`: adicionar, agrupado por item com comentário `// SIS-0N`:
   - SIS-01 Aplicativo: `allAplicativos`, `createAplicativo`, `updateAplicativo(id)`,
     `deleteAplicativo(id)` → `/api/aplicativo`.
   - SIS-02 Cadastro Empresa: `createEmpresa` (`/api/empresa`), `createLogin` (`/api/login`),
     `createParceiro` (`/api/parceiro`), `createContaPagar` (`/api/conta_pagar`),
     `createContaReceber` (`/api/conta_receber`), `createNfe` (`/api/nfe`),
     `createChamado` (`/api/chamados`), `createChat` (`/api/chat`), mais
     `deleteEmpresa(id)`/`deleteLogin(id)`/`deleteParceiro(id)`/etc. para o rollback LIFO
     (mesmo path base, verbo `DELETE {url}/{id}`).
   - SIS-04 Importação Cadastros (`_ImportacaoCadastrosSection` — consumido por P08a, Wave 2):
     **contrato distinto do de SIS-02 acima, endpoints/verbos diferentes, não reutilizar por
     engano.** `allEmpresasByAplicativo(codApp)` (`GET /api/empresa?codApp=`),
     `parceirosByEmpresa(empresaId)` (`GET /api/parceiro/empresa/{empresaId}`),
     `updateEmpresa(id)` (`PUT /api/empresa/update/{id}`), `insertParceiro`
     (`POST /api/parceiro/insert`), `updateParceiro(id)` (`PUT /api/parceiro/update/{id}`),
     `loginsByEmpresa(empId)` (`GET /api/logins?empId=`), `createLoginCadastro`
     (`POST /api/logins`, plural — distinto de `createLogin` acima que é singular),
     `updateLoginCadastro(id)` (`PUT /api/logins/{id}`), `funcionariosByEmpresa(empId)`
     (`GET /api/funcionario?empId=`), `createFuncionario`/`updateFuncionario(id)`
     (`POST`/`PUT /api/funcionario`[`/{id}`]), `allPlanos`/`allPlanosAcademia`,
     `createPlano`/`updatePlano(id)` (`/api/planos`), `createPlanoAcademia`/
     `updatePlanoAcademia(id)` (`/api/planos_academia`), `servicosContratados`
     (`GET /api/servico-contratado?tamanho=10000`), `createServicoContratado`/
     `updateServicoContratado(id)` (`/api/servico-contratado`[`/{id}`]).
   - SIS-03 Config. Admin (6 sub-CRUDs): `allCargos`/`createCargo`/`updateCargo(id)`/
     `deleteCargo(id)` (`/api/cargo`); idem para `centroCusto` (`/api/centro-custo`),
     `departamento` (`/api/departamento`), `feriado` (`/api/feriado`), `horarioFunc`
     (`/api/horarioFunc`), `tipoProduto` (`/api/tipoProdutos`).
   - SIS-04 Config. Sistema: `gerarTelas` (`POST /api/telas/generate?forceUpdate=&fullReset=`),
     `regenerarTelas` (`POST /api/admin/regenerar-telas`), `seedMock` (`POST /api/admin/seed`),
     `deleteSeedMock(empresaId)` (`DELETE /api/admin/seed?empresaId=`), `noticiasLimparEBaixar`
     (`POST /api/admin/jobs/noticias-limpar-e-baixar`), `noticiasApagar` (`DELETE
     /api/admin/jobs/noticias-apagar`), `dbStatus` (`GET /api/admin/db-status`), `fixDb`
     (`POST /api/admin/fix-db`), `resetDatabase` (`POST /api/admin/reset-database`), `allJobs`
     (`GET /api/admin/jobs`), `executarJob(nome, {forcar})` (`POST
     /api/admin/jobs/{nome}/executar`), `historicoJob(nome)` (`GET
     /api/admin/jobs/{nome}/historico`), `importacaoPreview` (`POST /api/importacao/preview`),
     `importacaoContaPagar`/`importacaoContaReceber` (`POST /api/importacao/conta-pagar`|
     `conta-receber`).
   - SIS-05 Editor de Telas: `allTelas` (`GET /api/telas?tamanho=500`), `telaByNome(nome)`
     (`GET /api/telas/{nome}`), `reorderTelaFields(telaId)` (`PUT
     /api/telas/{telaId}/fields/reorder`), `updateTelaField(telaId, fieldId)` (`PUT
     /api/telas/{telaId}/fields/{fieldId}`).
   - SIS-06 Permissões: `allRolePermissoes` (`GET /api/role-permissao/all`), `allRoles`
     (`GET /api/role`), `updateRolePermissao(roleId, telaNome)` (`PUT
     /api/role-permissao/{roleId}/{telaNome-encoded}`), `batchRolePermissao`
     (`POST /api/role-permissao/batch`).
   - SIS-07 Teste de Endpoints: `adminEndpointsReflection` (`GET /api/admin/endpoints`) —
     usado só para popular a lista de paths conhecidos no terminal livre, não para reconstruir
     os testes hardcoded antigos.
   - SIS-08 Query Builder: `queryBuilderSchemas` (`GET
     /api/ferramentas/query-builder/schemas`), `queryBuilderTabelas` (`GET .../tabelas`),
     `queryBuilderColunas(schema,tabela)` (`GET .../tabelas/{schema}/{tabela}/colunas`),
     `queryBuilderExecutar` (`POST .../executar`).
   - Verify: `flutter analyze lib/config/api_links.dart` limpo (0 erros/warnings).
   - Done: todos os getters acima existem, compilam, seguem o padrão `static String get` /
     `static String Function(...)` já usado para Contatos.

3. **Task 01.3 — Adicionar dependência `file_picker` ao `pubspec.yaml`.**
   Achado do `gsd-plan-checker`: `RESEARCH.md` linha 320 já registra que a Fase 1 não instalou
   `file_picker`, mas nenhuma task anterior declarava a adição — P07 (Task 07.1) e P08b (Task
   08b.1) referenciam `FilePicker.platform.pickFiles(...)` sem o pacote declarado, quebrando
   `flutter analyze`/compilação. `pubspec.yaml`: adicionar `file_picker: ^8.1.0` (versão fixada,
   não `any` — mesma exigência já registrada na mitigação T-02-SC do threat model desta fase)
   em `dependencies:`, rodar `flutter pub get`.
   - Verify: `flutter pub get` sem erro; `grep file_picker pubspec.lock` retorna entrada.
   - Done: `import 'package:file_picker/file_picker.dart';` resolve sem erro em qualquer
     arquivo do projeto.

4. **Task 01.4 — Extrair corpo embutível de `GenericGridScreen` (sem `Scaffold` próprio).**
   Achado do `gsd-plan-checker`: `GenericGridScreen.build()` (linha 210) retorna `Scaffold`
   completo com `AppBar`+`FloatingActionButton` próprios — usá-lo diretamente como corpo de
   aba (Task 02.2) produziria `Scaffold` aninhado (6 `AppBar`s duplicados dentro do conteúdo
   da aba), contradizendo a Decisão do PO item 2 ("menor ruído no menu, mais coeso").
   `lib/widgets/generic/generic_grid_screen.dart`: extrair o conteúdo atual do `Scaffold` (a
   `Column`/lista/paginação, sem `AppBar`/`FloatingActionButton`) para um widget interno
   `_GenericGridBody` reutilizável, e adicionar parâmetro `embedded` (default `false`) a
   `GenericGridScreen`: quando `true`, `build()` retorna `_GenericGridBody` direto (sem
   `Scaffold`/`AppBar`); a ação de "criar novo" (hoje no FAB) vira um botão inline no topo do
   corpo quando `embedded==true`, preservando a funcionalidade sem depender de FAB posicionado
   pelo `Scaffold` externo. Comportamento com `embedded==false` (default, usado pela Fase 1 e
   por todos os outros itens desta fase que abrem tela cheia) não muda.
   - Behavior: `GenericGridScreen(embedded:false, ...)` continua retornando `Scaffold`+`AppBar`+
     `FAB` (regressão zero para os usos existentes). `GenericGridScreen(embedded:true, ...)`
     retorna o corpo sem `Scaffold`, sem `AppBar`, com botão "Novo" inline visível.
   - Verify: `flutter test test/widgets/generic_grid_screen_test.dart` (caso novo cobrindo
     `embedded:true`, mais os casos existentes intactos).
   - Done: Task 02.2 pode montar 6 instâncias com `embedded:true` dentro de um `TabBarView`
     sem `Scaffold`/`AppBar` duplicado.

### P01b — Fundação: utilitário CSV + shell de menu "Sistema"

**Objetivo:** criar o parser CSV puro (reusado por P07 e P08a) e o ponto de entrada de
navegação para os 8 itens (esqueleto, sem wiring real ainda — wiring final é P13).

1. **Task 01b.1 — `lib/utils/csv_parser.dart` (função pura, TDD).**
   Portar `_parseCsv` de `configuracoes_sistema_screen.dart` (RFC4180-ish, separador `;`/`,`
   auto-detectado por contagem de ocorrências na 1ª linha) como função top-level
   `List<List<String>> parseCsv(String content)`, sem estado, sem dependência de widget.
   `tdd="true"`.
   - Behavior: `parseCsv("a;b\n1;2")` → `[['a','b'],['1','2']]`. `parseCsv("a,b\n1,2")` →
     idem (auto-detecta vírgula). Célula com aspas contendo separador (`"a;b";c`) não quebra
     em 3 colunas. Linha vazia no fim do arquivo é ignorada.
   - Verify: `flutter test test/utils/csv_parser_test.dart`

2. **Task 01b.2 — `SistemaMenuScreen` (esqueleto) + tile em `HomeScreen`.**
   `lib/screens/sistema/sistema_menu_screen.dart`: `StatelessWidget` com 8 `ListTile`s (um
   por SIS-01..SIS-08, título/ícone/subtítulo conforme a tabela de mapeamento do
   `RESEARCH.md`), `onTap` inicial mostrando `SnackBar('Em construção — wave N')` para os
   itens ainda não implementados (todos, nesta task) — evita link morto/crash ao navegar
   antes do wiring final (P13 substitui os `SnackBar` por navegação real). `lib/screens/
   home_screen.dart`: adicionar `ListTile` "Sistema" (ícone `Icons.settings_outlined`)
   navegando para `SistemaMenuScreen`, seguindo o mesmo padrão do tile "Contatos" já
   existente.
   - Verify: `flutter test test/widgets/sistema_menu_screen_test.dart` (renderiza 8 tiles).
   - Done: `HomeScreen` → tile "Sistema" → `SistemaMenuScreen` com 8 itens navegável sem crash.

---

## Wave 2 (todos dependem só de P01; `files_modified` disjuntos entre si)

### P02 — SIS-01 Aplicativo + SIS-03 Configurações Admin (6 sub-CRUDs)

1. **Task 02.1 — `AplicativoScreen`.** `lib/screens/sistema/aplicativo_screen.dart`: wrapper
   fino retornando `GenericGridScreen(title:'Aplicativo', listUrl: ApiLinks.allAplicativos,
   ..., fields:[FieldConfig(key:'nome',label:'Nome',required:true),
   FieldConfig(key:'observacao',label:'Observação',type:FieldType.multiline)])` — campo `id`
   não entra em `fields` (grid já usa `row['id']` internamente). Mesmo padrão do
   `aplicativo_screen.dart` original (20 linhas), adaptado ao par genérico do admin panel.
2. **Task 02.2 — `ConfiguracoesAdminScreen` (tab container + 6 sub-CRUDs).**
   `lib/screens/sistema/configuracoes_admin_screen.dart`: `StatefulWidget` com `TabBar`/
   `IndexedStack` de 6 abas (Cargos, Centro de Custo, Departamentos, Feriados, Horários,
   Tipos de Produto — per Decisão do PO item 2, tab único), cada aba um `GenericGridScreen(
   embedded: true, ...)` (Task 01.4 — sem `Scaffold`/`AppBar`/`FAB` próprios, evita telas
   cheias e duplicação de chrome dentro da aba) com os `FieldConfig` mapeados: Cargo(`nome`), CentroCusto(`nome`),
   Departamento(`nome`,`numeroFolha`:number), Feriado(`nome`,`data`,`repeteAno`:boolean),
   HorarioFunc(`nome`,`tipo`,`ativo`:boolean), TipoProduto(`tipoProduto`).
   - Verify: `flutter test test/screens/sistema/configuracoes_admin_screen_test.dart`
     (renderiza 6 abas, troca de aba funciona).
   - Done: as 6 abas carregam via `ApiLinks` correspondente, create/edit/delete funcionam
     (herdado do `GenericGridScreen`, sem lógica nova).

### P03 — SIS-02 Cadastro Empresa: lógica de orquestração (TDD)

1. **Task 03.1 — Modelos de suporte.** `lib/models/cadastro_empresa_models.dart`:
   `EmpresaRef{id}`, `CreatedEntity{tipo,id,deleteUrl}` (para o rollback LIFO), `LogEntry
   {timestamp,mensagem,sucesso}`, `CadastroException(String mensagem)`.
2. **Task 03.2 — `CadastroEmpresaService` (lógica pura, orquestra via `NetworkCaller`).**
   `lib/services/cadastro_empresa_service.dart`: portar a sequência de `_execute` do arquivo
   original (empresa → 2 logins fixos ADMIN/FINANCEIRO `tipoLogin:1` → 5 clientes
   [parceiro+login `tipoLogin:2`] → 5 contas a pagar [campo `parceiro`] → 5 contas a receber
   [**campo `cliente`, não `parceiro`** — assimetria do backend, replicar fielmente] → 1 nfe
   → 3 chamados → 1 chat condicional → 5 funcionários [parceiro `tipoAluno:'FUNCIONARIO'` +
   login `tipoLogin:3`]), usando `NetworkCaller.postRequest`/`deleteRequest` (não `http` cru).
   **Assumption A1 do RESEARCH.md não totalmente confirmada** (arquivo original lido só até a linha 150 antes da leitura completa desta rodada) — antes de codar, reconfirmar os paths reais de `/api/login`, `/api/parceiro`, `/api/conta_pagar`, `/api/conta_receber`, `/api/nfe`, `/api/chamados`, `/api/chat`, `/api/funcionario` contra os controllers do backend (`AppAcademia/src/main/java/br/com/appAcademia/controller/`) — a leitura completa de `cadastro_empresa_wizard.dart` já feita nesta pesquisa confirma os paths acima, mas o payload exato de cada endpoint (nomes de campo) deve ser conferido no controller/DTO real, não assumido só pelo nome do path.
   `_extractId` tentando 4 formatos (`body.id`, `body.data.id`, `body.data.parceiro.id`,
   `body.data.login.id`). Primeira falha (`id==null`) lança `CadastroException` e interrompe;
   rollback percorre `_createdEntities` em ordem reversa, `DELETE`, sem parar em falha
   individual. Expor callback `void Function(LogEntry)` para a UI (P04) plotar log
   incrementalmente sem acoplar a um `StatefulWidget`. `tdd="true"`.
   - Behavior: `execute()` com todas as chamadas retornando sucesso produz 1+2+10+10+1+3+1+5×2
     = 38 `CreatedEntity` e nenhuma chamada de rollback. `execute()` com falha na 3ª conta a
     pagar lança `CadastroException` e dispara `deleteRequest` para as entidades já criadas
     em ordem reversa (empresa por último). Payload de conta a receber usa chave `cliente`
     (não `parceiro`).
   - Verify: `flutter test test/services/cadastro_empresa_service_test.dart` (usar
     `NetworkCaller` com `http.Client` mockado via `mockito`, já disponível como dev dep).

### P05 — SIS-04 Config. Sistema: ações simples + `AdminActionCard`

1. **Task 05.1 — Confirmar `@PreAuthorize` das ações destrutivas no backend (verificação, não
   implementação).** Rodar `grep -n "PreAuthorize\|RequestMapping" AppAcademia/src/main/java/
   br/com/appAcademia/controller/AdminFixController.java` (caminho relativo ao workspace) e
   confirmar que `fix-db` e a rota usada por `DELETE /api/admin/seed` (mock) têm
   `@tenantSecurity.isMaster()` (já confirmado para `reset-database`, ver seção
   "Confirmações de backend" acima). Se algum endpoint não tiver proteção equivalente,
   registrar achado em comentário no código (`// TODO-SEGURANCA:`) e não remover a
   confirmação client-side do Task 05.2 mesmo assim (defesa em profundidade) — não é bloqueio
   para prosseguir, mas deve ser reportado ao usuário no relatório final desta fase.
2. **Task 05.2 — `AdminActionCard` + `ConfiguracoesSistemaAcoesScreen`.**
   `lib/widgets/admin/admin_action_card.dart`: widget reutilizável (`title`, `subtitle`,
   `icon`, `color`, `onTap: Future<Map<String,dynamic>> Function()`, exibe resultado
   JSON/erro formatado após execução, estado de loading no botão) — extraído já na primeira
   tela bespoke, conforme recomendação do `RESEARCH.md` ("Architecture Patterns"), para
   reuso em P06/P07/P08b. `lib/screens/sistema/configuracoes_sistema/acoes_screen.dart`:
   4 `AdminActionCard`s — Geração de Telas (`ApiLinks.gerarTelas`/`regenerarTelas`, com
   opções `forceUpdate`/`fullReset` via checkbox antes de disparar), Dados de Teste/Mock
   (`ApiLinks.seedMock` com campos `quantidade`/`meses`/`empresaId`,
   `ApiLinks.deleteSeedMock(empresaId)` **atrás de `AlertDialog` de confirmação** — reusa
   padrão "digite RESET" adaptado para "digite APAGAR"), Notícias
   (`noticiasLimparEBaixar`/`noticiasApagar`), Banco de Dados (`dbStatus` sem confirmação,
   `fixDb` com confirmação simples, `resetDatabase` **com `AlertDialog` exigindo digitar
   literalmente "RESET"** antes de habilitar o botão de confirmar — replicar o padrão exato
   do arquivo original, por decisão do PO item 3 do `RESEARCH.md`).
   - Verify: `flutter test test/screens/sistema/configuracoes_sistema/acoes_screen_test.dart`
     (confirma que `resetDatabase`/`deleteSeedMock` não disparam sem o texto de confirmação
     correto digitado).
   - Done: as 4 seções chamam os endpoints corretos; as 3 ações destrutivas (`resetDatabase`,
     `fixDb`, `deleteSeedMock`) exigem confirmação explícita antes do `NetworkCaller` disparar.

### P07 — SIS-04 Config. Sistema: Importação CSV — Contas a Pagar/Receber

1. **Task 07.1 — `ImportacaoContasScreen`.**
   `lib/screens/sistema/configuracoes_sistema/importacao_contas_screen.dart`: usar
   `file_picker` (`FilePicker.platform.pickFiles(type: FileType.custom,
   allowedExtensions:['csv'], withData:true)` — funciona nas 3 plataformas, ver seção
   "Decisão de arquitetura" acima) para selecionar o CSV, `parseCsv` (de P01b) para pré-visualizar
   colunas, dicionário de sinônimos normalizado (minúsculas, sem acento) para auto-mapeamento
   de colunas, `POST ApiLinks.importacaoPreview` (multipart) para preview server-side, depois
   `POST ApiLinks.importacaoContaPagar`|`importacaoContaReceber` (multipart, query
   `empId`/`parId`/`upsert=true`, form-data com mapeamento + arquivo no campo `arquivo`) para
   importar de fato. Selecionar tipo (Pagar/Receber) e destino (empId/parId) antes de
   habilitar o botão de importar.
   - Verify: `flutter test test/screens/sistema/configuracoes_sistema/
     importacao_contas_screen_test.dart` (mapeamento de colunas por sinônimo, validação de
     campos obrigatórios antes de habilitar importação).
   - Done: fluxo completo seleção → preview → mapeamento → importação real, erros do backend
     exibidos ao usuário (não apenas logados).

### P08a — SIS-04 Config. Sistema: Importação CSV — Cadastros (lógica, TDD)

**Item de maior risco desta fase** (RESEARCH.md classifica como "port ALTO" — não existe
endpoint de importação em lote, toda a lógica roda no cliente).

1. **Task 08a.1 — `ImportacaoCadastrosService` (dedup + create-vs-update, lógica pura onde
   possível).** `lib/services/importacao_cadastros_service.dart`: para cada linha do CSV
   (Empresas/Parceiros/Funcionários/Logins/Planos), decidir create-vs-update via `GET` +
   filtro em memória (dedup por chave natural — replicar critério exato do arquivo original,
   ex. e-mail para login, CNPJ/nome para empresa), resolver FK empresa/parceiro por nome
   quando o CSV não trouxer o ID, heurísticas como `_isFaturamentoServico` (portar verbatim).
   Disparar os ~10 endpoints REST individuais por linha (`ApiLinks.createEmpresa`/
   `createParceiro`(`/insert`)/`createLogin`(`/api/logins`)/`/api/funcionario`/`/api/planos`/
   `/api/servico-contratado`) via `NetworkCaller`, cada um com seu GET de dedup prévio.
   Expor callback de progresso `void Function(int linhaAtual, int total, LogEntry)` (mesmo
   padrão de P03, para a UI de P08b plotar incrementalmente). `tdd="true"`.
   - Behavior: linha de CSV cujo e-mail já existe em `/api/logins` gera `PUT`, não `POST`.
     Linha nova gera `POST`. Falha em uma linha não interrompe as seguintes (diferente do
     Cadastro Empresa — aqui é processamento em lote independente por linha, log de erro por
     linha e continua).
   - Verify: `flutter test test/services/importacao_cadastros_service_test.dart`
     (`NetworkCaller` mockado, cenários create/update/erro-continua).

### P09 — SIS-05 Editor de Telas

1. **Task 09.1 — `TelaEditorScreen` (grid de telas).**
   `lib/screens/sistema/tela_editor_screen.dart`: `GET ApiLinks.allTelas`, parser tolerante a
   3 formatos de resposta (reusar a mesma lógica de Task 01.1 — `data` lista direta, ou
   `data.dados`/`data.content`), busca client-side por nome/título, card por tela mostrando
   contagem de campos, botão "Editar" navega para `TelaFieldEditorScreen`.
2. **Task 09.2 — `TelaFieldEditorScreen` (editor de campos, 2 painéis).**
   `lib/screens/sistema/tela_field_editor_screen.dart`: `GET ApiLinks.telaByNome(nome)` carrega
   `fields` ordenados por `fieldOrder`; painel esquerdo `ReorderableListView` (drag dispara
   `PUT ApiLinks.reorderTelaFields(telaId)` com `[{id,fieldOrder}]`); painel direito edita UM
   campo selecionado — seções Identificação (label, fieldName, displayFieldName, fieldOrder),
   Tipo (16 opções de `fieldType` incl. dropdown/multiselect/currency/cpf/cnpj, `maxLines` se
   multiline, `dropdownEndpoint` se dropdown/multiselect, `mask`), Visibilidade (6 switches:
   isInForm, isVisibleByDefault, isFilterable, isSortable, showInInsert, showInUpdate),
   Comportamento (4 switches: isRequired, enabled, isFixed, multiSelect), `defaultValue` com
   parsing especial (JSON, bool, número, string literal, templates `{{now+Nd}}`/
   `{{campo:xxx}}` — portar o parser verbatim, não reinventar). Salvar dispara `PUT
   ApiLinks.updateTelaField(telaId,fieldId)` com o campo inteiro.
   - Verify: `flutter test test/screens/sistema/tela_field_editor_screen_test.dart` (reorder
     dispara PUT correto, parsing de `defaultValue` cobre os 5 formatos).
   - Done: listar → abrir tela → reordenar campo → editar propriedades → salvar, ponta a
     ponta contra os 3 endpoints (`allTelas`, `reorderTelaFields`, `updateTelaField`).

### P10 — SIS-06 Permissões

1. **Task 10.1 — Normalização de nomes (lógica pura, TDD) + modelos de suporte.**
   `lib/utils/role_permissao_normalizacao.dart`: portar **verbatim**
   `_normalizeTelaNome` (lowercase + remove `_`) e `toBackendTelaNome` (snake_case→camelCase)
   de `role_permissao_screen.dart` — débito técnico já corrigido nos cards #460/#471/#493 do
   cliente, não reinventar. `lib/models/role_permission_catalog.dart`: portar
   `RolePermissionCatalog`/`RolePermissionGroup`/`RolePermissionMenuEntry` e
   `buildRolePermissionGroupBatch` (de `role_permission_group_selection.dart`, usado só pelo
   checkbox de "grupo"). `tdd="true"`.
   - Behavior: `toBackendTelaNome('nfe_entrada')` → `'nfeEntrada'`.
     `_normalizeTelaNome('Nfe_Entrada')` == `_normalizeTelaNome('nfeentrada')`.
   - Verify: `flutter test test/utils/role_permissao_normalizacao_test.dart`
2. **Task 10.2 — `RolePermissaoScreen` (matriz).**
   `lib/screens/sistema/role_permissao_screen.dart`: `GET ApiLinks.allRolePermissoes` (todas
   as permissões, filtro por role em memória) + `GET ApiLinks.allRoles`, matriz de checkboxes
   por tela×campo, save individual via `PUT ApiLinks.updateRolePermissao(roleId,telaNome)`
   (telaNome via `Uri.encodeComponent`, body `{campo:valor}` — **não** POST batch), checkbox
   de "grupo" (marca/desmarca as 5 permissões de todas as telas de um menu de uma vez) via
   `POST ApiLinks.batchRolePermissao` usando `buildRolePermissionGroupBatch` de Task 10.1.
   - Verify: `flutter test test/screens/sistema/role_permissao_screen_test.dart` (toggle
     individual chama PUT com telaNome convertido; checkbox de grupo chama POST batch).
   - Done: matriz carrega, toggle individual persiste, toggle de grupo persiste em batch,
     nomes de tela batem com o backend (sem o bug histórico reintroduzido).

### P11 — SIS-07 Teste de Endpoints (reconstruído como terminal HTTP livre)

**Por decisão do RESEARCH.md ("Recomendação para o admin panel"): portar SÓ a 3ª aba,
reconstruída como terminal livre — não portar as abas 1/2 (roteiros hardcoded amarrados ao
domínio do `task_manager_flutter` atual, valor limitado fora daquele contexto).**

1. **Task 11.1 — `EndpointTesterScreen`.**
   `lib/screens/sistema/endpoint_tester_screen.dart`: campo de texto para `path` (livre,
   digitável — não lista hardcoded, ao contrário do original), dropdown de verbo
   (GET/POST/PUT/DELETE), editor de body JSON (`TextField` multiline com validação de JSON
   antes de enviar), botão "Executar" chamando `NetworkCaller` dinamicamente conforme o verbo
   escolhido contra `ApiLinks.baseUrl + path`, exibindo status code + body de resposta
   formatado. Opcional: `GET ApiLinks.adminEndpointsReflection` para autocompletar/sugerir
   paths conhecidos (não obrigatório para o `done`).
   - Verify: `flutter test test/screens/sistema/endpoint_tester_screen_test.dart` (body JSON
     inválido bloqueia o botão Executar; GET não exige body).
   - Done: terminal livre funcional para os 4 verbos contra qualquer path digitado.

### P12 — SIS-08 Query Builder

1. **Task 12.1 — Confirmação de segurança (verificação leve, não bloqueante — já mitigado no
   backend, ver seção "Confirmações de backend" acima).** Registrar no código-fonte
   (comentário) a referência ao `@PreAuthorize` e à restrição `SELECT`/`WITH` confirmados,
   para que a UI não precise reimplementar validação (defesa já está no backend).
2. **Task 12.2 — `QueryBuilderService` + `QueryBuilderScreen`.**
   `lib/services/query_builder_service.dart`: `listarSchemas()`/`listarTabelas()`/
   `listarColunas(schema,tabela)`/`executar(sql)` chamando os 4 endpoints via
   `NetworkCaller`. `lib/screens/sistema/query_builder_screen.dart`: layout 3 painéis
   (explorer de schema/tabela em árvore à esquerda, editor SQL no centro, grid de resultados
   embaixo/direita), botão "Executar" desabilitado se o texto não começar com
   `SELECT`/`WITH` (validação client-side **redundante** à do backend, feedback mais rápido
   ao usuário — não substitui a validação server-side).
   - Verify: `flutter test test/screens/sistema/query_builder_screen_test.dart` (botão
     Executar desabilitado para `DELETE FROM x`; habilitado para `SELECT * FROM x`).
   - Done: explorer lista schemas/tabelas/colunas reais, execução de `SELECT` retorna grid de
     resultado, tentativa de DML é bloqueada no cliente antes mesmo de chamar o backend.

---

## Wave 3

### P04 — SIS-02 Cadastro Empresa: UI (wizard 7 passos)

**Depende de P03** (`CadastroEmpresaService`, `CadastroEmpresaModels`).

1. **Task 04.1 — `CadastroEmpresaWizardScreen` (passos 1-4: Empresa, Usuários, Clientes,
   Contas).** `lib/screens/sistema/cadastro_empresa_wizard_screen.dart`: `StatefulWidget`
   com `Stepper`/abas `['Empresa','Usuários','Clientes','Contas','Chamados',
   'Funcionários','Executar']` (mesmos 7 passos do original), formulários pré-preenchidos com
   os mesmos defaults do arquivo original para os passos 1-4. Mapear usos de `GridColors.*`
   do arquivo original para `AppColors`/`Theme.of(context).colorScheme` (não existe
   `GridColors` no admin panel — ver seção "Interfaces herdadas").
2. **Task 04.2 — Passos 5-7 (Chamados, Funcionários, Executar) + integração com
   `CadastroEmpresaService`.** Completar os 3 passos restantes; passo "Executar" chama
   `CadastroEmpresaService.execute()` (de P03), plota `LogEntry`s incrementalmente via o
   callback já definido, mostra sucesso/erro final e permite novo rollback manual se
   necessário.
   - Verify: `flutter test test/screens/sistema/cadastro_empresa_wizard_screen_test.dart`
     (navegação entre os 7 passos, passo Executar aciona o service e reflete o log na tela).
   - Done: wizard completo, passo Executar dispara `CadastroEmpresaService` real (não
     duplica lógica de orquestração na UI).

### P06 — SIS-04 Config. Sistema: Controle de Jobs

**Depende de P05** (`AdminActionCard`).

1. **Task 06.1 — `JobsScreen`.** `lib/screens/sistema/configuracoes_sistema/jobs_screen.dart`:
   `GET ApiLinks.allJobs` lista ~18 jobs cron (nome, status, última execução), cada item com
   `AdminActionCard`-like row (reusar o widget de P05) para "Executar agora"
   (`ApiLinks.executarJob(nome)`, com switch opcional `forcar=true` **atrás de confirmação**
   — job forçado pode reprocessar dados já processados) e botão "Histórico" abrindo
   `ApiLinks.historicoJob(nome)` em modal/painel expansível.
   - Verify: `flutter test test/screens/sistema/configuracoes_sistema/jobs_screen_test.dart`
     (lista renderiza N jobs, executar com `forcar=true` exige confirmação).
   - Done: lista de jobs reais do backend, executar/forçar/histórico funcionais.

### P08b — SIS-04 Config. Sistema: Importação CSV — Cadastros (UI)

**Depende de P08a** (`ImportacaoCadastrosService`) **e P07** (padrão de seleção de arquivo
via `file_picker` já estabelecido, reusar mesma UX).

1. **Task 08b.1 — `ImportacaoCadastrosScreen`.** `lib/screens/sistema/configuracoes_sistema/
   importacao_cadastros_screen.dart`: seleção de tipo de cadastro (Empresas/Parceiros/
   Funcionários/Logins/Planos), seleção de arquivo via `file_picker` (mesmo padrão de P07),
   preview de linhas parseadas (`parseCsv`), execução linha-a-linha via
   `ImportacaoCadastrosService` (de P08a) com barra de progresso e log por linha (usando o
   callback de progresso já definido em Task 08a.1).
   - Verify: `flutter test test/screens/sistema/configuracoes_sistema/
     importacao_cadastros_screen_test.dart` (progresso avança por linha, erro em 1 linha não
     trava as seguintes, log final mostra resumo create/update/erro).
   - Done: fluxo completo seleção → preview → importação em lote → log de resultado por
     linha, sem travar em erro pontual.

---

## Wave 4

### P13 — Container final "Config. Sistema" + wiring do menu "Sistema"

**Depende de TODOS os planos anteriores** (só pode rodar depois que os 8 itens existirem).

1. **Task 13.1 — `ConfiguracoesSistemaScreen` (container final).**
   `lib/screens/sistema/configuracoes_sistema/configuracoes_sistema_screen.dart`: `TabBar`/
   `IndexedStack` agrupando as 4 seções já implementadas (Ações simples [P05], Jobs [P06],
   Importação Contas [P07], Importação Cadastros [P08b]) sob um único item de menu
   "Config. Sistema" (SIS-04), evitando o anti-padrão de arquivo monolítico do original —
   cada seção continua em seu próprio arquivo, este container só orquestra a navegação por
   abas.
2. **Task 13.2 — Wiring final de `SistemaMenuScreen`.**
   `lib/screens/sistema/sistema_menu_screen.dart`: substituir os 8 `SnackBar` placeholder
   (de Task 01b.2) pela navegação real: SIS-01→`AplicativoScreen`, SIS-02→
   `CadastroEmpresaWizardScreen`, SIS-03→`ConfiguracoesAdminScreen`, SIS-04→
   `ConfiguracoesSistemaScreen` (novo container desta task), SIS-05→`TelaEditorScreen`,
   SIS-06→`RolePermissaoScreen`, SIS-07→`EndpointTesterScreen`, SIS-08→
   `QueryBuilderScreen`.
   - Verify: `flutter test test/widgets/sistema_menu_screen_test.dart` (atualizado — cada
     tile navega para a tela real, não mais `SnackBar`).
3. **Task 13.3 — Validação final da fase.** `flutter analyze` limpo (0 erros/warnings) em
   todo o projeto; `flutter test` passando (suíte completa, incluindo todos os testes criados
   nas 14 tasks anteriores); `code-review` (skill) sobre o diff acumulado da Fase 2 inteira
   antes de considerar pronta para merge em `desenv`.
   - Verify: `flutter analyze && flutter test`
   - Done: os 8 itens acessíveis a partir de `HomeScreen → Sistema → {item}`, sem placeholder
     restante, `flutter analyze`/`flutter test` limpos, code-review sem blocker aberto.

---

## Threat Model (STRIDE) — itens desta fase com maior superfície

| Trust Boundary | Descrição |
|---|---|
| Admin panel (cliente MASTER) → backend `/api/admin/*`, `/api/ferramentas/query-builder/*` | Ações administrativas/destrutivas server-side, chamadas por login autenticado JWT do dono do sistema |
| Admin panel → `/api/importacao/*` | Upload de CSV com dados de terceiros (empresas/parceiros/contas), multipart |

| Threat ID | Categoria | Componente | Disposição | Mitigação |
|---|---|---|---|---|
| T-02-01 | Elevation of Privilege | `POST /api/admin/reset-database`, `fix-db`, `DELETE /api/admin/seed` | mitigate | Backend já exige `@tenantSecurity.isMaster()` (confirmado nesta sessão para `reset-database`; Task 05.1 confirma os demais). Cliente adiciona confirmação explícita (dialog "digite RESET"/"digite APAGAR") como defesa em profundidade — Task 05.2. |
| T-02-02 | Tampering | `POST /api/ferramentas/query-builder/executar` | mitigate | Backend restringe a `SELECT`/`WITH` via regex + `@PreAuthorize isMaster()` (confirmado nesta sessão). Cliente replica a mesma checagem antes de habilitar o botão — Task 12.2 (redundante, não substitui a defesa do backend). |
| T-02-03 | Tampering | `POST /api/importacao/*`, criação em lote via `ImportacaoCadastrosService` | accept | Superfície já existente no cliente (`task_manager_flutter`) sob o mesmo contrato de auth/tenant; admin panel só expõe a mesma capacidade a um usuário já MASTER. Sem mitigação adicional necessária nesta fase. |
| T-02-04 | Information Disclosure | `GET /api/admin/endpoints` (reflection, usado em SIS-07) | accept | Só lista paths/métodos já existentes no backend, sem dados sensíveis; usuário já é MASTER autenticado. |
| T-02-05 | Repudiation | Ações destrutivas sem log de auditoria client-side | accept | Fora do escopo desta fase (não há requisito de auditoria formal no `RESEARCH.md`/`ROADMAP.md`); backend já expõe `historicoJob` para jobs. Registrar como débito técnico se o PO quiser auditoria completa em fase futura. |
| T-02-SC | Tampering (supply chain) | `file_picker` (novo pacote, Task 07.1) | mitigate | Pacote já em uso no ecossistema do mesmo workspace (`task_manager_flutter`), Flutter Favorite oficial — não requer checkpoint bloqueante adicional de legitimidade, mas confirmar versão fixada em `pubspec.yaml` (não `any`). |

---

## Verificação goal-backward (o que prova que a Fase 2 atingiu seu objetivo)

**Objetivo (ROADMAP.md):** migrar os itens do grupo "Sistema" para o admin panel, exceto
"Empresas", reusando o par grid/form/detail da Fase 1.

**Verdades observáveis (usuário MASTER logado no admin panel):**
1. A partir de `HomeScreen`, existe um caminho "Sistema" que lista os 8 itens (SIS-01..08).
2. Aplicativo: lista, cria, edita, exclui um registro real contra `/api/aplicativo`.
3. Configurações Admin: as 6 abas (Cargo/CentroCusto/Departamento/Feriado/HorarioFunc/
   TipoProduto) fazem CRUD real contra seus respectivos endpoints.
4. Cadastro Empresa: o wizard de 7 passos cria uma empresa completa (empresa + 2 logins + 5
   clientes + 10 contas + 1 nfe + 3 chamados + 5 funcionários) no passo "Executar", com
   rollback funcional se qualquer etapa falhar.
5. Config. Sistema: as 4 seções (Ações simples, Jobs, Importação Contas, Importação
   Cadastros) disparam as ações reais correspondentes; as 3 ações destrutivas exigem
   confirmação explícita antes de executar.
6. Editor de Telas: lista telas reais, edita/reordena campos de uma tela e persiste via PUT.
7. Permissões: matriz reflete o estado real de `role-permissao`, toggle individual e em
   grupo persistem corretamente (nomes de tela convertidos sem reintroduzir o bug histórico).
8. Teste de Endpoints: terminal livre executa qualquer combinação verbo+path+body contra o
   backend real e mostra a resposta.
9. Query Builder: lista schemas/tabelas/colunas reais, executa `SELECT` e mostra resultado;
   tentativa de `DELETE`/`UPDATE`/`DROP` é bloqueada tanto no cliente quanto no backend.

**Artefatos obrigatórios (arquivos que devem existir ao final da fase):** todos os arquivos
listados na coluna "Arquivos principais" da tabela de execução acima (15 planos), mais os
testes correspondentes de cada `Verify`.

**Key links (onde é mais provável quebrar):**
- `GenericGridScreen._load()` → parser de `data`/`dados` aninhado (Task 01.1) — se quebrar,
  Aplicativo e os 6 sub-CRUDs de Config. Admin ficam com grid vazio silenciosamente.
- `CadastroEmpresaService.execute()` → `NetworkCaller.postRequest` com propagação de
  `empresaId`/`parceiroId` entre payloads — se quebrar, wizard cria empresa órfã sem os
  dados dependentes.
- `role_permissao_normalizacao.dart` → `toBackendTelaNome` — se divergir do backend, matriz
  de permissões parece salvar mas não reflete estado real (bug histórico #460/#471/#493).
- `QueryBuilderScreen` botão Executar → regex client-side igual à do backend — se divergir
  (client mais permissivo), UX engana o usuário até o backend rejeitar; se mais restritivo,
  bloqueia SELECTs válidos.

## Testes (resumo)

TDD (`tdd="true"`) em: Task 01.1 (parser), 01b.1 (`csv_parser`), 03.2
(`CadastroEmpresaService`), 08a.1 (`ImportacaoCadastrosService`), 10.1 (normalização de
nomes). Demais tasks: teste de widget cobrindo o `Verify` declarado. `flutter analyze` limpo
e `flutter test` completo são gate final (Task 13.3), não apenas por task individual — ver
aviso do `CLAUDE.md` do workspace sobre `flutter analyze` não pegar tudo (checar
`const`/`final` em campos usados por telas críticas manualmente quando aplicável, embora
nenhuma task desta fase mexa em `String.fromEnvironment`).

## Fluxo git

Branch única para a fase inteira, a partir de `desenv`:
`card-578-fase2-menu-sistema`. Cada um dos 15 planos acima = 1 commit atômico em PT-BR, sem
`Co-Authored-By`, na ordem das waves (1→2→3→4; dentro da wave 2, ordem livre). Merge local em
`desenv` só após Task 13.3 (validação final) e `code-review` sem blocker. Sem push (remoto só
na Fase 6, mesma decisão já registrada na Fase 1).
