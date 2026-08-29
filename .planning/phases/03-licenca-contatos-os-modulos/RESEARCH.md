# RESEARCH — Fase 3: Licença, Contatos, Ordem de Serviço, Módulos Contratados

**Pesquisado em:** 2026-08-29
**Domínio:** CRUD administrativo cross-tenant de 4 domínios do backend `AppAcademia` para o
`task_manager_admin_panel` ("Painel do Dono"), reusando o par `GenericGridScreen`/
`GenericDetailFormScreen` já existente (Fases 1-2).
**Confiança:** ALTA para os itens com backend confirmado por leitura direta de código-fonte
(Licença, Ordem de Serviço via `Chamado`, Módulos via `ParceiroModulo`/`EmpresaModulo`/
`ModuloServico`). BAIXA/MÉDIA para "Contatos" — ver achado crítico abaixo, é o único item com
ambiguidade real de domínio que bloqueia planejamento sem decisão do PO.

## Resumo executivo

Dos 4 itens do ROADMAP.md, **3 têm backend real e mapeável 1:1 para o padrão CRUD genérico já
existente** (Licença, Ordem de Serviço, Módulos Contratados), todos classificáveis como
**CRUD-compatível com adaptação** — nenhum é bespoke no sentido da Fase 2 (sem wizard, sem dashboard
de ações, sem editor visual), mas **dois deles exigem estender `FieldType`/`FieldConfig`** antes de
serem portáveis (data e dropdown de FK/enum não existem hoje no admin panel).

O quarto item, **"Contatos", tem um achado crítico que bloqueia decisão de escopo**: o único
domínio backend que corresponde literalmente ao nome (`ContatoController` → `/api/contato(s)`,
entidade `Contatos`) **não é um cadastro de "pessoa de contato"** — é um log de
mensagens (e-mail/SMS/alerta) vinculado a uma **negociação de compra e venda de grãos**
(`Negociacao`: `vendaId`, `compradorId`, `vendedorId`, `qtdSacos`, `vlrSacos`), um domínio de
trading agrícola sem nenhuma relação com "gestão do dono da plataforma SaaS". Pior: **a Fase 1 já
portou uma tela de demonstração ("Contatos") apontando para esse endpoint com campos errados**
(`nome`/`email`/`telefone`, que não existem na entidade real — os campos reais são `titulo`,
`mensagem`, `tipoContato`, `enderecoContato`, `status`, `negociacao`). Essa tela de demo nunca foi
testada contra o schema real (nenhum teste de integração no admin panel cobre o parsing das
colunas retornadas) — é provável que hoje ela carregue linhas mas mostre células vazias, porque
nenhum dos 3 `FieldConfig` (`nome`, `email`, `telefone`) bate com os campos reais do JSON
retornado. Ver `## Item 2 — Contatos` para o detalhamento completo e a decisão de PO recomendada
(criar domínio novo, não reaproveitar `/api/contatos`).

**Recomendação primária:** tratar esta fase como 4 sub-entregas independentes de complexidade
CRUD-compatível — mas com 2 pré-requisitos de infraestrutura compartilhada antes de qualquer uma
delas: (1) adicionar `FieldType.date` e um novo `FieldType.dropdown`/`FieldType.dropdownStatic`
(lista fixa client-side, sem busca remota — suficiente para status/prioridade/módulo, ver
`## Don't Hand-Roll`) ao par genérico; (2) resolver a ambiguidade de "Contatos" com o PO antes do
`plan-phase` (única pergunta desta pesquisa que bloqueia genuinamente, as demais têm default
seguro já aplicado — ver `## Decisões do PO`).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Gestão de Licença (ativar/desativar app, data vencimento) | Frontend (admin panel) | API (`/api/licencas`) | CRUD puro sobre tabela `licenca`, sem lógica de negócio no cliente além de validação de data |
| Bloqueio de acesso por licença vencida | API/Backend (`LicencaFilter`) | — | Já implementado e fora do escopo desta fase — o admin panel só ADMINISTRA os dados que o filtro já consome |
| Contatos (pendente de definição de domínio) | Frontend (admin panel) | API (endpoint a definir — ver Item 2) | Sem endpoint correto identificado ainda; qualquer que seja a decisão, é CRUD simples |
| Ordem de Serviço (via `Chamado`) | Frontend (admin panel) | API (`/api/chamados`) | CRUD + transições de status já implementadas no backend com autorização; cliente só orquestra chamadas |
| Módulos Contratados — catálogo (`ModuloServico`) | Frontend (admin panel) | API (`/api/modulo-servico`) | Catálogo global simples, CRUD puro |
| Módulos Contratados — atribuição a Parceiro/Empresa | Frontend (admin panel) | API (`/api/parceiro-modulo`, `/api/empresa-modulo`) | Lógica de "substituição total do conjunto" já implementada no backend (DELETE+INSERT); cliente só monta a lista de IDs marcados |

## User Constraints

Não há `CONTEXT.md` nesta fase (nenhum `/gsd:discuss-phase` prévio rodou para a Fase 3
especificamente). Constraints explícitas herdadas do `ROADMAP.md` e da tarefa desta pesquisa:

- CRUD completo dos 4 domínios, reusando o par `GenericGridScreen`/`GenericDetailFormScreen`.
- Gestão de Licença "pode exigir schema/backend novo" — **RESOLVIDO nesta pesquisa: schema e
  backend já existem por completo** (`Licenca`/`LicencaController`/`V110__Licenca.sql`), não
  precisa de trabalho de backend novo.
- Módulos contratados "reusa dominio `modulo-servico`/`servico-contratado` já existente" — **parcialmente
  impreciso**: `ServicoContratado` (`/api/servico-contratado`) é na verdade um domínio fiscal (item
  de serviço para NFS-e, com campos de tributação CBS/IBS) usado no onboarding de cadastros (Fase
  2, importação), **não** o mecanismo de atribuir módulo a parceiro/empresa. O mecanismo correto é
  `ParceiroModuloController`/`EmpresaModuloController` — já identificado na pesquisa da Fase 2b
  (`.planning/phases/02b-onboarding-cross-tenant/RESEARCH.md`), reconfirmado aqui por leitura
  direta do código-fonte.

## Project Constraints (from CLAUDE.md)

- Workspace `C:\App_Academia`: backend `AppAcademia` (Spring Boot, Java 17, PostgreSQL, Railway),
  Flutter cliente `task_manager_flutter`, Flutter base `task_manager_flutter_merged_final`
  (deve ficar igual, exceto branding), `task_manager_admin_panel` (este projeto, Painel do Dono —
  já listado no CLAUDE.md do workspace desde a Fase 2).
- Fluxo git obrigatório: branch `desenv` como base, branch própria por card, code review antes de
  merge, QA em `desenv` antes de MR/PR para `main`.
- Idioma: comentários e commits em PT-BR, sem `Co-Authored-By`.
- Testar antes de concluir; TDD quando cabível.
- Java 17 sempre — só relevante se a decisão de "Contatos" (Item 2) exigir backend novo (migration
  Flyway + entity + controller), não para os outros 3 itens.
- Banco: PostgreSQL, migrations Flyway numeradas em `src/main/resources/db/migration/`, índices
  explícitos para busca frequente, nunca `ddl-auto=update` em produção — relevante apenas se a
  decisão do Item 2 exigir tabela nova.
- `GenericGridScreen`/`FieldConfig` do admin panel: nunca fazer find-replace em massa de
  `const`→`final` em campos `String.fromEnvironment` (`api_links.dart`) — não há necessidade de
  tocar nesses campos nesta fase, mas o aviso do CLAUDE.md do workspace continua valendo para
  qualquer edição em `_backendUrl`/`_backendContextPath`.

## Item 1 — Gestão de Licença

**Arquivos lidos por completo:**
`AppAcademia/src/main/java/br/com/appAcademia/controller/LicencaController.java`,
`persistence/entity/Licenca.java`, `persistence/repository/LicencaRepository.java` (assinatura),
`config/LicencaFilter.java`, `src/main/resources/db/migration/V110__Licenca.sql`.

**Endpoints confirmados** (`@RequestMapping("/api/licencas")`, `@CrossOrigin(origins = "*")`,
**sem `@PreAuthorize` em nenhum método**):
- `GET /api/licencas` — lista **todas** as licenças, `List<Licenca>` direto (não paginado, sem
  envelope `{data:...}`, formato diferente de `GenericController`/`ChamadoController`).
- `GET /api/licencas/{id}` — busca por `id` (PK da tabela `licenca`, **não** `codApp`).
- `GET /api/licencas/status/{codApp}` — endpoint público (liberado no `LicencaFilter`, mas **não**
  no `SecurityConfig.permitAll()** — ver Pitfall 1 abaixo), retorna resumo `{codApp, ativo, valida,
  dataVencimento, diasRestantes, nomeApp}`; se não existir licença para o app, retorna
  `ativo:false, valida:false, diasRestantes:-1` (200 OK, não 404).
- `PUT /api/licencas/{id}` — atualiza `ativo`, `dataVencimento`, `dataInicio`, `observacao`,
  `nomeApp` (ignora `codApp` do body — não permite trocar o app vinculado via update).
- `POST /api/licencas` — cria nova licença (sem validar unicidade de `codApp` no controller —
  a constraint `UNIQUE` é só no banco, um `POST` duplicado retorna 500 genérico do Spring/JPA, não
  um 409/400 tratado).

**Campos da entidade `Licenca`** (tabela `licenca`, FK `cod_app` → `aplicativo.id`):
`id` (PK), `codApp` (Integer, `UNIQUE`, obrigatório), `nomeApp` (String, 100), `ativo` (boolean,
default `true`), `dataInicio` (LocalDate, default hoje), `dataVencimento` (LocalDate,
**obrigatório**, `NOT NULL` no banco), `observacao` (String, 500), `dhCreatedAt`/`dhUpdatedAt`
(LocalDateTime, gerenciados pelo controller no create/update, não pelo cliente).
Campos calculados (`@Transient`, só leitura, não existem na tabela): `isValida()` (ativo E
`hoje <= dataVencimento`), `getDiasRestantes()` (dias até o vencimento, negativo se vencida).

**Regra de negócio que a tela administra** (`LicencaFilter`, `@Order(20)`, roda logo após o
filtro JWT): bloqueia com HTTP 402 (Payment Required) qualquer request autenticado cujo `appId`
do token não tenha `Licenca` válida — exceto rotas de auth/status/actuator/websocket e **exceto
login MASTER, que nunca é bloqueado independente da licença**. Ou seja: a tela de gestão de
licença é o único lugar onde o dono do sistema pode reativar/estender/desativar o acesso de um
app inteiro — ação de alto impacto (derruba TODOS os tenants daquele `codApp` se `ativo=false` ou
a data vencer).

**Classificação:** CRUD-compatível, com 2 adaptações pontuais (não bespoke):
1. `GenericGridScreen._load()` espera `response.body['data']`/`['dados']` — `GET /api/licencas`
   retorna `List<Licenca>` **direto na raiz**, sem envelope. Precisa de um parser alternativo (ou
   um parâmetro `listResponseIsRawArray: true` no `GenericGridScreen`) — **novo achado, não
   coberto pelo Pitfall 1 da Fase 2** (que tratava só do caso `data: {dados:[...]}`).
2. Campos `dataInicio`/`dataVencimento` são `LocalDate` — precisam de `FieldType.date` (não existe
   hoje, ver `## Don't Hand-Roll`).

**Esforço estimado:** BAIXO — 1 tela `GenericGridScreen` (ou variante com parser de array raw) +
form com 5 campos editáveis (`nomeApp`, `ativo` boolean, `dataInicio`/`dataVencimento` date,
`observacao` multiline) + 1 campo somente-leitura calculado (`isValida`/`diasRestantes`, exibido
na grid mas não no form de edição). `codApp` deve ser somente-leitura no update (o backend ignora
mudança) e obrigatório+dropdown-de-Aplicativo no create (reusar `ApiLinks.allAplicativos` da Fase
2, `SIS-01`).

## Item 2 — Contatos (ACHADO CRÍTICO — bloqueia decisão de escopo)

**Arquivos lidos por completo:**
`AppAcademia/.../controller/ContatoController.java`, `persistence/entity/Contatos.java`,
`service/implementation/ContatoServiceImpl.java`, `persistence/entity/Negociacao.java`,
`task_manager_admin_panel/lib/screens/home_screen.dart` (tela de demonstração da Fase 1),
`task_manager_admin_panel/lib/config/api_links.dart` (getters `allContatos`/`createContato`/
`updateContato`/`deleteContato`, linhas 37-42).

**O que existe hoje:** `ContatoController` (`@RequestMapping({"/api/contato", "/api/contatos"})`)
é um wrapper fino de `GenericController<Contatos, Integer>` (o CRUD genérico do backend, com
paginação/filtros/tenant — ver `## Item 3` para o contrato completo de `GenericController`, é o
mesmo usado por `Chamado`... não, por outros domínios simples). A entidade `Contatos` tem:
`id`, `mensagem` (String), `titulo` (String), `tipoContato` (String, comentário no código: `E =
Email, S = SMS, A = Alert`), `enderecoContato` (String — endereço de envio, ex. e-mail/telefone),
`dtcontato` (LocalDateTime), `status` (String), e um `@ManyToOne` **obrigatório na prática**
`negociacao` (FK para `Negociacao`, com `@JsonBackReference` — não serializado na resposta, mas a
coluna `negociacao_id` existe no banco).

`Negociacao` é uma entidade de **negociação de compra/venda de sacos de grão** (`vendaId`,
`compradorId`, `vendedorId`, `dataNegociacao`, `qtdSacos`, `vlrSacos`, `status` com valores tipo
`A Aberta`/`D CONTR DISPONIVEL`/`F Finalizada`, `motivo`, `tipo` P/C/A/X/F). **Não tem nenhuma
relação com "gestão do dono da plataforma SaaS"** — é um domínio de trading agrícola completamente
alheio ao escopo do Painel do Dono descrito no `ROADMAP.md`/card #578 (dashboards de acesso,
licença, contatos, OS, módulos).

**Achado adicional (regressão silenciosa já em produção do admin panel):** a tela de demonstração
da Fase 1 (`lib/screens/home_screen.dart`, linhas 18-22 e 63-84) já usa
`ApiLinks.allContatos`/`createContato`/etc. apontando para este mesmo `/api/contatos`, com
`FieldConfig` de 3 campos: `nome`, `email` (`FieldType.email`), `telefone`. **Nenhum desses 3
campos existe na entidade `Contatos` real.** Isso não quebra com erro visível (o `GenericGridScreen`
simplesmente mostra colunas vazias para linhas cujo `row['nome']`/`row['email']`/`row['telefone']`
são sempre `null`, e um `POST`/`PUT` grava um JSON com chaves que o backend ignora — Jackson por
padrão ignora propriedades desconhecidas no bind, então a entidade é salva com `mensagem`/`titulo`/
etc. todos `null`). **Nenhum teste do admin panel cobre esse fluxo ponta-a-ponta contra o schema
real** — é um achado de código morto/quebrado desde a Fase 1, não introduzido por esta pesquisa.

**Decisão que bloqueia o plan-phase:** o que "Contatos" deveria significar no Painel do Dono não
está definido em nenhum lugar (card #578, `ROADMAP.md`, ou `.agents/memory/` — busca feita, sem
resultado além da menção genérica "contatos" na lista de features do card). Duas interpretações
plausíveis, nenhuma com backend pronto:

1. **Reaproveitar literalmente `/api/contatos`** (renomeando a tela para algo como "Log de
   Contatos de Negociação") — tecnicamente possível hoje (schema existe), mas semanticamente
   estranho para um "Painel do Dono" de um SaaS de academia/gestão (o domínio é de grãos/trading,
   não faz sentido de produto).
2. **Criar um domínio novo** "Contato" no sentido de agenda/CRM do dono (ex.: pessoa de contato de
   um Parceiro/Empresa para suporte comercial — nome, e-mail, telefone, cargo, vinculado a
   `Parceiro`/`Empresa`) — **backend não existe, precisa de migration Flyway + entity + controller
   novos**, fora do escopo Flutter puro que esta fase assumia.

Ver `## Decisões do PO` para o default recomendado (opção 2, com escopo backend mínimo) e a
justificativa de por que isso precisa de confirmação explícita do usuário antes do `plan-phase`
(é a única decisão desta pesquisa que muda o tipo de trabalho — Flutter-only vs. full-stack).

**Classificação:** **BLOQUEADO até decisão do PO.** Se a decisão for "criar domínio novo" (opção
2), o card muda de escopo (`Flutter cliente/admin panel` → `Full-stack AppAcademia + admin panel`)
e precisa seguir a regra "Escopo Obrigatório do Card" do `CLAUDE.md` do workspace ao virar card
Trello.

**Esforço estimado:** BAIXO (Flutter) se a opção 1 for aceita; BAIXO-MÉDIO (backend: 1 migration +
1 entity + reusar `GenericController`, seguindo o padrão idêntico de `ContatoController` mas para
tabela nova) + BAIXO (Flutter) se a opção 2 for aceita.

## Item 3 — Ordem de Serviço (via domínio `Chamado`)

**Arquivos lidos por completo:**
`AppAcademia/.../controller/ChamadoController.java` (393 linhas), `persistence/entity/Chamado.java`,
`enums/StatusChamadoEnum.java`, `enums/PrioridadeChamadoEnum.java`, `persistence/entity/Setor.java`.
`ChamadoServiceImpl.java` lido parcialmente (grep dirigido às linhas de `isMaster`/
`findByFilters`/`getEstatisticas` — suficiente para confirmar comportamento cross-tenant, não a
implementação completa de `fecharChamado`/`atualizarStatus`).

**Não existe domínio literal "OrdemServico"/"ordem-servico" no backend** (busca por glob
`*OrdemServico*`/`*ordem*` sem resultado). O domínio mais próximo e funcionalmente equivalente a
uma "ordem de serviço"/ticket administrativo é **`Chamado`** — já usado no cliente
(`task_manager_flutter`) e no wizard `CadastroEmpresaWizard` (Fase 2, `ApiLinks.createChamado`)
para abrir chamados de suporte. Tem workflow com status
(`ABERTO`/`EM_ANDAMENTO`/`FECHADO`/`CANCELADO`/`AGUARDANDO_CLIENTE`/`BLOQUEADO`) e prioridade
(`BAIXA`/`MEDIA`/`ALTA`/`URGENTE`/`NORMAL`) — mais estruturado que um simples CRUD de registro,
mais próximo de uma OS real do que `ServicoContratado` (que é puramente fiscal/tributário).

**Nota de nomenclatura para o `enum` descrições:** `StatusChamadoEnum`/`PrioridadeChamadoEnum` têm
os campos `descricao` claramente copiados/colados de outro contexto (`"App Pablo"`, `"App
Personal"`, `"App Academia"`, `"App Nutricionista"` como "descrição" de status como `ABERTO`,
`EM_ANDAMENTO` etc. — não fazem sentido semântico, parecem placeholder de código legado nunca
corrigido). **Não usar `getDescricao()` como label na UI** — usar o próprio nome do enum
(`ABERTO`→"Aberto" etc., mapeamento manual de label amigável no Flutter) para não vazar esse lixo
de dados para a tela do dono.

**Endpoints confirmados** (`@RequestMapping({"/api/chamados", "/api/chamado"})`):
- `GET /api/chamados?pagina=&tamanho=&ordenarPor=&direcao=&titulo=&status=&prioridade=&setorId=
  &parceiroId=&empresaId=&aplicativoId=&usuarioAberturaId=&dataInicio=&dataFim=` — paginado,
  resposta `{data: ComunicadosResponseDTO{dados, total}, response:{...}}` (mesmo formato aninhado
  já suportado pelo parser atual do `GenericGridScreen`, ver Item 1). **`status`/`prioridade`
  filtram por índice ordinal (Integer), não por nome do enum** — ex. `status=0` filtra
  `ABERTO`, `status=1` filtra `EM_ANDAMENTO`.
- `GET /api/chamados/{id}` — retorna `Chamado` direto (não envelopado em `Response`).
- `POST /api/chamados` (body `ChamadoDTO`) — `@PreAuthorize("@tenantSecurity.isCliente() or
  @tenantSecurity.isMaster()")`. Aceita `empresa:{id}`, `usuarioAberturaId` (ou infere do audit).
- `PUT /api/chamados/{id}` (body `JsonNode` livre, não DTO tipado) — mesmo `@PreAuthorize`. Aceita
  parcialmente qualquer subconjunto de: `titulo`, `descricao`, `status` (aceita string, int
  ordinal, ou `{id:N}`), `prioridade` (idem), `setor:{id}` (ou `null` para remover), `parceiro:{id}`
  (não-master só pode manter o próprio `parceiroId`, valida via `TenantAccessDeniedException`),
  `usuarioAbertura:{id}`, `empresa:{id}` (não-master só pode manter a própria empresa).
- `POST /api/chamados/{id}/fechar` (body `ChamadoDTO`, contendo motivo) —
  `@PreAuthorize("@tenantSecurity.isCliente() or @tenantSecurity.isMasterOrContabilidade()")`.
- `PATCH /api/chamados/{id}/status?status=<ENUM_NAME>` —
  `@PreAuthorize("@tenantSecurity.isCliente() or @tenantSecurity.isMasterOrContabilidade()")`,
  transição de status dedicada (uso alternativo ao `PUT` genérico).
- `DELETE /api/chamados/{id}` — `@PreAuthorize("@tenantSecurity.isCliente() or
  @tenantSecurity.isMaster()")`.
- `GET /api/chamados/estatisticas?empresa=&parceiro=` — contagem por status, útil para um card de
  dashboard futuro (Fase 4), não necessário para o CRUD desta fase.

**Cross-tenant confirmado para MASTER** (`ChamadoServiceImpl`, grep dirigido): `findByFilters`
aplica filtro de `parceiro_id`/`empresa_id` só quando `!isMaster()` — MASTER lista TODOS os
chamados de TODAS as empresas/parceiros sem filtro forçado, exatamente o comportamento cross-tenant
que o Painel do Dono precisa. `@PreAuthorize` em `criar`/`atualizar`/`excluir`/`fecharChamado`/
`atualizarStatus` já libera `isMaster()` explicitamente — **nenhum endpoint precisa de mudança de
backend para o admin panel**, mesmo padrão de confirmação já feito para outros domínios na Fase 2b.

**Classificação:** CRUD-compatível com adaptação — não é um wizard nem dashboard, mas precisa de:
1. `FieldType.date` para `dataAbertura`/`dataFechamento`/`dataVencimentoObrigacao` (mesma
   necessidade do Item 1).
2. Um novo `FieldType` de seleção fixa (enum) para `status`/`prioridade` — ver `## Don't
   Hand-Roll`.
3. Um dropdown de FK para `empresa`/`parceiro`/`setor` — reusar o padrão de dropdown remoto já
   recomendado na Fase 2b/card 580 do cliente (busca debounced paginada), ou, se o volume de
   Setor/Empresa/Parceiro for pequeno o suficiente, um dropdown estático carregado uma vez (ver
   Pitfall 2).

**Esforço estimado:** MÉDIO — mais campos e relações que Licença, mas nenhuma lógica de
orquestração multi-entidade (diferente do wizard da Fase 2). Recomenda-se usar `PATCH
/api/chamados/{id}/status` para a mudança de status (ação dedicada, evita reenviar o objeto
inteiro) em vez do `PUT` genérico para esse caso específico.

## Item 4 — Módulos Contratados

**Arquivos lidos por completo:** `AppAcademia/.../controller/ModuloServicoController.java`,
`persistence/entity/ModuloServico.java`, `controller/ServicoContratadoController.java`,
`persistence/entity/ServicoContratado.java`, `controller/ParceiroModuloController.java` (195
linhas), `controller/EmpresaModuloController.java` (61 linhas). Cruzado com achado já registrado em
`.planning/phases/02b-onboarding-cross-tenant/RESEARCH.md` (seção "5. Módulo Contratado" e "6.
Catálogos globais") — **reconfirmado nesta pesquisa por leitura direta**, não apenas citado.

**Existem 3 domínios distintos sob o nome "módulo/serviço" — não confundir:**

1. **`ModuloServico`** (`/api/modulo-servico`, `/api/modulo_servico`) — **catálogo global** de
   módulos do sistema (`id`, `nome`, `descricao`, `ativo`). CRUD simples, `GET` paginado (formato
   `{data:{dados, totalElements}}`, já suportado pelo parser atual). **Sem `@PreAuthorize`, sem
   `TenantContext`** — qualquer autenticado (não só MASTER) pode criar/editar/excluir módulos do
   catálogo global. Já registrado como débito de segurança pré-existente na Fase 2b (não introduzido
   por esta pesquisa, mas relevante aqui porque **esta é a tela que EXPÕE esse catálogo pela
   primeira vez no admin panel** — recomenda-se ao menos confirmar/registrar o risco, ver
   `## Common Pitfalls`).
2. **`ServicoContratado`** (`/api/servico-contratado`) — **domínio fiscal**, item de serviço para
   emissão de NFS-e (campos `codigoNbs`, `indicadorOperacao`, `cstIbsCbs`, `cClassTrib`,
   `aliquotaCbs`/`aliquotaIbsUf`/`aliquotaIbsMun`, `valor`, vinculado a `Parceiro`/`Empresa`). **Não
   é o mecanismo de "módulo contratado da plataforma"** apesar do nome parecido — é usado hoje só
   no fluxo de importação de cadastros da Fase 2 (`ApiLinks.servicosContratados`/
   `createServicoContratado`). **Não faz parte do escopo desta fase** (ROADMAP.md menciona esse
   getter por engano/imprecisão — ver `## User Constraints` acima).
3. **`ParceiroModuloController`/`EmpresaModuloController`** — **o mecanismo real de "atribuir
   módulo contratado"**: `GET /api/parceiro-modulo?parceiroId=X` (retorna módulos já vinculados,
   com `valor`/`diaVencimento` calculados via JOIN SQL cru — `JdbcTemplate`, não JPA),
   `PUT /api/parceiro-modulo/{moduloId}` (body `{parceiroId, valor, diaVencimento}`, atualiza
   valor/dia de UM módulo já vinculado), `POST /api/parceiro-modulo` (body `{parceiroId,
   moduloIds:[...]}`, **substitui TODO o conjunto de módulos do parceiro — DELETE+INSERT, não
   incremental**: enviar `moduloIds` sem um módulo que já estava vinculado o remove). Equivalente
   para empresa: `GET`/`POST /api/empresa-modulo?empresaId=`/body `{empresaId, moduloIds:[...]}`
   (mesmo padrão de substituição total, mas **sem nenhum `@PreAuthorize`/validação de tenant** —
   IDOR real já documentado na Fase 2b, herdado aqui sem mitigação nova).

**Autorização confirmada** (`ParceiroModuloController.java`, leitura direta):
`GET` → `@PreAuthorize("@tenantSecurity.isMasterOrContabilidade() or @tenantSecurity.isCliente()")`
com validação adicional restringindo Cliente ao próprio `parceiroId`; `PUT`/`POST` →
`@PreAuthorize("@tenantSecurity.isMasterOrContabilidade()")`, e `validarParceiroPertenceAoTenant`
libera MASTER incondicionalmente (`if (tenantContext.isMaster()) return;`). **Nenhuma mudança de
backend necessária para o admin panel usar esses 2 endpoints.** `EmpresaModuloController` não tem
NENHUMA validação — MASTER (e qualquer autenticado) passa livre; já é um débito conhecido, fora do
escopo desta fase corrigir, mas a tela do admin panel deve ter cuidado de sempre confirmar
`empresaId` antes de disparar o `POST` destrutivo (ver Pitfall 3).

**Classificação:** CRUD-compatível, mas com **UX não-trivial** (não é um form linear) — a tela
precisa ser: (a) catálogo `ModuloServico` como `GenericGridScreen` simples (CRUD puro); (b) uma
tela de atribuição por Parceiro OU Empresa — buscar o parceiro/empresa (dropdown remoto, reusar
padrão de busca do card 580 do cliente ou o "Claude's Discretion" da Fase 2b), listar o catálogo
completo com checkbox "vinculado?" pré-marcado pelo `GET`, e no salvar montar o payload
`{parceiroId/empresaId, moduloIds: [ids marcados]}` — **não é um `GenericDetailFormScreen`
convencional**, precisa de widget custom (matriz de checkboxes, análogo em espírito à tela de
Permissões da Fase 2, mas mais simples — 1 dimensão, não 2).

**Esforço estimado:** MÉDIO — o catálogo (`ModuloServico`) é trivial (BAIXO), mas a tela de
atribuição é bespoke o suficiente para não caber no `GenericDetailFormScreen` puro (precisa de
lógica de "conjunto completo" — mesma classe de cuidado UX que "Permissões" da Fase 2, onde
"salvar" não é incremental).

## Standard Stack

Nenhuma biblioteca externa nova é necessária nesta fase — 100% reuso de `NetworkCaller`/
`GenericGridScreen`/`GenericDetailFormScreen`/`ApiLinks` já existentes. As mudanças são
**extensões internas** ao par genérico do admin panel (não pacotes pub.dev):

| Mudança interna | Motivo | Usada por |
|---|---|---|
| `FieldType.date` (novo) | `Licenca.dataInicio`/`dataVencimento`, `Chamado.dataAbertura`/`dataFechamento`/`dataVencimentoObrigacao` | Item 1, Item 3 |
| `FieldType.select`/`FieldType.dropdownStatic` (novo, lista fixa client-side de `{value,label}`) | `Chamado.status`/`prioridade` (enums fixos, poucos valores, não precisam de busca remota) | Item 3 |
| Suporte a `GET` cuja resposta é `List<T>` direto na raiz (sem envelope `data`/`dados`) no `GenericGridScreen` | `GET /api/licencas` | Item 1 |
| Widget novo `ModuloAtribuicaoScreen` (fora do par genérico, análogo em espírito a `RolePermissaoScreen` da Fase 2) | Atribuição de módulos não é CRUD de registro único, é edição de conjunto | Item 4 |

`## Package Legitimacy Audit` omitido — nenhum pacote pub.dev novo nesta pesquisa.

## Architecture Patterns

### Padrão a reusar (CRUD simples — Itens 1 e parte do 4)

```dart
GenericGridScreen(
  title: 'Licenças',
  listUrl: ApiLinks.allLicencas,       // GET /api/licencas — resposta é List direto, não envelope
  createUrl: ApiLinks.createLicenca,
  updateUrl: ApiLinks.updateLicenca,   // String Function(String id)
  deleteUrl: ApiLinks.deleteLicenca,   // NAO EXISTE no backend (sem DELETE em LicencaController) —
                                        // ver Common Pitfalls — considerar desabilitar exclusao na UI
  fields: [
    FieldConfig(key: 'codApp', label: 'Aplicativo', type: FieldType.dropdownStatic, required: true),
    FieldConfig(key: 'nomeApp', label: 'Nome do App'),
    FieldConfig(key: 'ativo', label: 'Ativo', type: FieldType.boolean),
    FieldConfig(key: 'dataInicio', label: 'Início', type: FieldType.date),
    FieldConfig(key: 'dataVencimento', label: 'Vencimento', type: FieldType.date, required: true),
    FieldConfig(key: 'observacao', label: 'Observação', type: FieldType.multiline),
  ],
)
```

### Padrão novo a criar (atribuição de conjunto — Item 4, análogo a Permissões da Fase 2)

Tela com 2 painéis: esquerda = seletor de Parceiro/Empresa (dropdown remoto ou campo de busca por
ID), direita = lista do catálogo `ModuloServico` com `Checkbox` por item, pré-marcado conforme
`GET /api/parceiro-modulo?parceiroId=X` (ou `empresa-modulo`). Botão "Salvar" monta
`{parceiroId, moduloIds: [ids marcados]}` e dispara `POST` — **alertar visualmente que salvar
substitui TODO o conjunto** (mesmo cuidado de UX já usado no `role_permissao_screen.dart` original
para o batch de grupo, adaptado aqui).

### Anti-padrão a evitar

- **Não tratar `ServicoContratado` como sinônimo de `ModuloServico`/módulo contratado.** São
  domínios diferentes (fiscal/NFS-e vs. catálogo de módulos de plataforma) que só coincidem no
  nome em português. Usar o endpoint errado aqui não dá erro de compilação nem 404 — simplesmente
  gerencia o domínio errado silenciosamente.
- **Não reaproveitar `/api/contatos` sem decisão explícita do PO** (Item 2) — mesmo que "funcione"
  tecnicamente, é o domínio errado (trading de grãos).

## Don't Hand-Roll

| Problema | Não construir | Usar em vez disso | Por quê |
|---|---|---|---|
| Seleção de data (`dataVencimento`, `dataAbertura` etc.) | `TextField` de texto livre validando formato manualmente | `showDatePicker` (Flutter SDK, já disponível, sem dependência nova) encapsulado em `FieldType.date` no `GenericDetailFormScreen` | Já é built-in do Flutter, zero dependência nova, evita bug de formato de data (DD/MM vs MM/DD, timezone) |
| Seleção de enum fixo (`status`, `prioridade` do Chamado) | Dropdown carregando de um endpoint remoto que não existe para esses enums | `DropdownButtonFormField` com lista de opções client-side hardcoded (os enums são estáveis, definidos no backend Java, não mudam em runtime) | Os valores já são conhecidos e fixos (6 status, 5 prioridades) — buscar de endpoint remoto seria over-engineering |
| Substituição de conjunto de módulos vinculados | Endpoint incremental (`PUT` por módulo individual) que não existe | `POST /api/parceiro-modulo`/`empresa-modulo` com a lista completa de `moduloIds` marcados (backend já faz DELETE+INSERT) | O backend já resolve a substituição; construir lógica de diff no cliente seria trabalho duplicado e arriscado (pode dessincronizar do servidor) |

**Key insight:** o maior risco desta fase não é complexidade de CRUD (baixa, comparado à Fase 2) —
é **confundir domínios com nomes parecidos** (`ServicoContratado` ≠ módulo contratado; `/api/contatos`
≠ contato de suporte do dono) e **assumir que `DELETE /api/licencas/{id}` existe** (não existe —
ver Common Pitfalls).

## Common Pitfalls

### Pitfall 1: `GET /api/licencas` não usa o envelope padrão `{data:...}`
**O que dá errado:** `GenericGridScreen._load()` espera `response.body['data']`/`['dados']`;
`LicencaController.listar()` retorna `ResponseEntity<List<Licenca>>` — o array vem direto na raiz
do JSON, sem chave `data`. O parser atual, ao não achar `data`/`dados`, cairia no fallback `[]` e
a grid ficaria vazia mesmo com licenças cadastradas.
**Por que acontece:** `LicencaController` foi implementado sem seguir o padrão `Response`/
`GenericResponseDTO` usado pela maioria dos outros controllers (`GenericController`,
`ChamadoController`) — provavelmente por ser um controller mais novo/simples, sem passar por
revisão de consistência de contrato.
**Como evitar:** adicionar suporte no `GenericGridScreen` para reconhecer resposta que é `List`
direto na raiz (`response.body is List`), além dos formatos já suportados (`data:[...]`,
`data:{dados:[...]}`). Alternativa mais isolada: um parâmetro `rawArrayResponse: bool` no
`GenericGridScreen`, testado só para este item.
**Sinais de alerta:** grid de Licenças carrega mas fica vazio mesmo com dados confirmados via
`curl`/Postman.

### Pitfall 2: Não existe endpoint `DELETE /api/licencas/{id}`
**O que dá errado:** `LicencaController` só expõe `GET`/`GET{id}`/`GET status/{codApp}`/`PUT`/
`POST` — **sem `DELETE`**. Se a tela genérica for montada com `deleteUrl` apontando para
`/api/licencas/{id}` mesmo assim, o botão de excluir vai retornar 405 (Method Not Allowed) do
Spring.
**Por que acontece:** provavelmente decisão intencional — excluir uma licença deixaria o app sem
registro nenhum, e o `LicencaFilter` trata "sem licença cadastrada" como bloqueio total
(`"Licença não encontrada para este aplicativo."`), o que é uma ação ainda mais drástica que
desativar (`ativo=false`, que already bloqueia mas preserva o registro/histórico).
**Como evitar:** não expor botão de excluir na tela de Licenças — usar apenas `ativo=false` via
`PUT` como "soft delete" funcional. Se o `GenericGridScreen` exigir `deleteUrl` obrigatório
(assinatura atual: `required this.deleteUrl`), avaliar tornar opcional (`String Function(String)?`)
ou passar uma função que sempre retorna erro tratado — **decisão de arquitetura pequena, mas real,
para o `plan-phase` resolver** (não é bloqueio, é ajuste de assinatura).
**Sinais de alerta:** botão de excluir na tela de Licenças retorna erro 405 em vez de confirmar
exclusão.

### Pitfall 3: `POST /api/empresa-modulo` sem nenhuma proteção de autorização
**O que dá errado:** diferente de `/api/parceiro-modulo` (protegido por
`@tenantSecurity.isMasterOrContabilidade()`), `/api/empresa-modulo` não tem `@PreAuthorize` nem
injeção de `TenantContext` — **qualquer login autenticado** (não só MASTER) pode chamar `POST
/api/empresa-modulo` e substituir o conjunto de módulos de **qualquer empresa** informando o
`empresaId` no body. Isso é um IDOR pré-existente, já documentado na pesquisa da Fase 2b, **não
introduzido por esta fase** — mas esta fase é a primeira a expor uma UI cliente que dispara esse
endpoint deliberadamente em massa (substituição total).
**Por que acontece:** o controller foi implementado como JDBC cru (`JdbcTemplate`) sem seguir o
padrão de segurança já estabelecido em `ParceiroModuloController` (mesmo pacote, mesmo dia,
aparentemente esquecido).
**Como evitar:** o admin panel em si não piora o risco (MASTER já teria acesso de qualquer forma),
mas o `plan-phase`/code-review desta fase deve **registrar o achado como débito a corrigir no
backend** (adicionar `@PreAuthorize("@tenantSecurity.isMasterOrContabilidade()")` +
`validarEmpresaPertenceAoTenant` análogo ao de `ParceiroModuloController`) — mesmo que não seja
tarefa desta fase Flutter, o usuário deve ser avisado explicitamente (ver `## Decisões do PO`).
**Sinais de alerta:** nenhum sintoma visível no admin panel (MASTER sempre tem acesso) — o risco é
para OUTROS tenants explorando o endpoint fora do admin panel, não detectável só testando esta
fase.

### Pitfall 4: Confundir `status`/`prioridade` do `Chamado` como string vs. ordinal
**O que dá errado:** o `GET /api/chamados` filtra `status`/`prioridade` por **índice ordinal
inteiro** (`status=1`), mas o `PUT /api/chamados/{id}` aceita **string, int, ou objeto** (`{id:N}`)
para o mesmo campo — contratos diferentes entre listar e editar do mesmo recurso.
**Por que acontece:** o `PUT` foi escrito para tolerar múltiplos formatos históricos (compat com
versões antigas do cliente), mas o `GET` nunca recebeu o mesmo tratamento.
**Como evitar:** ao montar o filtro de busca da grid, enviar o índice ordinal do enum
(`StatusChamadoEnum.values.indexOf(...)`); ao montar o payload de update, enviar a string do nome
do enum (`'ABERTO'`) — mais legível e já suportado por `valueOf`.
**Sinais de alerta:** filtro de status na grid não retorna nada (ou retorna tudo) porque o valor
enviado não bate com o índice esperado.

## Assumptions Log

| # | Claim | Seção | Risco se errado |
|---|---|---|---|
| A1 | "Ordem de Serviço" do ROADMAP.md deve reusar o domínio `Chamado` (não existe domínio literal "OrdemServico" no backend) | Item 3 | Se o PO tiver em mente um conceito de OS diferente (ex. ordem de serviço de manutenção/instalação, não um ticket de suporte), o mapeamento inteiro muda e precisaria de backend novo, análogo ao Item 2 |
| A2 | "Contatos" não deve reaproveitar `/api/contatos` (domínio de negociação de grãos) — recomendação de criar domínio novo | Item 2 | Já marcado como decisão que precisa de confirmação explícita do PO, não é assumido como fechado |
| A3 | `EmpresaController`/outros domínios de FK (Parceiro, Empresa, Setor) para os dropdowns do Item 3/4 já têm endpoint de listagem paginada reusável (`/api/parceiro`, `/api/empresa`, `/api/setor`) — não lidos nesta pesquisa, apenas inferido pela convenção já confirmada em outros domínios (Fase 2b) | Item 3, Item 4 | Se `/api/setor` não existir ou tiver contrato diferente, o dropdown de Setor no formulário de Chamado precisa de investigação extra no plan-phase |
| A4 | `ModuloServicoController`/`ServicoContratadoController` sem `@PreAuthorize` é aceitável para esta fase por já ser débito pré-existente fora de escopo, não uma regressão desta fase | Item 4 | Se o code-review considerar bloqueante expor uma UI nova sobre endpoint sem autorização (mesmo pré-existente), a fase pode precisar de uma task de backend adicional não estimada aqui |

## Decisões do PO (rascunho — default aplicado, pendente de confirmação onde marcado)

1. **Contatos — qual domínio implementar?** (ÚNICA decisão desta pesquisa que bloqueia
   genuinamente o `plan-phase`, ver Item 2) **DEFAULT RECOMENDADO: criar domínio novo** "Contato"
   com sentido de agenda/CRM do dono (pessoa de contato vinculada a Parceiro/Empresa — nome,
   e-mail, telefone, cargo/observação), com backend mínimo novo (1 migration Flyway + 1 entity +
   reusar `GenericController` — mesmo padrão trivial já usado por `ContatoController` atual, só
   que numa tabela/entidade nova, ex. `contato_comercial`/`ContatoComercial`, para não colidir com
   a tabela `contatos` existente do domínio de negociação). Justificativa: a alternativa (reusar
   `/api/contatos`) entrega uma feature que não faz sentido de produto (log de negociação de
   grãos) e herdaria a tela quebrada da Fase 1 sem consertar o problema real. **PRECISA DE
   APROVAÇÃO EXPLÍCITA DO USUÁRIO** antes do `plan-phase`, porque muda o tipo de card (Flutter-only
   → Full-stack) e o nome/schema da tabela nova (arbitrário até aqui, é sugestão desta pesquisa).

2. **Licença — a exclusão (`DELETE`) deve ser adicionada ao backend, ou a UI deve simplesmente
   não oferecer excluir?** DEFAULT: não oferecer excluir na UI (usar `ativo=false` como
   "desativar", já suficiente para a regra de negócio do `LicencaFilter`). Risco baixo de manter
   assim — não é decisão irreversível, pode virar `DELETE` depois se o PO quiser limpeza de dados
   de teste. Não bloqueia.

3. **Pitfall 3 (`EmpresaModuloController` sem autorização) — corrigir nesta fase ou só
   registrar?** DEFAULT: registrar como débito técnico no relatório final desta fase (mesmo
   padrão já usado nas Fases 2/2b para achados de segurança fora do escopo Flutter), sem bloquear
   o `plan-phase`. Ressalva: se o usuário preferir corrigir junto (adicionar `@PreAuthorize`
   análogo ao de `ParceiroModuloController`), é uma mudança de baixo risco e pequena, pode entrar
   como task extra de backend nesta mesma fase — **decisão de conveniência, não de bloqueio**.

4. **Módulos Contratados — a tela de atribuição gerencia Parceiro, Empresa, ou ambos?** DEFAULT:
   ambos (2 sub-telas ou 1 tela com seletor "Parceiro vs. Empresa" no topo), já que os 2 endpoints
   existem e o `ROADMAP.md` não distingue. Não bloqueia — é decisão de granularidade de UI, não de
   escopo de dados.

**Resumo para o usuário:** das 4 perguntas acima, **apenas a #1 (Contatos) precisa de resposta
explícita antes do `plan-phase`** — as outras 3 têm default seguro já aplicado e podem ser
ajustadas durante o planejamento sem re-trabalho significativo.

**DECISÃO CONFIRMADA PELO USUÁRIO (2026-08-29):** item 1 — criar domínio novo. Card desta fase
passa a ser **full-stack** (`AppAcademia` + `task_manager_admin_panel`), não Flutter-only. Nome
de tabela/entidade sugerido nesta pesquisa (`contato_comercial`/`ContatoComercial`) fica como
default a confirmar/ajustar durante o `plan-phase` se o planner achar nome melhor — não é
decisão de alto risco, só nomenclatura.

## Open Questions

1. **Contatos — ver `## Decisões do PO` item 1.** Bloqueia até resposta do usuário.
2. **Setor/dropdowns de FK do Item 3 (`/api/setor`, `/api/parceiro`, `/api/empresa` para listagem
   simples)** — não lidos nesta pesquisa (assumido via convenção, ver Assumption A3). Recomenda-se
   1 leitura rápida desses 3 controllers no início do `plan-phase` antes de estimar as tasks de
   dropdown do Item 3/4, para confirmar contrato de paginação/parâmetros de busca.
3. **`LicencaFilter` bloqueia com HTTP 402 — o Flutter cliente/admin panel já tratam esse código
   de status de forma amigável, ou aparece como erro genérico?** Não verificado nesta pesquisa
   (fora do escopo — a tela de gestão em si não precisa tratar 402, só o consumo do bloqueio nos
   apps clientes, que já está em produção). Mencionar no relatório final se o usuário quiser
   confirmar a UX do bloqueio como parte desta fase (fora do escopo original do ROADMAP.md).

## Sources

### Primária (leitura direta de código-fonte — ALTA confiança)
- `AppAcademia/.../controller/LicencaController.java` (completo)
- `AppAcademia/.../persistence/entity/Licenca.java` (completo)
- `AppAcademia/.../config/LicencaFilter.java` (completo)
- `AppAcademia/src/main/resources/db/migration/V110__Licenca.sql` (completo)
- `AppAcademia/.../controller/ContatoController.java` (completo)
- `AppAcademia/.../persistence/entity/Contatos.java` (completo)
- `AppAcademia/.../service/implementation/ContatoServiceImpl.java` (completo)
- `AppAcademia/.../persistence/entity/Negociacao.java` (completo)
- `AppAcademia/.../controller/ChamadoController.java` (completo, 393 linhas)
- `AppAcademia/.../persistence/entity/Chamado.java` (completo)
- `AppAcademia/.../enums/StatusChamadoEnum.java` (completo)
- `AppAcademia/.../enums/PrioridadeChamadoEnum.java` (completo)
- `AppAcademia/.../persistence/entity/Setor.java` (completo)
- `AppAcademia/.../service/implementation/ChamadoServiceImpl.java` (grep dirigido a
  `isMaster`/`findByFilters`/`getEstatisticas`/`findByParceiroId`, não lido por completo)
- `AppAcademia/.../controller/ModuloServicoController.java` (completo)
- `AppAcademia/.../persistence/entity/ModuloServico.java` (completo)
- `AppAcademia/.../controller/ServicoContratadoController.java` (completo)
- `AppAcademia/.../persistence/entity/ServicoContratado.java` (completo)
- `AppAcademia/.../controller/ParceiroModuloController.java` (completo, 195 linhas)
- `AppAcademia/.../controller/EmpresaModuloController.java` (completo, 61 linhas)
- `AppAcademia/.../controller/GenericController.java` (completo — contrato-base de vários domínios)
- `AppAcademia/.../config/SecurityConfig.java` (completo)
- `task_manager_admin_panel/lib/screens/home_screen.dart` (completo)
- `task_manager_admin_panel/lib/config/api_links.dart` (grep dirigido a Contato/Servico/Modulo/
  Licenca)
- `task_manager_admin_panel/lib/widgets/generic/field_config.dart` (completo)
- `task_manager_admin_panel/lib/widgets/generic/generic_grid_screen.dart` (completo)
- `task_manager_admin_panel/.planning/phases/02-menu-sistema/{RESEARCH,PLAN,02-REVIEW}.md`
  (formato/profundidade de referência, achados de `GenericGridScreen` reconfirmados)
- `task_manager_admin_panel/.planning/phases/02b-onboarding-cross-tenant/RESEARCH.md` (achado de
  `ParceiroModulo`/`EmpresaModulo`/catálogos globais reconfirmado por leitura direta nesta pesquisa)
- `.agents/memory/appacademia-trello-operational-log.md` (busca por "licenca", "ordem de servi",
  "painel do dono", "card 578", "wh94M1uI" — sem detalhamento adicional além do já conhecido: card
  #578 tem 110 SP estimados e "contatos"/"OS"/"licença"/"módulos" citados só como itens de escopo
  genéricos, sem especificação de domínio)

### Não consultadas (fora do escopo desta pesquisa)
- Nenhuma consulta a Context7/documentação externa — pesquisa 100% interna ao workspace (código-
  fonte já existente), sem necessidade de biblioteca externa nova.
- `/api/setor`, `/api/parceiro`, `/api/empresa` (controllers) — não lidos nesta rodada, ver `##
  Open Questions` item 2.

## Metadata

**Confidence breakdown:**
- Licença (schema, endpoints, regra de negócio do filtro): ALTA — leitura completa de todos os
  arquivos-fonte relevantes.
- Ordem de Serviço via `Chamado` (endpoints, autorização, cross-tenant para MASTER): ALTA — leitura
  completa do controller e reconfirmação direta do comportamento MASTER-safe.
- Módulos Contratados (3 domínios distintos, autorização de cada um): ALTA — leitura completa dos
  5 controllers/entidades envolvidos, cruzado com achado já registrado na Fase 2b.
- Contatos: BAIXA para "qual é o domínio correto" (não determinável só por código-fonte — é uma
  decisão de produto) / ALTA para "o que existe hoje está semanticamente errado e a tela de demo
  da Fase 1 está quebrada" (confirmado por leitura direta das 2 entidades e do código Flutter).

**Research date:** 2026-08-29
**Valid until:** válido enquanto o código-fonte referenciado não mudar (sem dependência de versão
de biblioteca externa). Se a decisão de "Contatos" (Item 2) resultar em backend novo, esta pesquisa
precisa de um adendo específico para o schema da tabela nova antes do `plan-phase` daquele item.
