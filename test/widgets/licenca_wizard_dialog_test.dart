import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:task_manager_admin_panel/config/api_links.dart';
import 'package:task_manager_admin_panel/models/network_response.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';
import 'package:task_manager_admin_panel/widgets/licenca_wizard_dialog.dart';

import 'licenca_wizard_dialog_test.mocks.dart';

@GenerateMocks([NetworkCaller])
void main() {
  Widget buildApp(Widget dialog) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                showDialog(
                  context: ctx,
                  builder: (_) => dialog,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('LicencaWizardDialog fetches logins correctly when tipoAlvo is empresa', (WidgetTester tester) async {
    // Provide a larger surface to prevent RenderFlex overflow
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;

    final mockCaller = MockNetworkCaller();
    final responseRoles = NetworkResponse(true, 200, jsonEncode({"data": {"dados": []}}));
    final responseLogins = NetworkResponse(true, 200, jsonEncode({"data": {"dados": []}}));

    when(mockCaller.getRequest(any)).thenAnswer((_) async => responseRoles);
    when(mockCaller.getRequest(ApiLinks.loginsByEmpresa('10'))).thenAnswer((_) async => responseLogins);

    await tester.pumpWidget(buildApp(LicencaWizardDialog(
      empresaId: 10,
      empresaNome: 'Teste',
      modulosNomes: [],
      tipoAlvo: 'empresa',
      networkCaller: mockCaller,
    )));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    verify(mockCaller.getRequest(ApiLinks.loginsByEmpresa('10'))).called(1);
    
    // reset physical size
    addTearDown(tester.view.resetPhysicalSize);
  });

  testWidgets('LicencaWizardDialog fetches logins correctly when tipoAlvo is parceiro', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;

    final mockCaller = MockNetworkCaller();
    final responseRoles = NetworkResponse(true, 200, jsonEncode({"data": {"dados": []}}));
    final responseLogins = NetworkResponse(true, 200, jsonEncode({"data": {"dados": []}}));

    when(mockCaller.getRequest(any)).thenAnswer((_) async => responseRoles);
    when(mockCaller.getRequest(ApiLinks.loginsByParceiro('20'))).thenAnswer((_) async => responseLogins);

    await tester.pumpWidget(buildApp(LicencaWizardDialog(
      empresaId: 20,
      empresaNome: 'Teste 2',
      modulosNomes: [],
      tipoAlvo: 'parceiro',
      networkCaller: mockCaller,
    )));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    verify(mockCaller.getRequest(ApiLinks.loginsByParceiro('20'))).called(1);

    addTearDown(tester.view.resetPhysicalSize);
  });
}
