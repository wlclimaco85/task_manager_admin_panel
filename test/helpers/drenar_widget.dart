import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Desmonta a arvore e avanca o relogio para drenar timers pendentes (ex.:
/// PaginatedDataTable2, debounce do SistemaErrorReporter) antes do fim do
/// teste, evitando "A Timer is still pending even after the widget tree was
/// disposed".
Future<void> desmontarEDrenar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 2));
}
