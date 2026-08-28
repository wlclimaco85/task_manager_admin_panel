# RESEARCH — Fase 2: Migração do grupo de menu "Sistema"

**Pesquisado em:** 2026-08-28
**Domínio:** Migração de 8 telas do grupo `sistema` (`task_manager_flutter/lib/utils/menu_config.dart`,
linha ~562) para `task_manager_admin_panel`, **exceto** "Empresas" (screenIndex 11, fica no cliente).
**Confiança:** ALTA para mapeamento de telas/endpoints (leitura direta do código-fonte de ambos os
repositórios); MÉDIA para escopo exato de campos de alguns modelos (grep parcial).

## Resumo executivo

Dos 8 itens do menu, **apenas 2 são genuinamente CRUD simples** compatíveis com o padrão
`GenericGridScreen`/`GenericDetailFormScreen` já existente no admin panel: **Aplicativo**
(3 campos: id/nome/observação) e, de forma indireta, os **6 sub-módulos dentro de "Configurações
Admin"** (Cargos, Centro de Custo, Departamentos, Feriados, Horários, Tipos de Produto) — mas
"Configurações Admin" em si é um container de abas, não uma tela CRUD.

Os outros 6 itens (**Cadastro Empresa, Config. Sistema, Editor de Telas, Permissões, Teste de
Endpoints, Query Builder**) são telas bespoke (wizard multi-step, dashboard de ações
administrativas, editor visual de metadados, matriz de permissões, terminal de teste HTTP,
query builder SQL) que **não cabem** no par grid/form genérico e precisam de telas próprias no
admin panel, reaproveitando os endpoints de backend já existentes (mesmo contrato JWT/tenant).

**Recomendação primária:** tratar esta fase como 3 sub-entregas independentes — (1) portar
Aplicativo via `GenericGridScreen` (trivial), (2) portar os 6 sub-CRUDs de Configurações Admin
como telas `GenericGridScreen` individuais dentro de um novo container de abas simples no admin
panel, (3) para os 4 itens realmente bespoke (Config. Sistema, Editor de Telas, Permissões, Teste
de Endpoints, Query Builder — 5 itens, não 4), decidir com o PO se cada um justifica port completo
nesta fase ou se alguns ficam para fase futura (ver `## Open Questions`).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Aplicativo (CRUD simples) | Frontend (admin panel) | API (`/api/aplicativo`) | CRUD puro, sem lógica de negócio no cliente |
| Cadastro Empresa (wizard) | Frontend (admin panel) | API (múltiplos endpoints: empresa, login, parceiro, conta, chamado, funcionário) | Orquestração multi-step no cliente, cada step chama endpoint já existente |
| Configurações Admin (6 sub-CRUDs) | Frontend (admin panel) | API (6 endpoints REST distintos) | Container de abas + 6 CRUDs simples |
| Config. Sistema (dashboard de ações) | Frontend (admin panel) | API (`/api/telas/generate`, `/api/admin/*`) | Disparo de ações administrativas server-side, sem estado próprio no cliente |
| Editor de Telas | Frontend (admin panel) | API (`/api/telas`) | Editor visual de metadados de tela — lógica de edição fica no cliente |
| Permissões (Role x Tela x Campo) | Frontend (admin panel) | API (`/api/role-permissao`, `/api/role`) | Matriz de permissões — regra de exibição/normalização de nomes de tela é lógica de cliente |
| Teste de Endpoints | Frontend (admin panel) | API (endpoints variados, hardcoded na tela) | Ferramenta de QA/dev — chama a API real para validar contratos |
| Query Builder | Frontend (admin panel) | API (`QueryBuilderCaller` — endpoints de schema/tabela/execução SQL) | Editor SQL ad-hoc — risco de segurança concentrado no backend (validar que endpoint já restringe a admin) |

## User Constraints

Não há CONTEXT.md nesta fase (pesquisa solicitada diretamente pelo usuário, sem `/gsd:discuss-phase`
prévio). Constraints explícitas dadas na tarefa:

- Migrar o grupo `sistema` **exceto** o item "Empresas" (screenIndex 11) — esse item fica no
  cliente `task_manager_flutter`.
- Escopo de itens a migrar: Aplicativo (3), Cadastro Empresa (66), Configurações Admin (40),
  Config. Sistema (63), Editor de Telas (52), Permissões (59), Teste de Endpoints (65), Query
  Builder (150).
- Apenas pesquisar/documentar nesta etapa — nenhuma implementação.

## Project Constraints (from CLAUDE.md)

- Workspace `C:\App_Academia`: backend `AppAcademia` (Spring Boot, Java 17, PostgreSQL, Railway),
  Flutter cliente `task_manager_flutter`, Flutter base `task_manager_flutter_merged_final`
  (deve ficar igual ao cliente, exceto branding). **`task_manager_admin_panel` não está listado
  explicitamente no CLAUDE.md do workspace** — ver `## Open Questions` (risco já registrado em
  MEMORY.md: "Pré-requisito: atualizar CLAUDE.md com path do projeto antes do plan-phase").
- Fluxo git obrigatório: branch `desenv` como base, branch própria por card
  (`card-<id>-<slug>`), code review antes de merge, QA em `desenv` antes de MR/PR para `main`.
- Toda alteração em `task_manager_flutter` deve ser avaliada para replicação em
  `task_manager_flutter_merged_final` — **não se aplica aqui**: esta fase só adiciona telas no
  admin panel; se qualquer item do grupo "Sistema" for **removido/desabilitado** do menu do
  cliente como parte da migração, essa remoção (se decidida) precisaria ser replicada nos dois
  repositórios Flutter cliente. Não assumir remoção sem confirmação do PO — ver Open Questions.
- Idioma: comentários e commits em PT-BR, sem `Co-Authored-By`.
- Testar antes de concluir; TDD quando cabível.
- Java 17 sempre (não 8/9) — relevante caso a fase precise de qualquer ajuste de backend
  (não deveria precisar; todos os endpoints já existem).
- Nunca fazer find-replace em massa `const`→`final` em `String.fromEnvironment(...)` —
  `task_manager_admin_panel/lib/config/api_links.dart` já documenta esse risco internamente.

## Mapeamento screenIndex → arquivo fonte → endpoints

Fonte da tabela: `task_manager_flutter/lib/web/screens/bottom_navbar_screen.dart`,
método `_buildScreensList()` (a lista de widgets é indexada diretamente pelo `screenIndex`
declarado em `menu_config.dart`).

| screenIndex | Item de menu | Arquivo fonte (web) | Widget | Tipo |
|---|---|---|---|---|
| 3 | Aplicativo | `web/screens/aplicativo_screen.dart` | `WebAplicativoGridScreen` | CRUD simples |
| 66 | Cadastro Empresa | `web/screens/cadastro_empresa_wizard.dart` | `CadastroEmpresaWizard` | Bespoke (wizard) |
| 40 | Configurações Admin | `web/screens/configuracoes_admin_screen.dart` | `WebConfiguracoesAdminScreen` | Container de abas (6 sub-CRUDs) |
| 63 | Config. Sistema | `web/screens/configuracoes_sistema_screen.dart` | `ConfiguracoesSistemaScreen` | Bespoke (dashboard de ações admin) |
| 52 | Editor de Telas | `web/screens/tela_editor_screen.dart` | `TelaEditorScreen` | Bespoke (editor visual) |
| 59 | Permissões | `web/screens/role_permissao_screen.dart` | `RolePermissaoScreen` | Bespoke (matriz role x tela x campo) |
| 65 | Teste de Endpoints | `web/screens/system_test_screen.dart` | `SystemTestScreen` | Bespoke (terminal de teste HTTP, 3 abas) |
| 150 | Query Builder | `windows/screens/query_builder_window_screen.dart` (usado no slot web também) | `QueryBuilderWindowScreen` | Bespoke (SQL query tool) |
| ~~11~~ | ~~Empresas~~ | ~~`web/screens/empresa_grid_screen.dart`~~ | — | **FORA DE ESCOPO** — fica no cliente |

Nota: há telas equivalentes em `windows/screens/` (mesma classe, plataforma Windows) para a
maioria dos itens — o mapeamento acima cobre a variante web, que é a fonte de contrato de
endpoints (mesma lógica HTTP, layout diferente).

## Item 1 — Aplicativo (screenIndex 3)

**Arquivo:** `task_manager_flutter/lib/web/screens/aplicativo_screen.dart` (20 linhas) —
wrapper fino sobre `DynamicGridWindowsScreen<Aplicativo>` (`lib/customization/dynamic_grid_windows_screen.dart`).

**Modelo:** `task_manager_flutter/lib/models/aplicativo_model.dart` — 3 campos: `id` (int),
`nome` (String), `observacao` (String). Nenhum campo relacional, nenhum dropdown.

**Endpoints (backend):** `AppAcademia/.../controller/AplicativoController.java`,
`@RequestMapping({"/api/aplicativo", "/api/aplicativos"})`:
- `GET /api/aplicativo?pagina=&tamanho=&ordenarPor=&direcao=&id=&observacao=&nome=` —
  paginado, resposta `Response{ data: ComunicadosResponseDTO{ dados, total } }`.
- `GET /api/aplicativo/{id}`
- `POST /api/aplicativo` (body `{nome, observacao}`)
- `PUT /api/aplicativo/{id}` ou `/api/aplicativo/update/{id}`
- `DELETE /api/aplicativo/{id}` ou `/api/aplicativo/delete/{id}`

**Classificação:** **CRUD-compatível com o padrão genérico do admin panel** — caso trivial,
mesmo perfil do "Contatos" de demonstração da Fase 1.

**Recomendação:** portar direto via `GenericGridScreen` + `FieldConfig` (3 campos: id readonly,
nome text required, observação multiline opcional). Nenhuma tela bespoke necessária.

**Atenção de contrato:** `GenericGridScreen` do admin panel (Fase 1) lê `response.body?['data'] ??
response.body?['dados']` esperando lista direta — mas o backend real de Aplicativo retorna
`data: { dados: [...], total: N }` (paginado, aninhado), não `data: [...]`. **Isso é uma limitação
já registrada no código-fonte da Fase 1** ("busca de listUrl não envia parâmetro de tamanho de
página... carrega um único lote e filtra localmente"). Adaptação necessária: ou (a) o parser do
grid genérico precisa reconhecer o formato `{data: {dados: [...], total}}` além de `{data: [...]}`,
ou (b) passar explicitamente `?tamanho=500` na URL como estratégia paliativa (mesmo padrão usado
em `tela_editor_screen.dart` linha 35: `/api/telas?tamanho=500`). Ver `## Common Pitfalls`.

## Item 2 — Cadastro Empresa (screenIndex 66)

**Arquivo:** `task_manager_flutter/lib/web/screens/cadastro_empresa_wizard.dart` (arquivo grande,
> 700 linhas prováveis — lido até linha 150). `CadastroEmpresaWizard`, `StatefulWidget` com wizard
de 7 passos (`_steps = ['Empresa', 'Usuários', 'Clientes', 'Contas', 'Chamados', 'Funcionários',
'Executar']`).

**Comportamento:** coleta dados de empresa + 2 usuários (ADMIN/FINANCEIRO) + 5 clientes + 10
contas (5 pagar/5 receber) + 3 chamados + 5 funcionários, todos pré-preenchidos com defaults, e no
passo "Executar" dispara sequencialmente chamadas `POST` para criar cada entidade (empresa
primeiro, depois dependentes usando o `empresaId` retornado), registrando log de sucesso/erro por
entidade (`_LogEntry`, `_CreatedEntity`, `_CadastroException`). Usa `NetworkCaller`,
`AuthUtility`, `ApiLinks` do cliente.

**Endpoints:** múltiplos, dependendo da implementação completa dos passos (não lidos até o fim do
arquivo nesta pesquisa) — plausivelmente `/api/empresa`, `/api/login` (ou `/api/usuario`),
`/api/parceiro`/`/cliente`, `/api/conta-pagar`, `/api/conta-receber`, `/api/chamado`,
`/api/funcionario`. **Não confirmado nesta pesquisa (arquivo lido parcialmente) — recomenda-se
leitura completa (`_step` >= 4, métodos de execução) antes do plan-phase.**

**Classificação:** **bespoke — wizard de orquestração multi-entidade**. Não cabe em
`GenericGridScreen`/`GenericDetailFormScreen` (não é CRUD de uma entidade, é criação encadeada de
~7 tipos de entidade com dados de teste/seed).

**Recomendação:** portar como tela própria no admin panel (`StatefulWidget` dedicado), reusando
`NetworkCaller` do admin panel e os mesmos endpoints. Avaliar se faz sentido nesta fase ou se é
candidata a fase separada, dado o tamanho do arquivo fonte.

## Item 3 — Configurações Admin (screenIndex 40)

**Arquivo:** `task_manager_flutter/lib/web/screens/configuracoes_admin_screen.dart` (104 linhas,
lido integralmente). `WebConfiguracoesAdminScreen` — container com abas horizontais (`_selectedTab`)
envolvendo 6 telas CRUD já existentes:

| Aba | Widget | Modelo | Campos | Endpoint backend |
|---|---|---|---|---|
| Cargos | `WebCargoGridScreen` | `Cargo` | nome | `/api/cargo` |
| Centro de Custo | `WebCentroCustoGridScreen` | `CentroCusto` | nome | `/api/centro-custo`, `/api/centro_custo` |
| Departamentos | `WebDepartamentoGridScreen` | `Departamento` | nome, numeroFolha | `/api/departamento` |
| Feriados | `WebFeriadoGridScreen` | `Feriado` | nome, data, repeteAno | `/api/feriado` |
| Horários | `WebHorarioFuncGridScreen` | `HorarioFunc` | nome, tipo, ativo | `/api/horarioFunc`, `/api/horario_func` |
| Tipos de Produto | `WebTipoProdutoGridScreen` | `TipoProduto` | tipoProduto | `/api/tipoProdutos`, `/api/tipoproduto` |

Cada uma dessas 6 telas é confirmada (`cargo_grid_screen.dart` lido integralmente) como wrapper
fino sobre o widget genérico **do cliente** (`lib/widgets/generic_grid_screen.dart` —
`GenericGridScreen<T>` legado, diferente do do admin panel, mas mesmo espírito: CRUD paginado
dirigido por `fieldConfigs`), com `fetchEndpoint`/`createEndpoint`/`updateEndpoint`/`deleteEndpoint`
apontando para REST simples.

**Classificação:** o container em si (`WebConfiguracoesAdminScreen`) é **bespoke apenas na
casca** (abas) — cada aba internamente é **100% CRUD-compatível** com o padrão
`GenericGridScreen`/`GenericDetailFormScreen` do admin panel.

**Recomendação:** não portar `WebConfiguracoesAdminScreen` como bloco monolítico. Em vez disso:
1. Portar os 6 sub-módulos como 6 instâncias de `GenericGridScreen` do admin panel (baixo esforço
   cada, mesmo padrão do item Aplicativo).
2. Criar um container de abas simples e próprio no admin panel (não precisa reusar código do
   cliente — é ~50 linhas de `TabBar`/`IndexedStack`) para agrupá-los sob "Configurações Admin",
   OU expor os 6 itens como entradas de menu separadas no admin panel (mais simples, evita
   recriar a UI de abas). **Decisão de UX a confirmar com o PO** — ver Open Questions.

## Item 4 — Config. Sistema (screenIndex 63)

**Arquivo:** `task_manager_flutter/lib/web/screens/configuracoes_sistema_screen.dart`
(4569 linhas totais — lido linhas 1-1341 nesta pesquisa, o suficiente para confirmar a natureza da
tela). `ConfiguracoesSistemaScreen` — dashboard de ações administrativas server-side, sem grid de
dados no sentido CRUD. Seções confirmadas:

- **Geração de Telas**: `POST /api/telas/generate?forceUpdate=&fullReset=`, `POST
  /api/admin/regenerar-telas`, limpeza de cache local de telas.
- **Dados de Teste (Mock)**: `POST /api/admin/seed?quantidade=&meses=&empresaId=`.
- **Notícias**: `POST /api/admin/jobs/noticias-limpar-e-baixar`, `DELETE
  /api/admin/jobs/noticias-apagar`.
- **Controle de Jobs** (`_JobsSection`, componente próprio): lista ~18 jobs cron do backend
  (scrapers, cotações, alertas, certificados NFC-e etc.), `GET /api/admin/jobs`,
  `POST /api/admin/jobs/{nome}/executar[?forcar=true]`, `GET
  /api/admin/jobs/{nome}/historico` — painel de monitoramento/disparo manual de jobs agendados.
- **Banco de Dados**: `GET /api/admin/db-status`, `POST /api/admin/fix-db`, `POST
  /api/admin/reset-database` (destrutivo, com dialog de confirmação "digite RESET"),
  `DELETE /api/admin/seed?empresaId=` (apagar empresa mock).
- **Importação** (`_ImportacaoSection`, `_ImportacaoCadastrosSection` — não lidas até o fim,
  arquivo continua além da linha 1341): upload de CSV com mapeamento de colunas configurável para
  Contas a Pagar/Receber, usa `file_picker` (dependência não presente no admin panel Fase 1).

**Classificação:** **bespoke — dashboard de ações administrativas + jobs + importação**. Não é
CRUD de nenhuma entidade única; é um painel de botões/formulários que disparam ações
server-side (`POST`/`GET` diretos via `TenantContext`), com resultado exibido em cards de log/JSON.

**Recomendação:** portar como tela própria. Dado o tamanho (4569 linhas, muito maior que os
demais itens), **fortemente candidata a ser dividida em sub-fases ou fase própria**: (1) ações de
telas/db/seed/notícias (menor risco, ~500 linhas), (2) controle de jobs (~600 linhas,
autocontido, dá para portar como widget separado), (3) importação CSV (depende de `file_picker`,
não presente no admin panel ainda — nova dependência). Ver Open Questions.

## Item 5 — Editor de Telas (screenIndex 52)

**Arquivo:** `task_manager_flutter/lib/web/screens/tela_editor_screen.dart` (lido 1-120 de um
arquivo maior). `TelaEditorScreen` — grid de telas (`GET /api/telas?tamanho=500`, resposta
`{data: [...]}` ou `{data: {dados/content: [...]}}`) com busca client-side por nome/título, e ao
clicar em "Editar" abre um editor (`_abrirEditor`, não lido até o fim) presumivelmente para editar
metadados/campos da tela (schema dinâmico usado pelo `DynamicGridWindowsScreen`/telas geradas
automaticamente via `/api/telas/generate`).

**Classificação:** **bespoke — editor de metadados de tela**. Superficialmente parece um grid
(lista de telas), mas a ação de "editar" abre um editor de estrutura (campos/colunas da tela),
não um form CRUD de valores simples — não confirmado em detalhe pois o arquivo não foi lido além
da linha 120. **Recomenda-se leitura completa antes do plan-phase** para confirmar se o editor em
si é portável para `GenericDetailFormScreen` ou se precisa de UI própria (provavelmente própria,
dado que edita definição de campos, não valores de registro).

**Recomendação:** a listagem (`GET /api/telas`) pode reusar `GenericGridScreen` só para a parte
de "visualizar/buscar tela", mas a ação de edição precisa de tela bespoke.

## Item 6 — Permissões (screenIndex 59)

**Arquivo:** `task_manager_flutter/lib/web/screens/role_permissao_screen.dart` (lido 1-120 de um
arquivo maior). `RolePermissaoScreen` — matriz de permissões por Role x Tela x Campo
(checkboxes), não um CRUD de registro único.

**Endpoints:**
- `GET /api/role-permissao/all` (resposta `{data: {dados: [...]}}`)
- `GET /api/role` (resposta `{data: {dados: [{id, description}]}}`)
- `PUT` (método `_salvar`, não lido até o fim — provavelmente `PUT /api/role-permissao/{id}` ou
  similar, por `telaNome`+`campo`+`valor`, com toggle de checkbox individual).

Contém lógica de negócio não-trivial: normalização de nomes de tela
(`_normalizeTelaNome` — lowercase + remove `_`) e conversão snake_case→camelCase
(`toBackendTelaNome`) para casar `menu_config.dart` (snake_case) com
`role_permissao.tela_nome` no backend (camelCase) — **débito técnico documentado inline no
próprio código-fonte** (fix de regressão do card #460/#471/#493). Essa lógica de matching
precisa ser replicada fielmente no port, não reinventada.

**Classificação:** **bespoke — matriz de permissões com lógica de normalização de nomes**. Não
cabe no padrão grid/form (não é uma lista de registros com create/update/delete individual, é uma
grade de checkboxes agregada por role selecionada).

**Recomendação:** portar como tela própria, copiando a lógica de normalização de nomes de tela
verbatim (é lógica pura, sem dependência de widget do cliente) para evitar reintroduzir o bug já
corrigido.

## Item 7 — Teste de Endpoints (screenIndex 65)

**Arquivo:** `task_manager_flutter/lib/web/screens/system_test_screen.dart` (lido 1-120 de um
arquivo maior). `SystemTestScreen` — ferramenta de QA/dev com 3 abas:
1. **Endpoints CRUD** (`_CrudTestTab`) — roteiro de testes CRUD hardcoded (`_CrudScenario`,
   `_TestStep` com method/path/expectedStatus/payload), executa sequência de chamadas e reporta
   log de sucesso/erro.
2. **Telas Dinâmicas** (`_TelasTestTab`) — não lida em detalhe.
3. **Teste Endpoints** (`_EndpointsTestTab`) — provavelmente terminal livre de request HTTP
   (method/path/body arbitrários), similar a um mini-Postman embutido.

**Classificação:** **bespoke — ferramenta de teste/diagnóstico HTTP**, claramente fora do padrão
grid/form (não representa nenhuma entidade de domínio).

**Recomendação:** portar como tela própria. Baixa prioridade de negócio (ferramenta de
dev/QA, não operação do "dono" da academia) — candidata a ficar para fase posterior ou ser
descartada do escopo do admin panel se o PO decidir que ferramentas de teste HTTP não pertencem
ao "Painel do Dono". **Confirmar com o PO** — ver Open Questions.

## Item 8 — Query Builder (screenIndex 150)

**Arquivo:** `task_manager_flutter/lib/windows/screens/query_builder_window_screen.dart` (usado
também no slot web da lista de telas — mesma classe `QueryBuilderWindowScreen`, sem variante web
separada). Layout de 3 painéis (explorer de schema/tabela em árvore, editor SQL, grid de
resultados). Usa `QueryBuilderCaller` (`lib/services/query_builder_caller.dart`, não lido) para
`listarSchemas()`, `listarTabelas()`, execução de SQL.

**Classificação:** **bespoke — ferramenta de query SQL ad-hoc**, análoga a um mini-DBeaver. Fora
do padrão CRUD.

**Risco de segurança a validar no backend (fora do escopo desta pesquisa, mas relevante para o
plan-phase):** um Query Builder que executa SQL livre contra o banco de produção, exposto num
"Painel do Dono", precisa confirmar que o endpoint já restringe por role/tenant e não permite
DDL/DML destrutivo sem proteção adicional. Verificar `QueryBuilderCaller`/controller
correspondente antes de portar.

**Recomendação:** portar como tela própria, reservando tempo para revisão de segurança do
endpoint de execução SQL antes de expor no admin panel (superfície de ataque maior que as demais
telas).

## Standard Stack

Nenhuma biblioteca nova é estritamente necessária para os itens 1 (Aplicativo) e 3
(sub-CRUDs de Config. Admin) — reaproveitam 100% do `NetworkCaller`/`GenericGridScreen`/
`GenericDetailFormScreen` já existentes na Fase 1.

Para os itens bespoke, dependências adicionais identificadas por item:

| Item | Nova dependência necessária | Já presente no admin panel? |
|---|---|---|
| Config. Sistema (seção Importação) | `file_picker` (upload de CSV) | Não — Fase 1 não instalou |
| Editor de Telas | Nenhuma óbvia (CRUD de metadados) | — |
| Permissões | Nenhuma | — |
| Teste de Endpoints | Nenhuma | — |
| Query Builder | Nenhuma óbvia além do que já existe (`http`) | — |

**Nenhum pacote novo precisa ser instalado nesta fase de pesquisa** — a decisão de adicionar
`file_picker` fica condicionada a se a seção de Importação de Config. Sistema entrar no escopo
desta fase ou de uma fase futura (ver Open Questions). `## Package Legitimacy Audit` omitido —
nenhum pacote novo recomendado nesta pesquisa.

## Architecture Patterns

### Padrão já estabelecido no admin panel (Fase 1) — reusar para itens CRUD

```
GenericGridScreen(
  title: 'Aplicativo',
  listUrl: ApiLinks.allAplicativos,          // novo getter em ApiLinks
  createUrl: ApiLinks.createAplicativo,
  updateUrl: ApiLinks.updateAplicativo,      // String Function(String id)
  deleteUrl: ApiLinks.deleteAplicativo,
  fields: [
    FieldConfig(key: 'nome', label: 'Nome', required: true),
    FieldConfig(key: 'observacao', label: 'Observação', type: FieldType.multiline),
  ],
)
```

### Padrão a criar para telas bespoke (dashboard de ações)

`Config. Sistema` não tem estado de lista/paginação — é uma coleção de `Card`s com botão
"Executar" que dispara `POST`/`GET`/`DELETE` e mostra resultado JSON formatado. Não há
componente genérico equivalente no admin panel ainda. Recomenda-se extrair um pequeno widget
reutilizável `AdminActionCard` (título, subtítulo, ícone, cor, `onTap` assíncrono, exibição de
resultado/erro) já na primeira tela bespoke portada, para reuso nas seções seguintes (jobs,
db, seed) — evita duplicar o padrão 3-4 vezes como o arquivo original do cliente faz.

### Anti-padrão a evitar

- **Não portar `configuracoes_sistema_screen.dart` (4569 linhas) em uma única tarefa/arquivo.**
  O arquivo original já mistura 5+ responsabilidades (geração de telas, seed, notícias, jobs,
  banco de dados, importação) em um único `StatefulWidget` gigante com múltiplos widgets
  privados auxiliares. Replicar essa estrutura monolítica no admin panel repete o problema.
  Dividir em arquivos/telas menores por seção.

## Don't Hand-Roll

| Problema | Não construir | Usar em vez disso | Por quê |
|---|---|---|---|
| CRUD paginado com busca/create/update/delete | Grid+form customizado por módulo | `GenericGridScreen`/`GenericDetailFormScreen` do admin panel | Já existe, testado na Fase 1, cobre Aplicativo e os 6 sub-CRUDs de Config. Admin sem código extra |
| Normalização de nome de tela snake_case↔camelCase | Reimplementar do zero | Copiar `_normalizeTelaNome`/`toBackendTelaNome` de `role_permissao_screen.dart` verbatim | Lógica corretiva de bugs reais já resolvidos (cards #460/#471/#493); reinventar reintroduz o bug |
| Parsing de resposta paginada do backend (`{data: {dados, total}}` vs `{data: [...]}`) | Assumir um único formato | Suportar ambos os formatos no parser do `GenericGridScreen` (ou usar `?tamanho=500` como paliativo, replicando `tela_editor_screen.dart`) | Endpoints do backend AppAcademia não são uniformes — alguns retornam lista direta, outros objeto paginado |

**Key insight:** o maior risco desta fase não é "construir CRUD" (já resolvido na Fase 1), é
**subestimar o tamanho real dos itens bespoke** — `configuracoes_sistema_screen.dart` sozinho
(4569 linhas) é maior que todo o escopo da Fase 1 combinado.

## Common Pitfalls

### Pitfall 1: Formato de resposta paginada inconsistente entre endpoints
**O que dá errado:** `GenericGridScreen` do admin panel (Fase 1) só reconhece
`response.body['data']` ou `response.body['dados']` como lista direta. O endpoint de Aplicativo
(e provavelmente Cargo/Feriado/etc.) retorna `data: { dados: [...], total: N }` — objeto
aninhado, não lista.
**Por que acontece:** o backend `AppAcademia` usa dois padrões de resposta diferentes conforme o
controller (`ComunicadosResponseDTO` paginado vs. lista simples), herdados de evolução histórica
do código.
**Como evitar:** antes de portar qualquer item desta fase, testar manualmente (curl/Postman) a
resposta real de cada endpoint (`GET /api/aplicativo`, `/api/cargo`, etc.) e ajustar o parser do
`GenericGridScreen` para aceitar ambos os formatos, ou usar o parâmetro de paginação
(`tamanho=500`) como paliativo temporário — mas isso replica a limitação de busca client-side
já registrada como débito técnico na Fase 1 (não escala se algum endpoint tiver > 500 registros).
**Sinais de alerta:** grid carrega mas fica vazio (`_filteredRows.isEmpty`) mesmo com dados no
banco — sintoma de `data` sendo `Map` em vez de `List` e o parser silenciosamente retornando `[]`.

### Pitfall 2: Reintroduzir o bug de normalização de nome de tela em Permissões
**O que dá errado:** `menu_config.dart` usa `snake_case` para `id` dos itens de menu
(`'nfe_entrada'`), mas `role_permissao.tela_nome` no backend usa `camelCase`
(`'nfeEntrada'`). Sem a conversão `toBackendTelaNome`/`_normalizeTelaNome`, os checkboxes de
permissão não batem com os registros salvos.
**Por que acontece:** convenção de nomenclatura inconsistente entre o menu do frontend e o
schema do backend, histórico de 3 cards de correção (#460, #471, #493).
**Como evitar:** copiar as duas funções verbatim do arquivo fonte ao portar a tela de Permissões
para o admin panel, sem reescrever a lógica de matching.
**Sinais de alerta:** checkbox de permissão não reflete o estado salvo, ou salva mas não
persiste visualmente até trocar de role e voltar.

### Pitfall 3: Subestimar Config. Sistema como "só um dashboard"
**O que dá errado:** planejar o item como uma única task de 1-2h porque "é só botões chamando
endpoints", sem contar a seção de Importação (upload CSV com mapeamento de ~15 colunas
configuráveis por tipo de conta, dependência nova de `file_picker`) nem o painel de Jobs
(~18 jobs cron com histórico expandível).
**Por que acontece:** o arquivo tem 4569 linhas mas a parte inicial (ações simples) parece
enganosamente simples.
**Como evitar:** tratar Config. Sistema como fase própria ou dividir em pelo menos 3 tarefas
(ações simples / jobs / importação), com leitura completa do arquivo (linhas 1341-4569 não
lidas nesta pesquisa) antes de estimar.
**Sinais de alerta:** estimativa de esforço para este item menor ou igual à de Aplicativo.

### Pitfall 4: Query Builder exposto sem revisão de segurança
**O que dá errado:** portar a tela de Query Builder assumindo que o endpoint de execução SQL já
é seguro, sem confirmar autorização/sanitização no backend.
**Por que acontece:** a tela em si (`QueryBuilderWindowScreen`) não faz validação nenhuma no
cliente — toda a responsabilidade de segurança está no backend (`QueryBuilderCaller` →
controller não identificado nesta pesquisa).
**Como evitar:** antes do plan-phase, localizar e ler o controller backend correspondente
(provavelmente algo como `QueryBuilderController` com endpoint de `execute`), confirmar
`@PreAuthorize`/restrição de role admin e proteção contra DDL/DML destrutivo.
**Sinais de alerta:** endpoint aceita SQL arbitrário sem allowlist de operações ou sem checar
role do usuário autenticado.

## Assumptions Log

| # | Claim | Seção | Risco se errado |
|---|---|---|---|
| A1 | Endpoints de criação de entidades no `CadastroEmpresaWizard` (usuário, cliente, conta, chamado, funcionário) seguem os padrões REST já conhecidos do backend (`/api/login`, `/api/parceiro`, `/api/conta-pagar`, `/api/conta-receber`, `/api/chamado`, `/api/funcionario`) | Item 2 | Se os paths reais forem diferentes, o esforço de port muda; arquivo não foi lido além da linha 150 |
| A2 | O "editor" acionado por `_abrirEditor` em Editor de Telas edita estrutura/campos da tela (não valores de registro) | Item 5 | Se for na verdade um form CRUD simples de metadados, poderia reusar `GenericDetailFormScreen` — arquivo não lido além da linha 120 |
| A3 | O método `_salvar` de Permissões faz `PUT` individual por combinação role+tela+campo | Item 6 | Se for batch/outro verbo, a estratégia de port muda; não lido além da linha 120 |
| A4 | `_EndpointsTestTab` de Teste de Endpoints é um terminal HTTP livre (method/path/body arbitrários) | Item 7 | Não lido — inferido pelo nome da aba e padrão das outras 2 abas |
| A5 | `QueryBuilderCaller` chama um controller backend que já existe e está protegido por role admin | Item 8 | Não verificado nesta pesquisa — risco de segurança se assumido incorretamente |
| A6 | Seções de Importação de CSV (`_ImportacaoSection`, `_ImportacaoCadastrosSection`) de Config. Sistema usam `file_picker`, ainda não instalado no admin panel | Item 4 / Standard Stack | Confirmado pelo import no topo do arquivo (linha 2: `package:file_picker/file_picker.dart`) — risco baixo, mas dependência não avaliada quanto a slop/legitimidade nesta pesquisa |

## Decisões do PO (2026-08-28 — resolve Open Questions 1-4)

Registradas pelo usuário/PO ao retomar esta fase, para destravar o plan-phase sem bloquear em
pergunta adicional:

1. **`task_manager_admin_panel` no CLAUDE.md do workspace** — RESOLVIDO. O escopo já foi
   atualizado em `C:\App_Academia\CLAUDE.md` (seção Escopo) incluindo o path e a descrição do
   projeto. As regras de branch/code review/replicação do workspace já se aplicam formalmente a
   este repositório.

2. **Configurações Admin: tabs vs. itens de menu separados** — DECISÃO: manter como
   tab-container único "Configurações Admin" (menor ruído no menu, mais coeso). Criar um
   container de abas simples e próprio no admin panel (`TabBar`/`IndexedStack`, ~50 linhas,
   conforme já estimado na seção Item 3) agrupando os 6 sub-CRUDs (`GenericGridScreen` cada um).
   Não expor como 6 entradas de menu separadas.

3. **Config. Sistema: seções dev-tool (reset de banco, jobs) pertencem ao Painel do Dono?** —
   DECISÃO: SIM, são ferramentas administrativas legítimas do dono do sistema. Migrar todas as
   seções (Geração de Telas, Dados de Teste/Mock, Notícias, Controle de Jobs, Banco de Dados,
   Importação CSV) para o admin panel. Ressalva de segurança: as ações destrutivas/sensíveis
   (reset de banco `POST /api/admin/reset-database`, `fix-db`, apagar empresa mock `DELETE
   /api/admin/seed`, qualquer ação de job com `forcar=true`) devem ficar atrás de diálogo de
   confirmação explícita no cliente — reusar/replicar o padrão já existente no arquivo fonte
   (dialog "digite RESET" para `reset-database`) e adicionar confirmação equivalente onde a tela
   original não tiver (ex.: `fix-db`, apagar empresa mock). Isso não dispensa a divisão em
   sub-telas menores já recomendada (ações simples / jobs / importação) — ver Anti-padrão a
   evitar.

4. **Teste de Endpoints / Query Builder cabem na persona "dono da academia"?** — DECISÃO: SIM,
   são ferramentas de suporte/diagnóstico que o dono/admin do sistema usa para investigar
   problemas dos clientes da plataforma; manter as duas no admin panel, sem reduzir o escopo dos
   8 itens. Query Builder mantém a ressalva de segurança já registrada (Pitfall 4): confirmar
   proteção de role/tenant no backend antes ou durante o port.

**Consequência prática para o plan-phase:** os 8 itens do grupo "Sistema" (exceto Empresas)
seguem no escopo integral desta Fase 2 — nenhum item foi cortado. O `gsd-planner` deve, ainda
assim, avaliar se o volume total (especialmente Config. Sistema, ~4569 linhas de origem, e
Cadastro Empresa, wizard de 7 passos) justifica dividir a execução em múltiplas tasks/commits
atômicos dentro da própria Fase 2, em vez de uma fase separada — a decisão de ESCOPO (o quê)
está fechada acima; a decisão de SEQUENCIAMENTO/granularidade de tasks (como) fica com o
planner.

## Open Questions (histórico — respondidas acima, mantidas para rastreabilidade)

1. ~~`task_manager_admin_panel` não está listado no `CLAUDE.md` do workspace~~ — RESOLVIDO, ver
   Decisões do PO item 1.

2. ~~Configurações Admin: manter UI de abas ou virar 6 itens de menu separados?~~ — RESOLVIDO,
   ver Decisões do PO item 2 (tab-container único).

3. ~~Config. Sistema: escopo completo nesta fase ou dividir em sub-fases?~~ — RESOLVIDO, ver
   Decisões do PO item 3 (escopo completo nesta fase, com confirmação explícita nas ações
   destrutivas).

4. ~~Teste de Endpoints e Query Builder: pertencem ao "Painel do Dono"?~~ — RESOLVIDO, ver
   Decisões do PO item 4 (sim, ambos ficam).

5. ~~Leitura incompleta de 5 arquivos grandes~~ — RESOLVIDO. Os 5 arquivos foram lidos por
   completo (`cadastro_empresa_wizard.dart` 1395 linhas, `configuracoes_sistema_screen.dart`
   4569 linhas, `tela_editor_screen.dart` 658 linhas, `role_permissao_screen.dart` 503 linhas,
   `system_test_screen.dart` 1867 linhas). Ver seção "Leitura completa dos 5 arquivos grandes"
   abaixo para o detalhamento usado pelo plan-phase.

## Leitura completa dos 5 arquivos grandes (resolve Open Question 5)

### Item 2 — `cadastro_empresa_wizard.dart` (1395 linhas, completo)

Wizard de 7 passos que cria uma empresa + dados de seed em sequência, via `http.post`/`http.delete`
crus (não `NetworkCaller`), com rollback automático (LIFO) em caso de falha em qualquer etapa.

**Sequência de execução (`_execute`)**: 1) `POST /api/empresa` → guarda `empresaId`. 2) `POST
/api/login` para 2 usuários fixos (ADMIN, FINANCEIRO; `tipoLogin:1`). 3) Para 5 clientes: `POST
/api/parceiro` + `POST /api/login` (`tipoLogin:2`, vinculado ao parceiro). 4) `POST
/api/conta_pagar` ×5 (payload usa campo `parceiro`). 5) `POST /api/conta_receber` ×5 (**atenção**:
mesmo payload mas campo se chama `cliente`, não `parceiro` — assimetria do backend a replicar
fielmente). 6) `POST /api/nfe` ×1. 7) `POST /api/chamados` ×3. 8) `POST /api/chat` ×1 (condicional
a existir cliente). 9) Para 5 funcionários: `POST /api/parceiro` (`tipoAluno:'FUNCIONARIO'`) +
`POST /api/login` (`tipoLogin:3`).

**Propagação de IDs**: `empresaRef={id:empresaId}` montado uma vez e reutilizado em todos os
payloads seguintes; `parceiroRef={id:primeiro cliente}` idem para contas/chamados/chat.
`_extractId` tenta 4 formatos de resposta (`body.id`, `body.data.id`, `body.data.parceiro.id`,
`body.data.login.id`) — necessário pois cada endpoint devolve formato diferente.

**Erro/rollback**: primeira falha (`id == null`) lança `_CadastroException` e interrompe TUDO
imediatamente (não continua os itens seguintes da mesma lista); rollback percorre
`_createdEntities` em ordem reversa chamando `DELETE {url}/{id}` por item, sem parar se uma
remoção individual falhar.

**Dependências a recriar no admin panel**: `GridColors` (não existe — precisa criar equivalente
mínimo ou usar tokens do tema próprio do admin panel); confirmar se `NetworkCaller` do admin panel
tem `deleteRequest` (o wizard original usa `http.delete` cru, precisa migrar para `NetworkCaller`
por consistência com o resto do app, verificando que `TenantContext.applyToBody`/`headers` não
conflita com os payloads que já montam `empresa:{id}` manualmente).

**Complexidade de port: MÉDIA.** Lógica de negócio isolada e portável quase 1:1; o trabalho real é
trocar `http` cru por `NetworkCaller` e recriar `GridColors`. UI (~450 linhas de widgets internos)
é mecânica/repetitiva, copiável quase sem alteração.

### Item 4 — `configuracoes_sistema_screen.dart`, seções de Importação CSV (linhas 1341-4569, completo)

(Seções 1-1341 já detalhadas na pesquisa original — Geração de Telas, Mock, Notícias, Jobs, Banco
de Dados.) O restante do arquivo (3228 linhas) é ocupado inteiramente por duas seções de
importação CSV:

**`_ImportacaoSection` (Contas a Pagar/Receber, linhas 1267-2656) — port BAIXO-MÉDIO.** Delega todo
o trabalho pesado ao backend: `POST /api/importacao/preview` (multipart, detecta colunas do CSV) e
`POST /api/importacao/conta-pagar`|`conta-receber` (multipart, importação real; query params
`empId`, `parId`, `upsert=true`; form-data com o mapeamento de colunas + arquivo no campo
`arquivo`). Usa `package:file_picker` (`FilePicker.pickFiles(type: FileType.custom,
allowedExtensions:['csv'], withData:true)`). Auto-mapeamento de colunas via dicionário de
sinônimos normalizado (minúsculas, sem acento).

**`_ImportacaoCadastrosSection` (Empresas/Parceiros/Funcionários/Logins/Planos, linhas 2658-4569) —
port ALTO.** NÃO existe endpoint de importação em lote — todo o parsing de CSV (`_parseCsv`,
RFC4180-ish, separador `;`/`,` auto-detectado) e toda a lógica de negócio (dedup via GET+filtro em
memória, decisão create-vs-update, resolução de FK empresa/parceiro, heurísticas como
`_isFaturamentoServico`) rodam no cliente, disparando ~10 endpoints REST individuais por linha do
CSV (`/api/empresa`, `/api/parceiro/insert`, `/api/logins`, `/api/funcionario`, `/api/planos`,
`/api/servico-contratado`, cada um com GET de dedup + POST/PUT). Usa um helper próprio
`pickAndReadFile()` (`lib/helpers/file_upload_helper_web.dart` — `<input type=file>` HTML +
`FileReader`, não `file_picker`) — **recomendação: reusar este padrão no admin panel para AMBAS
as seções**, evitando a dependência externa `file_picker` (o próprio código-fonte já demonstra que
não é necessária).

### Item 5 — `tela_editor_screen.dart` (658 linhas, completo)

**Confirmado**: não é apenas um grid — é um editor de metadados de campo em 2 telas encadeadas.

1. **`TelaEditorScreen`** (grid): `GET /api/telas?tamanho=500` (parse de 3 formatos possíveis de
   resposta), busca client-side por nome/título, card por tela mostrando contagem de campos, botão
   "Editar" navega para o editor.
2. **`_FieldEditorScreen`** (editor, 2 painéis): `GET /api/telas/{telaNome}` carrega `fields`
   (ordenados por `fieldOrder`); painel esquerdo é `ReorderableListView` dos campos (drag-to-reorder
   dispara `PUT /api/telas/{telaId}/fields/reorder` com `[{id, fieldOrder}]`); painel direito
   (`_FieldPropertiesPanel`) edita as propriedades de UM campo selecionado — Identificação
   (label, fieldName, displayFieldName, fieldOrder), Tipo (`fieldType`: 16 opções incl.
   dropdown/multiselect/currency/cpf/cnpj — mais `maxLines` se multiline, `dropdownEndpoint` se
   dropdown/multiselect, `mask`), Visibilidade (6 switches: isInForm, isVisibleByDefault,
   isFilterable, isSortable, showInInsert, showInUpdate), Comportamento (4 switches: isRequired,
   enabled, isFixed, multiSelect), Payload (`defaultValue` com parsing especial: aceita JSON,
   bool, número, string literal ou templates `{{now+Nd}}`/`{{campo:xxx}}`). Salvar dispara `PUT
   /api/telas/{telaId}/fields/{fieldId}` com o campo inteiro.

**Complexidade de port: BAIXA-MÉDIA.** Arquivo autocontido, sem dependência externa incomum além
de `GridColors`/`AuthUtility`/`ApiLinks` (mesmos gaps do item 2). Não usa `NetworkCaller` (usa
`http` cru) — migrar por consistência. O `ReorderableListView` + os 2 endpoints extras de
reorder/update-por-campo são a única parte não-trivial; o resto é formulário mecânico.

### Item 6 — `role_permissao_screen.dart` (503 linhas, completo)

Confirma a pesquisa original: matriz Role × Tela × Campo. `GET /api/role-permissao/all` (todas as
permissões de todas as roles, filtro por role feito em memória) + `GET /api/role`. Save individual
por checkbox é **PUT** `${baseUrl}/api/role-permissao/{roleId}/{telaNome}` (telaNome via
`Uri.encodeComponent`, body `{campo: valor}`) — não POST batch como se poderia supor; o **POST
`/api/role-permissao/batch`** só é usado pelo checkbox de "grupo" (marca/desmarca todas as 5
permissões de todas as telas de um menu de uma vez, via `buildRolePermissionGroupBatch` — função
externa em `role_permission_group_selection.dart`, precisa ser portada junto).

**Lógica crítica a replicar verbatim** (funções top-level, puras, sem dependência de widget —
copiáveis 1:1): `_normalizeTelaNome` (lowercase + remove `_`) e `toBackendTelaNome`
(snake_case→camelCase) — corrigem uma regressão documentada nos cards #460/#471/#493 de mismatch
entre `menu_config.dart` (snake_case) e `role_permissao.tela_nome` no backend (camelCase). Não
reinventar esta lógica.

**Dependências a portar**: model `RolePermissao`, `RolePermissionCatalog`/`RolePermissionGroup`/
`RolePermissionMenuEntry` (`role_permission_catalog.dart`), `buildRolePermissionGroupBatch` e
funções irmãs (`role_permission_group_selection.dart`). Esse trio de arquivos de suporte é o
grosso do esforço, não a tela em si.

**Complexidade de port: BAIXA-MÉDIA.**

### Item 7 — `system_test_screen.dart` (1867 linhas, completo)

3 abas via `TabController`:

1. **`_CrudTestTab`** ("Endpoints CRUD") — dois modos: (a) "Iniciar Testes" roda ~25 cenários
   hardcoded (`_buildScenarios()`) contra ~35 endpoints reais de domínio (login, noticias,
   comunicado, chamados, contas, cotações, role, parceiro, dashboard, etc.), payloads fixos; (b)
   "Testar Todos" busca `GET /api/admin/endpoints` (reflection do backend, lista todos os
   controllers/paths/métodos do sistema) e roda CRUD genérico com payload heurístico
   (`_buildDynamicPayload`). Port ALTO (cenários muito amarrados ao domínio atual).
2. **`_TelasTestTab`** ("Telas Dinâmicas") — itera `GET /api/telas` e testa GET/POST/PUT/DELETE de
   cada tela dinâmica, resolvendo FK real via `_resolveFkId`. Port ALTO — depende do model
   `TelaConfig`/`telas_model.dart` completo.
3. **`_EndpointsTestTab`** ("Teste Endpoints") — **não é terminal HTTP livre**: path restrito a
   lista hardcoded de ~50 endpoints (comentário no código-fonte: "hardcoded 50 endpoints principais
   (reflection adicionado quando escalar)" — vários nem existem mais no backend real). UI: busca
   filtra a lista fixa, dropdown de método GET/POST/PUT/DELETE, botão testa o primeiro item
   filtrado. **Sem campo de body editável** — POST/PUT sempre enviam `{}` fixo. Port BAIXO-MÉDIO
   **se reconstruído do zero como path livre** (`TextField` de path + editor de JSON de body) em
   vez de copiar a lista hardcoded — o próprio comentário no código-fonte já sinaliza essa
   intenção original. **Recomendação para o admin panel**: portar SÓ esta 3ª aba, reconstruída
   como terminal HTTP genuinamente livre (path digitável, verbo, body JSON editável) — as abas 1
   e 2 são ferramentas de regressão amarradas a payloads do `task_manager_flutter` atual e têm
   valor limitado fora daquele contexto; não portar 1:1.

## Sources

### Primária (leitura direta de código-fonte — ALTA confiança)
- `task_manager_flutter/lib/utils/menu_config.dart` (linhas 520-620) — definição do grupo de menu "sistema"
- `task_manager_flutter/lib/web/screens/bottom_navbar_screen.dart` (linhas 170-540) — mapeamento screenIndex → widget
- `task_manager_flutter/lib/web/screens/aplicativo_screen.dart` (completo)
- `task_manager_flutter/lib/models/aplicativo_model.dart` (completo)
- `AppAcademia/src/main/java/br/com/appAcademia/controller/AplicativoController.java` (completo)
- `task_manager_flutter/lib/web/screens/cadastro_empresa_wizard.dart` (linhas 1-150)
- `task_manager_flutter/lib/web/screens/configuracoes_admin_screen.dart` (completo)
- `task_manager_flutter/lib/web/screens/cargo_grid_screen.dart` (completo)
- `task_manager_flutter/lib/models/{cargo,centro_custo,departamento,feriado,horario_func,tipo_produto}_model.dart` (grep de fieldConfigs)
- Controllers backend: `CargoController`, `CentroCustoController`, `DepartamentoController`, `FeriadoController`, `HorarioFuncController`, `TipoProdutoController` (grep de `@RequestMapping`)
- `task_manager_flutter/lib/web/screens/configuracoes_sistema_screen.dart` (linhas 1-1341 de 4569)
- `task_manager_flutter/lib/web/screens/tela_editor_screen.dart` (linhas 1-120)
- `task_manager_flutter/lib/web/screens/role_permissao_screen.dart` (linhas 1-120)
- `task_manager_flutter/lib/web/screens/system_test_screen.dart` (linhas 1-120)
- `task_manager_flutter/lib/windows/screens/query_builder_window_screen.dart` (linhas 1-120)
- `task_manager_admin_panel/lib/widgets/generic/field_config.dart` (completo)
- `task_manager_admin_panel/lib/widgets/generic/generic_grid_screen.dart` (completo)
- `task_manager_admin_panel/lib/widgets/generic/generic_detail_form_screen.dart` (completo)
- `task_manager_admin_panel/lib/config/api_links.dart` (completo)
- `task_manager_admin_panel/.planning/phases/01-scaffold-auth-base/{PLAN,RESEARCH}.md` (completo)

### Não consultadas (fora do escopo desta pesquisa — não precisou de doc externa/Context7)
Esta pesquisa é 100% interna ao workspace (mapeamento de código-fonte existente), sem
necessidade de biblioteca externa nova nesta etapa.

## Metadata

**Confidence breakdown:**
- Mapeamento screenIndex → arquivo/endpoint: ALTA — leitura direta do código-fonte de ambos os repos.
- Classificação CRUD vs. bespoke: ALTA para os 8 itens (padrão claro em cada arquivo lido).
- Detalhamento completo de comportamento (Cadastro Empresa, Config. Sistema seções finais, Editor de Telas, Permissões método `_salvar`, Teste de Endpoints aba 3): MÉDIA — arquivos grandes, lidos parcialmente; suficiente para classificação, insuficiente para task-by-task do plan-phase.
- Segurança do Query Builder: BAIXA — controller backend não localizado/lido nesta pesquisa.

**Research date:** 2026-08-28
**Valid until:** válido enquanto o código-fonte referenciado não mudar (não há dependência de versão de biblioteca externa nesta pesquisa) — recomenda-se reconfirmar se `menu_config.dart` ou `bottom_navbar_screen.dart` forem alterados antes do plan-phase.
