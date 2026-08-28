/// Normalizacao de nomes de tela para a matriz de Permissoes (SIS-06).
///
/// Portado VERBATIM (mesma logica, sem reescrever) de
/// `task_manager_flutter/lib/web/screens/role_permissao_screen.dart` --
/// funcoes `_normalizeTelaNome`/`toBackendTelaNome`. Corrige uma regressao
/// documentada nos cards #460/#471/#493 do cliente: `menu_config.dart` usa
/// `snake_case` para o id dos itens de menu (`'nfe_entrada'`), mas
/// `role_permissao.tela_nome` no backend usa `camelCase`
/// (`'nfeEntrada'`). Sem esta normalizacao/conversao, os checkboxes da
/// matriz de permissoes nao batem com os registros salvos. Ver
/// RESEARCH.md/PLAN.md da Fase 2 (Item 6 / Task 10.1) -- nao reinventar.
library;

/// Normaliza um nome de tela para comparacao independente de convencao
/// (lowercase + remove `_`). Necessario porque `role_permissao.tela_nome`
/// usa multiplas convencoes historicamente no banco.
String normalizeTelaNome(String s) => s.toLowerCase().replaceAll('_', '');

/// Converte nomes de tela de snake_case para camelCase (formato backend).
/// Exemplo: `'nfe_entrada'` -> `'nfeEntrada'`, `'chat'` -> `'chat'`.
String toBackendTelaNome(String screenName) {
  if (!screenName.contains('_')) {
    return screenName; // Ja esta em camelCase ou e simples.
  }

  final parts = screenName.split('_');
  final buffer = StringBuffer(parts[0]); // Primeira palavra em minuscula.

  for (int i = 1; i < parts.length; i++) {
    final part = parts[i];
    if (part.isNotEmpty) {
      buffer.write(part[0].toUpperCase() + part.substring(1));
    }
  }

  return buffer.toString();
}
