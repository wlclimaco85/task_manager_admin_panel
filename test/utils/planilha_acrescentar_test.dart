import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/utils/planilha_acrescentar.dart';

void main() {
  const atual = {
    'A1': 'CNPJ', 'B1': 'Nome', 'C1': 'Cidade',
    'A2': '12.345.678/0001-90', 'B2': 'Alfa', 'C2': 'Uberaba',
  };
  const arquivo = {
    'A1': 'nome', 'B1': 'cnpj', 'C1': 'Telefone',
    'A2': 'Alfa Ltda', 'B2': '12345678000190', 'C2': '3499',
    'A3': 'Beta', 'B3': '98.765.432/0001-10',
  };

  test('sem chave acrescenta tudo, casando colunas pelo titulo e criando as novas', () {
    final r = acrescentarLinhas(atual, arquivo);
    expect(r.novas, 2);
    expect(r.colunasCriadas, ['Telefone']);
    expect(r.celulas['D1'], 'Telefone');
    expect(r.celulas['A3'], '12345678000190');
    expect(r.celulas['B3'], 'Alfa Ltda');
    expect(r.celulas['B4'], 'Beta');
    expect(r.celulas['B2'], 'Alfa', reason: 'o que ja existia nao muda');
    expect(atual.length, 6);
  });

  test('chave repetida: ignorar mantem a linha antiga', () {
    final r = acrescentarLinhas(atual, arquivo, colunaChave: 'CNPJ');
    expect((r.novas, r.ignoradas, r.atualizadas), (1, 1, 0));
    expect(r.celulas['B2'], 'Alfa');
    expect(r.celulas['B3'], 'Beta');
  });

  test('chave repetida: atualizar troca so o que veio preenchido', () {
    final r = acrescentarLinhas(atual, arquivo, colunaChave: 'cnpj', repetida: LinhaRepetida.atualizar);
    expect((r.novas, r.atualizadas, r.ignoradas), (1, 1, 0));
    expect(r.celulas['B2'], 'Alfa Ltda');
    expect(r.celulas['C2'], 'Uberaba');
    expect(r.celulas['D2'], '3499');
  });

  test('formula do arquivo entra como valor e texto com = nunca vira formula', () {
    final r = acrescentarLinhas({'A1': 'N'}, {'A1': 'N', 'A2': '=2+3', 'A3': "'=HYPERLINK(1)"});
    expect(r.celulas['A2'], '5');
    expect(r.celulas['A3'], "'=HYPERLINK(1)");
  });

  test('recusa sem titulos, chave inexistente e formula com erro', () {
    expect(() => acrescentarLinhas({}, arquivo), throwsA(isA<AcrescentarException>()));
    expect(() => acrescentarLinhas(atual, {'A2': 'x'}), throwsA(isA<AcrescentarException>()));
    expect(() => acrescentarLinhas(atual, arquivo, colunaChave: 'Telefone'), throwsA(isA<AcrescentarException>()));
    expect(() => acrescentarLinhas(atual, {'A1': 'Nome', 'A2': '=1/0'}), throwsA(isA<AcrescentarException>()));
  });
}
