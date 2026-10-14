# FASE 4 — Painel do Dono como Central Multi-App

Data: 2026-10-14 | Agente: Claude (Sonnet 5.5) | Status: PLANEJAMENTO (sem codigo)

## 1. Visao

O `task_manager_admin_panel` deixa de ser "painel de licencas/modulos" e vira a
**torre de controle unica** de todos os apps do ecossistema, que compartilham o
mesmo backend (`AppAcademia`, Spring Boot) e o mesmo banco (PostgreSQL):

| App (pasta) | Publico | `LoginEnum` principal |
|---|---|---|
| `task_manager_flutter` | Escritorio Abraco + clientes | `APP_ABRACO` / `APP_CONTABILIDADE` |
| `task_manager_flutter_merged_final` | Multi-escritorios white-label | `APP_CONTABILIDADE` / `APP_ABRACO` |
| `task_manager_flutter_por_cliente` | Empresario direto (Conta Propria) | (definir — ver D1) |
| `task_manager_AppAcademiaV003` | Academia / Aluno / Personal | `APP_ACADEMIA`, `APP_ALUNO`, `APP_PERSONAL` |
| `task_manager_appDaniel` | Projeto separado | (definir — ver D1) |
| `task_manager_pdv_windows` | PDV Windows | (definir — ver D1) |
| Site Joao (Entusiasta Tributario) | Portal | `APP_SITE_JOAO` |

Meta final: o dono opera **tudo** daqui — usuarios, roles, logs de erro,
chamados, licencas, faturamento e metricas — **filtrado por app**, sem nunca
misturar dados entre apps.

## 2. Levantamento do estado atual (evidencias)

### 2.1 Painel (Flutter)
- 70 arquivos Dart. Telas existentes: Licenca, NFS-e admin, Contatos, Ordem de
  Servico, Modulos (catalogo/atribuicao/trial/termos), Dashboard de Crescimento,
  Logs do Sistema, e menu "Sistema" (Aplicativo, Permissoes, Editor de Telas,
  Teste de Endpoints, Query Builder, Sessoes, Jobs, Importacoes).
- `home_screen.dart` e uma lista de cards: **nao existe conceito de "app
  selecionado"**; nada e filtrado por app.
- `README.md` do painel e o template padrao do Flutter (nao documenta nada);
  a documentacao real esta em `.planning/` (ROADMAP + fases 01, 02, 02b, 03) e em
  `C:\App_Academia\task_manager_admin_panel_refatoracao.md` (testes ainda
  quebrados apos a refatoracao para `GenericGridWindowsScreen`).

### 2.2 Backend — o que ja separa por app
- `LoginEnum` (MASTER, APP_PERSONAL, APP_ACADEMIA, APP_NUTRICIONISTA, APP_ALUNO,
  APP_ABRACO, APP_CONTABILIDADE, APP_SITE_JOAO). `Login.tipoLogin` + `Login.aplicativo`
  (FK `id_aplicativo`).
- Entidade `Aplicativo` (tabela `aplicativo`: id, nome, observacao) referenciada
  por `Login`, `Empresa`, `Role` (`codApp`), `Academia`, `Personal`, `Comunicado`,
  `FileAttachment`, `Artigo`...
- `Licenca` ja e por app (`cod_app`, `nome_app`, `ativo`, vencimento).
- `TenantContext`/`TenantContextPopulator`: MASTER bypassa filtro de tenant.

### 2.3 Lacunas (o que impede a gestao por app)
1. **`LoginEnum` e `Aplicativo` sao dois conceitos paralelos.** Varios apps
   compartilham o mesmo `LoginEnum` (ex.: `APP_ALUNO`, `APP_ACADEMIA` e
   `APP_ABRACO` tem descricao "App Academia"), e `Conta Propria`, `appDaniel` e
   `PDV` nem tem valor no enum. Nao existe chave unica "de qual app veio".
2. **`sistema_log` nao tem app.** Campos: nivel, origem (30), mensagem, classeOuRota,
   usuario, empresaId, parceiroId, versaoApp, ambiente. `origem` e texto livre;
   nao da pra filtrar de forma confiavel "erros do App Aluno".
3. **`log_acesso` nao tem app nem empresa**; so usuario/acao/IP/dispositivo.
4. **`Chamado` nao tem app** (so empresa/parceiro/setor) — contagem por app so
   por inferencia via login de abertura.
5. **`Role`** tem `codApp -> Aplicativo` (bom) mas e `nullable`; roles sem app
   ficam "globais" sem regra clara. Nao ha tela de roles agrupada por app.
6. **`Login.tipoLogin` ja teve bug de default silencioso** para MASTER/ordinal
   (ver `LoginController` ~l.442/588) — qualquer gestao cross-app depende de
   eliminar esse default.
7. Dashboards atuais (crescimento) sao globais, sem recorte por app.

## 3. Decisoes que precisam do dono (bloqueiam a Fase 4.1)

- **D1 — Chave de app.** Recomendado: usar a tabela `aplicativo` como
  fonte unica (uma linha por app, com `codigo` estavel tipo `ABRACO`, `ALUNO`,
  `PERSONAL`, `CONTA_PROPRIA`, `PDV`, `DANIEL`, `SITE_JOAO`) e manter o
  `LoginEnum` apenas como perfil de acesso. Alternativa: estender o enum
  (mais rapido, mas continua misturando "app" com "tipo de usuario").
- **D2 — Apps a incluir na v1:** todos os 7 ou so os que ja estao em producao?
  (`appDaniel` esta marcado como "vida propria" no CLAUDE.md — confirmar se
  entra na gestao centralizada.)
- **D3 — Isolamento:** o MASTER do painel enxerga todos os apps; deve existir
  um perfil "gestor de app" (ve so 1 app)? Recomendado sim, para suporte.

## 4. Fases propostas

### 4.1 Fundacao: identidade de app (backend + painel)  — PRIORIDADE 1
- Migration Flyway nova (numero seguinte a mais alta; nunca editar aplicada):
  `aplicativo.codigo` unico + seed dos apps; `sistema_log.app_id`,
  `log_acesso.app_id`, `chamado.app_id` (nullable + backfill por login/empresa).
- Backfill idempotente: `login.tipoLogin`/`id_aplicativo` -> `app_id`.
- Remover default silencioso para MASTER no cadastro de login (exigir app).
- Filtro `appId` opcional nos endpoints `/api/sistema-logs`, `/api/chamado`,
  `/api/login`, `/api/role`, `/api/licenca`, sempre respeitando tenant.
- Testes JUnit: usuario do App A nunca aparece em listagem filtrada pelo App B;
  nao-MASTER nao consegue passar `appId` de outro app (anti-IDOR).
- Cada app cliente passa a enviar seu `appCodigo` no login e nos logs
  (`AppLogger`) — replicar nos 3 Flutter (tríade) + V003 sem tocar layout.

### 4.2 Seletor global de App no painel
- `AppContext` no painel (app selecionado: "Todos" ou um app) persistido em
  `SharedPreferences`; chip/dropdown no AppBar; toda grid/endpoint passa
  `appId` automaticamente.
- Reaproveitar `SearchableDropdownField`; **sem preencher filtros de grid
  automaticamente com dados do usuario logado** (regra de filtros visuais) — o
  seletor de app e escolha explicita do dono.

### 4.3 Roles por app
- Tela "Roles" agrupada por app (tabs ou seletor), CRUD de role com `app`
  obrigatorio; copiar roles de um app para outro (template).
- Matriz Role x Tela por app (reusar `role_permissao_screen`), lembrando a
  regra: toda tela nova entra em `PermissionService._menuIdToTelaNome`.
- Relatorio "roles sem app" para saneamento antes de tornar obrigatorio.

### 4.4 Logs de erro por app
- Reaproveitar `sistema_logs_screen.dart` com filtros: app, nivel, ambiente,
  versaoApp, periodo, empresa/parceiro; agrupamento por `classeOuRota`+mensagem
  (fingerprint) para mostrar **erros distintos** e nao 10 mil linhas iguais.
- Indicadores por app: erros/hora, taxa de erro, top 10 rotas com falha,
  versao do app mais problematica.
- Alerta: pico de erros em um app dispara notificacao ao dono.
- Retencao: job que arquiva/expurga logs antigos (tabela cresce rapido).

### 4.5 Dashboards e graficos de progressao (por app e consolidado)
Metricas (cada uma com recorte por app e periodo):
- Usuarios: total, ativos 7/30 dias (DAU/MAU), novos por semana, churn.
- Cadastros-chave por app: **personais, alunos, academias** (V003); **escritorios,
  parceiros/clientes** (Abraco/merged); **empresas/contatos** (Conta Propria).
- Chamados: abertos/fechados, tempo medio de resposta e de resolucao, backlog
  por app e por prioridade, % reabertos.
- Qualidade: erros por 1.000 acessos, versao instalada x ultima versao.
- Comercial: trials solicitados/aprovados/convertidos, licencas a vencer em 30
  dias, receita recorrente (MRR) por app, inadimplencia.
- Fiscal (apps contabeis): notas emitidas, rejeicoes SEFAZ por app.
- Uso: telas/modulos mais usados, horario de pico.
Graficos: linha (progressao semanal/mensal), barras empilhadas por app, funil
de trial, heatmap de uso. Backend: endpoint agregador unico
`/api/admin/metricas?appId=&de=&ate=` (queries agregadas, nunca N+1) com cache
curto.

### 4.6 Central de Chamados unificada
- Caixa unica com coluna "App", SLA por app/prioridade, atribuicao, status e
  historico; contador por app no card inicial.
- Reusar `ChamadoAtendimento/Atribuicao/Escalonamento` existentes.

### 4.7 Gestao de usuarios e acesso cross-app
- Tela "Usuarios" cross-app: busca por email/CPF, mostra em quais apps o
  usuario existe, reset de senha, bloqueio, forcar logout (sessoes).
- Trilha de auditoria de acoes do MASTER (quem mudou role/licenca/modulo).

### 4.8 Saude e operacao
- Painel de saude: status do backend/Railway, banco, filas/jobs, ultima
  versao publicada de cada app, `server_status_service` ja existente.
- Teste de Endpoints (System Tests) por escopo de app (regra: endpoint novo =
  fluxo real nessa tela, em todas as plataformas).

### 4.9 Divida pendente do painel (fazer antes/junto da 4.2)
- Revisar testes quebrados pela refatoracao (mocks de `GenericGridScreen`).
- README real do painel; paridade Web/Windows/Mobile das telas novas.
- Mobile do painel: layout vertical, alvos 44px, dashboard em cards.

## 5. Ideias extras de gestao (para decidir depois)
1. **Feature flags por app** (ligar/desligar modulo sem deploy).
2. **Comunicados/push por app** (aviso de manutencao, novidade) — ja ha
   entidade `Comunicado`.
3. **Painel de custos** (infra Railway / e-mail / SEFAZ) por app -> margem.
4. **Health score do cliente** (uso + chamados + atraso) para antecipar churn.
5. **Controle de versao minima por app** (forcar atualizacao de app velho).
6. **Backups/restore e LGPD**: exportar/anonimizar dados de um usuario por app.
7. **Onboarding guiado** de novo cliente (Fase 2b) com checklist por app.
8. **Modo suporte "ver como"** (impersonate com auditoria) para reproduzir bug.
9. **Relatorio mensal automatico** por e-mail/WhatsApp ao dono (resumo por app).

## 6. Riscos
- Backfill de `app_id` em dados antigos pode classificar errado (validar por
  amostra antes de tornar NOT NULL).
- Mistura de usuarios: qualquer endpoint novo sem filtro de app/tenant vira
  vazamento; exigir teste de isolamento em todo endpoint (JUnit + HTTP real).
- Postgres real vs H2: validar migrations/queries agregadas em Postgres.
- Replicacao na tríade + V003 sem sobrescrever layouts; coordenar com as outras
  IAs (Codex/Antigravity) para nao perder implementacoes — commits pequenos.

## 7. Ordem recomendada
4.1 -> 4.2 -> 4.4 (logs) -> 4.3 (roles) -> 4.5 (dashboards) -> 4.6/4.7 -> 4.8.
Logs e roles dao valor imediato com baixo risco; dashboards dependem do
`app_id` estar populado.

## 8. Criterios de pronto da Fase 4.1
- Todo log/chamado/login novo grava `app_id` correto.
- Teste automatizado prova isolamento entre dois apps.
- Painel filtra logs por app no seletor global.
- `bugs.md` atualizado (data, pedido, causa, arquivos, testes, status, branch,
  hash, IA/agente).
