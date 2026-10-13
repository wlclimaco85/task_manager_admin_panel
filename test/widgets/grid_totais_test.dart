import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/widgets/generic_grid_windows_screen.dart';

void main() {
  const valor = FieldConfigWindows(
      label: 'Valor', fieldName: 'valor', fieldType: FieldType.currency);
  const quantidade = FieldConfigWindows(
      label: 'Qtd', fieldName: 'qtd', fieldType: FieldType.number);
  const quantidadeSomada = FieldConfigWindows(
      label: 'Qtd', fieldName: 'qtd', fieldType: FieldType.number, showTotal: true);
  const valorSemTotal = FieldConfigWindows(
      label: 'Valor', fieldName: 'valor', fieldType: FieldType.currency, showTotal: false);

  dynamic valorDe(Map<String, dynamic> linha, FieldConfigWindows c) => linha[c.fieldName];

  test('currency soma automaticamente; number so com showTotal; false desliga', () {
    expect(fieldConfigSomaNoRodape(valor), isTrue);
    expect(fieldConfigSomaNoRodape(quantidade), isFalse);
    expect(fieldConfigSomaNoRodape(quantidadeSomada), isTrue);
    expect(fieldConfigSomaNoRodape(valorSemTotal), isFalse);
  });

  test('valorNumericoGrid entende num, texto pt-BR e texto com R\$', () {
    expect(valorNumericoGrid(10.5), 10.5);
    expect(valorNumericoGrid('1.050,25'), 1050.25);
    expect(valorNumericoGrid('R\$ 20,00'), 20.0);
    expect(valorNumericoGrid('12.5'), 12.5);
    expect(valorNumericoGrid('abc'), isNull);
    expect(valorNumericoGrid(null), isNull);
  });

  test('calcularTotaisGrid soma a pagina e ignora linhas nao numericas e colunas sem valor', () {
    final linhas = [
      {'valor': 100.5, 'qtd': 2},
      {'valor': '49,50', 'qtd': 3},
      {'valor': null, 'qtd': 1},
    ];

    final totais = calcularTotaisGrid(linhas, [valor, quantidadeSomada], valorDe);

    expect(totais['valor'], 150.0);
    expect(totais['qtd'], 6.0);
    expect(calcularTotaisGrid(linhas, [quantidade], valorDe), isEmpty);
    expect(calcularTotaisGrid([{'valor': null}], [valor], valorDe), isEmpty);
  });
}
