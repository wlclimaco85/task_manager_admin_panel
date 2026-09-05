import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/models/login_model.dart';
import 'package:task_manager_admin_panel/services/auth_utility.dart';
import 'package:task_manager_admin_panel/widgets/importacao_sped_card.dart';

void main() {
  tearDown(() {
    AuthUtility.userInfo = null;
  });


  testWidgets('exige empresa antes de importar SPED', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportacaoSpedCard(
            baseUrl: 'http://localhost',
            carregarEmpresas: () async => [
              {'id': '1', 'nome': 'Empresa Smoke Test'},
            ],
            arquivoInicial: PlatformFile(
              name: 'sped.txt',
              size: 3,
              bytes: Uint8List.fromList([49, 48, 32]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('importacao-sped-importar')));
    await tester.pump();

    expect(find.text('Selecione a empresa antes de importar.'), findsOneWidget);
  });

  testWidgets('exibe resumo retornado pela importacao SPED', (
    tester,
  ) async {
    String? empresaEnviada;
    String? arquivoEnviado;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportacaoSpedCard(
            baseUrl: 'http://localhost',
            empresaIdInicial: '1',
            carregarEmpresas: () async => [
              {'id': '1', 'nome': 'Empresa Smoke Test'},
            ],
            arquivoInicial: PlatformFile(
              name: 'sped.txt',
              size: 3,
              bytes: Uint8List.fromList([49, 48, 32]),
            ),
            importar: (empresaId, arquivo) async {
              empresaEnviada = empresaId;
              arquivoEnviado = arquivo.name;
              return {
                'notasEntrada': 1,
                'notasSaida': 0,
                'itens': 2,
                'produtosCriados': 1,
                'produtosAtualizados': 0,
                'parceirosCriados': 1,
                'parceirosAtualizados': 0,
                'tributacoes': 1,
                'financeirosPendentes': 1,
                'avisos': [
                  'Financeiro ficou pendente por falta de vencimento.',
                ],
                'ignorados': ['Registro 9900: 1 linha sem destino seguro.'],
              };
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('importacao-sped-importar')));
    await tester.pumpAndSettle();

    expect(empresaEnviada, '1');
    expect(arquivoEnviado, 'sped.txt');
    expect(find.byKey(const Key('importacao-sped-resumo')), findsOneWidget);
    expect(find.text('Entradas: 1'), findsOneWidget);
    expect(find.text('Itens: 2'), findsOneWidget);
    expect(find.text('Financeiro pendente: 1'), findsOneWidget);
    expect(
      find.text('Registro 9900: 1 linha sem destino seguro.'),
      findsOneWidget,
    );
  });

  // Pedido explicito do usuario: erro inesperado na importacao mostra o
  // stack trace completo, com botao pra copiar.
  testWidgets('exibe trace completo e botao de copiar quando erro traz trace', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportacaoSpedCard(
            baseUrl: 'http://localhost',
            empresaIdInicial: '1',
            carregarEmpresas: () async => [
              {'id': '1', 'nome': 'Empresa Smoke Test'},
            ],
            arquivoInicial: PlatformFile(
              name: 'sped.txt',
              size: 3,
              bytes: Uint8List.fromList([49, 48, 32]),
            ),
            importar: (empresaId, arquivo) async {
              throw ErroImportacaoComTrace(
                'Data invalida no arquivo SPED: ',
                'java.lang.IllegalArgumentException: Data invalida\n\tat Foo.bar(Foo.java:1)',
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('importacao-sped-importar')));
    await tester.pumpAndSettle();

    expect(find.text('Data invalida no arquivo SPED: '), findsOneWidget);
    expect(find.byKey(const Key('importacao-sped-trace')), findsOneWidget);
    expect(find.textContaining('IllegalArgumentException'), findsOneWidget);
    expect(find.byKey(const Key('importacao-sped-copiar-erro')), findsOneWidget);
  });

  // Pedido explicito do usuario: combo de conta bancaria/caixa e centro de
  // custo na propria tela de import, opcionais.
  testWidgets('exibe campos opcionais de conta bancaria e centro de custo', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportacaoSpedCard(
            baseUrl: 'http://localhost',
            empresaIdInicial: '1',
            carregarEmpresas: () async => [
              {'id': '1', 'nome': 'Empresa Smoke Test'},
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('importacao-sped-conta-bancaria')), findsOneWidget);
    expect(find.byKey(const Key('importacao-sped-centro-custo')), findsOneWidget);

    await tester.tap(find.byKey(const Key('importacao-sped-importar')));
    await tester.pump();
    expect(find.text('Selecione um arquivo SPED.'), findsOneWidget);
  });

  // Bug real reportado pelo usuario -- ver comentario completo no teste
  // equivalente de importacao_sintegra_card_test.dart.
  testWidgets(
    'combos de financeiro so carregam depois da empresa ser resolvida via TenantContext',
    (tester) async {
      AuthUtility.userInfo = LoginModel(
        login: LoginInfo(id: 1, empresa: EmpresaRef(id: 7)),
      );
      final idsRecebidosConta = <String?>[];
      final idsRecebidosCentro = <String?>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportacaoSpedCard(
              baseUrl: 'http://localhost',
              carregarEmpresas: () async => [
                {'id': '7', 'nome': 'Empresa do Tenant'},
              ],
              carregarContasBancarias: (empresaId) async {
                idsRecebidosConta.add(empresaId);
                return [
                  {'id': '10', 'nome': 'Conta da empresa 7'},
                ];
              },
              carregarCentrosCusto: (empresaId) async {
                idsRecebidosCentro.add(empresaId);
                return [
                  {'id': '20', 'nome': 'Centro da empresa 7'},
                ];
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(idsRecebidosConta, isNot(contains(null)));
      expect(idsRecebidosCentro, isNot(contains(null)));
      expect(idsRecebidosConta, contains('7'));
      expect(idsRecebidosCentro, contains('7'));
    },
  );
}
