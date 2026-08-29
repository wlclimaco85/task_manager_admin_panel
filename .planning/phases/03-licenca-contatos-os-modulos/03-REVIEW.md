# Code Review Final — Fase 3 (Licença, Contatos, OS, Módulos, Dashboard de Crescimento)

**Reviewed:** 2026-08-29
**Depth:** adversarial completo — diff inteiro dos 2 repositórios (`task_manager_admin_panel`
`e931c7f..HEAD`, `AppAcademia` `5aecd753..HEAD` + fix pós-review `32a24452`)
**Status:** APROVADO (após correção do achado crítico abaixo)

## Histórico desta revisão

1. O `gsd-executor` da Wave 3 (P08) fez uma auto-revisão manual (não é um `gsd-code-reviewer` de
   verdade — a ferramenta `Task`/`Agent` não estava disponível no contexto dele) e concluiu
   "APROVADO sem ressalvas".
2. Um `gsd-code-reviewer` real foi disparado em seguida para verificar essa auto-revisão de forma
   adversarial (não aceitar como fato estabelecido) — encontrou **1 achado crítico real** que a
   auto-revisão não pegou.
3. O achado foi verificado por leitura direta do código (não por achismo) e corrigido no mesmo
   dia, com teste de regressão e suíte completa confirmando zero regressão.

## CR-01 (CRÍTICO, CORRIGIDO) — `ContatoComercialController` sem autorização

**Achado:** `ContatoComercial` é um domínio exclusivo do dono da plataforma (agenda/CRM do
MASTER — ver comentário da entidade e da migration `V20261020`), mas o controller não tinha
nenhuma restrição de autorização. Qualquer login autenticado (inclusive cliente `APP_ABRACO`)
conseguia criar/listar/editar/apagar registros nesta tabela via `/api/contato-comercial`. O guard
de tenant genérico (`GenericServiceImpl`) só isola por tenant para não-MASTER — não restringe
QUEM pode acessar o domínio.

**Causa raiz da omissão:** a fronteira de autorização não estava explícita no Threat Model
original da fase (o item mais próximo, T-03-04, cobria só `ModuloAtribuicaoScreen`) — nenhum dos
2 dominios novos desta fase (`ContatoComercial`, `DashboardCrescimento`) teve essa checagem
verificada explicitamente na auto-revisão do executor, e só o Dashboard acertou por ter sido
implementado seguindo o padrão de `QueryBuilderController` desde o início.

**Fix aplicado** (commit `32a24452`, backend `AppAcademia`, branch `desenv`):
`ContatoComercialController.java` reescrito — os 5 métodos HTTP (`getAll`/`getById`/`create`/
`update`/`delete`), antes herdados sem override de `GenericController`, foram sobrescritos
explicitamente, cada um com `@PreAuthorize("@tenantSecurity.isMaster()")`, delegando para a
implementação genérica via `super`. **Achado técnico relevante durante o fix:** `@PreAuthorize`
a nível de classe NÃO funciona para métodos herdados sem override — Spring Method Security
resolve a anotação contra `method.getDeclaringClass()` do método efetivamente invocado, que
continua sendo `GenericController` (compartilhado por outros domínios sem essa restrição), não a
subclasse. Confirmado ao vivo: a primeira tentativa (`@PreAuthorize` só na classe) fez os testes
de regressão falharem com 200/201 em vez de 403 — só a segunda tentativa (override explícito de
cada método) funcionou.

**Testes:** novo `ContatoComercialControllerSecurityTest.java` (4 casos: MASTER→200,
não-MASTER→403 em GET e POST, sem autenticação→4xx) + suíte de negócio existente
`ContatoComercialControllerTest` (5 casos) continuam passando. Suíte completa do backend: 2287
testes, 26 falhas/134 erros — idêntico ao baseline pré-existente documentado, zero regressão
nova.

## Confirmado correto (verificado contra o código, não só a auto-revisão aceita)

- `transformChamadoPayload` (`ordem_servico_screen.dart`) — assimetria POST (`parceiroId` plano)
  vs PUT (`parceiro:{id}` aninhado) confirmada contra `ChamadoDTO`/`ChamadoController` reais.
- `ModuloAtribuicaoScreen._salvar()` — dialog de confirmação bloqueia de verdade o POST, sem
  race condition entre confirmação e o corpo enviado.
- `GenericGridScreen.deleteUrl` opcional — `LicencaScreen` usa `deleteUrl: null` corretamente,
  ícone de excluir não aparece.
- `DashboardCrescimentoController` — todos os 3 endpoints com `@PreAuthorize isMaster()`
  corretos desde o início; SQL via `JdbcTemplate` com placeholders `?` parametrizados, sem
  concatenação de string (sem risco de SQL injection).
- Wiring final do `home_screen.dart` — getters órfãos de `/api/contatos` (negociação de grãos)
  confirmados removidos, zero referência remanescente.
- `growth_projection.dart` — regressão linear por mínimos quadrados, casos de borda (vazio,
  1 ponto, histórico constante) tratados corretamente, projeção negativa clampada em 0.

## WARNING (não bloqueia, ação futura recomendada)

**WR-01:** nenhum teste do domínio `ContatoComercial` cobria a fronteira de autorização antes
desta correção (o `@WebMvcTest` original desabilitava segurança inteiramente) — é exatamente por
isso que a auto-revisão da Wave 3 não pegou o CR-01 por leitura isolada. Recomenda-se, como
ação de acompanhamento (não bloqueia esta fase), varrer os demais controllers exclusivos do
admin panel (`LicencaController`, `EmpresaModuloController`) em busca do mesmo padrão de
autorização ausente — ambos já registrados como débito técnico conhecido no `PLAN.md` (T-03-01,
T-03-02), mas nenhum teve teste de regressão de autorização escrito ainda.

## Débito técnico aceito (não é achado novo, já registrado no PLAN.md antes desta fase)

- `PUT /api/licencas/{id}` sem `@PreAuthorize` (T-03-01).
- `POST /api/empresa-modulo` sem `@PreAuthorize`/validação de tenant (T-03-02).
- Sem log de auditoria client-side para ações de Licença/Módulos (T-03-06).
- Limitação de modelagem do gráfico "módulos novos por mês" (reset de `dh_created_at` por
  DELETE+INSERT) — disclosed visivelmente na própria tela do dashboard.
- Backend `TelaController` (Fase 2) sem endpoints de reorder/update de campo — registrado
  separadamente no `ROADMAP.md`.

## Pendência real (não corrigida nesta sessão)

O `PLAN.md` (Task 08.2) exige um `checkpoint:human-verify` contra o backend real rodando
localmente (Postgres), cobrindo os 5 fluxos novos (Licença, Contatos, OS, Módulos, Dashboard).
**Isso não foi executado nesta sessão** — fica como validação manual do usuário antes de
considerar a Fase 3 definitivamente fechada para uso real.

---
_Reviewed: 2026-08-29_
_Reviewer: Claude (gsd-code-reviewer, adversarial) + correção aplicada pela sessão principal_
