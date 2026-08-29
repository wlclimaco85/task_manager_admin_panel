---
phase: 02-menu-sistema
reviewed: 2026-08-29T01:57:24Z
depth: standard
files_reviewed: 29
files_reviewed_list:
  - lib/config/api_links.dart
  - lib/models/cadastro_empresa_models.dart
  - lib/models/role_permission_catalog.dart
  - lib/screens/home_screen.dart
  - lib/screens/sistema/aplicativo_screen.dart
  - lib/screens/sistema/cadastro_empresa_wizard_screen.dart
  - lib/screens/sistema/configuracoes_admin_screen.dart
  - lib/screens/sistema/configuracoes_sistema/acoes_screen.dart
  - lib/screens/sistema/configuracoes_sistema/configuracoes_sistema_screen.dart
  - lib/screens/sistema/configuracoes_sistema/importacao_cadastros_screen.dart
  - lib/screens/sistema/configuracoes_sistema/importacao_contas_screen.dart
  - lib/screens/sistema/configuracoes_sistema/jobs_screen.dart
  - lib/screens/sistema/endpoint_tester_screen.dart
  - lib/screens/sistema/query_builder_screen.dart
  - lib/screens/sistema/role_permissao_screen.dart
  - lib/screens/sistema/sistema_menu_screen.dart
  - lib/screens/sistema/tela_editor_screen.dart
  - lib/screens/sistema/tela_field_editor_screen.dart
  - lib/services/cadastro_empresa_service.dart
  - lib/services/importacao_cadastros_service.dart
  - lib/services/query_builder_service.dart
  - lib/utils/csv_parser.dart
  - lib/utils/role_permissao_normalizacao.dart
  - lib/utils/tenant_context.dart
  - lib/services/network_caller.dart
  - lib/widgets/admin/admin_action_card.dart
  - lib/widgets/generic/generic_grid_screen.dart
  - pubspec.yaml
  - test/screens/sistema/configuracoes_sistema/configuracoes_sistema_screen_test.dart
findings:
  critical: 0
  warning: 4
  info: 3
  total: 7
status: issues_found
---

# Phase 2: Code Review Report — Migração do menu "Sistema"

**Reviewed:** 2026-08-29T01:57:24Z
**Depth:** standard (full diff `ec32a53..HEAD`, 42 commits, 53 files, ~12.9k linhas; leitura
completa dos arquivos de maior risco listados acima + amostragem dos demais via `flutter
analyze`/`flutter test`)
**Files Reviewed:** 29 arquivos lib/ lidos por completo (dos 53 do diff; os 24 restantes são
arquivos de teste, `pubspec.lock`, `ROADMAP.md`/`RESEARCH.md`/`PLAN.md` já usados como
contexto, e telas de menor risco cobertas indiretamente pelos testes/analyze)
**Status:** issues_found (nenhum achado crítico; 4 warnings, 3 info)

## Verificação executada nesta rodada

- `flutter analyze`: **2 issues** (info, `deprecated_member_use` em `onReorder` de
  `ReorderableListView` — `lib/screens/sistema/tela_field_editor_screen.dart:202` e no teste
  correspondente). Zero erros, zero warnings — a claim "0 erros/warnings" do PLAN.md
  (Task 13.3) é literalmente verdadeira, mas "flutter analyze limpo" no sentido amplo não é
  (ver IN-01).
- `flutter test`: **126/126 passando** (confirma a claim do PLAN.md).

## Summary

Revisão adversarial do diff completo da Fase 2 (migração dos 8 itens do menu "Sistema").
Achados prévios de risco conhecido (ações destrutivas, Query Builder, usos de `http` cru,
`embedded` do grid, rollback LIFO, normalização de nome de tela) foram todos **verificados e
confirmados corretos** — nenhum deles vira achado nesta rodada:

- As 3 confirmações "digite X" (RESET/APAGAR) e a confirmação simples (Fix DB) **bloqueiam
  de verdade** o botão de confirmar até o texto bater exatamente, e o teste de widget prova
  que nenhuma chamada de rede dispara antes da confirmação (`acoes_screen_test.dart`).
- Query Builder: o texto de erro do cliente ("Apenas SELECT/WITH são permitidos") não afirma
  nem sugere ser a única camada de proteção; a defesa real já está documentada como
  server-side (`@PreAuthorize` + regex) tanto no comentário de classe quanto no comportamento.
- Os 2 usos de `http` cru (`importacao_contas_screen.dart` multipart,
  `role_permissao_screen.dart` batch) aplicam `TenantContext.headers`/`jsonHeaders`
  corretamente — incluem `Authorization: Bearer` e `X-Tenant-ID`, sem brecha de bypass de
  autenticação/tenant.
- `GenericGridScreen(embedded: false)` (default) permanece byte-a-byte equivalente ao
  comportamento da Fase 1 — `embedded` é aditivo, sem regressão para os usos existentes.
- `CadastroEmpresaService`: rollback LIFO percorre `_createdEntities` em ordem reversa e não
  para em falha individual de delete, coberto por teste dedicado
  (`rollback nao interrompe em falha de remocao individual`).
- `role_permissao_normalizacao.dart` (`normalizeTelaNome`/`toBackendTelaNome`) é cópia
  verbatim confirmada linha a linha contra
  `task_manager_flutter/lib/web/screens/role_permissao_screen.dart` — a regressão histórica
  dos cards #460/#471/#493 não foi reintroduzida.

Os achados abaixo são de bugs/gaps reais encontrados nesta rodada, não repetições do que já
era esperado ser verificado.

## Warnings

### WR-01: `ImportacaoContasScreen` duplica `Scaffold`/`AppBar` quando embutida na aba "Config. Sistema"

**File:** `lib/screens/sistema/configuracoes_sistema/importacao_contas_screen.dart:420-421`
**Issue:** `ImportacaoContasScreen.build()` retorna um `Scaffold` completo com `AppBar` próprio
(`title: 'Importação CSV — Contas'`). Essa tela só é instanciada em um único lugar do código
(`lib/screens/sistema/configuracoes_sistema/configuracoes_sistema_screen.dart:65`), como filha
direta do `TabBarView` de `ConfiguracoesSistemaScreen` — que já tem seu próprio
`Scaffold`/`AppBar`/`TabBar`. O resultado é um `AppBar` aninhado renderizado dentro da área de
conteúdo da aba "Importação Contas": exatamente o "anti-padrão de arquivo monolítico"/"chrome
duplicado" que a Task 01.4 do próprio PLAN.md desta fase foi criada para eliminar (motivo pelo
qual `GenericGridScreen` ganhou o parâmetro `embedded`) — mas o padrão não foi aplicado aqui.
`ImportacaoCadastrosScreen` (a outra aba do mesmo container) já foi implementada sem
`Scaffold` próprio (embeddable), confirmando que o padrão correto era conhecido e só não foi
seguido neste arquivo.
O teste `configuracoes_sistema_screen_test.dart` (`troca de aba funciona`) só verifica que o
texto "Importação Contas" aparece após trocar de aba — não captura a duplicação de chrome
porque não faz `find.byType(AppBar)` com contagem.
**Fix:** Seguir o mesmo contrato de `GenericGridScreen`/`ImportacaoCadastrosScreen`: remover o
`Scaffold`/`AppBar` de `ImportacaoContasScreen.build()` e devolver só o `SingleChildScrollView`
atual (ou adicionar um parâmetro `embedded` como em `GenericGridScreen`, condicionando o
`Scaffold` a `embedded == false` para não quebrar outros usos futuros). Ajustar/estender o
teste para `expect(find.byType(AppBar), findsOneWidget)` dentro do container, prevenindo
regressão futura.

### WR-02: `TelaFieldEditorScreen` — Editor de Telas ainda não persiste ponta-a-ponta (backend sem os 2 endpoints usados)

**File:** `lib/screens/sistema/tela_field_editor_screen.dart:18-25` (comentário de classe, já
autodeclarado pelos autores)
**Issue:** O próprio código documenta que `PUT /api/telas/{telaId}/fields/reorder` e
`PUT /api/telas/{telaId}/fields/{fieldId}` (usados por `_reordenar`/`_salvarCampo`) **ainda não
existem no backend** (`TelaController` só expõe `GET /api/telas` e `GET /api/telas/{nome}`).
Isso significa que a "Verdade observável" #6 do PLAN.md ("Editor de Telas: lista telas reais,
edita/reordena campos de uma tela e persiste via PUT") **não é atendida hoje** — reordenar ou
salvar um campo sempre retorna erro de rede (404), exibido ao usuário via `SnackBar`, sem
travar a UI, mas sem nenhuma persistência real. Isso não é um bug de código nesta fase (o
contrato client-side está correto e testado com o `NetworkCaller` mockado), mas é um gap
funcional relevante que deveria bloquear a alegação de "os 8 itens acessíveis... sem
placeholder restante" do Done da Task 13.3, já que "Editor de Telas" hoje é, na prática, um
placeholder funcional (lista funciona, edição não persiste).
**Fix:** Não é fix de código Flutter — reportar ao dono do backend (`AppAcademia`) para
implementar os 2 endpoints antes de considerar SIS-05 pronto ponta-a-ponta; ou, no mínimo,
registrar esse débito explicitamente no relatório de fechamento da fase entregue ao PO (não
apenas em comentário de código), já que muda o veredito de "8/8 itens funcionais" para "7/8 +
1 parcial".

### WR-03: `ImportacaoCadastrosService._buscarExistente`/`_get` engolem exceção de rede e tratam como "não existe"

**File:** `lib/services/importacao_cadastros_service.dart:858-866` (`_get`) usado por
`_buscarExistente` (linha 886) e `_listarParceirosEmpresa`/`_buscarServicoContratadoExistente`
**Issue:** `_get()` captura qualquer exceção (timeout, erro de parsing, DNS, etc.) e retorna
`null`. `_buscarExistente()` trata `body == null` da mesma forma que "nenhum resultado
encontrado" (retorna `null`, ou seja "não existe registro com essa chave"). Como consequência,
uma falha transitória de rede durante a checagem de dedup de uma linha do CSV (chamada de GET
antes do create-vs-update) faz o serviço concluir erroneamente que o registro não existe e
seguir para `POST` (criação), mesmo quando o registro já existe — criando um duplicado em vez
de atualizar, silenciosamente (sem erro reportado na linha, porque o create pode ter sucesso).
Isso é uma classe de bug real de dedup em processamento de CSV em lote (a garantia
"create-vs-update" do PLAN.md/RESEARCH.md fica quebrada sob falha de rede intermitente).
**Fix:** Diferenciar "não encontrado" (200 com lista vazia/sem match) de "falha ao consultar"
(exceção/erro HTTP) em `_get`/`_buscarExistente`: propagar a falha como
`ImportacaoCadastroException` (linha marcada como `erro`, não `sucesso`) em vez de
silenciosamente prosseguir como se o registro não existisse. Exemplo mínimo: trocar o
`catch (_) { return null; }` de `_get` por um catch que sinaliza falha distinta de "lista
vazia", e propagar essa distinção até `_buscarExistente`.

### WR-04: Multipart request de `ImportacaoContasScreen` não trata 401 (sem logout automático)

**File:** `lib/screens/sistema/configuracoes_sistema/importacao_contas_screen.dart:336-349`
(`_multipartPost`)
**Issue:** `_multipartPost` usa `http.MultipartRequest` diretamente com
`TenantContext.headers` (correto para tenant/auth), mas não chama nenhum equivalente ao
`NetworkCaller._handleUnauthorized` — se o token expirar durante uma importação de CSV, o
usuário recebe apenas um card de erro genérico ("HTTP 401: ...") em vez do fluxo de
logout/redirecionamento para login que o resto do app aplica em qualquer outro 401 fora de
rota pública. Não é falha de segurança (o tenant/auth continuam corretos, a chamada
simplesmente falha), mas é uma inconsistência de UX que os outros dois pontos de `http` cru
desta fase (`role_permissao_screen.dart` batch) também têm — nenhum dos dois plugs no
`onUnauthorized` do `NetworkCaller` principal da tela.
**Fix:** Se o app já usa `onUnauthorized` em algum lugar central (verificar
`main.dart`/`NetworkCaller()` default), replicar a mesma checagem de status 401 após o
`http.Response.fromStream(streamed)` nos dois pontos de `http` cru, ou aceitar formalmente o
gap como débito documentado (comentário already existing não menciona esse ponto
especificamente).

## Info

### IN-01: `flutter analyze` não está 100% limpo — 2 issues de `deprecated_member_use`

**File:** `lib/screens/sistema/tela_field_editor_screen.dart:202`,
`test/screens/sistema/tela_field_editor_screen_test.dart:100`
**Issue:** `ReorderableListView.builder(..., onReorder: _reordenar)` usa o callback `onReorder`,
deprecated desde Flutter 3.41 em favor de `onReorderItem`. `flutter analyze` reporta 2 `info`
(não error/warning) — a claim "0 erros/warnings" da Task 13.3 é tecnicamente verdadeira, mas
vale registrar para não acumular dívida de depreciação silenciosamente.
**Fix:** Migrar para `onReorderItem` quando a versão do Flutter usada pelo projeto expuser o
callback substituto de forma estável (checar changelog antes de migrar, pois o comportamento
de ajuste de índice é diferente).

### IN-02: `CadastroEmpresaService._extractId` retornando `null` após POST 2xx deixa entidade órfã sem rastro para rollback

**File:** `lib/services/cadastro_empresa_service.dart:437-448` (`_post`) e `453-474`
(`_extractId`)
**Issue:** Se o backend responder 2xx mas em um formato de corpo não coberto pelos 4 formatos
conhecidos (`body.id`, `body.data.id`, `body.data.parceiro.id`, `body.data.login.id`),
`_extractId` retorna `null`, `_post` trata como falha e lança `CadastroException` — mas a
entidade **foi de fato criada no backend** e nunca é adicionada a `_createdEntities` (só é
adicionada quando `id != null`), então o rollback LIFO não tem como localizá-la e excluí-la.
Resultado: uma empresa/parceiro/login órfão no banco, sem qualquer id conhecido pelo cliente
para limpeza manual. Este é um risco herdado da heurística original (mesmo comportamento do
arquivo-fonte, não uma regressão introduzida nesta fase), mas vale registrar explicitamente
porque é justamente o cenário que a pergunta de revisão sobre "rollback LIFO... não deixa
estado inconsistente" pede para confirmar — e a resposta é: não deixa inconsistência **na lista
local do serviço**, mas pode deixar no backend quando o formato de resposta foge do esperado.
**Fix:** Não é bloqueio para esta fase (comportamento idêntico ao original, path de baixa
probabilidade). Se quiser fechar o gap: logar o `response.body` bruto no `LogEntry` de falha de
extração de ID para permitir limpeza manual rápida via Query Builder/backend, já que o cliente
não tem como automatizar o rollback nesse caso.

### IN-03: `ApiLinks.telaByNome`/`queryBuilderColunas` interpolam parâmetros sem `Uri.encodeComponent`, diferente do padrão já usado em `updateRolePermissao`

**File:** `lib/config/api_links.dart:176` (`telaByNome`), `198-199`
(`queryBuilderColunas`) vs. `185-186` (`updateRolePermissao`, que já encoda o telaNome no
call-site)
**Issue:** `role_permissao_screen.dart` aplica `Uri.encodeComponent(telaNome)` antes de montar
a URL (CR-05 portado, comentário explícito na linha 127-131), mas `telaByNome`/
`queryBuilderColunas` interpolam `nome`/`schema`/`tabela` diretamente na URL sem encoding.
Como os valores hoje vêm de listas já retornadas pelo próprio backend (nomes de tela/schema/
tabela reais, não texto livre digitado pelo usuário), o risco prático é baixo, mas é uma
inconsistência de padrão dentro do mesmo arquivo que pode gerar bug real se algum nome de tela
algum dia contiver espaço ou caractere especial.
**Fix:** Por consistência e defesa preventiva, aplicar `Uri.encodeComponent` dentro dos
próprios getters (`telaByNome`, `queryBuilderColunas`) em vez de depender do call-site lembrar
de fazer isso — reduz risco de esquecimento em usos futuros.

---

## Veredito

**Aprovado com ressalvas.**

Nenhum achado crítico (bug de segurança, perda de dados, ou quebra funcional generalizada).
Os pontos de maior risco levantados no threat model da fase (ações destrutivas, Query Builder,
`http` cru, rollback LIFO, normalização de nome de tela) foram todos verificados e estão
corretos. Os 4 warnings são reais e acionáveis, mas nenhum bloqueia o merge por si só:

- **WR-01** (AppBar duplicado em "Importação Contas") é o mais visível — deveria ser corrigido
  antes de considerar a fase "visualmente pronta", mas não quebra funcionalidade.
- **WR-02** (Editor de Telas sem persistência real) é o mais importante para gestão de
  expectativa — recomendo garantir que o relatório de fechamento da fase para o PO deixe
  explícito que SIS-05 está parcialmente funcional (lista sim, edição/reorder não, por
  dependência de backend), não "8/8 completo".
- **WR-03** (dedup silencioso em falha de rede) é o de maior risco de dado incorreto em
  produção real (duplicação em importação em lote) — recomendo corrigir antes do primeiro uso
  real da Importação de Cadastros com volume.
- **WR-04** é cosmético/UX.

`flutter analyze` (0 erros/warnings, 2 infos) e `flutter test` (126/126) confirmados
localmente nesta rodada, batendo com a claim do PLAN.md.

---

_Reviewed: 2026-08-29T01:57:24Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
