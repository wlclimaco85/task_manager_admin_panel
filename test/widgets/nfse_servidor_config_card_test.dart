import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/widgets/nfse_servidor_config_card.dart';

const _servidores = [
  {'value': 'SEFIN_NACIONAL', 'label': 'Portal Nacional (Emissor Nacional)'},
  {'value': 'WEBISS_UBERABA', 'label': 'WebISS Uberaba'},
];

const _uberaba = NfseServidorConfig(
    id: 5,
    codigoIbge: 3170107,
    uf: 'MG',
    municipio: 'Uberaba',
    servidor: 'WEBISS_UBERABA');

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('lista municipios configurados com o rotulo do servidor',
      (tester) async {
    await tester.pumpWidget(_app(NfseServidorConfigCard(
      baseUrl: 'http://x',
      carregar: () async => [_uberaba],
      carregarServidores: () async => _servidores,
    )));
    await tester.pumpAndSettle();

    expect(find.text('Configurar servidor NFS-e'), findsOneWidget);
    expect(find.text('Uberaba / MG'), findsOneWidget);
    expect(find.text('WebISS Uberaba'), findsOneWidget);
  });

  testWidgets('sem configuracao mostra o padrao Portal Nacional',
      (tester) async {
    await tester.pumpWidget(_app(NfseServidorConfigCard(
      baseUrl: 'http://x',
      carregar: () async => [],
      carregarServidores: () async => _servidores,
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('todos usam o Portal Nacional'), findsOneWidget);
  });

  testWidgets('editar troca o servidor e salva e recarrega', (tester) async {
    NfseServidorConfig? salvo;
    var cargas = 0;
    await tester.pumpWidget(_app(NfseServidorConfigCard(
      baseUrl: 'http://x',
      carregar: () async {
        cargas++;
        return [_uberaba];
      },
      carregarServidores: () async => _servidores,
      salvar: (item) async {
        salvo = item;
        return null;
      },
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nfse-servidor-editar-5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nfse-servidor-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Portal Nacional (Emissor Nacional)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nfse-servidor-confirmar')));
    await tester.pumpAndSettle();

    expect(salvo?.id, 5);
    expect(salvo?.codigoIbge, 3170107);
    expect(salvo?.servidor, 'SEFIN_NACIONAL');
    expect(cargas, 2);
  });

  testWidgets('excluir pede confirmacao e remove', (tester) async {
    int? excluido;
    await tester.pumpWidget(_app(NfseServidorConfigCard(
      baseUrl: 'http://x',
      carregar: () async => [_uberaba],
      carregarServidores: () async => _servidores,
      excluir: (id) async {
        excluido = id;
        return null;
      },
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nfse-servidor-excluir-5')));
    await tester.pumpAndSettle();
    expect(excluido, isNull);
    await tester.tap(find.text('Remover'));
    await tester.pumpAndSettle();

    expect(excluido, 5);
  });

  testWidgets('erro do backend ao salvar aparece e nao recarrega',
      (tester) async {
    var cargas = 0;
    await tester.pumpWidget(_app(NfseServidorConfigCard(
      baseUrl: 'http://x',
      carregar: () async {
        cargas++;
        return [_uberaba];
      },
      carregarServidores: () async => _servidores,
      salvar: (_) async => 'Municipio ja configurado.',
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nfse-servidor-editar-5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nfse-servidor-confirmar')));
    await tester.pumpAndSettle();

    expect(find.text('Municipio ja configurado.'), findsOneWidget);
    expect(cargas, 1);
  });

  testWidgets('falha ao carregar mostra mensagem', (tester) async {
    await tester.pumpWidget(_app(NfseServidorConfigCard(
      baseUrl: 'http://x',
      carregar: () async => throw Exception('rede'),
      carregarServidores: () async => _servidores,
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nao foi possivel carregar'), findsOneWidget);
  });
}
