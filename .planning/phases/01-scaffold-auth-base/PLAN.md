# PLAN — Fase 1: Scaffold + Auth + Grid/Form/Detail base

Ver RESEARCH.md desta mesma pasta para o racional das decisoes de escopo.

## Tarefas

1. `flutter create --platforms=web,windows,android,ios task_manager_admin_panel`
   — FEITO.
2. `pubspec.yaml`: nome/descricao proprios; deps `http`, `shared_preferences`,
   `google_fonts`, `intl`; dev dep `mockito`.
3. Design system proprio via `ui-ux-pro-max` -> `lib/core/theme/app_theme.dart`
   (`AppColors` dark/light, `AppSpacing`, `ThemeData` completo,
   `DataTableThemeData` para grids densos) — FEITO.
4. Camada de config/rede/auth (nova, enxuta, mesmo contrato do cliente):
   - `lib/config/api_links.dart` — const `_backendUrl`/`_backendContextPath`
     (`String.fromEnvironment`), `login`, base para futuros endpoints.
   - `lib/models/login_model.dart` — modelo simplificado de sessao.
   - `lib/models/network_response.dart` — copiado verbatim do cliente
     (generico, sem alteracao de logica).
   - `lib/services/auth_utility.dart` — sessao/JWT (persistencia
     SharedPreferences + checagem de expiracao).
   - `lib/utils/tenant_context.dart` — headers/tenant + auto-logout em 401.
   - `lib/services/network_caller.dart` — GET/POST/PUT/DELETE com tenant e
     auth.
   - `lib/services/auth_service.dart` — `login(email, senha)` chamando
     `ApiLinks.login`.
5. `lib/screens/login_screen.dart` — tela de login propria (email/senha,
   validacao, chamada a `AuthService`, feedback de erro, loading state).
6. `lib/widgets/generic/field_config.dart` — `FieldType` + `FieldConfig`.
7. `lib/widgets/generic/generic_grid_screen.dart` — grid base: paginacao,
   busca, colunas configuraveis, acoes (novo/editar/excluir) chamando
   `NetworkCaller`.
8. `lib/widgets/generic/generic_detail_form_screen.dart` — form base
   dirigido por `List<FieldConfig>`, validacao, submit (create/update) via
   `NetworkCaller`.
9. `lib/screens/home_screen.dart` — shell pos-login com um modulo de
   demonstracao (Contatos, endpoint placeholder) provando grid+form+detail
   ponta a ponta.
10. `lib/main.dart` — `MaterialApp` com `AppTheme`, rota inicial decide
    Login vs Home conforme sessao persistida.
11. Testes:
    - `test/services/auth_utility_test.dart` — expiracao de JWT,
      persistir/limpar sessao.
    - `test/widgets/login_screen_test.dart` — validacao de campos
      obrigatorios, estado de loading/erro.
    - `test/widgets/generic_grid_screen_test.dart` — renderiza colunas,
      estado vazio, estado de erro.
12. `flutter analyze` limpo.
13. `flutter test` passando.
14. `code-review` (skill) sobre o diff.
15. Commit(s) em PT-BR sem `Co-Authored-By`; branch de card
    `card-578-fase1-scaffold-auth-base` a partir de `desenv`; merge local em
    `desenv` apos revisao. SEM push (remote so na Fase 6, por decisao do
    PO desta rodada).

## Criterio de pronto (goal-backward)

- App abre em Web/Windows (validado nesta sessao com `flutter test`/`analyze`;
  execucao visual completa fica a criterio do PO/QA, dado o ambiente
  sandboxed desta sessao).
- Login real contra o backend Railway funciona no fluxo de codigo (mesmo
  endpoint/contrato do cliente) — validacao de integracao ponta a ponta
  contra o backend real fica marcada como pendente de teste manual pelo PO,
  registrada no relatorio final.
- Grid + form + detail base compilam, tem teste cobrindo estrutura, e sao o
  ponto de extensao para as Fases 2-5.
