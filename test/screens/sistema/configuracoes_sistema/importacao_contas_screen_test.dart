import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/screens/sistema/configuracoes_sistema/importacao_contas_screen.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.darkTheme, home: child);

PlatformFile _csvFile(String conteudo, {String name = 'contas.csv'}) {
  final bytes = Uint8List.fromList(utf8.encode(conteudo));
  return PlatformFile(name: name, size: bytes.length, bytes: bytes);
}

Future<FilePickerResult?> _pickReturning(PlatformFile file) {
  return Future.value(FilePickerResult([file]));
}

http.Client _clientReturningPreviewFailure() {
  // Simula backend indisponivel no preview — a tela deve manter a deteccao
  // local (via parseCsv) mesmo assim.
  return MockClient((request) async => http.Response('erro', 500));
}

void main() {
  testWidgets(
      'seleciona CSV de Contas a Pagar e auto-mapeia colunas por sinonimo',
      (tester) async {
    final csv = _csvFile('historico;vlr_do_desdobramento;dt_vencimento;parceiro\n'
        'Aluguel;1500,00;10/01/2026;Locador X\n');

    await tester.pumpWidget(_wrap(ImportacaoContasScreen(
      httpClient: _clientReturningPreviewFailure(),
      pickFileOverride: () => _pickReturning(csv),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cp_pick_file_button')));
    await tester.pumpAndSettle();

    // Expande o mapeamento para inspecionar os TextFields preenchidos.
    await tester.tap(find.byKey(const Key('cp_mapeamento_expansion')));
    await tester.pumpAndSettle();

    final descricaoField = tester
        .widget<TextField>(find.byKey(const Key('cp_map_colDescricao')));
    expect(descricaoField.controller?.text, 'historico');

    final valorField =
        tester.widget<TextField>(find.byKey(const Key('cp_map_colValor')));
    expect(valorField.controller?.text, 'vlr_do_desdobramento');

    final vencimentoField = tester
        .widget<TextField>(find.byKey(const Key('cp_map_colVencimento')));
    expect(vencimentoField.controller?.text, 'dt_vencimento');
  });

  testWidgets(
      'botao Importar fica desabilitado ate arquivo + empresa + mapeamento obrigatorio estarem preenchidos',
      (tester) async {
    final csv = _csvFile('historico;vlr_do_desdobramento;dt_vencimento\n'
        'Aluguel;1500,00;10/01/2026\n');

    await tester.pumpWidget(_wrap(ImportacaoContasScreen(
      httpClient: _clientReturningPreviewFailure(),
      pickFileOverride: () => _pickReturning(csv),
    )));
    await tester.pumpAndSettle();

    // Sem arquivo e sem empresa: desabilitado.
    ElevatedButton importarButton() =>
        tester.widget<ElevatedButton>(find.byKey(const Key('cp_import_button')));
    expect(importarButton().onPressed, isNull);

    // Preenche empresa, mas ainda sem arquivo: continua desabilitado.
    await tester.enterText(
        find.byKey(const Key('importacao_empresa_field')), '42');
    await tester.pumpAndSettle();
    expect(importarButton().onPressed, isNull);

    // Seleciona o arquivo: mapeamento obrigatorio ja vem auto-preenchido
    // pelos sinonimos, agora deve habilitar.
    await tester.tap(find.byKey(const Key('cp_pick_file_button')));
    await tester.pumpAndSettle();
    expect(importarButton().onPressed, isNotNull);

    // Limpa um campo obrigatorio do mapeamento: volta a desabilitar.
    await tester.tap(find.byKey(const Key('cp_mapeamento_expansion')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('cp_map_colDescricao')), '');
    await tester.pumpAndSettle();
    expect(importarButton().onPressed, isNull);
  });

  testWidgets('importacao real dispara multipart com campos mapeados e exibe resultado',
      (tester) async {
    final csv = _csvFile('historico;vlr_do_desdobramento;dt_vencimento\n'
        'Aluguel;1500,00;10/01/2026\n');

    http.MultipartRequest? capturedRequest;
    // MockClient (nao-streaming) reconstroi o request recebido como um
    // http.Request plano, perdendo fields/files do MultipartRequest
    // original — usa-se .streaming() aqui para inspecionar o request real.
    final client = MockClient.streaming((request, bodyStream) async {
      await bodyStream.toBytes();
      if (request.url.path.contains('/importacao/preview')) {
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'colunas': []}))),
          200,
        );
      }
      capturedRequest = request as http.MultipartRequest;
      return http.StreamedResponse(
        Stream.value(
            utf8.encode(jsonEncode({'sucesso': 3, 'erros': 0, 'ignorados': 0}))),
        200,
      );
    });

    await tester.pumpWidget(_wrap(ImportacaoContasScreen(
      httpClient: client,
      pickFileOverride: () => _pickReturning(csv),
    )));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('importacao_empresa_field')), '42');
    await tester.tap(find.byKey(const Key('cp_pick_file_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cp_import_button')));
    await tester.pumpAndSettle();

    expect(capturedRequest, isNotNull);
    expect(capturedRequest!.url.path, contains('/importacao/conta-pagar'));
    expect(capturedRequest!.url.queryParameters['empId'], '42');
    expect(capturedRequest!.fields['colDescricao'], 'historico');
    expect(capturedRequest!.files.first.field, 'arquivo');

    expect(find.byKey(const Key('cp_resultado_text')), findsOneWidget);
    expect(find.textContaining('Sucesso: 3'), findsOneWidget);
  });
}
