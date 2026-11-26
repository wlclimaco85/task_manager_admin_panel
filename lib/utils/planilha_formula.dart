/// Calculo de formulas da planilha (estilo Excel): + - * /, parenteses, referencias (A1), intervalos (A1:B3) e as
/// funcoes SOMA, MEDIA, MIN, MAX e CONT (tambem em ingles). Texto iniciado por apostrofo e' literal.
/// shortcut: outras funcoes do Excel (SE, PROCV...) mostram #NOME? na tela, mas sao exportadas para o .xlsx.
library;

const int kPlanilhaMaxLinhas = 2000;
const int kPlanilhaMaxColunas = 52;

/// 0 -> A, 25 -> Z, 26 -> AA.
String nomeColuna(int c) => c < 26
    ? String.fromCharCode(65 + c)
    : '${String.fromCharCode(64 + c ~/ 26)}${String.fromCharCode(65 + c % 26)}';

int indiceColuna(String nome) =>
    nome.toUpperCase().codeUnits.fold(0, (a, u) => a * 26 + u - 64) - 1;

String endereco(int linha, int coluna) => '${nomeColuna(coluna)}${linha + 1}';

/// (linha, coluna) com base zero, ou null se o endereco for invalido.
(int, int)? posicao(String ref) {
  final m = RegExp(r'^([A-Z]{1,2})([1-9]\d{0,4})$').firstMatch(ref);
  if (m == null) return null;
  return (int.parse(m[2]!) - 1, indiceColuna(m[1]!));
}

/// Numero em pt-BR (1.234,56) ou com ponto decimal (10.5).
double? lerNumero(String texto) {
  final t = texto.trim();
  if (RegExp(r'^-?(\d{1,3}(\.\d{3})+|\d+),\d+$').hasMatch(t) ||
      RegExp(r'^-?\d{1,3}(\.\d{3}){2,}$').hasMatch(t)) {
    return double.parse(t.replaceAll('.', '').replaceAll(',', '.'));
  }
  if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(t)) return double.parse(t);
  return null;
}

String formatarNumero(num v) {
  if (v.isNaN || v.isInfinite) return '#ERRO';
  var s = v.toStringAsFixed(10);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return (s == '-0' ? '0' : s).replaceAll('.', ',');
}

class _ErroFormula implements Exception {
  final String codigo;
  const _ErroFormula(this.codigo);
}

/// Avalia as celulas de um mapa {"A1": "texto"}. Crie um novo a cada alteracao (guarda cache dos resultados).
class PlanilhaCalculo {
  final Map<String, String> celulas;
  final Map<String, Object> _cache = {};
  final Set<String> _visitando = {};

  PlanilhaCalculo(this.celulas);

  /// Texto a exibir na celula.
  String exibir(String ref) {
    final bruto = celulas[ref] ?? '';
    if (bruto.startsWith("'")) return bruto.substring(1);
    if (!bruto.startsWith('=') || bruto.length < 2) return bruto;
    try {
      final v = _valor(ref);
      return v is double ? formatarNumero(v) : '$v';
    } on _ErroFormula catch (e) {
      return e.codigo;
    }
  }

  Object _valor(String ref) {
    final pronto = _cache[ref];
    if (pronto != null) return pronto;
    final bruto = celulas[ref] ?? '';
    if (bruto.startsWith("'")) return bruto.substring(1);
    if (!bruto.startsWith('=') || bruto.length < 2) {
      return lerNumero(bruto) ?? bruto;
    }
    // Limite de profundidade evita estouro de pilha em cadeias enormes.
    if (_visitando.length > 500 || !_visitando.add(ref)) {
      throw const _ErroFormula('#CICLO');
    }
    try {
      return _cache[ref] = _Leitor(bruto.substring(1), this).resultado();
    } finally {
      _visitando.remove(ref);
    }
  }
}

class _Leitor {
  static final _token = RegExp(
      r'\s*(?:(\d+(?:\.\d+)?)|"([^"]*)"|([A-Z]{1,2}[1-9]\d*)(?![A-Z0-9(])|([A-ZÀ-Ü][A-ZÀ-Ü.]*)(?=\()|([-+*/():,]))');

  final PlanilhaCalculo calc;
  final List<RegExpMatch> _tokens = [];
  int _i = 0;

  _Leitor(String formula, this.calc) {
    // Mesmo criterio do servidor: com ";" a formula esta no padrao brasileiro (virgula decimal).
    var f = formula;
    if (f.contains(';')) {
      f = f.replaceAll(RegExp(r'(?<=\d),(?=\d)'), '.').replaceAll(';', ',');
    }
    f = f.toUpperCase().trimRight();
    var pos = 0;
    while (pos < f.length) {
      final m = _token.matchAsPrefix(f, pos) as RegExpMatch?;
      if (m == null) throw const _ErroFormula('#NOME?');
      _tokens.add(m);
      pos = m.end;
    }
  }

  Object resultado() {
    final v = _soma();
    if (_i != _tokens.length) throw const _ErroFormula('#ERRO');
    return v;
  }

  String? get _simbolo => _i < _tokens.length ? _tokens[_i][5] : null;

  void _exigir(String s) {
    if (_simbolo != s) throw const _ErroFormula('#ERRO');
    _i++;
  }

  double _numero(Object v) {
    if (v is double) return v;
    if ('$v'.isEmpty) return 0;
    throw const _ErroFormula('#VALOR!');
  }

  Object _soma() {
    var v = _produto();
    while (_simbolo == '+' || _simbolo == '-') {
      final op = _tokens[_i++][5];
      final d = _numero(_produto());
      v = op == '+' ? _numero(v) + d : _numero(v) - d;
    }
    return v;
  }

  Object _produto() {
    var v = _fator();
    while (_simbolo == '*' || _simbolo == '/') {
      final op = _tokens[_i++][5];
      final d = _numero(_fator());
      if (op == '/' && d == 0) throw const _ErroFormula('#DIV/0!');
      v = op == '*' ? _numero(v) * d : _numero(v) / d;
    }
    return v;
  }

  Object _fator() {
    if (_i >= _tokens.length) throw const _ErroFormula('#ERRO');
    final t = _tokens[_i++];
    if (t[1] != null) return double.parse(t[1]!);
    if (t[2] != null) return t[2]!;
    if (t[3] != null) return calc._valor(t[3]!);
    if (t[4] != null) return _funcao(t[4]!);
    if (t[5] == '-') return -_numero(_fator());
    if (t[5] == '+') return _numero(_fator());
    if (t[5] == '(') {
      final v = _soma();
      _exigir(')');
      return v;
    }
    throw const _ErroFormula('#ERRO');
  }

  double _funcao(String nome) {
    const conhecidas = {
      'SOMA', 'SUM', 'MEDIA', 'MÉDIA', 'AVERAGE', 'MIN', 'MINIMO', 'MÍNIMO', 'MAX', 'MAXIMO', 'MÁXIMO',
      'CONT', 'COUNT', 'CONT.NUM', 'CONT.NÚM'
    };
    if (!conhecidas.contains(nome)) throw const _ErroFormula('#NOME?');
    _exigir('(');
    final numeros = <double>[];
    while (true) {
      final ref = _i < _tokens.length ? _tokens[_i][3] : null;
      final intervalo = ref != null &&
          _i + 2 < _tokens.length &&
          _tokens[_i + 1][5] == ':' &&
          _tokens[_i + 2][3] != null;
      if (intervalo) {
        _lerIntervalo(ref, _tokens[_i + 2][3]!, numeros);
        _i += 3;
      } else {
        final v = _soma();
        if (v is double) numeros.add(v);
      }
      if (_simbolo != ',') break;
      _i++;
    }
    _exigir(')');
    double soma() => numeros.fold(0.0, (a, b) => a + b);
    switch (nome) {
      case 'SOMA' || 'SUM':
        return soma();
      case 'MEDIA' || 'MÉDIA' || 'AVERAGE':
        if (numeros.isEmpty) throw const _ErroFormula('#DIV/0!');
        return soma() / numeros.length;
      case 'MIN' || 'MINIMO' || 'MÍNIMO':
        return numeros.isEmpty ? 0 : numeros.reduce((a, b) => a < b ? a : b);
      case 'MAX' || 'MAXIMO' || 'MÁXIMO':
        return numeros.isEmpty ? 0 : numeros.reduce((a, b) => a > b ? a : b);
      case 'CONT' || 'COUNT' || 'CONT.NUM' || 'CONT.NÚM':
        return numeros.length.toDouble();
      default:
        throw const _ErroFormula('#NOME?');
    }
  }

  void _lerIntervalo(String de, String ate, List<double> numeros) {
    final a = posicao(de), b = posicao(ate);
    if (a == null || b == null) throw const _ErroFormula('#REF!');
    final l1 = a.$1 < b.$1 ? a.$1 : b.$1, l2 = a.$1 < b.$1 ? b.$1 : a.$1;
    final c1 = a.$2 < b.$2 ? a.$2 : b.$2, c2 = a.$2 < b.$2 ? b.$2 : a.$2;
    if (l2 >= kPlanilhaMaxLinhas || c2 >= kPlanilhaMaxColunas) {
      throw const _ErroFormula('#REF!');
    }
    for (var l = l1; l <= l2; l++) {
      for (var c = c1; c <= c2; c++) {
        final ref = endereco(l, c);
        if (!calc.celulas.containsKey(ref)) continue;
        final v = calc._valor(ref);
        if (v is double) numeros.add(v);
      }
    }
  }
}

/// Valor vindo do sistema vira texto de celula. Texto que comece com "=" ou "'" e' protegido com apostrofo para nunca
/// virar formula (injecao de formula a partir de um cadastro).
String celulaDeValor(Object? v) {
  if (v == null) return '';
  if (v is num) return formatarNumero(v);
  if (v is bool) return v ? 'Sim' : 'Não';
  final s = '$v';
  return s.startsWith('=') || s.startsWith("'") ? "'$s" : s;
}

/// Grava um bloco (linhas x colunas) a partir de uma celula. Devolve false, sem alterar nada, se passar do limite.
bool inserirBloco(Map<String, String> celulas, int linha, int coluna, List<List<String>> bloco) {
  final largura = bloco.fold(0, (m, l) => l.length > m ? l.length : m);
  if (linha + bloco.length > kPlanilhaMaxLinhas || coluna + largura > kPlanilhaMaxColunas) return false;
  for (var l = 0; l < bloco.length; l++) {
    for (var c = 0; c < bloco[l].length; c++) {
      final ref = endereco(linha + l, coluna + c);
      if (bloco[l][c].isEmpty) {
        celulas.remove(ref);
      } else {
        celulas[ref] = bloco[l][c];
      }
    }
  }
  return true;
}

/// Texto copiado do Excel/Google Planilhas: linhas separadas por quebra, colunas por TAB.
List<List<String>> blocoDeTextoColado(String texto) {
  final linhas = texto.replaceAll('\r\n', '\n').split('\n');
  if (linhas.isNotEmpty && linhas.last.isEmpty) linhas.removeLast();
  return [for (final l in linhas) l.split('\t')];
}
