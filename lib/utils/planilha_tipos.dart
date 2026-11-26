import '../services/planilha_service.dart';
import 'planilha_formula.dart';

const Map<String, String> kTiposDeColuna = {
  'texto': 'Texto',
  'numero': 'Número',
  'soma': 'Número com soma',
  'data': 'Data',
  'check': 'Caixa de marcar',
  'lista': 'Lista (escolher uma opção)',
  'pesquisa': 'Pesquisa',
};

/// Valor da caixa de marcar; a celula guarda "Sim" ou "Não", que o Excel e as formulas entendem como texto.
bool marcado(String valor) => const {'sim', 'true', 's', '1', 'x'}.contains(valor.trim().toLowerCase());

String textoDaCaixa(bool v) => v ? 'Sim' : 'Não';

/// Soma da coluna a partir da linha 2 (a linha 1 e' o titulo). Formulas entram ja calculadas.
double somaDaColuna(Map<String, String> celulas, PlanilhaCalculo calculo, int coluna) {
  var total = 0.0;
  for (final ref in celulas.keys) {
    final p = posicao(ref);
    if (p == null || p.$2 != coluna || p.$1 == 0) continue;
    total += lerNumero(calculo.exibir(ref)) ?? 0;
  }
  return total;
}

/// Valores vindos do banco no formato da coluna: opcao vira rotulo, logico vira Sim/Não e data vira dd/MM/yyyy.
/// A protecao contra formula (celulaDeValor) e aplicada depois, uma vez so, na hora de gravar na celula.
Object? valorDaFonte(Object? valor, TipoDaFonte? tipo) {
  if (valor == null || tipo == null) return valor;
  final rotulo = tipo.valores['$valor'];
  if (rotulo != null) return rotulo;
  if (tipo.coluna.tipo == 'check') return textoDaCaixa(valor == true || marcado('$valor'));
  if (tipo.coluna.tipo == 'data') {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch('$valor');
    if (m != null) return '${m[3]}/${m[2]}/${m[1]}';
  }
  return valor;
}
