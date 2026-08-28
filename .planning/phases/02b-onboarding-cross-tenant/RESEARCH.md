# Phase 2b: Onboarding / Gestão Cross-Tenant (Parceiro, Empresa, Login, Roles, Módulo Contratado) - Research

**Researched:** 2026-08-28
**Domain:** Backend AppAcademia (Spring Boot) — endpoints MASTER cross-tenant + contrato Flutter admin panel
**Confidence:** HIGH (todas as afirmações de código vêm de leitura direta do controller/service, não de suposição)

## Summary

Card Trello #578, sequência da Fase 1 (scaffold/auth/grid/form já entregues em
`task_manager_admin_panel/.planning/phases/01-scaffold-auth-base/`). Esta fase
cobre o fluxo de onboarding de cliente novo (dono do sistema cria Empresa +
Parceiro + Login + atribui Roles/Módulo Contratado para QUALQUER tenant da
plataforma), o que exige que o usuário logado no admin panel seja
`tipoLogin = MASTER`.

Toda a superfície necessária (Parceiro, Empresa, Login, Role,
ParceiroModulo, EmpresaModulo, ModuloServico, ServicoContratado) foi lida
diretamente no código-fonte. **Nenhum endpoint bloqueia MASTER** — todos que
têm alguma checagem de tenant liberam explicitamente `isMaster()`. Mas há uma
descoberta importante fora do escopo da pergunta original: **vários
endpoints de escrita/leitura de Login e todo o `ModuloServicoController`/
`ServicoContratadoController`/`EmpresaModuloController` não têm NENHUMA
checagem de tenant** — o que os torna "MASTER-safe" por serem irrestritos
para qualquer usuário autenticado, não só MASTER. Isso é um débito de
segurança pré-existente, não deste card, mas deve ser registrado porque o
admin panel vai depender desses mesmos endpoints sem adicionar proteção
nova.

Achado crítico de regra de negócio: `GET /api/role/disponiveis` (usado pela
tela de Login > Roles para filtrar por módulo contratado) é um **stub não
implementado** — `RoleServiceImpl.recuperarModulosContratados()` sempre
retorna lista vazia (`TODO: Integrar com ParceiroModuloRepository ou
EmpresaModuloRepository`), então o endpoint sempre cai no fallback
`findRolesAlwaysAvailable()` (roles sem `moduloNecessario`). Isso significa
que hoje **não existe, no backend, nenhum gate real "role X só pode ser
atribuída se o parceiro/empresa tiver o módulo Y contratado"** — o campo
"Módulo Contratado" e a tela de Roles são desacoplados na prática.

**Primary recommendation:** implementar o wizard de onboarding como
sequência de chamadas separadas e idempotentes (não uma transação atômica
única no backend, pois não existe endpoint composto) — Empresa → Parceiro →
Login → Roles → Módulo Contratado — com possibilidade de retomar em qualquer
etapa se uma falhar no meio.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Criar Empresa (novo tenant) | API/Backend (`EmpresaController.createEmpresa`) | — | Só MASTER pode; regra de autorização já no backend |
| Criar Parceiro vinculado à Empresa | API/Backend (`ParceiroController.inserir`) | — | Regra de mass-assignment (empresa vem do tenant) só é bypassada para MASTER — DTO controla `empresa.id` explicitamente |
| Criar Login (usuário) vinculado a Empresa+Parceiro | API/Backend (`LoginController.createLoginAndPersonal`) | — | Nenhuma restrição de tenant hoje (débito, ver Pitfalls) |
| Atribuir Roles ao Login | API/Backend (`LoginController` PUT + `POST/{loginId}/roles/{roleId}`) | — | Validação de "role existe" é feita no backend; gate por módulo contratado é stub |
| Atribuir Módulo Contratado a Parceiro | API/Backend (`ParceiroModuloController`) | — | `@PreAuthorize` explícito `isMasterOrContabilidade()` |
| Atribuir Módulo Contratado a Empresa | API/Backend (`EmpresaModuloController`) | — | Sem checagem nenhuma (débito) |
| Orquestração do wizard multi-etapa | Frontend (admin panel Flutter) | — | Backend não tem endpoint composto/transacional único |

## User Constraints

Não há CONTEXT.md nesta pasta de fase (`02b-onboarding-cross-tenant`) — esta
pesquisa foi solicitada diretamente pelo orquestrador/usuário sem
`/gsd:discuss-phase` prévio. Constraints efetivas vêm do `CLAUDE.md` do
workspace (ver seção seguinte) e do pedido explícito da tarefa: cobertura
cross-tenant real, com evidência de código, sem implementação nesta etapa.

## Project Constraints (from CLAUDE.md)

- Workspace `C:\App_Academia\AppAcademia\CLAUDE.md` é a fonte de verdade
  para o backend: `desenv` é a branch base obrigatória; toda tarefa nasce em
  branch própria; code review obrigatório antes de merge; QA testa em
  `desenv`; MR/PR para `main` só após QA aprovado.
- Java 17 obrigatório (não 8, não 9).
- Migrations via Flyway; nunca `ddl-auto=update` em produção; secrets via
  variável de ambiente.
- Comentários e mensagens de commit em Português do Brasil; nunca incluir
  `Co-Authored-By`.
- Trello: todo card precisa declarar `Projeto alvo` e `Plataformas alvo`
  explicitamente (para este card: `Full-stack AppAcademia + Flutter cliente
  + base` NÃO se aplica — é um projeto novo, `task_manager_admin_panel`,
  fora da lista pré-definida do CLAUDE.md; deve ser declarado explicitamente
  ao criar/mover o card).
- Flutter (regras gerais do workspace, aplicáveis ao admin panel por
  analogia arquitetural, mesmo não sendo `task_manager_flutter`): `const`
  em widgets sem estado; nunca fazer find-replace mecânico de
  `const`→`final` em campos que usam `String.fromEnvironment` (incidente
  documentado — `lib/utils/api_links.dart` do cliente).

## Phase Requirements

Nenhum ID de requirement formal foi fornecido pelo orquestrador para esta
pesquisa (tarefa de pesquisa avulsa, não integrada a `/gsd:plan-phase`).
Mapeamento informal com base no pedido:

| # | Descrição | Research Support |
|---|-----------|-------------------|
| R1 | Onboarding cross-tenant de cliente novo (Parceiro+Empresa) | Seção "Endpoints" — Parceiro/Empresa confirmados MASTER-safe |
| R2 | Criar/editar Login para qualquer empresa/parceiro | Seção "Endpoints" — Login confirmado sem bloqueio (mas sem proteção nenhuma) |
| R3 | Gerenciar Roles | Seção "Endpoints" — Role é catálogo global, sem tenant |
| R4 | Atribuir Módulo Contratado a Parceiro/Empresa | Seção "Endpoints" — ParceiroModulo MASTER-safe via `@PreAuthorize`; EmpresaModulo sem proteção |

## Endpoints — Confirmação MASTER Cross-Tenant (com evidência)

### 1. Parceiro — `br.com.appAcademia.controller.ParceiroController` (`/api/parceiro`)

**CONFIRMADO MASTER-safe.**

- `GET /api/parceiro` (`listarComPaginacao`): filtro de empresa só é forçado
  quando `tenantContext != null && !tenantContext.isMaster()` (linha 267-271).
  MASTER pode listar parceiros de qualquer empresa passando `empresa`/
  `empresaId`/`empId` na query, sem restrição.
- `POST /api/parceiro/insert` (`inserir`): o bloco de mass-assignment
  protection que força `parceiroDTO.setEmpresa(tenantContext.getEmpresaId())`
  só roda `if (tenantContext != null && !tenantContext.isMaster())` (linha
  91). Para MASTER, o `empresa.id` do corpo da requisição é respeitado
  integralmente — **é assim que o admin panel cria um Parceiro sob QUALQUER
  Empresa**.
- `GET/PUT/DELETE /api/parceiro/{id}`: `validarAcessoProprioParceiro(id)`
  (linha 40-45) só lança `AccessDeniedException` quando
  `!tenantContext.isMaster()`. MASTER passa livre.
- `GET /api/parceiro/empresa/{id}` (`getByEmpresaId`): chama
  `tenantContext.validateCrossTenantAccess(id)`, que (ver `TenantContext.java`
  linha 90-103) retorna sem lançar exceção quando `isMaster()` é implícito
  pelo `!isMaster() && ...` do `if`.

Evidência-chave (`ParceiroController.java:91-98`):
```java
if (tenantContext != null && !tenantContext.isMaster()) {
    if (tenantContext.getEmpresaId() == null) {
        throw new AccessDeniedException("Acesso negado");
    }
    Empresa empresa = new Empresa();
    empresa.setId(tenantContext.getEmpresaId());
    parceiroDTO.setEmpresa(empresa);
}
```

**Nota de service:** `ParceiroServiceImpl.insert()` cria APENAS o registro
`Parceiro` (mais uma Conta Bancária padrão via
`cadastrosFinanceirosPadraoService.seedContaBancariaParaParceiro`). Não cria
Login. O fluxo "criar cliente novo" precisa de chamadas separadas para
Parceiro e Login.

### 2. Empresa — `br.com.appAcademia.controller.EmpresaController` (`/api/empresa`)

**CONFIRMADO MASTER-safe.**

- `GET /api/empresa`: usuários não-master recebem SOMENTE a própria empresa
  (ignora todos os filtros de query); MASTER cai no branch "comportamento
  original (sem restrições)" (linhas 49-91).
- `POST /api/empresa` (`createEmpresa`): bloqueia explicitamente não-MASTER
  com 403 ("Apenas administradores podem criar empresas") — linha 111-116.
  **Esta é a única forma de criar uma Empresa (novo tenant) e é
  exclusivamente MASTER.**
- `GET/PUT/DELETE /{id}`: usam `temAcessoTenant(id)` (linha 205-216), que
  retorna `true` sempre quando `tenantContext.isMaster()`.

Evidência-chave (`EmpresaController.java:110-118`):
```java
@PostMapping
public ResponseEntity<?> createEmpresa(@RequestBody EmpresaDTO empresaDTO) {
    if (tenantContext != null && !tenantContext.isMaster()) {
        Response response = Response.builder()
                .response(new ResponseError(true, "Apenas administradores podem criar empresas", HttpStatus.FORBIDDEN.value()))
                .build();
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(response);
    }
    return ResponseEntity.ok(empresaService.saveDto(empresaDTO));
}
```

### 3. Login — `br.com.appAcademia.controller.LoginController` (`/api/login`, `/api/logins`)

**CONFIRMADO MASTER-safe — mas com ressalva de segurança fora de escopo.**

- `GET /api/login` (`listarComPaginacao`): filtro de empresa via
  `LoginServiceImpl.buscarComPaginacao` → `tenantFilter.buildEmpresaFetchPredicate`
  (`TenantFilter.java:85-95`), que retorna `cb.conjunction()` (sem filtro)
  quando `ctx.isMaster()`. MASTER lista logins de qualquer empresa/parceiro.
- `POST /api/login` (`createLoginAndPersonal`): **nenhuma checagem de tenant
  no controller nem no service** — `login.setEmpresa(request.getEmpresa())`
  e `login.setParceiro(request.getParceiro())` (linhas 367-368) usam
  diretamente o que veio no corpo, sem validar contra `tenantContext`. Isso
  é MASTER-safe por definição (MASTER pode fazer qualquer coisa), mas
  também significa que **qualquer usuário autenticado, não só MASTER,
  poderia hoje criar um Login para outra empresa/parceiro via chamada
  direta à API** — não há `@PreAuthorize` nem checagem análoga à
  `validarAcessoProprioParceiro` do ParceiroController. Ver Common Pitfalls.
- `GET/PUT/DELETE /api/login/{id}`: idem — sem checagem de tenant nenhuma.
  MASTER passa livre (trivialmente, por ausência total de restrição).
- Validação obrigatória: `tipoLogin` é campo obrigatório desde correção de
  bug de produção documentada no próprio código (linhas 335-348) — login
  criado sem `tipoLogin` explícito **antes** defaultava silenciosamente para
  MASTER (vazamento cross-tenant real, já corrigido). Para onboarding de
  cliente novo, o admin panel deve sempre enviar `tipoLogin` explicitamente
  (`LoginEnum.APP_ABRACO`, id=6, é o tipo "Cliente" usado pelo
  `task_manager_flutter`).
- `POST /api/login/alterar-senha`: identifica o login por `email` (não por
  id/tenant), sem checagem de tenant — MASTER-safe.

Evidência-chave da obrigatoriedade de `tipoLogin` (`LoginController.java:335-348`):
```java
// Bug de producao CRITICO (vazamento cross-tenant): quando o campo
// "Tipo Login" era deixado em branco no Cadastro, o codigo antigo
// defaultava SILENCIOSAMENTE para LoginEnum.MASTER ...
if (request.getTipoLogin() == null) {
    throw new BadRequestException("Tipo Login é obrigatório.");
}
```

### 4. Roles — `br.com.appAcademia.controller.RoleController` (`/api/role`, `/api/roles`)

**CONFIRMADO MASTER-safe (Role é catálogo global, não tenant-aware).**

- `Role` não tem `codemp`/`codcli` nem relação com tenant — não há filtro de
  tenant em `RoleServiceImpl` (grep confirmado: nenhuma referência a
  `tenantFilter`/`tenantContext` no arquivo). Todos os CRUDs
  (`GET/POST/PUT/DELETE /api/role`) são irrestritos para QUALQUER usuário
  autenticado, incluindo MASTER — MASTER-safe trivialmente.
- `GET /api/role/disponiveis?empresaId=X&parceiroId=Y`: **stub não
  implementado**. `RoleServiceImpl.recuperarModulosContratados()` (linhas
  104-115) tem `TODO: Integrar com ParceiroModuloRepository ou
  EmpresaModuloRepository` e sempre `return List.of()`. Consequência:
  `getRolesDisponiveis()` cai sempre no fallback
  `roleRepository.findRolesAlwaysAvailable()` — roles com
  `moduloNecessario` preenchido (ex.: Comercial, Fiscal, Financeiro,
  Faturista, Ponto, Projetos, Precificação, GME, Service — 9 roles,
  conforme comentário em `LoginController.java:99-101`) nunca aparecem
  nesse endpoint, independentemente do módulo realmente contratado.
- `POST/{loginId}/roles/{roleId}` e `DELETE/{loginId}/roles/{roleId}`
  (em `LoginController`): sem checagem de tenant — atribuição/remoção de
  role a qualquer login por id, MASTER-safe (e também sem proteção para
  não-master, mesmo padrão do item 3).

Evidência-chave do stub (`RoleServiceImpl.java:104-115`):
```java
private List<String> recuperarModulosContratados(Integer empresaId, Integer parceiroId) {
    // TODO: Integrar com ParceiroModuloRepository ou EmpresaModuloRepository
    // Exemplo estrutura esperada: ...
    return List.of(); // Fallback vazio
}
```

### 5. Módulo Contratado — `ParceiroModuloController` (`/api/parceiro-modulo`) e `EmpresaModuloController` (`/api/empresa-modulo`)

**ParceiroModulo: CONFIRMADO MASTER-safe via `@PreAuthorize` explícito.**
**EmpresaModulo: MASTER-safe por ausência TOTAL de checagem (mesma ressalva de segurança do item 3).**

- `GET /api/parceiro-modulo?parceiroId=X`:
  `@PreAuthorize("@tenantSecurity.isMasterOrContabilidade() or @tenantSecurity.isCliente()")`.
  Dentro, `validarLeituraDoParceiro` chama `validarParceiroPertenceAoTenant`
  para MASTER/Contabilidade, que retorna imediatamente `if
  (tenantContext.isMaster()) { return; }` (`ParceiroModuloController.java:43-45`).
- `PUT /api/parceiro-modulo/{moduloId}` e `POST /api/parceiro-modulo`:
  `@PreAuthorize("@tenantSecurity.isMasterOrContabilidade()")` — MASTER
  autorizado; `validarParceiroPertenceAoTenant` também libera MASTER.
- `TenantSecurity.isMasterOrContabilidade()` (`TenantSecurity.java:37-40`)
  confirma: `tenantContext.isMaster() || tenantContext.isContabilidade()`.
- `EmpresaModuloController` (`GET/POST /api/empresa-modulo`): **nenhum
  `@PreAuthorize`, nenhuma injeção de `TenantContext`, nenhuma validação**.
  MASTER passa livre por definição — mas também qualquer login autenticado
  passa livre, o que é um IDOR real (qualquer cliente pode reatribuir
  módulos de qualquer empresa). Fora de escopo desta pesquisa (não é bug
  introduzido pelo admin panel), mas deve ser registrado como débito a
  corrigir eventualmente no backend (issue separada, não deste card).

Evidência-chave (`ParceiroModuloController.java:42-56`):
```java
private void validarParceiroPertenceAoTenant(Integer parceiroId) {
    if (tenantContext.isMaster()) {
        return;
    }
    ...
}
```

### 6. Catálogos globais — `ModuloServicoController` (`/api/modulo-servico`) e `ServicoContratadoController` (`/api/servico-contratado`)

**CONFIRMADO MASTER-safe (sem tenant algum, catálogo global).**

- Nenhum dos dois controllers injeta `TenantContext` nem tem
  `@PreAuthorize`. São repositórios JPA simples (`ModuloServicoRepository`,
  `ServicoContratadoRepository`) sobre entidades sem campo de tenant. MASTER
  usa livremente; mesma ressalva de "qualquer autenticado também pode" do
  item 5.

## Fluxo de Onboarding — Sequência de Chamadas (não há endpoint composto)

Não existe endpoint transacional único "criar cliente completo". O fluxo
real, orquestrado no cliente (admin panel), é uma sequência de chamadas
separadas:

```
1. POST /api/empresa                     { nome, razaoSocial, email, ... }
   -> retorna Empresa criada com id

2. POST /api/parceiro/insert              { nome, cpf/cnpj, email,
                                             empresa: { id: <empresaId> },
                                             tiposParceiro: [...], ... }
   -> retorna ParceiroResponse.parceiro com id
   -> efeito colateral automático: cria 1 Conta Bancária padrão para o
      parceiro (CadastrosFinanceirosPadraoService)

3. POST /api/login                        { email, senha?, nome,
                                             tipoLogin: 6,  // APP_ABRACO
                                             empresa: { id: <empresaId> },
                                             parceiro: { id: <parceiroId> },
                                             aplicativo: { id: <appId> },
                                             ativo: true }
   -> se "senha" omitido, backend usa senha padrão "123456" (BCrypt) —
      login.setSenha default (LoginController.java:353-358)
   -> se "roles" omitido, backend atribui automaticamente
      MODULE_EDIT/MODULE_OPEN/MODULE_INSERT/MODULE_DELET + role do app
      (APP_ROLE_KEY map, linha 53-58) — NÃO fica sem role nenhuma

4. PUT /api/login/{id}  { "roles": [{"id": X}, ...] }
   -> só mexe em roles se a chave "roles" vier explicitamente no JSON
      (bug de produção documentado — payload parcial sem "roles" NÃO apaga
      as roles existentes, mas também não seta nada se a chave faltar)

5. POST /api/parceiro-modulo  { parceiroId, moduloIds: [...] }
   -> substitui TODO o conjunto de módulos vinculados ao parceiro (DELETE +
      INSERT, não é incremental)
   OU
   POST /api/empresa-modulo  { empresaId, moduloIds: [...] }
   -> mesmo padrão substituição total, nível empresa
```

Cada etapa pode falhar independentemente (não há rollback automático entre
etapas — se o Login falhar após a Empresa+Parceiro já terem sido criados, o
wizard precisa suportar retomar a partir do passo 3, não recomeçar do zero).

## Contratos de Request/Response

### `EmpresaDTO` (`POST /api/empresa`)
```java
// br.com.appAcademia.persistence.dtos.EmpresaDTO
{
  "id": null,
  "nome": "string",
  "razaoSocial": "string",
  "email": "string",
  "site": "string",
  "contato": "string",
  "emailContato": "string",
  "telefoneContato": "string",
  "telefone": "string",
  "rua": "string",
  "numero": "string",
  "cep": "string",
  "cidade": { /* CidadeDTO */ },
  "centroCustoObrigatorio": false
}
```
Nota: `EmpresaController.createEmpresa` chama `empresaService.saveDto(empresaDTO)`
(não lido em detalhe — service não inspecionado nesta pesquisa, apenas o
controller). Campos como `cnpj`, `ie`, `ambiente`, `regime` existem na
entidade `Empresa` (usados em `updateEmpresa`) mas não estão em
`EmpresaDTO` — o create pode ter menos campos que o update. Validar em
planejamento se o create precisa desses campos extras (marcar como
`[ASSUMED]` — não verificado se `saveDto` aceita campos fora do DTO).

### `ParceiroDTO` (`POST /api/parceiro/insert`)
Campos completos em `ParceiroController.java`/`ParceiroDTO.java` — id, nome,
cpf, codProdutor, email, telefone1/2, razaoSocial (`@JsonAlias razao_social`),
incrMun, status, senha, endereco, fileAttachmentId, empresa (objeto com id),
regime (RegimeTributario), tipoCliente, tiposParceiro (List<TipoParceiro>),
valorMensal, diaVencimentoMensalidade, observacao, ie, rua, bairro, cidade,
estado, cep, numero, complemento, fileAttachment, ambiente
(PRODUCAO/HOMOLOGACAO, aceita string ou `{"id": "..."}` legado).

**Resposta:** `ParceiroResponse { parceiro: Parceiro, login: Login,
dadosPessoaisDto, personalDto }` — mas `ParceiroServiceImpl.insert()` só
popula o campo `parceiro`; os outros 3 campos ficam `null` neste fluxo (o
fluxo antigo Personal/Login foi removido do `insert`, conforme comentário
"Monta a entity Parceiro direto do DTO (sem fluxo Personal/Login antigo)").

### `Login` entity (`POST /api/login`, `PUT /api/login/{id}`)
Campos: id, email, senha (BCrypt, texto puro no request), nome, cpfCnpj,
ativo (default true), foto (data URI base64, máx. ~2.8MB — ver
`FOTO_MAX_BASE64_LENGTH`/`FOTO_DATA_URI_PATTERN`), roles (`List<Role>`,
`@ManyToMany` EAGER), setores (`List<Setor>`, `@ManyToMany` EAGER),
tipoLogin (`LoginEnum`, **obrigatório**), empresa (`Empresa`, `@ManyToOne`),
parceiro (`Parceiro`, `@ManyToOne`), aplicativo (`Aplicativo`), chamados
(`@OneToMany`, ignorar no create), audit.

`LoginEnum` valores confirmados (`LoginEnum.java`):
| id | nome | uso |
|----|------|-----|
| 1 | MASTER | dono do sistema — NUNCA deixar em branco no create (bug histórico) |
| 2 | APP_PERSONAL | |
| 3 | APP_ACADEMIA | |
| 4 | APP_NUTRICIONISTA | |
| 5 | APP_ALUNO | |
| 6 | APP_ABRACO | **tipo "Cliente" usado pelo task_manager_flutter** — provável valor default para onboarding de cliente novo via admin panel |
| 7 | APP_CONTABILIDADE | |
| 8 | APP_SITE_JOAO | portal separado, fora de escopo |

### `Role` (`GET /api/role`, `GET /api/role/disponiveis`)
Campos usados no Flutter cliente: `id`, `description` (label do
multiselect), `key` (chave de authority, ex. `ROLE_COMERCIAL`), `module`
(FK obrigatória), `aplicativo` (FK obrigatória, cod_app).

### Módulo Contratado — `parceiro_modulo` / `empresa_modulo` (tabelas nativas, sem entidade JPA dedicada — acesso via `JdbcTemplate`)
```
GET /api/parceiro-modulo?parceiroId=X
-> [{ "id": moduloId, "nome": "...", "descricao": "...", "valor": <valor_mensal>, "dia_vencimento": <int> }]

PUT /api/parceiro-modulo/{moduloId}
Body: { "parceiroId": X, "valor": 199.90, "diaVencimento": 10 }

POST /api/parceiro-modulo
Body: { "parceiroId": X, "moduloIds": [1,2,3] }   // substitui TODOS os vínculos

GET /api/empresa-modulo?empresaId=X
-> [{ "id", "nome", "descricao", "valor": SUM(valor_mensal dos parceiros) }]

POST /api/empresa-modulo
Body: { "empresaId": X, "moduloIds": [1,2,3] }    // substitui TODOS os vínculos
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Autorização MASTER cross-tenant | Nova checagem de tenant no Flutter | `@tenantSecurity.isMaster()`/`isMasterOrContabilidade()` já existentes no backend | Duplicar a regra no client é falso senso de segurança — o backend é a fonte de verdade; client só decide o que EXIBIR |
| Validação de "role permitida para o módulo" | Filtro client-side por módulo contratado | Nenhum — a feature não existe no backend (stub) | Implementar isso corretamente exige resolver o TODO em `RoleServiceImpl.recuperarModulosContratados()` primeiro — fora de escopo deste card |
| Wizard multi-step com estado | Gerenciamento de estado ad-hoc por tela | Um único `Stepper`/state controller no admin panel que guarda `empresaId`/`parceiroId` criados a cada etapa, permitindo retomar | Backend não é transacional entre as 4-5 chamadas — o client PRECISA rastrear onde parou |

**Key insight:** o backend não tem endpoint composto de onboarding. Toda a
orquestração e recuperação de falha parcial é responsabilidade do admin
panel Flutter.

## Common Pitfalls

### Pitfall 1: Login/Role/EmpresaModulo/ModuloServico/ServicoContratado não têm proteção de tenant NENHUMA
**O que dá errado:** não é um risco para o admin panel MASTER (que deve ter
acesso irrestrito mesmo), mas se o admin panel reutilizar código/rotas
pensando que "já está protegido" (como está em Parceiro/Empresa/
ParceiroModulo), pode assumir erroneamente uma garantia de tenant que não
existe nesses 5 endpoints.
**Por que acontece:** parte do código foi escrita antes do sistema de
`TenantContext`/`TenantFilter` existir (comentários confirmam: proteção foi
adicionada incrementalmente, endpoint por endpoint, conforme bugs de
produção eram reportados — ver comentários "CR:", "Bug de producao
CRITICO" espalhados pelos controllers lidos).
**Como evitar:** não é escopo deste card corrigir isso no backend (seria
outro card de segurança), mas o RESEARCH deve deixar claro para o planner
que o admin panel MASTER-only não introduz risco NOVO — o risco já existe
para QUALQUER usuário autenticado hoje.
**Sinais de alerta:** qualquer novo endpoint que precise ser adicionado
deve seguir o padrão de `ParceiroModuloController`
(`@PreAuthorize` + validação explícita), não o padrão de
`EmpresaModuloController` (sem nada).

### Pitfall 2: `GET /api/role/disponiveis` não reflete módulo contratado de verdade
**O que dá errado:** se a tela de atribuição de Roles do admin panel filtrar
por "módulo contratado" usando esse endpoint, o filtro nunca vai excluir
nada de fato — sempre retorna o mesmo conjunto fixo de "roles sempre
disponíveis" independentemente do que foi contratado.
**Por que acontece:** `recuperarModulosContratados()` é um stub
(`return List.of()`), documentado no próprio código como TODO.
**Como evitar:** para esta fase, tratar o filtro por módulo como
"aspiracional"/decorativo — não bloquear a UI nele. Se o card exigir
enforcement real, é pré-requisito resolver a integração com
`ParceiroModuloRepository`/`EmpresaModuloRepository` no backend antes.
**Sinais de alerta:** qualquer teste manual que atribua uma role de módulo
pago (ex. ROLE_FISCAL) sem o módulo estar contratado vai "funcionar" sem
erro — não é regressão do admin panel, é comportamento pré-existente.

### Pitfall 3: `POST /api/parceiro-modulo` e `POST /api/empresa-modulo` substituem TODO o conjunto, não são incrementais
**O que dá errado:** se a tela do admin panel mandar só os módulos que
mudaram (delta), o backend vai `DELETE FROM ... WHERE parceiro_id = ?`
seguido de `INSERT` só dos ids enviados — qualquer módulo não incluído no
payload é DESVINCULADO silenciosamente.
**Por que acontece:** implementação simples via `JdbcTemplate` direta
(`ParceiroModuloController.java:179-190`, `EmpresaModuloController.java:47-56`),
sem semântica de PATCH incremental.
**Como evitar:** a tela do admin panel deve sempre enviar a lista COMPLETA
de `moduloIds` desejados (estado final), nunca um delta.
**Sinais de alerta:** módulos desaparecendo do parceiro após uma edição que
só devia adicionar um módulo novo.

### Pitfall 4: `Login.roles`/`Login.setores`/`Login.ativo` têm inicializador padrão — PUT parcial pode apagar silenciosamente
**O que dá errado:** já documentado como bug de produção corrigido no
próprio `LoginController` (linhas 432-486) — o fix atual só mexe em
roles/setores/ativo quando a CHAVE veio explicitamente no JSON (`body.containsKey(...)`).
**Por que acontece:** Jackson nunca deserializa como `null` campos com
inicializador padrão (`= new ArrayList<>()`, `= true`).
**Como evitar:** o cliente Flutter do admin panel DEVE sempre enviar a
chave, mesmo que vazia (`"roles": []` para limpar, nunca omitir a chave se
a intenção é não mexer — omitir = "não mexer" é o contrato correto hoje).
**Sinais de alerta:** roles/setores/status ativo "sumindo" após qualquer
edição parcial do Login que não passe pelo formulário completo.

### Pitfall 5: senha default fraca ("123456") quando omitida no create
**O que dá errado:** `LoginController.createLoginAndPersonal` seta senha
BCrypt de "123456" se `senha` vier vazia/nula (linha 356-358) — sem forçar
troca no primeiro acesso.
**Por que acontece:** comportamento legado, não alterado nesta pesquisa.
**Como evitar:** o wizard do admin panel deveria SEMPRE gerar/exigir uma
senha explícita (ou pelo menos avisar visivelmente o operador MASTER da
senha padrão), já que não há fluxo de "definir senha no primeiro acesso"
confirmado nesta pesquisa (fora de escopo verificar — marcar como
`[ASSUMED: não existe fluxo de troca obrigatória]`, não confirmado).

## Recomendação: Tela Única vs Wizard Multi-Tela

### Opção A — Wizard multi-tela (Stepper), 4-5 passos (Empresa → Parceiro → Login → Roles → Módulo)

**Prós:**
- Espelha exatamente a sequência real de chamadas ao backend (não há
  atomicidade — o wizard reflete a realidade, não a esconde).
- Permite validação incremental por etapa (ex.: não deixar avançar para
  "Login" sem `empresaId`/`parceiroId` confirmados).
- Suporta retomada de onboarding incompleto (ex.: Empresa+Parceiro criados,
  mas Login falhou) — cada etapa pode reabrir isoladamente, reutilizando
  `GenericDetailFormScreen` já existente da Fase 1 para cada entidade.
- Reaproveita 100% os componentes genéricos da Fase 1 (`FieldConfigWindows`,
  `GenericDetailFormScreen`) — cada step é essencialmente um form já
  conhecido, só encadeado.
- Operador MASTER tem contexto claro do que já foi criado (ids visíveis a
  cada passo), reduzindo erro de digitar `empresaId` errado manualmente.

**Contras:**
- Mais telas/estado para implementar do que uma tela única.
- Precisa de um "estado de sessão do wizard" (empresaId/parceiroId
  temporários) que não existe hoje no admin panel.

### Opção B — Tela única com todos os campos (Empresa+Parceiro+Login+Roles+Módulo em um só form)

**Prós:**
- Menos navegação, potencialmente mais rápido para o caso feliz.

**Contras:**
- **Não reflete a realidade do backend**: são 4-5 chamadas HTTP
  sequenciais e independentes, não uma transação. Uma tela única precisaria
  simular atomicidade no client (criar Empresa, se falhar Parceiro precisa
  desfazer/avisar sobre Empresa órfã) — risco real de dados parciais
  inconsistentes sem tratamento explícito de rollback manual.
- Formulário gigante (Empresa tem ~13 campos, Parceiro ~20+, Login ~10,
  Roles multiselect, Módulos multiselect) — validação e UX ficam
  confusas em uma tela só.
- Dificulta reaproveitar os `FieldConfigWindows` já validados
  individualmente por entidade na Fase 1 (cada tela genérica hoje assume
  1 entidade por form).

### Recomendação

**Wizard multi-tela (Opção A).** A ausência de endpoint transacional
composto no backend torna a Opção B arriscada (estado parcial sem
rollback) e a Opção A é a que mais se alinha ao padrão já estabelecido na
Fase 1 (`GenericDetailFormScreen` por entidade). Cada etapa do wizard é
essencialmente uma instância do form genérico já existente, navegando em
sequência e carregando o id resultante para a etapa seguinte.

## Runtime State Inventory

Não aplicável — esta é uma fase de pesquisa para feature nova (onboarding),
não um rename/refactor/migração de dado existente.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `EmpresaDTO` não inclui `cnpj`/`ie`/`ambiente`/`regime` porque o create não precisa — não verificado se `EmpresaService.saveDto` aceita campos extras fora do DTO ou se são obrigatórios em outro fluxo | Contratos de Request/Response | Onboarding pode falhar silenciosamente ao criar Empresa sem CNPJ, se for obrigatório em regra de negócio fiscal não coberta por esta pesquisa |
| A2 | `LoginEnum.APP_ABRACO` (id=6) é o tipo correto para "cliente novo" criado via admin panel | Contratos — LoginEnum | Se o tipo correto for outro (ex. um tipo específico "cliente cadastrado pelo dono"), o onboarding atribuiria authorities erradas |
| A3 | Não existe fluxo de "definir senha no primeiro acesso"/"forçar troca de senha" para logins criados com senha default "123456" | Pitfall 5 | Se existir e não foi encontrado, a recomendação de UX pode ser redundante; se não existir mesmo, é risco de segurança real que o planner deveria considerar mitigar no wizard (gerar senha aleatória + enviar por e-mail, por exemplo) |

## Open Questions

1. **`EmpresaService.saveDto()` — regras de negócio no create de Empresa não lidas**
   - O que sabemos: `EmpresaController.createEmpresa` delega para
     `empresaService.saveDto(empresaDTO)`, MASTER-only.
   - O que não está claro: se há criação automática de dados padrão
     (catálogos financeiros — Forma de Pagamento, Categoria Financeira,
     Centro de Custo — mencionados em comentário de
     `ParceiroServiceImpl.insert()` como "já seedados quando a empresa foi
     criada") dentro do próprio `saveDto`, ou se é responsabilidade de outro
     fluxo.
   - Recomendação: ler `EmpresaServiceImpl.saveDto()` durante o
     `/gsd:plan-phase` real (fora do escopo desta pesquisa avulsa) antes de
     desenhar o formulário de criação de Empresa — pode haver campos
     obrigatórios não capturados em `EmpresaDTO`.

2. **Existe endpoint para desfazer/limpar uma Empresa criada sem Parceiro (onboarding abandonado no meio)?**
   - O que sabemos: `DELETE /api/empresa/{id}` existe e é MASTER-safe.
   - O que não está claro: se apagar uma Empresa que já tem Parceiro/Login
     vinculado causa erro de FK ou cascade — não testado nesta pesquisa.
   - Recomendação: tratar como ação manual/perigosa no wizard (não
     automatizar "desfazer"), exigir confirmação explícita do operador
     MASTER.

## Environment Availability

Não aplicável a esta pesquisa — não há dependência de ferramenta externa
nova além do backend AppAcademia (Railway) já em uso pela Fase 1.

## Sources

### Primary (HIGH confidence — leitura direta de código)
- `C:\App_Academia\AppAcademia\src\main\java\br\com\appAcademia\config\TenantContext.java`
- `C:\App_Academia\AppAcademia\src\main\java\br\com\appAcademia\config\TenantFilter.java`
- `C:\App_Academia\AppAcademia\src\main\java\br\com\appAcademia\config\TenantSecurity.java`
- `C:\App_Academia\AppAcademia\src\main\java\br\com\appAcademia\controller\ParceiroController.java`
- `C:\App_Academia\AppAcademia\src\main\java\br\com\appAcademia\controller\EmpresaController.java`
- `C:\App_Academia\AppAcademia\src\main\java\br\com\appAcademia\controller\LoginController.java`
- `C:\App_Academia\AppAcademia\src\main\java\br\com\appAcademia\controller\RoleController.java`
- `C:\App_Academia\AppAcademia\src\main\java\br\com\appAcademia\controller\ParceiroModuloController.java`
- `C:\App_Academia\AppAcademia\src\main\java\br\com\appAcademia\controller\EmpresaModuloController.java`
- `C:\App_Academia\AppAcademia\src\main\java\br\com\appAcademia\controller\ModuloServicoController.java`
- `C:\App_Academia\AppAcademia\src\main\java\br\com\appAcademia\controller\ServicoContratadoController.java`
- `C:\App_Academia\AppAcademia\src\main\java\br\com\appAcademia\service\implementation\LoginServiceImpl.java`
- `C:\App_Academia\AppAcademia\src\main\java\br\com\appAcademia\service\implementation\ParceiroServiceImpl.java`
- `C:\App_Academia\AppAcademia\src\main\java\br\com\appAcademia\service\implementation\RoleServiceImpl.java`
- `C:\App_Academia\AppAcademia\src\main\java\br\com\appAcademia\persistence\dtos\ParceiroDTO.java`
- `C:\App_Academia\AppAcademia\src\main\java\br\com\appAcademia\persistence\dtos\EmpresaDTO.java`
- `C:\App_Academia\AppAcademia\src\main\java\br\com\appAcademia\persistence\dtos\ParceiroResponse.java`
- `C:\App_Academia\AppAcademia\src\main\java\br\com\appAcademia\persistence\entity\Login.java`
- `C:\App_Academia\AppAcademia\src\main\java\br\com\appAcademia\enums\LoginEnum.java`
- `C:\App_Academia\task_manager_flutter\lib\web\screens\details\login_detail_screen.dart`
- `C:\App_Academia\task_manager_flutter\lib\utils\dropdown_helpers.dart`
- `C:\App_Academia\task_manager_flutter\lib\utils\api_links.dart`
- `C:\App_Academia\task_manager_admin_panel\.planning\phases\01-scaffold-auth-base\PLAN.md` e `RESEARCH.md`

### Secondary / Tertiary
- Nenhuma (pesquisa 100% baseada em leitura de código-fonte real do
  workspace, sem Context7/WebSearch — domínio é código proprietário, não
  biblioteca externa).

## Metadata

**Confidence breakdown:**
- Confirmação MASTER cross-tenant por endpoint: HIGH — cada afirmação tem
  trecho de código citado e caminho de arquivo.
- Contratos de request/response: HIGH para campos confirmados via DTO/
  entidade lida; MEDIUM para `EmpresaDTO` (ver Assumption A1 — não li
  `EmpresaServiceImpl.saveDto`).
- Recomendação wizard vs tela única: HIGH — decorre diretamente da ausência
  factual de endpoint transacional composto (fato verificado, não opinião).

**Research date:** 2026-08-28
**Valid until:** válido enquanto os controllers/services listados não forem
alterados — recomenda-se re-verificar `LoginController`/`RoleServiceImpl`
antes de implementar (ambos têm TODOs/débitos ativos sinalizados no próprio
código-fonte, sujeitos a fix em paralelo por outro card).
