import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/utils/csv_parser.dart';

void main() {
  group('parseCsv', () {
    test('separador ; (ponto-e-virgula)', () {
      final result = parseCsv('a;b\n1;2');
      expect(result, [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('auto-detecta separador , (virgula) quando nao ha ;', () {
      final result = parseCsv('a,b\n1,2');
      expect(result, [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('celula entre aspas contendo o separador nao quebra em colunas extras', () {
      final result = parseCsv('nome;obs\n"a;b";c');
      expect(result, [
        ['nome', 'obs'],
        ['a;b', 'c'],
      ]);
    });

    test('linha vazia no fim do arquivo e ignorada', () {
      final result = parseCsv('a;b\n1;2\n\n');
      expect(result, [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('conteudo vazio retorna lista vazia', () {
      expect(parseCsv(''), <List<String>>[]);
    });

    test('aceita CRLF (\\r\\n) alem de LF', () {
      final result = parseCsv('a;b\r\n1;2\r\n');
      expect(result, [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('aspas duplicadas dentro de celula entre aspas viram uma aspas literal', () {
      final result = parseCsv('nome\n"ele disse ""oi"""');
      expect(result, [
        ['nome'],
        ['ele disse "oi"'],
      ]);
    });
  });
}
