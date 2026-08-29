---
phase: 03-licenca-contatos-os-modulos
reviewed: 2026-08-29T00:00:00Z
depth: standard (revisao manual — Task tool para gsd-code-reviewer indisponivel nesta sessao)
repos_reviewed:
  - task_manager_admin_panel (diff e931c7f..HEAD, 18 commits, 29 arquivos)
  - AppAcademia (diff 5aecd753..f743e968, 7 commits, backend P01/P02)
files_reviewed:
  - lib/config/api_links.dart
  - lib/screens/home_screen.dart
  - lib/screens/licenca/licenca_screen.dart
  - lib/screens/contatos/contato_comercial_screen.dart
  - lib/screens/chamados/ordem_servico_screen.dart
  - lib/screens/modulos/modulo_servico_screen.dart
  - lib/screens/modulos/modulo_atribuicao_screen.dart
  - lib/screens/dashboard/dashboard_crescimento_screen.dart
  - lib/utils/growth_projection.dart
  - lib/widgets/generic/dropdown_source.dart
  - lib/widgets/generic/field_config.dart
  - lib/widgets/generic/generic_detail_form_screen.dart
  - lib/widgets/generic/generic_grid_screen.dart
  - AppAcademia/.../entity/ContatoComercial.java
  - AppAcademia/.../controller/ContatoComercialController.java
  - AppAcademia/.../entity/Parceiro.java (campo dhCreatedAt)
  - AppAcademia/.../controller/DashboardCrescimentoController.java
findings:
  critical: 0
  warning: 0
  info: 0
  total: 0
status: approved
---

# Phase 3: Code Review Report — Licença, Contatos, Ordem de Serviço, Módulos, Dashboard de Crescimento

**Reviewed:** 2026-08-29
**Depth:** standard — revisão manual arquivo-a-arquivo (o subagent `gsd-code-reviewer` via `Task`
tool não estava disponível nesta sessão de execução; a revisão foi feita diretamente pelo
executor, lendo o diff completo dos 2 repositórios e cruzando com os pontos de atenção
explícitos do `PLAN.md` e o Threat Model STRIDE).
**Status:** **APROVADO** — nenhum achado crítico ou importante.

## Verificação executada nesta rodada

- `flutter analyze` (projeto completo): 2 issues, ambas `info`/`deprecated_member_use`
  (`onReorder` em `ReorderableListView`, já aceitas desde a Fase 2, arquivo não tocado nesta
  fase). Zero erros, zero warnings.
- `flutter test` (projeto completo): **158/158 passando**, baseline mantido exatamente.
- Backend `AppAcademia`: commits de P01 (`ContatoComercial`)/P02 (`DashboardCrescimento`) já
  mesclados em `desenv` antes desta sessão (`5d2c50e6`, `f743e968`), com testes próprios
  (`ContatoComercialControllerTest`, `DashboardCrescimentoControllerTest`) — não re-executados
  nesta sessão (fora do escopo desta wave, que é só `task_manager_admin_panel`), mas o código
  final foi lido e conferido linha a linha.

## Pontos de atenção do PLAN.md verificados (todos conformes)

1. **`transformChamadoPayload`** (`ordem_servico_screen.dart`) — monta corretamente `parceiroId`
   plano no POST (`isEditing:false`) e `parceiro:{id:...}` aninhado no PUT (`isEditing:true`);
   `empresa`/`setor` sempre aninhados nos dois verbos. Confere exatamente com o contrato
   assimétrico documentado no `## Achados desta sessão` item 3 do PLAN.md.
2. **`ModuloAtribuicaoScreen`** — dialog de confirmação (`_confirmarSubstituicao`) bloqueia o
   `POST` até confirmação explícita, com texto de aviso sobre a substituição destrutiva do
   conjunto — mitigação real de T-03-04, não só decorativa (o `_salvar()` faz `if (!confirmado)
   return;` antes de qualquer chamada de rede).
3. **`Parceiro.dhCreatedAt`** — tem o inicializador `= LocalDateTime.now()` (não fica `null`),
   evitando o Hibernate gravar `NULL` explícito e sobrescrever o `DEFAULT` do banco.
4. **`DashboardCrescimentoController`** — os 3 endpoints (`parceiros-por-mes`,
   `empresas-por-mes`, `modulos-por-mes`) têm `@PreAuthorize("@tenantSecurity.isMaster()")`.
5. **`GenericGridScreen.deleteUrl`** — agora `final String Function(String)? deleteUrl` (não
   mais `required`); `_delete()` faz early-return se `null`; o ícone de excluir na `DataRow` só
   aparece se `widget.deleteUrl != null`. `LicencaScreen` usa `deleteUrl: null` corretamente
   (backend não expõe `DELETE`, ver Pitfall 2 do RESEARCH.md).
6. **Wiring final (`home_screen.dart`/`api_links.dart`)** — o tile "Contatos (demonstração)" e
   os getters `allContatos`/`createContato`/`updateContato`/`deleteContato` (apontando pro
   domínio errado `/api/contatos`, log de negociação de grãos) foram completamente removidos.
   `grep -rn "ApiLinks.allContatos\b|ApiLinks.createContato\b|ApiLinks.updateContato\b|ApiLinks.deleteContato\b" lib test`
   retorna vazio — sem uso órfão remanescente. 5 novos tiles adicionados (Licença, Contatos,
   Ordem de Serviço, Módulos Contratados [Catálogo+Atribuição], Dashboard de Crescimento).

## Débitos técnicos já conhecidos e aceitos (Threat Model do PLAN.md, disposição mantida)

Nenhum destes é um achado novo desta revisão — todos já estavam registrados como `accept` no
Threat Model do `PLAN.md` antes da implementação, e a implementação não alterou essa disposição:

- **T-03-01** — `PUT /api/licencas/{id}` sem `@PreAuthorize` no backend (pré-existente, fora do
  escopo desta fase corrigir; ação de alto impacto mas já restrita a quem acessa o admin panel
  MASTER).
- **T-03-02** — `POST /api/empresa-modulo` sem `@PreAuthorize`/validação de tenant (pré-existente,
  mesmo achado do `RESEARCH.md` Pitfall 3; recomendação de backend registrada, não bloqueante
  para esta fase Flutter).
- **T-03-06** — sem log de auditoria client-side para ações de Licença/Módulos (fora de escopo,
  sem requisito formal no `ROADMAP.md`).
- **Limitação de modelagem do gráfico "módulos novos por mês"** (reset de `dh_created_at` de
  TODO o conjunto a cada re-salvamento parcial, por ser DELETE+INSERT) — documentada de forma
  visível na própria tela do Dashboard de Crescimento (texto abaixo do gráfico de módulos,
  `dashboard_crescimento_screen.dart:65`), conforme exigido pela Task 07.2.

## Conclusão

Nenhum achado crítico ou importante. A implementação segue fielmente os 8 planos do PLAN.md,
os contratos assimétricos de backend foram tratados corretamente, a mitigação de threat
destrutiva (T-03-04) está implementada e testada, e o wiring final removeu completamente o
código morto/quebrado da demo da Fase 1. **Aprovado sem ressalvas.**
