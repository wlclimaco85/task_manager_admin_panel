# CLAUDE.md — task_manager_admin_panel (Painel do Dono / Admin)

> Regras globais da workspace estão em `C:\App_Academia\CLAUDE.md`. Em conflito, o pai prevalece.

## Project

**Flutter — Painel do Dono/Admin. App NOVO e SEPARADO dos apps cliente.**

Gestão do servidor/produto (não é app de cliente final): dashboards de acessos/performance, gestão de
licença, contatos, ordem de serviço, módulos, mapeamento dinâmico de telas/rotas por módulo, e a aba
"Sistema" do menu principal (config, usuários, perfis, integrações, rotinas administrativas, Console
de Logs, Teste de Endpoints, E-mail SMTP, Sessões). Consome o backend `AppAcademia`.

**Core Value:** console de administração de alta densidade de dados para o dono do produto — separado
dos apps de cliente, com repositório e identidade próprios.

## Stack & Plataformas

- **Flutter/Dart**, Material 3 + `google_fonts`. Package próprio.
- **Plataformas: android, ios, windows, web** (multiplataforma desde a fase inicial). Sem fastlane.
- Estrutura enxuta: `lib/{config,core,models,screens,services,utils,widgets}` + `main.dart`.

## Tema (IDENTIDADE PRÓPRIA — NÃO MISTURAR)

- Design system próprio **"Control Room"** em `lib/core/theme/app_theme.dart` (`AppColors`,
  `AppSpacing`, `AppTheme`): **dark-first**, alta densidade, contraste alto para grids longos.
- **Deliberadamente distinto** da paleta verde/laranja do app cliente — decisão aprovada pelo PO:
  a exceção de branding do CLAUDE.md pai se aplica, este app tem identidade visual própria.
- **PROIBIDO** misturar com o tema de qualquer outro app (e vice-versa).

## Replicação de Componentes (REGRA IMPORTANTE)

- Reutiliza a arquitetura de grid/form/detail/login do `task_manager_flutter` como **base** — adaptar,
  não copiar cego (e nunca o tema).
- **Sub menu "Sistema":** sempre que alterarem os fontes do sub menu "Sistema" no `task_manager_flutter`,
  é OBRIGATÓRIO replicar aqui também (igual ao que se faz com o `merged_final`). Avaliar também telas/
  componentes base comuns de `lib/widgets` e services básicos.
- Ao adicionar item no menu Sistema, manter os blocos coerentes (lista de itens, map de builders,
  métodos builder) — ex.: itens coexistem, não se excluem.

## UI/UX (OBRIGATÓRIO para mudança de layout)

- O design system foi definido pelo agente `ui-ux-pro-max`. Qualquer mudança de layout/design DEVE
  envolver o agente de UI/UX (`ui-ux-pro-max` / skill `frontend-design`) e respeitar o "Control Room".

## Testes & Code Review (OBRIGATÓRIO)

- **Criar e rodar o teste do cenário (`flutter test` focado) antes de concluir.** Suíte inteira só antes
  de push pra `main`. `analyze` é só apoio.
- **Push para `main` → code review OBRIGATÓRIO.** Branch base: `desenv`. Encoding UTF-8.
