/// Projecao mensal simples para o Dashboard de Crescimento (DASH-01).
///
/// Regressao linear por minimos quadrados sobre o historico informado (eixo
/// x = indice 0..n-1 dos meses), projetando os proximos `mesesProjetados`
/// pontos. Deliberadamente simples (nao e' uma serie temporal sofisticada):
/// o pedido do usuario foi "media movel ou regressao linear simples", ver
/// PLAN.md Task 07.1.
///
/// Casos de borda:
/// - `historico` vazio: nao ha dado suficiente para nenhuma projecao,
///   retorna zeros.
/// - `historico` com 1 unico ponto: nao ha 2 pontos para calcular uma reta,
///   retorna uma projecao plana (repete o unico valor conhecido).
/// - Nunca projeta valor negativo (clamp em 0) — contagens de novos
///   parceiros/empresas/modulos nunca sao negativas.
List<double> projectNextMonths(
  List<double> historico, {
  int mesesProjetados = 3,
}) {
  if (historico.isEmpty) {
    return List.filled(mesesProjetados, 0.0);
  }
  if (historico.length == 1) {
    return List.filled(mesesProjetados, historico.first);
  }

  final n = historico.length;
  final xs = List<double>.generate(n, (i) => i.toDouble());
  final meanX = xs.reduce((a, b) => a + b) / n;
  final meanY = historico.reduce((a, b) => a + b) / n;

  double numerador = 0;
  double denominador = 0;
  for (var i = 0; i < n; i++) {
    final dx = xs[i] - meanX;
    numerador += dx * (historico[i] - meanY);
    denominador += dx * dx;
  }

  // Historico constante (todos os pontos identicos): reta horizontal.
  final slope = denominador == 0 ? 0.0 : numerador / denominador;
  final intercept = meanY - slope * meanX;

  return List<double>.generate(mesesProjetados, (i) {
    final x = (n + i).toDouble();
    final y = intercept + slope * x;
    return y < 0 ? 0.0 : y;
  });
}
