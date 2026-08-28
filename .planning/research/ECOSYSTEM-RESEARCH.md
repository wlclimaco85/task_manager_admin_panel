# Pesquisa de ecossistema — task_manager_admin_panel (Painel do Dono)

Gerado por `gsd-project-researcher` em 2026-08-28 (persistido manualmente pelo especialista Flutter/GSD porque o agente foi bloqueado de escrever arquivo diretamente).

Confiança geral: MEDIA-ALTA.

## Contexto verificado no código-fonte do task_manager_flutter

- `pubspec.yaml` do cliente: Dart SDK `>=3.5.0 <4.0.0`; o admin panel recém-criado está em `^3.12.2` — **incompatibilidade de faixa de SDK entre os dois apps**, relevante para decisão de monorepo.
- `lib/utils/api_links.dart`: `ApiLinks._backendUrl`/`_backendContextPath` via `String.fromEnvironment` — precisam ficar `const`, nunca `final`. Incidente real documentado (P0 producao 2026-08-13/21): find-replace mecanico const->final quebrou login em producao por 8 dias, mascarado como erro de CORS.
- `lib/utils/tenant_context.dart`: `TenantContext` estatico injeta `Authorization: Bearer <token>`, `X-Tenant-ID` e query params (`empId`/`parceiro`/`parceiroId`/`parcId`/`clienteId`/`userId`) automaticamente, trata 401 exceto em rotas publicas. `isAdminEmail` e heuristica por e-mail hardcoded (`wlclimaco@gmail.com`), nao e um modelo de autorizacao robusto.
- `generic_grid_windows_screen.dart` (~6160 linhas) e `generic_detail_form_screen.dart` (~2090 linhas): grid/form genericos maduros, validados em producao (ex. card 580 — busca remota debounced em dropdown), mas fortemente acoplados a servicos especificos do cliente (`PermissionService`, `AlertaPollingService`, `LoginPopup_screens`, `session_expired_handler`, `login_model.dart` completo).
- `lib/core/design/design_tokens.dart` + `core/theme/*_breakpoint_styles.dart` + `core/responsive/responsive_helper.dart`: sistema de tokens/responsividade maduro — reaproveitar a *estrutura*, nunca a paleta (regra ja existente no CLAUDE.md do workspace).
- `lib/widgets/dashboard_area/` e `lib/widgets/accessibility/` (WCAG AA): base reaproveitavel para a fase de dashboards.

## 1. Padroes de admin panel Flutter multiplataforma

Flutter e opcao viavel para admin dashboards internos autenticados (web+desktop+mobile de uma base). Arquitetura recomendada 2025-2026: MVVM + feature-first (`features/<nome>/{data,domain,presentation}`), divergindo da estrutura atual do cliente (por-tipo: `screens/`, `models/`, `services/`). Recomendacao: nao copiar cegamente a organizacao por-tipo do cliente; adotar feature-first nos modulos novos (licenca, contatos, OS, modulos contratados), reaproveitando como esta a camada `core/`/`widgets/` generica herdada.

Fontes: dev.to/techwithsam (clean architecture flutter 2026), adminlte.io/blog/flutter-admin-dashboard-templates, docs.flutter.dev/app-architecture/guide

## 2. State management para painel denso em dados

Consenso de mercado 2026: Riverpod e o padrao default para projetos novos; BLoC para times grandes/regulados; Provider considerado datado para greenfield.

**Decisao para este projeto (diverge do "padrao de mercado"):** manter **Provider** como base para os componentes ADAPTADOS do cliente (grid/form genericos, dropdown remoto) — ja validados em producao, reescrever para Riverpod so por tendencia aumenta risco de regressao sem ganho real. Considerar Riverpod apenas em modulos 100% novos e isolados (ex. analytics com multiplas fontes assincronas concorrentes), caso a caso.

Fontes: sharpskill.dev/flutter-state-management-2026, softaims.com/flutter-state-management-riverpod-bloc-2026

## 3. Design system distinto do app cliente

Mercado recomenda monorepo (Melos ou `workspace:` do Dart) quando ha pacotes compartilhados versionados juntos.

**Nao recomendado aqui:** (1) SDKs Dart ja divergem entre os dois apps; (2) os repos do ecossistema ja sao independentes com deploy proprio e convencao estabelecida (CLAUDE.md): copiar/adaptar estrutura, nunca tema/cor. Estrategia adotada: copiar a *estrutura* de `core/design`/`core/theme`/`core/responsive`, adaptar nomes de pacote, paleta 100% propria (feita nesta fase via `ui-ux-pro-max`, tema "Control Room" dark-first).

Fontes: designsystemscollective.com (monorepos flutter workspaces), lazebny.io/dart-flutter-workspaces

## 4. Autenticacao JWT compartilhada entre dois apps Flutter

JWT stateless e adequado para multiplos apps sem SSO real: cada app faz login independente contra o mesmo `/rest/auth/login` e guarda seu proprio token localmente. Padrao ja usado no cliente (`AuthUtility` + Bearer + `TenantContext`) e adequado.

**Ponto de atencao real (nao tecnico de auth, e de autorizacao no backend):** hoje "admin/dono" e identificado por heuristica de e-mail hardcoded (`TenantContext.isAdminEmail`), aceitavel como atalho de MVP mas nao deve virar o modelo de autorizacao do painel administrativo em producao. Recomenda-se avaliar no backend Spring Security um `TipoLogin`/role dedicado com `@PreAuthorize`, analogo ao ja existente para `MASTER` — **registrado como debito tecnico / decisao de arquitetura pendente para o PO**, nao resolvido nesta fase.

Fontes: carmine.dev/posts/jwtauth, vibe-studio.ai/insights/jwt-authentication-flutter-web

## 5. Estrutura de ajuda in-app para SaaS/ERP de gestao

Ajuda contextual vinculada a artigo especifico da tela supera "resource center" generico solto. Aplicado ao AppAcademia: estrutura de dados de ajuda deve ser indexada por **identificador estavel de tela/rota** (nao por topico solto), para alimentar tanto um botao de ajuda contextual no cliente (fase futura) quanto o CMS de conteudo no admin panel. Implica que as telas do `task_manager_flutter` precisam ter nomes/rotas estaveis antes dessa fase.

Fontes: document360.com/blog/contextual-in-app-documentation, userpilot.com/blog/in-app-resource-center

## Achados-chave

- Reaproveitar (adaptar, nao copiar cego) `TenantContext`, `ApiLinks`, `ResponsiveHelper`, padrao dos grids/forms genericos do cliente.
- Cuidado obrigatorio ao portar `api_links.dart`: grep por `.fromEnvironment(` antes de qualquer conversao const->final.
- Manter Provider (nao Riverpod) nos componentes herdados/adaptados.
- Nao fazer monorepo/pub workspace agora entre os apps Flutter do ecossistema.
- Autenticacao JWT independente por app; autorizacao de admin/dono via heuristica de e-mail e debito tecnico a resolver no backend antes de producao real do painel.
- Ajuda in-app: desenhar modelo de dados indexado por tela/rota estavel desde ja, mesmo que o conteudo real so seja escrito na ultima fase.

## Avaliacao de confianca

| Area | Nivel | Motivo |
|------|-------|--------|
| Stack | ALTA | Verificado direto no codigo-fonte real do task_manager_flutter |
| Features | MEDIA | Escopo veio do usuario; sem pesquisa de concorrentes de admin panel de academia especificamente |
| Arquitetura | ALTA | Codigo-fonte real + multiplas fontes de mercado concordantes |
| Pitfalls | ALTA | Incidente real documentado no CLAUDE.md do proprio workspace |

## Implicacoes para o roadmap

1. Fundacao (auth adaptada + design tokens proprios + scaffold responsivo) — pre-requisito de tudo, risco baixo. **= Fase 1 desta rodada.**
2. Migracao da aba "Sistema" (sem "Empresas") — valor imediato, reusa grid/form genericos.
3. Gestao de licenca + Modulos contratados — pode exigir schema/backend novo; precisa pesquisa dedicada de backend antes de detalhar.
4. Contatos + Ordem de Servico — CRUD padrao sobre os componentes adaptados na Fase 1.
5. Dashboards de acesso/performance + telas mais usadas — precisa pesquisa dedicada sobre instrumentacao de eventos de uso existente (ou nao) no backend/cliente.
6. Sistema de ajuda in-app — por ultimo; depende de rotas/nomes de tela estaveis das fases anteriores e de inventario completo das telas do cliente.

## Lacunas / perguntas em aberto (nao resolvidas nesta pesquisa)

- Schema de licenca/modulos contratados no backend Spring Boot.
- Se ja existe instrumentacao de analytics/uso de tela no backend ou cliente.
- Modelo de autorizacao "dono/admin" no Spring Security (hoje heuristica de e-mail).
- Inventario completo de telas do task_manager_flutter para estruturar conteudo de ajuda por tela.
