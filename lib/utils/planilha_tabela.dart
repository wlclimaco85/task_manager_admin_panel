import 'planilha_formula.dart';

/// Planilha lida como tabela: a linha 1 tem os titulos das colunas e as demais sao os registros, ja calculados.
class TabelaDaPlanilha {
  final List<String> colunas;
  final List<List<String>> linhas;

  /// Colunas (A, B...) que tem dados mas nenhum titulo na linha 1: ficam fora da tela.
  final List<String> ignoradas;

  /// Celulas com formula que nao calculou (#ERRO, #DIV/0!...): a tela nao deve ser criada com elas.
  final List<String> comErro;

  const TabelaDaPlanilha(this.colunas, this.linhas, this.ignoradas, this.comErro);
}

TabelaDaPlanilha tabelaDaPlanilha(Map<String, String> celulas) {
  final calculo = PlanilhaCalculo(celulas);
  final porLinha = <int, Map<int, String>>{};
  final comErro = <String>[];
  for (final ref in celulas.keys) {
    final p = posicao(ref);
    if (p == null) continue;
    final texto = calculo.exibir(ref).trim();
    if (celulas[ref]!.startsWith('=') && texto.startsWith('#')) comErro.add(ref);
    if (texto.isNotEmpty) (porLinha[p.$1] ??= {})[p.$2] = texto;
  }
  final titulos = porLinha[0] ?? const <int, String>{};
  final indices = titulos.keys.toList()..sort();
  final linhas = <List<String>>[];
  final semTitulo = <int>{};
  for (final l in porLinha.keys.where((l) => l > 0).toList()..sort()) {
    semTitulo.addAll(porLinha[l]!.keys.where((c) => !titulos.containsKey(c)));
    final linha = [for (final c in indices) porLinha[l]![c] ?? ''];
    if (linha.any((v) => v.isNotEmpty)) linhas.add(linha);
  }
  return TabelaDaPlanilha(
    [for (final c in indices) titulos[c]!],
    linhas,
    [for (final c in semTitulo.toList()..sort()) nomeColuna(c)],
    comErro..sort(),
  );
}
