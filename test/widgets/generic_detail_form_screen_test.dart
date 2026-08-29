import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';
import 'package:task_manager_admin_panel/widgets/generic/field_config.dart';
import 'package:task_manager_admin_panel/widgets/generic/generic_detail_form_screen.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.darkTheme, home: child);

void main() {
  testWidgets('campo FieldType.date mostra valor inicial formatado dd/MM/yyyy',
      (tester) async {
    final client = MockClient((request) async {
      return http.Response('{}', 200,
          headers: {'content-type': 'application/json'});
    });
    final caller = NetworkCaller(client: client);

    await tester.pumpWidget(_wrap(GenericDetailFormScreen(
      title: 'Licenca',
      fields: const [
        FieldConfig(
          key: 'venc',
          label: 'Vencimento',
          type: FieldType.date,
        ),
      ],
      createUrl: 'http://backend/api/licencas',
      initialValues: const {'venc': '2026-12-31'},
      networkCaller: caller,
    )));

    await tester.pumpAndSettle();

    expect(find.text('31/12/2026'), findsOneWidget);
  });

  testWidgets('campo FieldType.date sem valor inicial mostra placeholder',
      (tester) async {
    final client = MockClient((request) async {
      return http.Response('{}', 200,
          headers: {'content-type': 'application/json'});
    });
    final caller = NetworkCaller(client: client);

    await tester.pumpWidget(_wrap(GenericDetailFormScreen(
      title: 'Licenca',
      fields: const [
        FieldConfig(
          key: 'venc',
          label: 'Vencimento',
          type: FieldType.date,
        ),
      ],
      createUrl: 'http://backend/api/licencas',
      networkCaller: caller,
    )));

    await tester.pumpAndSettle();

    expect(find.text('Selecionar data'), findsOneWidget);
  });

  testWidgets('transformPayload transforma o payload antes do POST',
      (tester) async {
    Map<String, dynamic>? capturedBody;
    final client = MockClient((request) async {
      capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('{}', 201,
          headers: {'content-type': 'application/json'});
    });
    final caller = NetworkCaller(client: client);

    await tester.pumpWidget(_wrap(GenericDetailFormScreen(
      title: 'Chamado',
      fields: const [
        FieldConfig(key: 'titulo', label: 'Titulo', required: true),
      ],
      createUrl: 'http://backend/api/chamados',
      networkCaller: caller,
      transformPayload: (raw, isEditing) => {
        ...raw,
        'extra': isEditing ? 'edit' : 'create',
      },
    )));

    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('form_field_titulo')), 'Chamado teste');
    await tester.tap(find.byKey(const Key('form_submit_button')));
    await tester.pumpAndSettle();

    expect(capturedBody, isNotNull);
    expect(capturedBody!['titulo'], 'Chamado teste');
    expect(capturedBody!['extra'], 'create');
  });

  testWidgets('sem transformPayload o payload segue o coletado do form',
      (tester) async {
    Map<String, dynamic>? capturedBody;
    final client = MockClient((request) async {
      capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('{}', 201,
          headers: {'content-type': 'application/json'});
    });
    final caller = NetworkCaller(client: client);

    await tester.pumpWidget(_wrap(GenericDetailFormScreen(
      title: 'Contato',
      fields: const [
        FieldConfig(key: 'nome', label: 'Nome', required: true),
      ],
      createUrl: 'http://backend/api/contato-comercial',
      networkCaller: caller,
    )));

    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('form_field_nome')), 'Fulano');
    await tester.tap(find.byKey(const Key('form_submit_button')));
    await tester.pumpAndSettle();

    expect(capturedBody, {'nome': 'Fulano'});
  });

  testWidgets('campo FieldType.dropdown com options fixas exibe as opcoes',
      (tester) async {
    final client = MockClient((request) async {
      return http.Response('{}', 200,
          headers: {'content-type': 'application/json'});
    });
    final caller = NetworkCaller(client: client);

    await tester.pumpWidget(_wrap(GenericDetailFormScreen(
      title: 'Chamado',
      fields: const [
        FieldConfig(
          key: 'status',
          label: 'Status',
          type: FieldType.dropdown,
          options: [
            DropdownOption(value: 'ABERTO', label: 'Aberto'),
            DropdownOption(value: 'FECHADO', label: 'Fechado'),
          ],
        ),
      ],
      createUrl: 'http://backend/api/chamados',
      networkCaller: caller,
    )));

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('form_field_status')), findsOneWidget);
    await tester.tap(find.byKey(const Key('form_field_status')));
    await tester.pumpAndSettle();

    expect(find.text('Aberto'), findsWidgets);
    expect(find.text('Fechado'), findsWidgets);
  });
}
