import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/utils/growth_projection.dart';

void main() {
  group('projectNextMonths', () {
    test('projeta pontos seguintes por regressao linear simples', () {
      final result = projectNextMonths([1, 2, 3, 4], mesesProjetados: 3);
      expect(result.length, 3);
      expect(result[0], closeTo(5, 0.01));
      expect(result[1], closeTo(6, 0.01));
      expect(result[2], closeTo(7, 0.01));
    });

    test('historico vazio retorna zeros', () {
      final result = projectNextMonths([], mesesProjetados: 3);
      expect(result, [0.0, 0.0, 0.0]);
    });

    test('historico com 1 ponto retorna projecao plana (sem regressao)', () {
      final result = projectNextMonths([5], mesesProjetados: 2);
      expect(result, [5.0, 5.0]);
    });

    test('nunca projeta valor negativo (clamp em 0)', () {
      final result = projectNextMonths([10, 5, 0], mesesProjetados: 2);
      expect(result.every((v) => v >= 0), isTrue);
    });
  });
}
