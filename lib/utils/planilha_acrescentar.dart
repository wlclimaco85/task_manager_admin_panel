import 'planilha_formula.dart';
import 'planilha_tabela.dart';

/// O que fazer com a linha importada cuja chave ja existe na planilha.
enum LinhaRepetida { ignorar, atualizar }

class ResultadoAcrescentar {
  /// Planilha pronta (a original nao e' alterada).
  final Map<String, String> celulas;
  final int novas;
  final int atualizadas;
  final int ignoradas;

  /// Titulos do arquivo que nao existiam e viraram colunas no fim.
  final List<String> colunasCriadas;

  const ResultadoAcrescentar(this.celulas, this.novas, this.atualizadas, this.ignoradas, this.colunasCriadas);
}

class AcrescentarException implements Exception {
  final String mensagem;
  const AcrescentarException(this.mensagem);
  @override
  String toString() => mensagem;
}

const _comAcento = 'áàâãäéèêëíìîïóòôõöúùûüç';
const _semAcento = 'aaaaaeeeeiiiiooooouuuuc';

/// "CNPJ " e "cnpj" sao a mesma coluna; "Código" e "codigo" tambem.
String chaveDeTitulo(String s) {
  var t = s.trim().toLowerCase();
  for (var i = 0; i < _comAcento.length; i++) {
    t = t.replaceAll(_comAcento[i], _semAcento[i]);
  }
  return t.replaceAll(RegExp(r'\s+'), ' ');
}

/// Documento com ou sem pontuacao e' o mesmo registro ("12.345.678/0001-90" = "12345678000190").
String chaveDeValor(String s) {
  final t = s.trim();
  if (RegExp(r'^[\d.\-/ ]+$').hasMatch(t)) {
    final digitos = t.replaceAll(RegExp(r'\D'), '');
    if (digitos.length >= 8) return digitos;
  }
  return chaveDeTitulo(t);
}

/// Junta as linhas de [arquivo] ao fim de [atual], casando as colunas pelo titulo da linha 1.
/// Com [colunaChave], a linha cuja chave ja existe segue [repetida]; sem chave, todas sao acrescentadas.
/// Do arquivo entram os VALORES calculados (uma formula movida de linha apontaria para a celula errada).
ResultadoAcrescentar acrescentarLinhas(
  Map<String, String> atual,
  Map<String, String> arquivo, {
  String? colunaChave,
  LinhaRepetida repetida = LinhaRepetida.ignorar,
}) {
  final novo = tabelaDaPlanilha(arquivo);
  if (novo.colunas.isEmpty) {
    throw const AcrescentarException('O arquivo precisa ter os títulos das colunas na linha 1.');
  }
  if (novo.comErro.isNotEmpty) {
    throw AcrescentarException('O arquivo tem fórmulas com erro nas células: ${novo.comErro.take(10).join(', ')}.');
  }

  // nada do arquivo pode sumir em silencio
  if (novo.ignoradas.isNotEmpty) {
    throw AcrescentarException(
        'O arquivo tem dados em colunas sem título na linha 1: ${novo.ignoradas.join(', ')}. Dê um título a elas.');
  }
  final titulosDoArquivo = <String>{};
  for (final titulo in novo.colunas) {
    if (!titulosDoArquivo.add(chaveDeTitulo(titulo))) {
      throw AcrescentarException('O arquivo tem mais de uma coluna chamada "$titulo". Renomeie uma delas.');
    }
  }

  final calculo = PlanilhaCalculo(atual);
  final colunas = <String, int>{};
  var ultimaColuna = -1;
  var ultimaLinha = 0;
  for (final e in atual.entries) {
    final p = posicao(e.key);
    if (p == null || e.value.trim().isEmpty) continue;
    if (p.$2 > ultimaColuna) ultimaColuna = p.$2;
    if (p.$1 > ultimaLinha) ultimaLinha = p.$1;
    if (p.$1 == 0) colunas.putIfAbsent(chaveDeTitulo(calculo.exibir(e.key)), () => p.$2);
  }
  if (colunas.isEmpty) {
    throw const AcrescentarException('A planilha atual precisa ter os títulos das colunas na linha 1.');
  }

  final saida = Map<String, String>.of(atual);
  final criadas = <String>[];
  final destino = <int>[];
  for (final titulo in novo.colunas) {
    var c = colunas[chaveDeTitulo(titulo)];
    if (c == null) {
      c = ++ultimaColuna;
      if (c >= kPlanilhaMaxColunas) {
        throw const AcrescentarException('Os dados passam do limite de $kPlanilhaMaxColunas colunas.');
      }
      colunas[chaveDeTitulo(titulo)] = c;
      saida[endereco(0, c)] = celulaDeValor(titulo);
      criadas.add(titulo);
    }
    destino.add(c);
  }

  var indiceChave = -1;
  final linhaDaChave = <String, int>{};
  if (colunaChave != null) {
    indiceChave = novo.colunas.indexWhere((t) => chaveDeTitulo(t) == chaveDeTitulo(colunaChave));
    if (indiceChave < 0 || criadas.contains(novo.colunas[indiceChave])) {
      throw AcrescentarException('A coluna "$colunaChave" precisa existir na planilha e no arquivo.');
    }
    final c = destino[indiceChave];
    for (var l = 1; l <= ultimaLinha; l++) {
      final v = calculo.exibir(endereco(l, c)).trim();
      if (v.isNotEmpty) linhaDaChave.putIfAbsent(chaveDeValor(v), () => l);
    }
  }

  var novas = 0, atualizadas = 0, ignoradas = 0;
  for (final linha in novo.linhas) {
    final chave = indiceChave < 0 || linha[indiceChave].isEmpty ? null : chaveDeValor(linha[indiceChave]);
    var alvo = chave == null ? null : linhaDaChave[chave];
    if (alvo != null) {
      if (repetida == LinhaRepetida.ignorar) {
        ignoradas++;
        continue;
      }
      atualizadas++;
    } else {
      alvo = ++ultimaLinha;
      if (alvo >= kPlanilhaMaxLinhas) {
        throw const AcrescentarException('Os dados passam do limite de $kPlanilhaMaxLinhas linhas.');
      }
      if (chave != null) linhaDaChave[chave] = alvo;
      novas++;
    }
    for (var i = 0; i < linha.length; i++) {
      // valor vazio no arquivo nunca apaga o que ja esta na planilha
      if (linha[i].isNotEmpty) saida[endereco(alvo, destino[i])] = celulaDeValor(linha[i]);
    }
  }
  return ResultadoAcrescentar(saida, novas, atualizadas, ignoradas, criadas);
}
