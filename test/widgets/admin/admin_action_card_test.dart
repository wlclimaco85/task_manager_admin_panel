import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/widgets/admin/admin_action_card.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: AppTheme.darkTheme, home: Scaffold(body: child));

void main() {
  testWidgets(
      'executa onExecute ao tocar no botao e mostra o resultado formatado',
      (tester) async {
    final completer = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(_wrap(AdminActionCard(
      title: 'Acao de teste',
      subtitle: 'Subtitulo',
      icon: Icons.build,
      color: Colors.blue,
      buttonKey: const Key('exec_button'),
      onExecute: () => completer.future,
    )));

    expect(find.text('Acao de teste'), findsOneWidget);
    expect(find.byKey(const Key('admin_action_card_result')), findsNothing);

    await tester.tap(find.byKey(const Key('exec_button')));
    await tester.pump();
    // Estado de loading enquanto onExecute ainda nao completou.
    expect(find.byKey(const Key('admin_action_card_loading')), findsOneWidget);

    completer.complete({'status': 'ok'});
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin_action_card_loading')), findsNothing);
    expect(find.byKey(const Key('admin_action_card_result')), findsOneWidget);
    expect(find.textContaining('"status": "ok"'), findsOneWidget);
  });

  testWidgets('mostra card de erro quando onExecute lanca excecao',
      (tester) async {
    await tester.pumpWidget(_wrap(AdminActionCard(
      title: 'Acao com erro',
      subtitle: 'Subtitulo',
      icon: Icons.build,
      color: Colors.blue,
      buttonKey: const Key('exec_button'),
      onExecute: () async => throw Exception('HTTP 500: falha'),
    )));

    await tester.tap(find.byKey(const Key('exec_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin_action_card_error')), findsOneWidget);
    expect(find.textContaining('HTTP 500'), findsOneWidget);
    expect(find.byKey(const Key('admin_action_card_result')), findsNothing);
  });

  testWidgets('quando onExecute retorna null (cancelado) nao mostra resultado nem erro',
      (tester) async {
    await tester.pumpWidget(_wrap(AdminActionCard(
      title: 'Acao cancelavel',
      subtitle: 'Subtitulo',
      icon: Icons.build,
      color: Colors.blue,
      buttonKey: const Key('exec_button'),
      onExecute: () async => null,
    )));

    await tester.tap(find.byKey(const Key('exec_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin_action_card_result')), findsNothing);
    expect(find.byKey(const Key('admin_action_card_error')), findsNothing);
    expect(find.byKey(const Key('exec_button')), findsOneWidget);
  });

  testWidgets('renderiza content extra entre subtitulo e botao', (tester) async {
    await tester.pumpWidget(_wrap(AdminActionCard(
      title: 'Acao com conteudo',
      subtitle: 'Subtitulo',
      icon: Icons.build,
      color: Colors.blue,
      buttonKey: const Key('exec_button'),
      content: const Text('Campo extra', key: Key('content_extra')),
      onExecute: () async => {'status': 'ok'},
    )));

    expect(find.byKey(const Key('content_extra')), findsOneWidget);
  });
}
