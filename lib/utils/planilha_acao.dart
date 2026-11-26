import 'planilha_acrescentar.dart';
import 'planilha_formula.dart';

/// Marca de "esta acao recebe os valores digitados na planilha" (campo tabela do cadastro da acao).
const String kTabelaPlanilha = 'planilha';

/// Valor devolvido pela rotina: [linha] e' o numero da linha na planilha (1 = titulo).
class AlteracaoDeCelula {
  final int linha;
  final String coluna;
  final String valor;
  const AlteracaoDeCelula(this.linha, this.coluna, this.valor);
}

/// Linhas (numeros a partir de 2) como o servidor recebe: titulo da linha 1 -> valor calculado, mais "_linha".
/// [linha] nulo traz todas as linhas com dados.
List<Map<String, dynamic>> linhasParaAcao(Map<String, String> celulas, {int? linha}) {
  final calculo = PlanilhaCalculo(celulas);
  final porLinha = <int, Map<int, String>>{};
  for (final ref in celulas.keys) {
    final p = posicao(ref);
    if (p == null) continue;
    final texto = calculo.exibir(ref).trim();
    if (texto.isNotEmpty) (porLinha[p.$1] ??= {})[p.$2] = texto;
  }
  final titulos = porLinha[0] ?? const <int, String>{};
  final numeros = porLinha.keys.where((l) => l > 0 && (linha == null || l == linha - 1)).toList()..sort();
  final saida = <Map<String, dynamic>>[];
  for (final l in numeros) {
    final mapa = <String, dynamic>{'_linha': l + 1};
    for (final e in titulos.entries) {
      mapa[e.value] = porLinha[l]![e.key] ?? '';
    }
    saida.add(mapa);
  }
  return saida;
}

/// Codigos dos registros, lidos da coluna cujo titulo e' [colunaId] (aceita tambem "Código" quando for "id").
/// Devolve null quando a coluna nao existe.
List<String>? codigosDaColuna(List<Map<String, dynamic>> linhas, String colunaId) {
  if (linhas.isEmpty) return const [];
  final aceitos = {chaveDeTitulo(colunaId), if (colunaId.toLowerCase() == 'id') 'codigo'};
  String? titulo;
  for (final k in linhas.first.keys) {
    if (k != '_linha' && aceitos.contains(chaveDeTitulo(k))) {
      titulo = k;
      break;
    }
  }
  if (titulo == null) return null;
  return [
    for (final l in linhas)
      if ('${l[titulo]}'.isNotEmpty) '${l[titulo]}'
  ];
}

/// Aplica os valores da rotina (nunca como formula). Coluna inexistente e' criada no fim.
/// Devolve null se passar do limite de colunas.
Map<String, String>? aplicarAlteracoes(Map<String, String> celulas, List<AlteracaoDeCelula> alteracoes) {
  final saida = Map<String, String>.of(celulas);
  final calculo = PlanilhaCalculo(celulas);
  final colunas = <String, int>{};
  var ultima = -1;
  for (final ref in celulas.keys) {
    final p = posicao(ref);
    if (p == null) continue;
    if (p.$2 > ultima) ultima = p.$2;
    if (p.$1 == 0) colunas.putIfAbsent(chaveDeTitulo(calculo.exibir(ref)), () => p.$2);
  }
  for (final a in alteracoes) {
    var c = colunas[chaveDeTitulo(a.coluna)];
    if (c == null) {
      c = ++ultima;
      if (c >= kPlanilhaMaxColunas) return null;
      colunas[chaveDeTitulo(a.coluna)] = c;
      saida[endereco(0, c)] = celulaDeValor(a.coluna);
    }
    if (a.linha < 2 || a.linha > kPlanilhaMaxLinhas) continue;
    final ref = endereco(a.linha - 1, c);
    if (a.valor.isEmpty) {
      saida.remove(ref);
    } else {
      saida[ref] = celulaDeValor(a.valor);
    }
  }
  return saida;
}
