import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/screens/sistema/email_smtp_screen.dart';
import 'package:task_manager_admin_panel/widgets/smtp_config_tab.dart';

void main() {
  testarSmtp();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final empresas = [
    {'value': 20001, 'label': 'Abraco Contabilidade'},
    {'value': 30002, 'label': 'Meu Treino'},
  ];

  testWidgets('lista as empresas e so mostra a configuracao SMTP depois de escolher uma', (tester) async {
    final pedidos = <http.Request>[];
    final cliente = MockClient((req) async {
      pedidos.add(req);
      return http.Response(
        jsonEncode({
          'ativo': false,
          'host': 'smtp.gmail.com',
          'porta': 587,
          'usuario': 'abracocontabeisapp@gmail.com',
          'senhaConfigurada': false,
          'remetenteEmail': 'abracocontabeisapp@gmail.com',
          'remetenteNome': 'Abraço Contabilidade',
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: EmailSmtpScreen(carregarEmpresas: () async => empresas),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Escolha a empresa para configurar o e-mail de envio.'), findsOneWidget);
      expect(find.byType(SmtpConfigTab), findsNothing);

      await tester.tap(find.byKey(const Key('email_smtp_empresa')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abraco Contabilidade').last);
      await tester.pumpAndSettle();

      expect(find.byType(SmtpConfigTab), findsOneWidget);
      expect(pedidos.any((r) => r.url.path.endsWith('/api/smtp-config/empresa/20001')), isTrue);
      expect(find.text('smtp.gmail.com'), findsWidgets);
    }, () => cliente);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}

void testarSmtp() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('botao Testar chama POST /testar da empresa e mostra a mensagem do backend', (tester) async {
    final pedidos = <http.Request>[];
    final cliente = MockClient((req) async {
      pedidos.add(req);
      if (req.method == 'POST') {
        return http.Response(
          jsonEncode({'enviado': true, 'destinatario': 'wlclimaco@gmail.com', 'mensagem': 'E-mail de teste enviado para wlclimaco@gmail.com.'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response(jsonEncode({'ativo': true, 'host': 'smtp.gmail.com', 'porta': 587}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(body: SmtpConfigTab(scope: SmtpConfigScope.empresa, id: 20002, nome: 'Meu Treino')),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('smtp_testar')));
      await tester.pumpAndSettle();

      final post = pedidos.firstWhere((r) => r.method == 'POST');
      expect(post.url.path, endsWith('/api/smtp-config/empresa/20002/testar'));
      expect(find.text('E-mail de teste enviado para wlclimaco@gmail.com.'), findsOneWidget);
    }, () => cliente);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('escopo parceiro nao mostra o botao Testar', (tester) async {
    final cliente = MockClient((req) async => http.Response('{}', 200, headers: {'content-type': 'application/json'}));

    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(body: SmtpConfigTab(scope: SmtpConfigScope.parceiro, id: 7)),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('smtp_testar')), findsNothing);
    }, () => cliente);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
