/// Parser CSV puro (RFC4180-ish), sem estado, sem dependencia de widget.
///
/// Portado de `_parseCsv`/`_separatorFor`/`_splitCsvLine`
/// (`task_manager_flutter/lib/web/screens/configuracoes_sistema_screen.dart`)
/// como funcao top-level reutilizavel por P07 (Importacao Contas) e P08a
/// (Importacao Cadastros) — ver Task 01b.1 do PLAN.md da Fase 2.
///
/// Separador (`;` ou `,`) e' auto-detectado por contagem de ocorrencias na
/// 1a linha (favorece `;`, padrao PT-BR, em caso de empate).
library;

/// Converte o conteudo bruto de um arquivo CSV em uma matriz de linhas x
/// colunas. A primeira linha do retorno corresponde ao cabecalho (nao e'
/// removida automaticamente — quem consome decide se usa como header).
///
/// Linhas totalmente vazias (inclusive a ultima, se o arquivo terminar com
/// quebra de linha) sao ignoradas. Celulas entre aspas duplas podem conter
/// o separador sem quebrar em colunas extras; `""` dentro de uma celula
/// entre aspas vira uma aspas literal.
List<List<String>> parseCsv(String content) {
  final linhas = content
      .split(RegExp(r'\r?\n'))
      .where((l) => l.trim().isNotEmpty)
      .toList();

  if (linhas.isEmpty) return <List<String>>[];

  final sep = _separatorFor(linhas.first);
  return linhas.map((linha) => _splitCsvLine(linha, sep)).toList();
}

String _separatorFor(String line) {
  final semicolon = ';'.allMatches(line).length;
  final comma = ','.allMatches(line).length;
  return semicolon >= comma ? ';' : ',';
}

List<String> _splitCsvLine(String line, String sep) {
  final out = <String>[];
  final buffer = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        buffer.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (char == sep && !quoted) {
      out.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  out.add(buffer.toString());
  return out;
}
