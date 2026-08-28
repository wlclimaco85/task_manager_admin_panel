# RESEARCH — Fase 1: Scaffold + Auth + Grid/Form/Detail base

Baseado em `.planning/research/ECOSYSTEM-RESEARCH.md` + leitura direta do
codigo-fonte de `task_manager_flutter` feita pelo especialista Flutter/GSD
nesta sessao.

## Arquivos do cliente inspecionados (para decidir o que reaproveitar)

- `lib/utils/api_links.dart` (920 linhas): classe estatica de constantes de
  URL. `_backendUrl`/`_backendContextPath`/`_windowsDownloadUrl` sao
  `String.fromEnvironment(...)` e DEVEM continuar `const` (incidente P0 real
  documentado no CLAUDE.md do workspace ao converter para `final`).
- `lib/models/network_response.dart` (18 linhas): wrapper generico
  `NetworkResponse(isSuccess, statusCode, body)` — 100% generico, reusavel
  verbatim.
- `lib/models/auth_utility.dart` (190 linhas): `AuthUtility` estatico com
  `LoginModel? userInfo`, persiste sessao em `SharedPreferences`, decodifica
  JWT p/ checar expiracao sem lib extra. Depende de `LoginModel`,
  `PermissionService` (menu dinamico do cliente) e `AlertaPollingService`
  (push notifications do cliente) — dependencias especificas de cliente,
  FORA de escopo do admin panel na Fase 1.
- `lib/utils/tenant_context.dart` (216 linhas): `TenantContext` estatico
  injeta `Authorization`/`X-Tenant-ID`/query params de tenant em toda
  chamada HTTP; `isAdminEmail` e heuristica de e-mail hardcoded (debito
  tecnico, registrado no ROADMAP, nao resolvido aqui). Depende de
  `SessionExpiredHandler` do cliente.
- `lib/services/network_caller.dart` (387 linhas): wrapper HTTP com
  auto-logout em 401 fora de rotas publicas. Depende de `LoginPopup_screens`
  do cliente (import so para tipo, nao usado diretamente na logica core).
- `lib/widgets/generic_grid_windows_screen.dart` (6159 linhas) +
  `lib/widgets/generic_detail_form_screen.dart` (2087 linhas): grid/form
  genericos maduros e validados em producao (ex. card 580), mas com
  acoplamento profundo a `PermissionService`, `AlertaPollingService`,
  `LoginPopup_screens`, `session_expired_handler.dart`, `login_model.dart`
  completo (com dezenas de campos especificos de academia/parceiro),
  `tela_ajuda_model`/`tela_ajuda_service`, `grid_colors.dart` (branding do
  cliente — NUNCA replicar por regra do CLAUDE.md), `grid_texts.dart`,
  `app_logger.dart` (671 linhas), alem de packages extras (`data_table_2`,
  `file_picker`, `file_saver`, `syncfusion_flutter_datagrid`, `printing`,
  `pdf`, `dio`, `firebase_*`).

## Decisao de escopo para a Fase 1 (registrada, nao e ambiguidade de regra de
## negocio — e decisao tecnica de engenharia sob restricao de tempo/risco)

Copiar os dois arquivos gigantes (~8250 linhas) verbatim e destrinchar a
teia de dependencias de cliente embutida neles (permissoes dinamicas, push
notifications, tela de ajuda, modelo de login com dezenas de campos de
academia) para so entao adaptar teria custo/risco de regressao alto para uma
Fase 1 de fundacao, e a maior parte dessas dependencias (permissoes
dinamicas de menu, push notification) nao faz sentido para o escopo do
admin panel nesta fase.

**Decisao:** reaproveitar verbatim (com import de pacote ajustado) as pecas
realmente genericas e desacopladas — `NetworkResponse` — e REESCREVER, de
forma enxuta e propria para este app, seguindo o MESMO padrao/contrato
(Bearer JWT + tenant headers + auto-logout em 401 + grid paginado/pesquisavel
+ form dirigido por config de campos):
- `LoginModel` simplificado (so os campos que o admin panel precisa: id,
  nome, email, token, tipoLogin, empresa, roles).
- `AuthUtility` sem `PermissionService`/`AlertaPollingService`.
- `TenantContext` e `NetworkCaller` adaptados, mesma logica de tenant/401.
- `GenericGridScreen` + `GenericDetailFormScreen` novos, no mesmo espirito
  (FieldConfig-driven, paginacao, busca, CRUD contra backend via
  `NetworkCaller`), em escopo bem menor que o par de 8250 linhas do
  cliente — o suficiente para servir de "base" as fases 2-5, que podem
  crescer esse par incrementalmente conforme a necessidade real de cada
  modulo (nao preventivamente).

Isso mantem a garantia central pedida ("reaproveitar o mesmo backend/endpoint
JWT... mesmo ApiLinks/fluxo adaptado de nome de pacote") sem herdar todo o
peso e acoplamento academia-especifico do cliente.

## Riscos e mitigacoes

- **Risco:** repetir o incidente historico de `const`→`final` em
  `.fromEnvironment(`. Mitigacao: grep por `.fromEnvironment(` no
  `api_links.dart` do admin panel antes de qualquer edicao de modificador,
  mantidos `const` nos 3 campos identificados.
- **Risco:** paridade de design tokens com o cliente (nao deveria haver).
  Mitigacao: paleta gerada do zero via `ui-ux-pro-max`, tema "Control Room"
  dark-first, documentada em `lib/core/theme/app_theme.dart`.
