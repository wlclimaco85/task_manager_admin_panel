import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/screens/sistema/tela_field_editor_screen.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.darkTheme, home: child);

const _fieldsResponse = {
  'fields': [
    {
      'id': 2,
      'label': 'Campo B',
      'fieldName': 'campoB',
      'fieldOrder': 2,
      'fieldType': 'text',
      'isInForm': true,
    },
    {
      'id': 1,
      'label': 'Campo A',
      'fieldName': 'campoA',
      'fieldOrder': 1,
      'fieldType': 'text',
      'isInForm': true,
    },
  ],
};

/// Client de teste que grava as requisicoes recebidas e responde de forma
/// generica: GET devolve sempre a mesma lista de campos (suficiente para
/// cobrir o reload apos salvar), PUT devolve 200 vazio.
class _RecordingClient {
  final List<http.Request> requests = [];

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    if (request.method == 'GET') {
      return http.Response(
        jsonEncode(_fieldsResponse),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('', 200, headers: {'content-type': 'application/json'});
  });
}

void main() {
  testWidgets(
      'carrega campos ordenados por fieldOrder e abre painel de propriedades ao selecionar',
      (tester) async {
    final recorder = _RecordingClient();
    final caller = NetworkCaller(client: recorder.client);

    await tester.pumpWidget(_wrap(TelaFieldEditorScreen(
      telaId: 10,
      telaNome: 'aplicativo',
      telaTitulo: 'Aplicativo',
      networkCaller: caller,
    )));
    await tester.pumpAndSettle();

    // Campo A (fieldOrder 1) deve aparecer antes de Campo B (fieldOrder 2).
    final posA = tester.getTopLeft(find.text('Campo A').first).dy;
    final posB = tester.getTopLeft(find.text('Campo B').first).dy;
    expect(posA, lessThan(posB));

    expect(find.byKey(const Key('field_editor_no_selection')), findsOneWidget);

    await tester.tap(find.byKey(const Key('field_editor_item_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('field_editor_save_button')), findsOneWidget);
    expect(find.byKey(const Key('field_editor_no_selection')), findsNothing);
  });

  testWidgets('reorder dispara PUT correto em reorderTelaFields', (tester) async {
    final recorder = _RecordingClient();
    final caller = NetworkCaller(client: recorder.client);

    await tester.pumpWidget(_wrap(TelaFieldEditorScreen(
      telaId: 10,
      telaNome: 'aplicativo',
      telaTitulo: 'Aplicativo',
      networkCaller: caller,
    )));
    await tester.pumpAndSettle();

    final reorderable = tester.widget<ReorderableListView>(
      find.byKey(const Key('field_editor_reorderable_list')),
    );
    // onReorder e declarado como `void Function(int,int)` na API publica do
    // widget, mas a implementacao real (_reordenar) retorna Future<void> —
    // cast para invocar e aguardar o efeito assincrono (PUT) no teste.
    final onReorder = reorderable.onReorder as Future<void> Function(int, int);
    await onReorder(0, 2); // move o 1o item (Campo A) para depois do 2o.
    await tester.pumpAndSettle();

    final putReorder = recorder.requests.firstWhere(
      (r) => r.method == 'PUT' && r.url.path.contains('/fields/reorder'),
    );
    expect(putReorder.url.path, contains('/api/telas/10/fields/reorder'));

    final body = jsonDecode(putReorder.body) as Map<String, dynamic>;
    final orders = (body['fields'] as List).cast<Map>();
    expect(orders[0]['id'], 2);
    expect(orders[0]['fieldOrder'], 1);
    expect(orders[1]['id'], 1);
    expect(orders[1]['fieldOrder'], 2);
  });

  group('parsing de defaultValue (Valor Fixo / Payload)', () {
    Future<Map<String, dynamic>> salvarComDefaultValue(
        WidgetTester tester, String texto) async {
      final recorder = _RecordingClient();
      final caller = NetworkCaller(client: recorder.client);

      await tester.pumpWidget(_wrap(TelaFieldEditorScreen(
        telaId: 10,
        telaNome: 'aplicativo',
        telaTitulo: 'Aplicativo',
        networkCaller: caller,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('field_editor_item_1')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('field_editor_default_value_field')),
        texto,
      );
      await tester.pumpAndSettle();

      final saveButton = find.byKey(const Key('field_editor_save_button'));
      await tester.ensureVisible(saveButton);
      await tester.pumpAndSettle();
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.pumpAndSettle();

      final putField = recorder.requests.firstWhere(
        (r) => r.method == 'PUT' && r.url.path.contains('/fields/1'),
      );
      return jsonDecode(putField.body) as Map<String, dynamic>;
    }

    testWidgets('texto vazio vira null', (tester) async {
      final body = await salvarComDefaultValue(tester, '');
      expect(body['defaultValue'], isNull);
    });

    testWidgets('true/false vira bool', (tester) async {
      final body = await salvarComDefaultValue(tester, 'true');
      expect(body['defaultValue'], true);
    });

    testWidgets('numero vira num', (tester) async {
      final body = await salvarComDefaultValue(tester, '42');
      expect(body['defaultValue'], 42);
    });

    testWidgets('JSON vira objeto decodificado', (tester) async {
      final body = await salvarComDefaultValue(tester, '{"id": 1}');
      expect(body['defaultValue'], {'id': 1});
    });

    testWidgets('string literal (incl. template) permanece string',
        (tester) async {
      final body = await salvarComDefaultValue(tester, '{{now+7d}}');
      expect(body['defaultValue'], '{{now+7d}}');
    });
  });
}
