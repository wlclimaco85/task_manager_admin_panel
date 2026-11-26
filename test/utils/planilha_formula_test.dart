import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/utils/planilha_formula.dart';

void main() {
  String calc(Map<String, String> c, String ref) => PlanilhaCalculo(c).exibir(ref);

  test('contas, referencias, intervalos e funcoes', () {
    final c = {
      'A1': '1.234,50', 'A2': '10.5', 'A3': 'texto', 'B1': '=SOMA(A1:A3)', 'B2': '=(A2+0,5)*2',
      'B3': '=MEDIA(A1:A2;0,5)', 'B4': '=SUM(A2,1.5)', 'B5': '=B1-B4',
    };
    expect(calc(c, 'B1'), '1245');
    expect(calc({'A2': '10.5', 'B2': '=(A2+1.5)*2'}, 'B2'), '24');
    expect(calc(c, 'B3'), '415,1666666667');
    expect(calc(c, 'B4'), '12');
    expect(calc(c, 'B5'), '1233');
  });

  test('ponto de milhar segue o pt-BR, como o servidor', () {
    expect(lerNumero('1.500'), 1500);
    expect(lerNumero('0.125'), 0.125);
    expect(lerNumero('10.5'), 10.5);
  });

  test('erros nao derrubam a tela', () {
    final c = {'A1': '=A2', 'A2': '=A1', 'B1': '=1/0', 'B2': '=SE(A1;1;2)', 'B3': '=1+', 'B4': 'x', 'B5': '=B4+1'};
    expect(calc(c, 'A1'), '#CICLO');
    expect(calc(c, 'B1'), '#DIV/0!');
    expect(calc(c, 'B2'), '#NOME?');
    expect(calc(c, 'B3'), '#ERRO');
    expect(calc(c, 'B5'), '#VALOR!');
  });

  test('dado do sistema nunca vira formula', () {
    expect(celulaDeValor('=HYPERLINK("x")'), '\'=HYPERLINK("x")');
    expect(calc({'A1': celulaDeValor('=1+1')}, 'A1'), '=1+1');
    expect(celulaDeValor(12.5), '12,5');
  });

  test('colar do Excel e limite sem alterar', () {
    final c = <String, String>{};
    expect(inserirBloco(c, 0, 25, blocoDeTextoColado('a\tb\r\n1\t2\r\n')), isTrue);
    expect(c, {'Z1': 'a', 'AA1': 'b', 'Z2': '1', 'AA2': '2'});
    expect(inserirBloco(c, 0, kPlanilhaMaxColunas - 1, [['x', 'y']]), isFalse);
    expect(c.length, 4);
  });
}
