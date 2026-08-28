import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/screens/sistema/configuracoes_sistema/acoes_screen.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(body: child),
    );

/// [NetworkCaller] cujo client registra cada chamada feita (metodo + path)
/// em [calls], para os testes confirmarem que uma acao destrutiva NAO
/// disparou a chamada de rede antes da confirmacao correta.
class _RecordingCallerResult {
  _RecordingCallerResult(this.caller, this.calls);
  final NetworkCaller caller;
  final List<String> calls;
}

_RecordingCallerResult _recordingCaller() {
  final calls = <String>[];
  final client = MockClient((request) async {
    calls.add('${request.method} ${request.url}');
    return http.Response(
      jsonEncode({'status': 'ok'}),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  return _RecordingCallerResult(NetworkCaller(client: client), calls);
}

/// Confirma que ALGUMA chamada registrada contem o [method]+[pathSuffix]
/// esperado. Nao usamos igualdade exata porque a URL final inclui o
/// context-path do backend (ex. `/boletobancos`) antes de `/api/...`.
Matcher _hasCallMatching(String method, String pathSuffix) => predicate<List<String>>(
    (calls) => calls.any((c) => c.startsWith(method) && c.contains(pathSuffix)),
    'contem uma chamada $method .../$pathSuffix');

/// Localiza e leva ao viewport o widget de [finder] antes de tocar —
/// necessario porque a tela usa `SingleChildScrollView` e o viewport de
/// teste (800x600) nao comporta todos os cards de uma vez.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

void main() {
  testWidgets('renderiza as 4 secoes e os cards de acao esperados',
      (tester) async {
    final rc = _recordingCaller();
    await tester.pumpWidget(_wrap(
      ConfiguracoesSistemaAcoesScreen(networkCaller: rc.caller),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Geração de Telas'), findsOneWidget);
    expect(find.text('Dados de Teste (Mock)'), findsOneWidget);
    expect(find.text('Notícias'), findsOneWidget);
    expect(find.text('Banco de Dados'), findsOneWidget);

    expect(find.byKey(const Key('acao_gerar_telas')), findsOneWidget);
    expect(find.byKey(const Key('acao_regenerar_telas')), findsOneWidget);
    expect(find.byKey(const Key('acao_seed_gerar')), findsOneWidget);
    expect(find.byKey(const Key('acao_seed_apagar')), findsOneWidget);
    expect(find.byKey(const Key('acao_noticias_limpar_baixar')), findsOneWidget);
    expect(find.byKey(const Key('acao_noticias_apagar')), findsOneWidget);
    expect(find.byKey(const Key('acao_db_status')), findsOneWidget);
    expect(find.byKey(const Key('acao_fix_db')), findsOneWidget);
    expect(find.byKey(const Key('acao_reset_database')), findsOneWidget);
  });

  group('Resetar Banco de Dados (digite RESET)', () {
    testWidgets(
        'botao de confirmar fica desabilitado ate digitar RESET exatamente, '
        'e a chamada de rede so dispara apos confirmar', (tester) async {
      final rc = _recordingCaller();
      await tester.pumpWidget(_wrap(
        ConfiguracoesSistemaAcoesScreen(networkCaller: rc.caller),
      ));
      await tester.pumpAndSettle();

      // Nao usar pumpAndSettle aqui: enquanto o dialog de confirmacao esta
      // aberto aguardando interacao do usuario, o AdminActionCard fica em
      // estado de loading (CircularProgressIndicator indeterminado) por
      // baixo do dialog — pumpAndSettle nunca settla com uma animacao
      // indeterminada em tela. Pump com duracao fixa e suficiente para a
      // transicao do dialog terminar.
      await _tapVisible(
          tester, find.byKey(const Key('acao_reset_database_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('confirm_typed_field')), findsOneWidget);
      final confirmButtonFinder = find.byKey(const Key('confirm_typed_button'));
      ElevatedButton confirmButton = tester.widget(confirmButtonFinder);
      expect(confirmButton.onPressed, isNull);

      // Texto errado continua desabilitado.
      await tester.enterText(
          find.byKey(const Key('confirm_typed_field')), 'reset');
      await tester.pump();
      confirmButton = tester.widget(confirmButtonFinder);
      expect(confirmButton.onPressed, isNull);
      expect(rc.calls, isEmpty);

      // Texto correto habilita o botao.
      await tester.enterText(
          find.byKey(const Key('confirm_typed_field')), 'RESET');
      await tester.pump();
      confirmButton = tester.widget(confirmButtonFinder);
      expect(confirmButton.onPressed, isNotNull);

      await tester.tap(confirmButtonFinder);
      await tester.pumpAndSettle();

      expect(rc.calls, _hasCallMatching('POST', '/api/admin/reset-database'));
    });

    testWidgets('cancelar o dialog nao dispara a chamada de rede',
        (tester) async {
      final rc = _recordingCaller();
      await tester.pumpWidget(_wrap(
        ConfiguracoesSistemaAcoesScreen(networkCaller: rc.caller),
      ));
      await tester.pumpAndSettle();

      await _tapVisible(
          tester, find.byKey(const Key('acao_reset_database_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await tester.pumpAndSettle();

      expect(rc.calls, isEmpty);
      expect(find.byKey(const Key('admin_action_card_result')), findsNothing);
    });
  });

  group('Apagar Dados Mock (digite APAGAR)', () {
    testWidgets(
        'exige empresaId preenchido e o texto APAGAR antes de disparar o DELETE',
        (tester) async {
      final rc = _recordingCaller();
      await tester.pumpWidget(_wrap(
        ConfiguracoesSistemaAcoesScreen(networkCaller: rc.caller),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('acao_seed_apagar_empresa_id_field')), '42');
      await _tapVisible(
          tester, find.byKey(const Key('acao_seed_apagar_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('confirm_typed_field')), findsOneWidget);
      final confirmButtonFinder = find.byKey(const Key('confirm_typed_button'));
      expect((tester.widget(confirmButtonFinder) as ElevatedButton).onPressed,
          isNull);

      await tester.enterText(
          find.byKey(const Key('confirm_typed_field')), 'APAGAR');
      await tester.pump();
      expect((tester.widget(confirmButtonFinder) as ElevatedButton).onPressed,
          isNotNull);

      await tester.tap(confirmButtonFinder);
      await tester.pumpAndSettle();

      expect(rc.calls, _hasCallMatching('DELETE', '/api/admin/seed'));
    });
  });

  group('Corrigir Banco (Fix DB) — confirmacao simples', () {
    testWidgets('so dispara o POST apos confirmar no dialog simples',
        (tester) async {
      final rc = _recordingCaller();
      await tester.pumpWidget(_wrap(
        ConfiguracoesSistemaAcoesScreen(networkCaller: rc.caller),
      ));
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.byKey(const Key('acao_fix_db_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(rc.calls, isEmpty);

      await tester.tap(find.byKey(const Key('confirm_simple_button')));
      await tester.pumpAndSettle();

      expect(rc.calls, _hasCallMatching('POST', '/api/admin/fix-db'));
    });
  });

  testWidgets('Gerar Telas envia forceUpdate/fullReset conforme checkboxes',
      (tester) async {
    final rc = _recordingCaller();
    await tester.pumpWidget(_wrap(
      ConfiguracoesSistemaAcoesScreen(networkCaller: rc.caller),
    ));
    await tester.pumpAndSettle();

    await _tapVisible(
        tester, find.byKey(const Key('acao_gerar_telas_force_update')));
    await tester.pumpAndSettle();
    await _tapVisible(
        tester, find.byKey(const Key('acao_gerar_telas_full_reset')));
    await tester.pump();

    await _tapVisible(
        tester, find.byKey(const Key('acao_gerar_telas_button')));
    await tester.pumpAndSettle();

    expect(rc.calls, _hasCallMatching('POST', '/api/telas/generate'));
  });

  testWidgets('Status do Banco dispara GET sem confirmacao', (tester) async {
    final rc = _recordingCaller();
    await tester.pumpWidget(_wrap(
      ConfiguracoesSistemaAcoesScreen(networkCaller: rc.caller),
    ));
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byKey(const Key('acao_db_status_button')));
    await tester.pumpAndSettle();

    expect(rc.calls, _hasCallMatching('GET', '/api/admin/db-status'));
  });
}
