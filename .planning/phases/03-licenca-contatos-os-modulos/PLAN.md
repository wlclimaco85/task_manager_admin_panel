# PLAN — Fase 3: Licença, Contatos, Ordem de Serviço, Módulos Contratados (+ Dashboard de Crescimento)

Ver `RESEARCH.md` desta mesma pasta para o racional completo dos 4 itens originais (mapeamento
de domínios, decisões do PO, pitfalls). Este PLAN.md segue o formato pragmático já usado nas
Fases 1-2 (arquivo único por fase, sem plumbing de `gsd-sdk`/`STATE.md` — este projeto ainda não
usa o pipeline completo do GSD).

**Esta fase é FULL-STACK**: além do `task_manager_admin_panel` (Flutter), inclui mudanças no
backend `AppAcademia` (Java/Spring Boot) — domínio novo `ContatoComercial` (Item 2) e 3
endpoints novos de agregação para o Item 5 (Dashboard de Crescimento).

## Escopo (fechado — 5 itens, não renegociar)

1. **Licença** (LIC-01) — CRUD sobre backend já pronto, sem `DELETE` (usar `ativo=false`).
2. **Contatos** (CONT-01) — domínio NOVO `ContatoComercial` (backend + Flutter), decisão do PO
   já confirmada em `RESEARCH.md` (não reaproveitar `/api/contatos`, que é log de negociação de
   grãos, domínio errado). Vinculado a Parceiro e/ou Empresa.
3. **Ordem de Serviço** (OS-01) — via domínio `Chamado` já existente, cross-tenant-safe p/
   MASTER, CRUD completo (sem endpoint literal "OrdemServico" no backend, ver RESEARCH.md A1).
4. **Módulos Contratados** (MOD-01) — catálogo `ModuloServico` (CRUD simples) + tela de
   atribuição a Parceiro E Empresa via `ParceiroModuloController`/`EmpresaModuloController`
   (substituição total do conjunto, DELETE+INSERT já implementado no backend).
5. **Dashboard de Crescimento** (DASH-01) — **item adicionado durante este `plan-phase`**, por
   pedido explícito do usuário (não estava no `RESEARCH.md` original, escopo antecipado da Fase
   4 do `ROADMAP.md` só para este recorte específico de crescimento). 3 gráficos: novos
   Parceiros/Empresas por mês, novos módulos contratados por mês, projeção linear simples dos
   próximos meses. Investigação de backend feita nesta sessão de planejamento (ver `## Achados
   desta sessão` — não havia endpoint de agregação cross-tenant pronto, precisou de tasks de
   backend novas, incluindo 1 achado de modelagem de dados que limita a precisão histórica do
   gráfico de módulos — documentado, não bloqueia).

## Mapeamento de requisitos (IDs internos desta fase, não há REQUIREMENTS.md formal)

| ID | Item | Repositório |
|----|---|---|
| FND-01 | Fundação Flutter compartilhada (FieldType.date/dropdown, ApiLinks, transformPayload, deleteUrl opcional) | `task_manager_admin_panel` |
| LIC-01 | Licença | `task_manager_admin_panel` (backend já pronto) |
| CONT-01 | Contatos (`ContatoComercial`, domínio novo) | `AppAcademia` + `task_manager_admin_panel` |
| OS-01 | Ordem de Serviço (via `Chamado`) | `task_manager_admin_panel` (backend já pronto) |
| MOD-01 | Módulos Contratados (catálogo + atribuição) | `task_manager_admin_panel` (backend já pronto) |
| DASH-01 | Dashboard de Crescimento | `AppAcademia` + `task_manager_admin_panel` |

## Achados desta sessão de planning (corrigem/completam o `RESEARCH.md`)

Verificações de código-fonte feitas durante este `plan-phase` que mudam ou reduzem risco em
relação ao que `RESEARCH.md` havia assumido — importante ler antes de codar para não repetir
investigação nem "corrigir" algo que já está certo:

1. **Pitfall 1 do RESEARCH.md (parser de array raw) NÃO precisa de mudança no
   `GenericGridScreen`.** `NetworkResponse._toMap` (`lib/models/network_response.dart`) já
   envolve qualquer resposta que seja `List` direto em `{'data': [...]}` antes de chegar no
   `GenericGridScreen._load()` — ou seja, `GET /api/licencas` (retorna `List<Licenca>` na raiz) e
   `GET /api/parceiro-modulo`/`GET /api/empresa-modulo` (idem) já funcionam hoje sem qualquer
   ajuste de parser. Confirmado pelo teste já existente `test/widgets/generic_grid_screen_test.dart`
   ("popula linhas quando dados vem direto na raiz"), que já passa. **Não criar task para isso.**
2. **`/api/setor` existe** (`SetorContabilController`, estende `GenericController<Setor,Integer>`,
   envelope padrão `{data:{dados,total}}`) — resolve a Open Question 2 do `RESEARCH.md`. Campo de
   label é `descricao` (não `nome`).
3. **Contrato exato do `Chamado` (POST vs PUT) é assimétrico** — `ChamadoDTO` (usado no `POST
   /api/chamados`) aceita `empresa:{id}` e `setor:{id}` (objetos aninhados) mas `parceiroId` **plano**
   (não aninhado); já o `PUT /api/chamados/{id}` (body `JsonNode` livre) aceita `parceiro:{id}`,
   `empresa:{id}` e `setor:{id}` **todos aninhados**. Task 05.1 precisa de um `transformPayload`
   por verbo (ver `## Interfaces herdadas`).
4. **`status`/`prioridade` do `Chamado`: enviar sempre como STRING do nome do enum** (ex.
   `"ABERTO"`, `"BAIXA"`) tanto no `POST` quanto no `PUT` — `StatusChamadoDeserializer`/
   `PrioridadeChamadoDeserializer` aceitam texto via `Enum.valueOf` nos dois casos, e isso evita
   por completo a inconsistência do Pitfall 4 do RESEARCH.md (`GET` filtra por ordinal 0-based,
   `POST` com int usa `id` 1-based do enum, `PUT` com int usa ordinal 0-based — três contratos
   diferentes para o mesmo campo). Como esta fase não implementa filtro server-side de
   status/prioridade na grid (só busca local, já suportada pelo `GenericGridScreen`), o caminho
   do enum ordinal nunca é exercitado — enviar sempre a string do nome do enum é seguro e mais
   simples.
5. **Achado de modelagem para o Item 5 (Dashboard de Crescimento) — limita precisão histórica:**
   - Tabela `parceiro` **não tem nenhuma coluna de timestamp de criação** (`CREATE TABLE parceiro`
     original em `V15__Updates_tables_Apps_Daniel.sql` não tem `dh_created_at`, nenhuma migration
     posterior adicionou). Precisa de migration nova (Task 02.1) — parceiros já existentes vão
     aparecer com "criado em" = data da migration (não há como recuperar a data real de criação
     retroativamente, é uma limitação honesta, não um bug a corrigir).
   - Tabela `empresa` **já tem** `dh_created_at` via `@Embedded Audit audit` na entity `Empresa`
     — usável direto, sem migration.
   - Tabelas `parceiro_modulo`/`empresa_modulo` (`V90__Modulo_servico_parceiro.sql`,
     `V20260731__Create_empresa_modulo.sql`) **não têm nenhuma coluna de timestamp**, e o
     mecanismo de gravação é DELETE+INSERT do conjunto inteiro a cada `POST` (já documentado no
     `RESEARCH.md` para o Item 4) — mesmo depois de adicionar a coluna (Task 02.1), **qualquer
     re-salvamento parcial do conjunto de módulos de um parceiro/empresa (ex.: admin adiciona 1
     módulo a mais) reescreve a data de criação de TODOS os módulos daquele parceiro/empresa para
     "agora"**, não só do módulo novo. Isso significa que o gráfico "módulos novos por mês" pode
     mostrar picos artificiais sempre que alguém reconfigurar o conjunto de módulos de um cliente
     (não é um bug desta fase, é a semântica já existente e usada em produção do endpoint
     `POST /api/parceiro-modulo`/`empresa-modulo` — mudar essa semântica para incremental está
     fora de escopo, seria uma mudança de comportamento maior e mais arriscada que o pedido
     original). **Documentar essa limitação de forma visível na própria tela do dashboard**
     (Task 07.2), não só no PLAN.md.
   - Os `INSERT`s existentes em `ParceiroModuloController`/`EmpresaModuloController` já listam
     colunas explícitas (`INSERT INTO ... (parceiro_id, modulo_id) VALUES (?, ?)`) sem incluir a
     coluna nova — **não precisam de nenhuma alteração**: o Postgres aplica o `DEFAULT
     CURRENT_TIMESTAMP` da coluna nova automaticamente quando ela é omitida da lista de colunas
     do INSERT (diferente de um INSERT via JPA/Hibernate de entidade completa, que enviaria
     `NULL` explícito e sobrescreveria o default — não é o caso aqui, é SQL cru com lista de
     colunas explícita).
6. **`fl_chart` já está em uso no ecossistema do mesmo workspace** (`task_manager_flutter/
   pubspec.yaml`, `^1.2.0`, usado em `lib/mobile/screens/chats_daily_chart.dart` e outros
   dashboards do cliente) — mesma justificativa já usada na Fase 2 para `file_picker`: não requer
   checkpoint bloqueante de legitimidade adicional, só fixar a mesma versão (`^1.2.0`) no
   `pubspec.yaml` do admin panel.

## Interfaces herdadas (Fases 1-2 — ler antes de codar, não reexplorar)

- `lib/widgets/generic/field_config.dart` — hoje `FieldType {text,number,email,boolean,
  multiline}`, `FieldConfig{key,label,type,required,showInGrid,validator}`. Esta fase adiciona
  `FieldType.date`, `FieldType.dropdown`, classe `DropdownOption{value,label}` e os campos
  `FieldConfig.dateTime` (bool, default `false`), `FieldConfig.options` (lista fixa síncrona) e
  `FieldConfig.optionsLoader` (`Future<List<DropdownOption>> Function(NetworkCaller)?`,
  carregado 1x, recebe o `NetworkCaller` já existente do form chamador).
- `lib/widgets/generic/generic_grid_screen.dart` — `GenericGridScreen({title,listUrl,createUrl,
  updateUrl:String Function(id),deleteUrl:String Function(id),fields,networkCaller,rowsPerPage,
  embedded})`. Esta fase torna `deleteUrl` **opcional** (nullable) e adiciona `transformPayload`
  (repassado ao `GenericDetailFormScreen`).
- `lib/widgets/generic/generic_detail_form_screen.dart` — `GenericDetailFormScreen({title,
  fields,createUrl,updateUrl,initialValues,networkCaller})`. Esta fase adiciona
  `transformPayload: Map<String,dynamic> Function(Map<String,dynamic> raw, bool isEditing)?`,
  aplicado em `_submit()` logo após `_collectFormData()`, antes do POST/PUT.
- `lib/services/network_caller.dart`/`lib/models/network_response.dart` — usar sempre este
  wrapper, nunca `http` cru (ver Fase 2). `NetworkResponse._toMap` já normaliza `List` raiz em
  `{data:[...]}` (ver `## Achados desta sessão` item 1) — não reimplementar essa normalização em
  nenhum código novo desta fase.
- `lib/screens/home_screen.dart` — shell pós-login. Hoje tem 1 tile quebrado ("Contatos
  (demonstração)", aponta pro domínio errado `/api/contatos`) e 1 tile "Sistema". Esta fase
  remove o tile quebrado e adiciona 5 tiles novos (Task 08.1).
- `lib/config/api_links.dart` — só getters estáticos. **Atenção**: `_backendUrl`/
  `_backendContextPath` são `String.fromEnvironment` const — nunca converter para `final`.
- Padrão de teste de controller trivial no backend: `src/test/java/.../controller/
  CargoControllerTest.java` (`@WebMvcTest` + `@MockBean` do service + `MockMvc`, exclui
  autoconfig de segurança/JPA/datasource) — replicar exatamente esse esqueleto para
  `ContatoComercialControllerTest` (Task 01.2).

---

## Estrutura de execução: 8 planos em 3 waves

| Wave | Plano | Item(ns) | Repositório | Depende de | Arquivos principais (novos, salvo indicação) |
|---|---|---|---|---|---|
| 1 | P01 | CONT-01 (backend) | `AppAcademia` | — | `V20261020__Create_contato_comercial.sql`, `ContatoComercial.java`, `ContatoComercialRepository.java`, `ContatoComercialServiceImpl.java`, `ContatoComercialController.java`, `ContatoComercialControllerTest.java` |
| 1 | P02 | DASH-01 (backend) | `AppAcademia` | — | `V20261021__Add_timestamps_parceiro_e_modulo.sql`, `Parceiro.java` (edit), `DashboardCrescimentoController.java`, `DashboardCrescimentoControllerTest.java` |
| 1 | P03 | FND-01 | `task_manager_admin_panel` | — | `api_links.dart` (edit), `field_config.dart` (edit), `generic_grid_screen.dart` (edit), `generic_detail_form_screen.dart` (edit), `dropdown_source.dart` (novo) |
| 2 | P04 | LIC-01, CONT-01 (Flutter) | `task_manager_admin_panel` | P03 | `screens/licenca/licenca_screen.dart`, `screens/contatos/contato_comercial_screen.dart` |
| 2 | P05 | OS-01 (Flutter) | `task_manager_admin_panel` | P03 | `screens/chamados/ordem_servico_screen.dart` |
| 2 | P06 | MOD-01 (Flutter) | `task_manager_admin_panel` | P03 | `screens/modulos/modulo_servico_screen.dart`, `screens/modulos/modulo_atribuicao_screen.dart` |
| 2 | P07 | DASH-01 (Flutter) | `task_manager_admin_panel` | P03 | `utils/growth_projection.dart`, `screens/dashboard/dashboard_crescimento_screen.dart`, `pubspec.yaml` (edit: `fl_chart`) |
| 3 | P08 | Wiring final + gate | `task_manager_admin_panel` | P04, P05, P06, P07 (+ P01, P02 mergeados p/ smoke manual) | `screens/home_screen.dart` (edit), `api_links.dart` (edit: remove getters da demo antiga) |

Todos os planos da wave 1 têm `files_modified` disjuntos entre si (2 repositórios diferentes +
`task_manager_admin_panel` P03 não colide com o backend) — **podem ser executados em paralelo**.
Wave 2 (P04-P07) também são disjuntos entre si (pastas diferentes dentro de `lib/screens/`) —
paralelizáveis, todos dependem só de P03. Wave 3 (P08) tem dependência real de arquivo/import
(consome os widgets criados nas 4 telas da wave 2) — não paralelizável com elas.

---

## Wave 1

### P01 — Backend: domínio novo `ContatoComercial` (CONT-01)

**Objetivo:** criar o domínio "pessoa de contato comercial" vinculado a Parceiro/Empresa,
seguindo o padrão trivial já usado por `ContatoController`/`Contatos` (CRUD genérico via
`GenericController`), mas em tabela/entidade nova (`contato_comercial`) para não colidir com
`/api/contatos` (log de negociação de grãos, domínio errado — ver `RESEARCH.md` Item 2).

1. **Task 01.1 — Migration + entity + repository.**
   `src/main/resources/db/migration/V20261020__Create_contato_comercial.sql`: `CREATE TABLE
   public.contato_comercial (id SERIAL PRIMARY KEY, nome VARCHAR(150) NOT NULL, email
   VARCHAR(150), telefone VARCHAR(30), cargo VARCHAR(100), observacao VARCHAR(500), parceiro_id
   INT REFERENCES public.parceiro(id) ON DELETE SET NULL, empresa_id INT REFERENCES
   public.empresa(id) ON DELETE SET NULL, dh_created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
   dh_updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)`, mais `CREATE INDEX
   idx_contato_comercial_parceiro ON public.contato_comercial(parceiro_id)` e idem para
   `empresa_id`. Comentário no topo do arquivo explicando a distinção de `/api/contatos`
   (negociação de grãos) — mesmo texto do `RESEARCH.md` Item 2, resumido.
   `src/main/java/br/com/appAcademia/persistence/entity/ContatoComercial.java`: `@Entity @Data
   @NoArgsConstructor @AllArgsConstructor @Table(name="contato_comercial", schema="public")`,
   campos `id` (Integer, PK), `nome`, `email`, `telefone`, `cargo`, `observacao` (String), mais
   `@ManyToOne @JoinColumn(name="parceiro_id") @JsonIgnoreProperties({"hibernateLazyInitializer",
   "handler","audit","empresa","aplicativo","enderecos","documentos"}) private Parceiro
   parceiro;` e `@ManyToOne @JoinColumn(name="empresa_id")
   @JsonIgnoreProperties({"hibernateLazyInitializer","handler"}) private Empresa empresa;`
   (ambos opcionais/nullable, mesmo padrão de `Chamado.java`). Seguir exatamente o estilo lombok
   `@Data` de `Cargo.java` (não o estilo manual de getters de `Contatos.java`/`Chamado.java`).
   `src/main/java/br/com/appAcademia/persistence/repository/ContatoComercialRepository.java`:
   `@Repository public interface ContatoComercialRepository extends
   JpaRepository<ContatoComercial, Integer> {}` (idêntico a `ContatoRepository.java`).
   - Verify: `mvn -q compile` sem erro.

2. **Task 01.2 — Service + Controller + teste.** `tdd="true"`.
   `src/main/java/br/com/appAcademia/service/implementation/ContatoComercialServiceImpl.java`:
   `@Slf4j @Service public class ContatoComercialServiceImpl extends
   GenericServiceImpl<ContatoComercial, Integer> { public ContatoComercialServiceImpl
   (ContatoComercialRepository repo) { super(repo); } }` (idêntico a `ContatoServiceImpl.java`).
   `src/main/java/br/com/appAcademia/controller/ContatoComercialController.java`:
   `@RestController @RequestMapping({"/api/contato-comercial","/api/contatos-comerciais"})
   public class ContatoComercialController extends GenericController<ContatoComercial,
   Integer> { public ContatoComercialController(ContatoComercialServiceImpl service) {
   super(service); } }` (idêntico a `ContatoController.java`, herda GET paginado
   `{data:{dados,total}}`, GET/{id}, POST 201, PUT, DELETE do `GenericController` — nenhum
   endpoint bespoke necessário).
   `src/test/java/br/com/appAcademia/controller/ContatoComercialControllerTest.java`: copiar
   exatamente o esqueleto de `CargoControllerTest.java` (`@WebMvcTest(value =
   ContatoComercialController.class, excludeAutoConfiguration = {...})`, `@MockBean
   ContatoComercialServiceImpl`), com os 5 testes (`getAll`/`getById`/`create`/`update`/
   `delete`) adaptados para `ContatoComercial` com `nome`/`email`/`telefone`.
   - Behavior: `POST /api/contato-comercial` com `{nome,email,telefone,cargo,parceiro:{id}}`
     retorna 201; `GET /api/contato-comercial` retorna 200 com envelope
     `{data:{dados:[...],totalElements:N}}` (achado do `gsd-plan-checker`: o campo real do
     `GenericResponseDTO` é `totalElements`, não `total` — corrigido aqui para não induzir uma
     asserção `jsonPath` errada).
   - Verify: `mvn -q test -Dtest=ContatoComercialControllerTest`

### P02 — Backend: agregações do Dashboard de Crescimento (DASH-01)

**Objetivo:** 3 endpoints MASTER-only de contagem por mês (Parceiros novos, Empresas novas,
Módulos contratados novos), resolvendo o achado de modelagem do item 5 acima.

1. **Task 02.1 — Migration de colunas de timestamp + entity `Parceiro`.**
   `src/main/resources/db/migration/V20261021__Add_timestamps_parceiro_e_modulo.sql`:
   `ALTER TABLE public.parceiro ADD COLUMN IF NOT EXISTS dh_created_at TIMESTAMP DEFAULT
   CURRENT_TIMESTAMP;` + `ALTER TABLE public.parceiro_modulo ADD COLUMN IF NOT EXISTS
   dh_created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;` + `ALTER TABLE public.empresa_modulo ADD
   COLUMN IF NOT EXISTS dh_created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;`. Comentário no topo
   explicando a limitação de histórico (parceiros/módulos pré-existentes aparecem com "criado
   em" = data desta migration; módulos são resetados a cada `POST /api/parceiro-modulo`/
   `empresa-modulo` por serem DELETE+INSERT do conjunto inteiro).
   `src/main/java/br/com/appAcademia/persistence/entity/Parceiro.java`: adicionar campo
   `@Column(name = "dh_created_at") private LocalDateTime dhCreatedAt =
   LocalDateTime.now();` **com inicializador `= LocalDateTime.now()`** (não deixar só `null`) —
   `@Data` já gera getter/setter. **Atenção**: sem esse inicializador, o Hibernate grava `NULL`
   explícito no INSERT (sobrescrevendo o `DEFAULT` do banco, que só se aplica quando a coluna é
   omitida da lista) — mesmo padrão de segurança já usado em `Licenca.java` (`dhCreatedAt =
   LocalDateTime.now()`), copiar esse idioma exatamente.
   - Verify: `mvn -q compile` sem erro; `mvn -q test -Dtest=GenericServiceImplTest` (smoke, não
     deve quebrar por causa do novo campo).

2. **Task 02.2 — `DashboardCrescimentoController` + teste.** `tdd="true"`.
   `src/main/java/br/com/appAcademia/controller/DashboardCrescimentoController.java`:
   `@RestController @RequestMapping("/api/dashboard/crescimento")` com `JdbcTemplate` injetado
   via construtor. 3 endpoints, todos `@PreAuthorize("@tenantSecurity.isMaster()")` (mesmo
   padrão de `QueryBuilderController`):
   - `GET /parceiros-por-mes?meses=12` — `jdbc.queryForList("SELECT to_char(date_trunc('month',
     dh_created_at), 'YYYY-MM') AS mes, count(*) AS total FROM public.parceiro WHERE
     dh_created_at >= (CURRENT_DATE - (? || ' months')::interval) GROUP BY 1 ORDER BY 1",
     meses)` → `ResponseEntity<List<Map<String,Object>>>`.
   - `GET /empresas-por-mes?meses=12` — mesma query, tabela `public.empresa`.
   - `GET /modulos-por-mes?meses=12` — `UNION ALL` de `parceiro_modulo` e `empresa_modulo`
     agrupados por mês e somados (`SELECT mes, SUM(total) AS total FROM (SELECT
     to_char(date_trunc('month',dh_created_at),'YYYY-MM') mes, count(*) total FROM
     public.parceiro_modulo WHERE dh_created_at >= (CURRENT_DATE - (?||' months')::interval)
     GROUP BY 1 UNION ALL SELECT to_char(date_trunc('month',dh_created_at),'YYYY-MM') mes,
     count(*) total FROM public.empresa_modulo WHERE dh_created_at >= (CURRENT_DATE - (?||'
     months')::interval) GROUP BY 1) x GROUP BY mes ORDER BY mes", meses, meses)`. Comentário no
     método citando a limitação de reset por re-salvamento (achado item 5 acima).
   `src/test/java/br/com/appAcademia/controller/DashboardCrescimentoControllerTest.java`: copiar
   a estrutura exata de `QueryBuilderControllerSecurityTest.java` (já existe neste módulo,
   arquivo de referência direta — `@WebMvcTest(value = DashboardCrescimentoController.class,
   excludeAutoConfiguration = {...})`, `@Import(...TestBeans.class)` com `@TestConfiguration
   @EnableWebSecurity @EnableMethodSecurity` expondo um `@Bean("tenantSecurity")
   mock(TenantSecurity.class)` + `SecurityFilterChain` mínimo, `@MockBean JdbcTemplate`,
   cenários com `@WithMockUser` + `when(tenantSecurity.isMaster()).thenReturn(true/false)`).
   Mockar `jdbc.queryForList(anyString(), org.mockito.ArgumentMatchers.<Object>any())` (varargs
   de 1 argumento — se o matcher não bater na assinatura vararg, usar
   `any(Object[].class)` explicitamente) retornando `List.of(Map.of("mes","2026-01","total",3))`.
   - Behavior: `GET /api/dashboard/crescimento/parceiros-por-mes?meses=6` autenticado como
     MASTER retorna 200 com lista de `{mes,total}`; sem ser MASTER retorna 403.
   - Verify: `mvn -q test -Dtest=DashboardCrescimentoControllerTest`

### P03 — Flutter: fundação compartilhada (FND-01)

**Objetivo:** declarar TODOS os contratos (`ApiLinks`) e estender o par genérico de uma vez,
como contrato para os 4 planos da wave 2 seguinte — mesmo padrão já usado na Fase 2 (P01).

1. **Task 03.1 — `ApiLinks`: getters de todos os 5 itens desta fase.**
   `lib/config/api_links.dart`, agrupado por item com comentário `// Fase 3 - <ID>`:
   - LIC-01: `allLicencas`, `createLicenca`, `updateLicenca(id)` → `/api/licencas` (**sem**
     `deleteLicenca` — backend não expõe `DELETE`, ver `RESEARCH.md` Pitfall 2).
   - CONT-01: `allContatosComerciais`, `createContatoComercial`,
     `updateContatoComercial(id)`, `deleteContatoComercial(id)` → `/api/contato-comercial`.
   - OS-01: `allChamadosOS` (`/api/chamados?tamanho=200`), `updateChamadoOS(id)` →
     `/api/chamados/{id}` (`createChamado`/`deleteChamado` já existem da Fase 2, SIS-02 —
     achado do `gsd-plan-checker`: `deleteChamadoOS` seria sinônimo duplicado do
     `ApiLinks.deleteChamado(id)` já existente, mesma URL — reusar, não criar getter novo).
   - MOD-01: `allModulosServico` (`/api/modulo-servico?tamanho=1000`), `createModuloServico`,
     `updateModuloServico(id)`, `deleteModuloServico(id)` → `/api/modulo-servico`;
     `parceiroModulos(parceiroId)` (`GET /api/parceiro-modulo?parceiroId=`),
     `vincularParceiroModulos` (`POST /api/parceiro-modulo`); `empresaModulos(empresaId)`
     (`GET /api/empresa-modulo?empresaId=`), `vincularEmpresaModulos` (`POST
     /api/empresa-modulo`).
   - DASH-01: `parceirosPorMes({meses=12})`, `empresasPorMes({meses=12})`,
     `modulosPorMes({meses=12})` → `/api/dashboard/crescimento/{...}?meses=`.
   - FK dropdowns (fonte de opções, carregadas 1x): reusar `allAplicativos` (já existe, Fase 2
     SIS-01) para o dropdown de Licença; adicionar `dropdownParceiros`
     (`/api/parceiro?tamanho=500`), `dropdownEmpresas` (`/api/empresa?tamanho=500`),
     `dropdownSetores` (`/api/setor?tamanho=500`) para os dropdowns de FK do Item 3.
   - Verify: `flutter analyze lib/config/api_links.dart` limpo.

2. **Task 03.2 — `field_config.dart`: `FieldType.date`/`FieldType.dropdown`.** `tdd="true"`.
   Adicionar ao enum `FieldType`: `date`, `dropdown`. Nova classe `DropdownOption` (`const
   DropdownOption({required this.value, required this.label})`, `final dynamic value; final
   String label;`). Em `FieldConfig`, adicionar `this.dateTime = false` (bool — `true` =
   backend espera `LocalDateTime` e o valor deve ser serializado com sufixo `T00:00:00`;
   `false` = backend espera `LocalDate`, formato `yyyy-MM-dd`), `this.options` (`List
   <DropdownOption>?`, opções fixas síncronas — ex. status/prioridade do `Chamado`) e
   `this.optionsLoader` (`Future<List<DropdownOption>> Function(NetworkCaller)?`, carregado 1x
   no `initState` do form, recebendo o `NetworkCaller` já existente do próprio form (nunca cria
   um `NetworkCaller`/`http.Client` próprio) — ex. FK remoto de Aplicativo/Parceiro/Empresa/
   Setor. Ambos opcionais,
   nunca os dois preenchidos ao mesmo tempo no mesmo campo.
   - Behavior: `FieldConfig` com `type: FieldType.date, dateTime: true` deve expor
     `dateTime == true` (getter trivial, testar construção).
   - Verify: `flutter test test/widgets/field_config_test.dart` (criar arquivo novo, cobrindo
     construção de `DropdownOption` e `FieldConfig` com os campos novos).

3. **Task 03.3 — `generic_grid_screen.dart`/`generic_detail_form_screen.dart`: renderizar os
   tipos novos + `transformPayload` + `deleteUrl` opcional + `dropdown_source.dart`.**
   `tdd="true"`.
   Em `generic_grid_screen.dart`: (a) `deleteUrl` deixa de ser `required`, vira `final String
   Function(String id)? deleteUrl;` — `_delete()` faz early-return se `null`, e o `IconButton`
   de excluir na `DataRow` só é incluído se `widget.deleteUrl != null`. (b) extrair a lógica de
   normalização de `response.body` (hoje inline em `_load()`) para um método estático
   `static List<Map<String,dynamic>> extractRows(Map<String,dynamic>? body)` reutilizável por
   `dropdown_source.dart` (evita duplicar a lógica de `data`/`dados`/`content`). (c) célula da
   grid: quando `field.type == FieldType.dropdown && field.options != null`, mapear o valor bruto
   da linha para o `label` da opção correspondente (`options.firstWhere((o) => o.value ==
   row[field.key], orElse: () => DropdownOption(value: row[field.key], label:
   row[field.key]?.toString() ?? ''))`) — campos com `optionsLoader` (FK remoto) continuam
   mostrando o valor bruto na grid (`showInGrid: false` nesses campos é a saída recomendada para
   os itens desta fase, não construir resolução de label remota na grid). (d) novo parâmetro
   `transformPayload` repassado ao `GenericDetailFormScreen` dentro de `_openForm()`.
   Em `generic_detail_form_screen.dart`: novo parâmetro `final Map<String,dynamic>
   Function(Map<String,dynamic> raw, bool isEditing)? transformPayload;`, aplicado em
   `_submit()` logo após `_collectFormData()` (`final payload = widget.transformPayload?.call(
   data, widget.isEditing) ?? data;`, usado no lugar de `data` no `postRequest`/`putRequest`).
   Novos estados `Map<String, DateTime?> _dateValues` e `Map<String, dynamic> _dropdownValues` +
   `Map<String, List<DropdownOption>> _loadedOptions` + `Set<String> _loadingOptionKeys`.
   `initState`: para campos `FieldType.date`, popular `_dateValues[key] =
   DateTime.tryParse(initial?.toString() ?? '')`; para `FieldType.dropdown`, popular
   `_dropdownValues[key] = initial is Map ? initial['id'] : initial` (normaliza tanto valor
   plano quanto objeto aninhado `{id:...}` vindo do backend) e, se `field.optionsLoader != null`,
   disparar o load assíncrono chamando `field.optionsLoader!(_caller)` (reaproveita o
   `NetworkCaller` já existente do próprio form, nunca instancia um novo) — `setState` ao
   concluir, com indicador de carregamento no meio tempo. `_collectFormData()`: para `FieldType.date`, formatar via `intl`
   (`DateFormat('yyyy-MM-dd').format(date)` + `'T00:00:00'` se `field.dateTime`); para
   `FieldType.dropdown`, usar o valor bruto de `_dropdownValues[key]` (deixar o `transformPayload`
   do campo aninhar `{id: valor}` quando o backend exigir, não fazer isso aqui de forma genérica).
   `_buildField`: `FieldType.date` → `InkWell` abrindo `showDatePicker` e mostrando o valor
   formatado (`dd/MM/yyyy`) ou "Selecionar data"; `FieldType.dropdown` → se ainda carregando
   (`optionsLoader` pendente), `LinearProgressIndicator` inline; senão
   `DropdownButtonFormField<dynamic>` com os itens de `field.options ?? _loadedOptions[key] ??
   []`, mais um item `null`/"Nenhum" quando `!field.required`.
   Novo arquivo `lib/widgets/generic/dropdown_source.dart`: `Future<List<DropdownOption>>
   Function(NetworkCaller) remoteDropdownSource({required String url, required String valueKey,
   required String Function(Map<String,dynamic>) labelBuilder})` — retorna uma função que recebe
   o `NetworkCaller` do form chamador (não cria um `NetworkCaller` próprio), faz
   `caller.getRequest(url)`, usa `GenericGridScreen.extractRows(response.body)` e mapeia cada
   linha para `DropdownOption(value: row[valueKey], label: labelBuilder(row))`.
   - Behavior: grid com `deleteUrl: null` não mostra ícone de excluir (teste novo em
     `generic_grid_screen_test.dart`); form com campo `FieldType.date` e `initialValues:
     {'venc':'2026-12-31'}` mostra "31/12/2026"; form com `transformPayload` recebe o payload
     transformado no `postRequest` mockado (verificar via `MockClient` capturando o `body` da
     requisição).
   - Verify: `flutter test test/widgets/generic_grid_screen_test.dart
     test/widgets/generic_detail_form_screen_test.dart` (criar o segundo arquivo, hoje não
     existe teste dedicado a `GenericDetailFormScreen` — cobrir os 2 comportamentos novos acima
     mais um smoke de submit básico).

---

## Wave 2

### P04 — Flutter: Licença (LIC-01) + Contatos (CONT-01)

**Depende de:** P03 (contratos de `ApiLinks`/`FieldConfig`/par genérico).

1. **Task 04.1 — `licenca_screen.dart`.** Novo arquivo `lib/screens/licenca/licenca_screen.dart`:
   `GenericGridScreen(title: 'Licenças', listUrl: ApiLinks.allLicencas, createUrl:
   ApiLinks.createLicenca, updateUrl: ApiLinks.updateLicenca, deleteUrl: null, fields: [...])`.
   Campos: `codApp` (`FieldType.dropdown`, `optionsLoader:
   remoteDropdownSource(url:ApiLinks.allAplicativos,valueKey:'id',
   labelBuilder:(r)=>r['nome']?.toString()??'')`, `required:true`, `showInGrid:true`),
   `nomeApp` (text), `ativo` (boolean), `dataInicio` (`FieldType.date`, `dateTime:false`),
   `dataVencimento` (`FieldType.date`, `dateTime:false`, `required:true`), `observacao`
   (multiline, `showInGrid:false`). Sem `transformPayload` (payload plano já bate com o
   contrato do `LicencaController`, que ignora `codApp` no update mas aceita no create).
   - Verify: `flutter analyze lib/screens/licenca/licenca_screen.dart` limpo; teste de widget
     básico (`test/screens/licenca/licenca_screen_test.dart`) confirmando que a grid renderiza
     com `deleteUrl` nulo (sem ícone de excluir) usando `MockClient`.

2. **Task 04.2 — `contato_comercial_screen.dart`.** Novo arquivo
   `lib/screens/contatos/contato_comercial_screen.dart`: `GenericGridScreen(title: 'Contatos',
   listUrl: ApiLinks.allContatosComerciais, createUrl: ApiLinks.createContatoComercial,
   updateUrl: ApiLinks.updateContatoComercial, deleteUrl: ApiLinks.deleteContatoComercial,
   fields: [...])`. Campos: `nome` (text, required), `email` (`FieldType.email`), `telefone`
   (text), `cargo` (text), `observacao` (multiline, `showInGrid:false`). `parceiroId`/
   `empresaId` **não** entram como campo de formulário nesta primeira versão da tela (CRUD
   completo do contato em si, sem seletor de Parceiro/Empresa na UI — vínculo pode ser feito
   depois via API/edição direta se necessário; não é regressão de escopo, é o que o
   `RESEARCH.md`/`ROADMAP.md` pedem: "Contatos" como CRUD simples, o vínculo a
   Parceiro/Empresa é um detalhe de modelagem do backend, não um requisito de UI explícito).
   - Verify: `flutter analyze lib/screens/contatos/contato_comercial_screen.dart` limpo; teste
     de widget (`test/screens/contatos/contato_comercial_screen_test.dart`) cobrindo criação com
     sucesso (mock 201) usando os campos reais (`nome`/`email`/`telefone`/`cargo`), **não** os
     campos quebrados da demo antiga.

### P05 — Flutter: Ordem de Serviço via `Chamado` (OS-01)

**Depende de:** P03.

1. **Task 05.1 — `ordem_servico_screen.dart`.** Novo arquivo
   `lib/screens/chamados/ordem_servico_screen.dart`. Campos: `titulo` (text, required,
   `showInGrid:true`), `descricao` (multiline, `showInGrid:false`), `status`
   (`FieldType.dropdown`, `options: [DropdownOption(value:'ABERTO',label:'Aberto'),
   DropdownOption(value:'EM_ANDAMENTO',label:'Em andamento'),
   DropdownOption(value:'FECHADO',label:'Fechado'),
   DropdownOption(value:'CANCELADO',label:'Cancelado'),
   DropdownOption(value:'AGUARDANDO_CLIENTE',label:'Aguardando cliente'),
   DropdownOption(value:'BLOQUEADO',label:'Bloqueado')]`, `showInGrid:true` — **nunca usar
   `getDescricao()` do enum Java como label, são placeholders de outro contexto** ("App Pablo"
   etc., ver `RESEARCH.md`), `prioridade` (`FieldType.dropdown`, `options:
   [DropdownOption(value:'BAIXA',label:'Baixa'), DropdownOption(value:'MEDIA',label:'Média'),
   DropdownOption(value:'ALTA',label:'Alta'), DropdownOption(value:'URGENTE',label:'Urgente'),
   DropdownOption(value:'NORMAL',label:'Normal')]`, `showInGrid:true`), `empresa`
   (`FieldType.dropdown`, `optionsLoader: remoteDropdownSource(url:ApiLinks.dropdownEmpresas,
   valueKey:'id',labelBuilder:(r)=>r['nome']?.toString()??'')`, `required:false,
   showInGrid:false`), `parceiro` (idem, `ApiLinks.dropdownParceiros`, `showInGrid:false`),
   `setor` (idem, `ApiLinks.dropdownSetores`, `labelBuilder:(r)=>r['descricao']?.toString()??''`,
   `showInGrid:false`), `dataAbertura`/`dataFechamento` (`FieldType.date`, `dateTime:true`,
   `showInGrid:false`), `dataVencimentoObrigacao` (`FieldType.date`, `dateTime:false`,
   `showInGrid:false`). `GenericGridScreen(listUrl: ApiLinks.allChamadosOS, createUrl:
   ApiLinks.createChamado, updateUrl: ApiLinks.updateChamadoOS, deleteUrl:
   ApiLinks.deleteChamado, transformPayload: _transformChamadoPayload)`.
   `_transformChamadoPayload(raw, isEditing)`: monta o payload correto por verbo (ver `##
   Achados desta sessão` item 3) — se `isEditing`: `{...raw, if (raw['parceiro'] != null)
   'parceiro': {'id': raw['parceiro']}, if (raw['empresa'] != null) 'empresa': {'id':
   raw['empresa']}, if (raw['setor'] != null) 'setor': {'id': raw['setor']}}` (remove as chaves
   originais planas antes de reinserir aninhadas); se `!isEditing` (create): `{...raw, if
   (raw['parceiro'] != null) 'parceiroId': raw['parceiro'], if (raw['empresa'] != null)
   'empresa': {'id': raw['empresa']}, if (raw['setor'] != null) 'setor': {'id': raw['setor']}}`
   (remove a chave `parceiro` plana, mantém `parceiroId`). Sem filtro server-side de
   status/prioridade na grid (só busca local já suportada) — CRUD completo continua satisfeito
   (listar/criar/editar/excluir).
   - Behavior: `_transformChamadoPayload({'parceiro': 5, 'titulo': 'X'}, false)` retorna
     `{'parceiroId': 5, 'titulo': 'X'}` (sem chave `parceiro`); mesma entrada com `isEditing:
     true` retorna `{'parceiro': {'id': 5}, 'titulo': 'X'}`.
   - Verify: `flutter test test/screens/chamados/ordem_servico_screen_test.dart` (função de
     transformação testável isoladamente, sem precisar montar o widget completo, mais 1 teste
     de widget smoke cobrindo o dropdown de status renderizando os 6 labels em português).

### P06 — Flutter: Módulos Contratados (MOD-01)

**Depende de:** P03.

1. **Task 06.1 — `modulo_servico_screen.dart` (catálogo).** Novo arquivo
   `lib/screens/modulos/modulo_servico_screen.dart`: `GenericGridScreen(title: 'Módulos
   (catálogo)', listUrl: ApiLinks.allModulosServico, createUrl: ApiLinks.createModuloServico,
   updateUrl: ApiLinks.updateModuloServico, deleteUrl: ApiLinks.deleteModuloServico, fields:
   [FieldConfig(key:'nome',label:'Nome',required:true),
   FieldConfig(key:'descricao',label:'Descrição'),
   FieldConfig(key:'ativo',label:'Ativo',type:FieldType.boolean)])`. CRUD puro, sem adaptação
   especial (`ModuloServicoController` já usa o envelope padrão e tem `DELETE`).
   - Verify: `flutter analyze lib/screens/modulos/modulo_servico_screen.dart` limpo.

2. **Task 06.2 — `modulo_atribuicao_screen.dart` (bespoke).** Novo arquivo
   `lib/screens/modulos/modulo_atribuicao_screen.dart`, `StatefulWidget` **não** baseado no par
   genérico (widget próprio, ver `RESEARCH.md` "Padrão novo a criar"). Estrutura: (a) topo —
   `SegmentedButton<String>` ou 2 `ChoiceChip` alternando entre `'parceiro'`/`'empresa'`; (b)
   `TextField` numérico "ID do Parceiro/Empresa" + botão "Carregar" que faz `GET
   /api/parceiro/{id}` ou `GET /api/empresa/{id}` (via `NetworkCaller`) para validar existência e
   exibir o nome encontrado (não carregar a lista inteira de parceiros/empresas em memória — ver
   `RESEARCH.md`, volume real de produção pode ser grande; buscar por ID é a opção mais simples
   e mais segura de escala aqui); (c) ao carregar com sucesso, dispara em paralelo `GET
   ApiLinks.allModulosServico` (catálogo completo) e `GET ApiLinks.parceiroModulos(id)`/
   `empresaModulos(id)` (módulos já vinculados) — **ambos retornam `List` raiz direto (`GET
   /api/parceiro-modulo`/`empresa-modulo` → `ResponseEntity<List<Map>>`, confirmado por leitura
   do controller, não o envelope `{data:...}` padrão), então parsear com o mesmo
   `GenericGridScreen.extractRows(response.body)` estático criado na Task 03.3 em vez de
   reinventar a normalização aqui** — e monta uma `List<CheckboxListTile>` com o
   catálogo completo, pré-marcado conforme os já vinculados (`Set<int> _moduloIdsMarcados`); (d)
   botão "Salvar" — `showDialog` de confirmação com o texto **"Isto substitui TODO o conjunto de
   módulos deste Parceiro/Empresa — módulos não marcados serão desvinculados."** antes de
   disparar `POST ApiLinks.vincularParceiroModulos`/`vincularEmpresaModulos` com body
   `{'parceiroId'/'empresaId': id, 'moduloIds': _moduloIdsMarcados.toList()}`. Usar
   `NetworkCaller` (nunca `http` cru).
   - Verify: `flutter test test/screens/modulos/modulo_atribuicao_screen_test.dart` — cobrir:
     carregar parceiro válido mostra catálogo com itens pré-marcados conforme
     `parceiro-modulo` mockado; salvar sem confirmar o dialog não dispara o `POST`; confirmar o
     dialog dispara `POST` com o `moduloIds` esperado (usar `MockClient` capturando o request
     body, mesmo padrão de `generic_grid_screen_test.dart`).

### P07 — Flutter: Dashboard de Crescimento (DASH-01)

**Depende de:** P03 (só usa os getters de `ApiLinks`, não usa `GenericGridScreen`/
`GenericDetailFormScreen` — item bespoke, gráficos).

1. **Task 07.1 — `growth_projection.dart` (função pura, TDD).** `tdd="true"`. Novo arquivo
   `lib/utils/growth_projection.dart`: `List<double> projectNextMonths(List<double> historico,
   {int mesesProjetados = 3})` — regressão linear simples (mínimos quadrados) sobre
   `historico` (eixo x = índice 0..n-1), projeta os próximos `mesesProjetados` pontos, com
   clamp em `0` (nunca projeta valor negativo). Casos de borda: `historico.isEmpty` → retorna
   `List.filled(mesesProjetados, 0.0)`; `historico.length == 1` → retorna
   `List.filled(mesesProjetados, historico.first)` (projeção plana, sem dado suficiente p/
   regressão).
   - Behavior: `projectNextMonths([1,2,3,4], mesesProjetados:3)` ≈ `[5,6,7]` (tolerância
     `closeTo`); `projectNextMonths([], mesesProjetados:3)` == `[0,0,0]`;
     `projectNextMonths([5], mesesProjetados:2)` == `[5,5]`; `projectNextMonths([10,5,0],
     mesesProjetados:2)` não deve conter valor negativo (clamp em 0).
   - Verify: `flutter test test/utils/growth_projection_test.dart` (criar arquivo, cobrir os 4
     casos acima).

2. **Task 07.2 — `dashboard_crescimento_screen.dart` + dependência `fl_chart`.**
   `pubspec.yaml`: adicionar `fl_chart: ^1.2.0` (mesma versão já usada em
   `task_manager_flutter`, ver `## Achados desta sessão` item 6 — não requer checkpoint de
   legitimidade adicional). Novo arquivo
   `lib/screens/dashboard/dashboard_crescimento_screen.dart`: busca as 3 séries
   (`ApiLinks.parceirosPorMes()`, `empresasPorMes()`, `modulosPorMes()`) via `NetworkCaller`,
   parseia `{mes:'YYYY-MM', total:N}` de cada uma. Layout "progressive disclosure" (per pedido
   do usuário — dashboards calmos, métrica única primeiro): 3 `Card`s compactos no topo
   (KPI do mês corrente de cada série: "Novos parceiros", "Novas empresas", "Módulos
   contratados"), cada um um `ExpansionTile` que, ao expandir, revela um `LineChart` (`fl_chart`,
   mesmo padrão visual de `chats_daily_chart.dart` do `task_manager_flutter` — `LineChartBarData`
   sólido para o histórico real + um segundo `LineChartBarData` tracejado/com cor diferenciada
   para os próximos `mesesProjetados` pontos, usando `projectNextMonths` do Item anterior).
   **Aviso visível na tela** (ex. `Tooltip`/texto pequeno abaixo do gráfico de "Módulos
   contratados") citando a limitação de modelagem: "picos podem refletir reconfiguração de
   módulos de um cliente existente, não necessariamente contratação nova" (ver `## Achados desta
   sessão` item 5). Estados de loading/erro/vazio por card, mesmo padrão de
   `chats_daily_chart.dart` (`CircularProgressIndicator`/mensagem de erro/"Nenhum dado").
   - Verify: `flutter analyze lib/screens/dashboard/dashboard_crescimento_screen.dart` limpo;
     teste de widget (`test/screens/dashboard/dashboard_crescimento_screen_test.dart`) cobrindo
     estado de loading, estado vazio e renderização do KPI do mês corrente com dados mockados
     (`MockClient` nas 3 URLs).

---

## Wave 3

### P08 — Wiring final + gate de qualidade

**Depende de:** P04, P05, P06, P07 (precisa que os 5 widgets de tela existam para importar).
Para o smoke manual (Task 08.2), depende também de P01/P02 (backend) já mergeados em `desenv`
do `AppAcademia` e rodando localmente/ambiente de teste.

1. **Task 08.1 — `home_screen.dart`: wiring dos 5 tiles + limpeza da demo quebrada.**
   `lib/screens/home_screen.dart`: remover o `Card`/`ListTile` "Contatos (demonstração)" e a
   constante `_contatoFields` (apontavam para `/api/contatos`, domínio errado — achado crítico
   do `RESEARCH.md`). Adicionar 5 novos `Card`/`ListTile` (mesmo padrão visual dos already
   existentes): "Licença" → `LicencaScreen`, "Contatos" → `ContatoComercialScreen`, "Ordem de
   Serviço" → `OrdemServicoScreen`, "Módulos Contratados" → sub-menu simples (2 `ListTile`
   dentro do mesmo `Card` ou 2 `Card`s separados: "Catálogo" → `ModuloServicoScreen`,
   "Atribuição" → `ModuloAtribuicaoScreen`), "Dashboard de Crescimento" →
   `DashboardCrescimentoScreen`. `lib/config/api_links.dart`: remover os getters órfãos da demo
   antiga (`allContatos`, `createContato`, `updateContato`, `deleteContato` — grep confirmou
   nenhum outro arquivo além de `home_screen.dart` os usa).
   - Verify: `grep -rn "ApiLinks.allContatos\b\|ApiLinks.createContato\b" lib test` retorna
     vazio (getters realmente removidos, sem uso órfão); `flutter analyze` limpo.

2. **Task 08.2 — Gate final: suite completa + smoke manual.**
   `flutter test` (suite completa, todos os testes novos desta fase + regressão das Fases 1-2)
   e `flutter analyze` (zero erros/warnings novos). Em seguida, `checkpoint:human-verify`:
   com o backend `AppAcademia` rodando localmente (branch `desenv` com P01+P02 já mesclados),
   validar manualmente contra o backend real (não só mocks): (1) Licença — criar, editar,
   desativar (sem excluir) uma licença; (2) Contatos — criar/editar/excluir um contato
   comercial; (3) Ordem de Serviço — criar um chamado com status/prioridade, editar o status,
   confirmar que a mudança persiste (GET seguinte reflete o novo status); (4) Módulos — no
   catálogo, confirmar que módulos já existem (seed `V90`); na atribuição, carregar um parceiro
   real, marcar/desmarcar módulos, salvar e confirmar via `GET
   /api/parceiro-modulo?parceiroId=` que o conjunto persistido bate com o marcado; (5) Dashboard
   — confirmar que os 3 gráficos carregam com dados reais (mesmo que baixo volume/zerado em
   ambiente de teste) e que a projeção aparece ao expandir.
   - Verify (automatizado): `flutter test` e `flutter analyze` (zero erros).
   - Verify (manual): resultado dos 5 fluxos acima relatado pelo usuário antes de fechar a fase.

---

## Threat Model (STRIDE)

| Trust Boundary | Descrição |
|---|---|
| Admin panel (MASTER) → `AppAcademia` `/api/contato-comercial`, `/api/licencas`, `/api/chamados`, `/api/modulo-servico`, `/api/parceiro-modulo`, `/api/empresa-modulo`, `/api/dashboard/crescimento/*` | CRUD/agregação cross-tenant, chamado por login MASTER autenticado JWT |

| Threat ID | Categoria | Componente | Disposição | Mitigação |
|---|---|---|---|---|
| T-03-01 | Tampering | `PUT /api/licencas/{id}` (`ativo`, `dataVencimento`) | accept | Ação de alto impacto por design (bloqueia/libera um app inteiro), mas já restrita a quem acessa o admin panel (MASTER); sem `@PreAuthorize` no backend (débito pré-existente, fora de escopo desta fase corrigir — registrar como recomendação ao dono do backend, mesmo tratamento do achado análogo da Fase 2). |
| T-03-02 | Elevation of Privilege | `POST /api/empresa-modulo` sem `@PreAuthorize`/validação de tenant (RESEARCH.md Pitfall 3) | accept | Débito pré-existente, não introduzido por esta fase — mesma disposição já registrada no `RESEARCH.md`: registrar como recomendação de backend (`@PreAuthorize` + `validarEmpresaPertenceAoTenant` análogos a `ParceiroModuloController`), não bloquear esta fase Flutter por isso. |
| T-03-03 | Information Disclosure | `GET /api/dashboard/crescimento/*` (contagens agregadas, sem dado individual de parceiro/empresa) | accept | Só números agregados por mês, sem PII; `@PreAuthorize(isMaster())` já restringe a quem acessa o admin panel. |
| T-03-04 | Tampering | `ModuloAtribuicaoScreen` → `POST /api/parceiro-modulo`/`empresa-modulo` (substituição total do conjunto) | mitigate | Dialog de confirmação explícito antes de salvar (Task 06.2), citando a semântica destrutiva — mesma defesa em profundidade já usada em telas de ação destrutiva da Fase 2. |
| T-03-05 | Tampering (supply chain) | `fl_chart` (Task 07.2) | mitigate | Pacote já em uso no mesmo workspace (`task_manager_flutter`), mesma versão fixada (`^1.2.0`) — não requer checkpoint bloqueante adicional (mesmo raciocínio de `file_picker` na Fase 2). |
| T-03-06 | Repudiation | Nenhum log de auditoria client-side para ações de Licença/Módulos (ações administrativas de alto impacto) | accept | Fora do escopo desta fase (sem requisito formal de auditoria no `ROADMAP.md`); registrar como débito técnico para fase futura se o PO quiser. |

---

## Verificação goal-backward (o que prova que a Fase 3 atingiu seu objetivo)

**Objetivo (ROADMAP.md + pedido adicional do usuário):** CRUD completo de Licença, Contatos,
Ordem de Serviço e Módulos Contratados, mais um dashboard de crescimento com projeção simples.

**Verdades observáveis (usuário MASTER logado no admin panel):**
1. A partir de `HomeScreen`, existem 5 novos caminhos: Licença, Contatos, Ordem de Serviço,
   Módulos (catálogo + atribuição), Dashboard de Crescimento — sem o tile quebrado da demo.
2. Licença: lista, cria, edita (inclusive `ativo`/datas) uma licença real; não existe botão de
   excluir (backend não suporta).
3. Contatos: lista, cria, edita, exclui um contato comercial real contra `/api/contato-comercial`
   — domínio correto, não mais o log de negociação de grãos.
4. Ordem de Serviço: lista, cria, edita (título/status/prioridade/datas/FKs), exclui um chamado
   real contra `/api/chamados`; status/prioridade aparecem com labels em português corretos
   (não o texto placeholder do `getDescricao()` do backend).
5. Módulos: catálogo CRUD completo; tela de atribuição carrega um parceiro/empresa real por ID,
   mostra o catálogo com os já vinculados pré-marcados, e salvar substitui o conjunto completo
   com confirmação prévia.
6. Dashboard de Crescimento: 3 gráficos carregam dados reais agregados por mês, com projeção dos
   próximos meses visível ao expandir cada card, e aviso sobre a limitação do gráfico de módulos.

**Artefatos obrigatórios:** todos os arquivos listados na tabela "Arquivos principais" da
Estrutura de Execução (8 planos), mais os testes correspondentes de cada `Verify`.

**Key links (onde é mais provável quebrar):**
- `ChamadoController.atualizar` (PUT, `JsonNode` livre) → `_transformChamadoPayload` com
  `isEditing:true` — se a forma aninhada `{'parceiro':{'id':...}}` divergir do que o backend
  espera, a reatribuição de parceiro/empresa/setor do chamado silenciosamente não persiste.
- `ParceiroModuloController.vincular`/`EmpresaModuloController.vincular` (DELETE+INSERT) →
  `ModuloAtribuicaoScreen._salvar` — se o `moduloIds` enviado não refletir exatamente o estado
  marcado na tela, módulos são desvinculados silenciosamente (por isso a confirmação explícita
  da Task 06.2 é uma mitigação real, não só UX).
- `DashboardCrescimentoController` (novas queries SQL com `date_trunc`/`to_char`) → parsing das
  respostas no Flutter (`{mes,total}`) — se o formato de `mes` divergir do esperado (`YYYY-MM`),
  o eixo X do gráfico quebra silenciosamente (mostra `NaN`/posição errada).
- `Parceiro.dhCreatedAt` sem o inicializador `= LocalDateTime.now()` — se removido/esquecido em
  refactor futuro, todo INSERT novo de Parceiro grava `NULL` na coluna, quebrando
  silenciosamente o gráfico "novos parceiros por mês" (linha some da série mais recente).

## Testes (resumo)

TDD (`tdd="true"`) em: Task 01.2 (`ContatoComercialControllerTest`), Task 02.2
(`DashboardCrescimentoControllerTest`), Task 03.2 (`field_config_test`), Task 03.3
(`generic_grid_screen_test`/`generic_detail_form_screen_test`), Task 07.1
(`growth_projection_test`). Demais tasks: teste de widget cobrindo o `Verify` declarado.
`flutter analyze` limpo e `flutter test` completo são gate final (Task 08.2), mais `mvn test`
limpo (ao menos os testes tocados/novos) no backend antes do merge de P01/P02 em `desenv` do
`AppAcademia` — ver `## Fluxo git` abaixo para os gates de code review de cada repositório.

## Fluxo git

**Dois repositórios, convenções DIFERENTES** (ver `CLAUDE.md` de cada um):

- **`AppAcademia`** (P01, P02): já tem remoto/produção — seguir o fluxo completo do
  `CLAUDE.md` do workspace: branch própria a partir de `desenv`
  (`card-578-fase3-contato-comercial-dashboard` ou 2 branches separadas se preferir isolar
  CONT-01 de DASH-01), code review antes de merge em `desenv`, QA em `desenv`, só depois PR
  para `main`. Rodar `mvn test` (ao menos os testes tocados) antes de cada code review.
- **`task_manager_admin_panel`** (P03-P08): **sem remoto ainda** (Fase 6 do `ROADMAP.md` cuida
  disso) — mesma convenção já usada nas Fases 1-2 deste projeto: branch única para a fase
  inteira a partir de `desenv`, ex. `card-578-fase3-licenca-contatos-os-modulos`. Cada um dos 6
  planos Flutter (P03-P08) = 1 commit atômico em PT-BR, sem `Co-Authored-By`, na ordem das waves
  (1→2→3; dentro da wave 2, ordem livre). Merge local em `desenv` só após Task 08.2 (gate final)
  e `code-review` sem blocker. Sem push (remoto só na Fase 6).
- **Ordem entre repositórios**: mergear P01/P02 (`AppAcademia`) em `desenv` **antes** de rodar o
  smoke manual da Task 08.2 (que depende do backend real rodando) — mas o desenvolvimento
  Flutter (P03-P07) pode prosseguir em paralelo, já que os contratos de request/response de
  todos os endpoints novos estão fixados neste `PLAN.md` (não precisa esperar o backend estar
  pronto para codar contra o contrato).
