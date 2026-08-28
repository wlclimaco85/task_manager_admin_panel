# ROADMAP — task_manager_admin_panel (Painel do Dono)

Card Trello #578 (https://trello.com/c/wh94M1uI, id `6a8cf4b8370441eef293f910`).
Projeto alvo: app Flutter novo e SEPARADO dos apps cliente (`task_manager_flutter` /
`task_manager_flutter_merged_final`) — painel de gestao do dono do sistema.
Plataformas: Web + Windows + Mobile (Android/iOS), todas desde o inicio.

Base de pesquisa: `.planning/research/ECOSYSTEM-RESEARCH.md`.

## Fase 1 — Scaffold + Auth + Grid/Form/Detail base (ESTA RODADA)

Objetivo: fundacao do app rodando nas 4 plataformas, com login funcional contra o
mesmo backend JWT do `task_manager_flutter`, design system proprio ("Control
Room", dark-first) e um par de widgets genericos grid+form+detail reutilizavel
pelas fases seguintes, validado com um modulo de demonstracao (Contatos).

Entrega:
- Estrutura de pastas `lib/core`, `lib/config`, `lib/models`, `lib/services`,
  `lib/screens`, `lib/widgets/generic`.
- `ApiLinks` adaptado (mesmo backend, mesmo padrao `String.fromEnvironment`
  const para `_backendUrl`/`_backendContextPath`).
- `AuthUtility` (sessao/JWT), `NetworkCaller`, `TenantContext` adaptados —
  sem as dependencias especificas de cliente (`PermissionService`,
  `AlertaPollingService`, push notifications).
- Tela de login propria, chamando `POST /rest/auth/login`.
- `GenericGridScreen` + `GenericDetailFormScreen` (par base reutilizavel).
- Design system proprio (`core/theme/app_theme.dart`), definido via
  `ui-ux-pro-max`.
- Testes: fluxo de login (unit/widget) + estrutura basica de grid/form.
- `flutter analyze` limpo, `flutter test` passando.

## Fase 2 — Migracao do menu "Sistema"

Migrar os itens do grupo "Sistema" de `task_manager_flutter/lib/utils/menu_config.dart`
para o admin panel, EXCETO "Empresas" (fica no cliente). Itens candidatos:
Aplicativo, Cadastro Empresa, Configuracoes Admin, Config. Sistema, Editor de
Telas, Permissoes, Teste de Endpoints, Query Builder. Reusa o par
grid/form/detail da Fase 1. Valor imediato: retira do cliente telas que so o
dono usa, valida o padrao de reuso no app novo.

## Fase 3 — Licenca, Contatos, Ordem de Servico, Modulos contratados

CRUD completo de:
- Gestao de licenca (pode exigir schema/backend novo — pesquisa dedicada de
  backend antes de detalhar o PLAN.md desta fase).
- Contatos.
- Ordem de servico.
- Gestao de modulos contratados (reusa dominio de `modulo-servico`/
  `servico-contratado` ja existente no backend, ver `ApiLinks`).

## Fase 4 — Dashboards de acesso/performance + telas mais usadas (analytics)

Dashboards de acesso e performance do sistema, e gestao/analytics de telas
mais usadas. Pre-requisito a checar: se ja existe instrumentacao de eventos
de uso no backend/cliente; se nao existir, entra sub-fase de instrumentacao
antes do dashboard em si.

## Fase 5 — Sistema de ajuda com conteudo real

Sistema de ajuda in-app com conteudo real para as telas do `task_manager_flutter`
(pesquisa de como SaaS/ERP estruturam ajuda in-app ja feita na Fase 1 —
ver research; conteudo indexado por identificador estavel de tela/rota, nao
por topico solto). Depende de inventario completo das telas do cliente e de
rotas/nomes estaveis definidos nas fases anteriores — por isso fica por
ultimo.

## Fase 6 — Publicacao remota

Criacao do repositorio remoto (`gh repo create wlclimaco85/task_manager_admin_panel`)
e push de `main`/`desenv`. Feita apos o trabalho local da Fase 1 estar pronto,
testado e revisado (ordem alterada pelo usuario/PO nesta rodada — decisao
registrada no comentario do card #578 e no relatorio final desta sessao).

## Debitos tecnicos / decisoes de arquitetura registradas (nao resolvidas nesta rodada)

- Autorizacao "dono/admin" hoje e heuristica de e-mail hardcoded
  (`TenantContext.isAdminEmail` no cliente); recomenda-se role dedicada no
  backend Spring Security com `@PreAuthorize`, analoga a `MASTER`, antes de
  usar o admin panel em producao real.
- Schema de licenca/modulos contratados no backend ainda nao investigado.
- Instrumentacao de analytics de uso de tela: existencia nao confirmada.
