import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/config/api_links.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/screens/contatos/contato_comercial_screen.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';
import 'package:task_manager_admin_panel/widgets/generic/field_config.dart';
import 'package:task_manager_admin_panel/widgets/generic/generic_detail_form_screen.dart';
import 'package:task_manager_admin_panel/widgets/generic/generic_grid_screen.dart';

/// Mesmos campos declarados em ContatoComercialScreen (privados la, ver
/// PLAN.md Task 04.2) — usados aqui so para exercitar o form de criacao
/// isoladamente contra `/api/contato-comercial`, os campos REAIS da
/// entidade `ContatoComercial` (nao `nome`/`email`/`telefone` da demo
/// quebrada da Fase 1, que apontava para `/api/contatos`).
const _camposContatoComercial = [
  FieldConfig(key: 'nome', label: 'Nome', required: true),
  FieldConfig(key: 'email', label: 'E-mail', type: FieldType.email),
  FieldConfig(key: 'telefone', label: 'Telefone'),
  FieldConfig(key: 'cargo', label: 'Cargo'),
];

void main() {
  testWidgets(
      'ContatoComercialScreen monta GenericGridScreen com os campos reais (nao a demo antiga)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: const ContatoComercialScreen(),
    ));
    await tester.pump();

    final grid = tester.widget<GenericGridScreen>(
      find.byType(GenericGridScreen),
    );

    expect(grid.title, 'Contatos');
    expect(grid.listUrl, ApiLinks.allContatosComerciais);
    expect(grid.createUrl, ApiLinks.createContatoComercial);
    expect(grid.updateUrl('1'), ApiLinks.updateContatoComercial('1'));
    expect(grid.deleteUrl!('1'), ApiLinks.deleteContatoComercial('1'));
    expect(
      grid.fields.map((f) => f.key),
      ['nome', 'email', 'telefone', 'cargo', 'observacao'],
    );
  });

  testWidgets('cria um contato comercial real com sucesso (POST 201)',
      (tester) async {
    Map<String, dynamic>? capturedBody;
    final client = MockClient((request) async {
      capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({'id': 1, ...capturedBody!}),
        201,
        headers: {'content-type': 'application/json'},
      );
    });
    final caller = NetworkCaller(client: client);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: GenericDetailFormScreen(
        title: 'Contatos',
        fields: _camposContatoComercial,
        createUrl: ApiLinks.createContatoComercial,
        networkCaller: caller,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('form_field_nome')), 'Fulano de Tal');
    await tester.enterText(
        find.byKey(const Key('form_field_email')), 'fulano@x.com');
    await tester.enterText(
        find.byKey(const Key('form_field_telefone')), '11999998888');
    await tester.enterText(
        find.byKey(const Key('form_field_cargo')), 'Gerente');

    await tester.tap(find.byKey(const Key('form_submit_button')));
    await tester.pumpAndSettle();

    expect(capturedBody, isNotNull);
    expect(capturedBody!['nome'], 'Fulano de Tal');
    expect(capturedBody!['email'], 'fulano@x.com');
    expect(capturedBody!['telefone'], '11999998888');
    expect(capturedBody!['cargo'], 'Gerente');
    // Campos da demo quebrada da Fase 1 (apontava para /api/contatos com
    // titulo/mensagem/tipoContato) nao devem existir aqui.
    expect(capturedBody!.containsKey('titulo'), isFalse);
    expect(capturedBody!.containsKey('mensagem'), isFalse);

    // form_submit_button fecha a tela com pop(true) em caso de sucesso —
    // confirma que nao ficou preso na tela por erro de validacao/rede.
    expect(find.byKey(const Key('form_error_text')), findsNothing);
  });
}
