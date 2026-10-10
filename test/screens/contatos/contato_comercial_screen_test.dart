import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_manager_admin_panel/config/api_links.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/screens/contatos/contato_comercial_screen.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';
import 'package:task_manager_admin_panel/widgets/generic_grid_windows_screen.dart';

import '../../helpers/drenar_widget.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'ContatoComercialScreen monta GenericGridWindowsScreen com os campos reais (nao a demo antiga)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: const ContatoComercialScreen(),
    ));
    await tester.pump();

    final grid = tester.widget<GenericGridWindowsScreen>(
      find.byType(GenericGridWindowsScreen),
    );

    expect(grid.title, 'Contatos');
    expect(
      grid.fieldConfigs.map((f) => f.fieldName),
      ['nome', 'email', 'telefone', 'cargo', 'observacao'],
    );

    await desmontarEDrenar(tester);
  });

  testWidgets('cria um contato comercial real com sucesso (POST 201)',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Map<String, dynamic>? capturedBody;
    String? capturedUrl;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        capturedUrl = request.url.toString();
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'id': 1, ...capturedBody!}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('[]', 200,
          headers: {'content-type': 'application/json'});
    });

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: ContatoComercialScreen(networkCaller: NetworkCaller(client: client)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Novo'));
    await tester.pumpAndSettle();

    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(0), 'Fulano de Tal');
    await tester.enterText(campos.at(1), 'fulano@x.com');
    await tester.enterText(campos.at(2), '11999998888');
    await tester.enterText(campos.at(3), 'Gerente');

    await tester.tap(find.text('SALVAR'));
    await tester.pumpAndSettle();

    expect(capturedUrl, startsWith(ApiLinks.createContatoComercial));
    expect(capturedBody, isNotNull);
    expect(capturedBody!['nome'], 'Fulano de Tal');
    expect(capturedBody!['email'], 'fulano@x.com');
    expect(capturedBody!['telefone'], '11999998888');
    expect(capturedBody!['cargo'], 'Gerente');
    // Campos da demo quebrada da Fase 1 (apontava para /api/contatos com
    // titulo/mensagem/tipoContato) nao devem existir aqui.
    expect(capturedBody!.containsKey('titulo'), isFalse);
    expect(capturedBody!.containsKey('mensagem'), isFalse);

    await desmontarEDrenar(tester);
  });
}
