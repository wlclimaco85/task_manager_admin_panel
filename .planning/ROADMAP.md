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

## Fase 2b — Onboarding/gestao CROSS-TENANT de Parceiro/Empresa/Login/Roles/Modulos

Pedido explicito do usuario (2026-08-28, apos entrega da Fase 1): o admin
panel precisa das telas de Parceiros, Roles, Logins e "todos os cadastros
pra cadastrar um cliente [novo na plataforma]: um parceiro, login, roles" —
mais a tela pra atribuir modulo contratado a Parceiro/Empresa.

Diferenca fundamental em relacao as telas equivalentes do `task_manager_flutter`:
la' sao sempre escopadas ao TENANT logado (isolamento por empresaId/parceiroId,
todo o trabalho de seguranca desta sessao — TenantFilter/TenantSecurity/
isCliente() etc.). Aqui e' o DONO DO SISTEMA gerenciando/cadastrando QUALQUER
cliente da plataforma inteira — cross-tenant, nao escopado a um empresaId
so'. Login usado no admin panel PRECISA ser genuinamente MASTER (tipoLogin
real, nao o bug de tipo_login=0/ordinal ja corrigido em outro hotfix desta
sessao) -- nunca reusar as mesmas chamadas de API do cliente sem confirmar
que o backend realmente bypassa TenantFilter so' pra MASTER (ja e o
comportamento hoje: `TenantFilter.buildFetchPredicate`/`buildEmpresaFetchPredicate`
retornam `cb.conjunction()` pra `ctx.isMaster()==true` — CONFIRMAR isso caso
a caso por endpoint antes de reusar, nao assumir).

Escopo desta fase:
- Tela de cadastro de Parceiro (novo cliente na plataforma) — cross-tenant,
  cria o Parceiro + a Empresa dele se ainda nao existir.
- Tela de Login (criar/editar) cross-tenant — reusa o backend
  `POST/PUT /api/login` (ja MASTER-aware), mas a TELA em si precisa permitir
  escolher QUALQUER empresa/parceiro da plataforma (nao so' a do usuario
  logado, que nem existe nesse contexto de admin).
- Tela de Roles (listar/gerenciar roles do sistema, nao por-tenant).
- Tela de atribuicao de Modulo Contratado a Parceiro/Empresa (dominio
  `modulo-servico`/`servico-contratado` ja existente no backend).
- Fluxo de "onboarding de cliente novo": parceiro + empresa + login inicial
  + roles + modulos contratados, numa sequencia coerente (nao
  necessariamente 1 tela so' — pode ser um wizard/fluxo de varias telas
  encadeadas, decidir no PLAN.md desta fase apos pesquisa).

Esta fase deve vir ANTES da Fase 3 (Licenca/Contatos/OS) na ordem de
implementacao, ja que "cadastrar cliente novo" e' o fluxo mais fundamental
do produto — mas so' apos a Fase 2 (migracao do menu "Sistema") estar
concluida e revisada, pra nao acumular mudanca demais numa unica rodada.

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
- **Fase 2, item SIS-05 (Editor de Telas) — backend incompleto.** `TelaController.java`
  (AppAcademia) so expoe `GET /api/telas` e `GET /api/telas/{nome}`. Os endpoints
  `PUT /api/telas/{telaId}/fields/reorder` (reordenar campos) e
  `PUT /api/telas/{telaId}/fields/{fieldId}` (salvar propriedades de um campo) NAO existem
  no backend ainda -- o Flutter (`tela_editor_screen.dart`/`tela_field_editor_screen.dart`)
  foi implementado contra o contrato ja declarado em `ApiLinks` (Wave 1 desta fase), com erro
  de rede tratado visivelmente, mas a funcionalidade de editar/reordenar campos so funciona
  de fato depois que esses 2 endpoints forem implementados no `AppAcademia`. Bloqueia a
  Task 13.3 (validacao end-to-end) da Fase 2 para este item especifico.
