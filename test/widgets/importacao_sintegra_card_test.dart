import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/models/login_model.dart';
import 'package:task_manager_admin_panel/services/auth_utility.dart';
import 'package:task_manager_admin_panel/widgets/importacao_sintegra_card.dart';

void main() {
  tearDown(() {
    AuthUtility.userInfo = null;
  });


  testWidgets('exige empresa antes de importar SINTEGRA', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportacaoSintegraCard(
            baseUrl: 'http://localhost',
            carregarEmpresas: () async => [
              {'id': '1', 'nome': 'Empresa Smoke Test'},
            ],
            arquivoInicial: PlatformFile(
              name: 'sintegra.txt',
              size: 3,
              bytes: Uint8List.fromList([49, 48, 32]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('importacao-sintegra-importar')));
    await tester.pump();

    expect(find.text('Selecione a empresa antes de importar.'), findsOneWidget);
  });

  testWidgets('exibe resumo retornado pela importacao SINTEGRA', (
    tester,
  ) async {
    String? empresaEnviada;
    String? arquivoEnviado;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportacaoSintegraCard(
            baseUrl: 'http://localhost',
            empresaIdInicial: '1',
            carregarEmpresas: () async => [
              {'id': '1', 'nome': 'Empresa Smoke Test'},
            ],
            arquivoInicial: PlatformFile(
              name: 'sintegra.txt',
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
                'ignorados': ['Registro 60: 1 linha sem destino seguro.'],
              };
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('importacao-sintegra-importar')));
    await tester.pumpAndSettle();

    expect(empresaEnviada, '1');
    expect(arquivoEnviado, 'sintegra.txt');
    expect(find.byKey(const Key('importacao-sintegra-resumo')), findsOneWidget);
    expect(find.text('Entradas: 1'), findsOneWidget);
    expect(find.text('Itens: 2'), findsOneWidget);
    expect(find.text('Financeiro pendente: 1'), findsOneWidget);
    expect(
      find.text('Registro 60: 1 linha sem destino seguro.'),
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
          body: ImportacaoSintegraCard(
            baseUrl: 'http://localhost',
            empresaIdInicial: '1',
            carregarEmpresas: () async => [
              {'id': '1', 'nome': 'Empresa Smoke Test'},
            ],
            arquivoInicial: PlatformFile(
              name: 'sintegra.txt',
              size: 3,
              bytes: Uint8List.fromList([49, 48, 32]),
            ),
            importar: (empresaId, arquivo) async {
              throw ErroImportacaoComTrace(
                'falha simulada de parsing',
                'java.lang.RuntimeException: falha simulada de parsing\n\tat Foo.bar(Foo.java:1)',
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('importacao-sintegra-importar')));
    await tester.pumpAndSettle();

    expect(find.text('falha simulada de parsing'), findsOneWidget);
    expect(find.byKey(const Key('importacao-sintegra-trace')), findsOneWidget);
    expect(find.textContaining('RuntimeException'), findsOneWidget);
    expect(find.byKey(const Key('importacao-sintegra-copiar-erro')), findsOneWidget);
  });

  // Pedido explicito do usuario: combo de conta bancaria/caixa e centro de
  // custo na propria tela de import, opcionais (usados so quando a empresa
  // nao tem defaults financeiros configurados).
  testWidgets('exibe campos opcionais de conta bancaria e centro de custo', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportacaoSintegraCard(
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

    expect(find.byKey(const Key('importacao-sintegra-conta-bancaria')), findsOneWidget);
    expect(find.byKey(const Key('importacao-sintegra-centro-custo')), findsOneWidget);

    // Sao opcionais -- importar sem escolher nenhum dos dois nao deve
    // travar por causa desses campos (bloqueio de arquivo ausente e' outro).
    await tester.tap(find.byKey(const Key('importacao-sintegra-importar')));
    await tester.pump();
    expect(find.text('Selecione um arquivo SINTEGRA.'), findsOneWidget);
  });

  // Bug real reportado pelo usuario: os combos de conta bancaria/centro de
  // custo traziam TODAS as empresas, nao so as da empresa selecionada.
  // Causa raiz: quando a empresa e' resolvida via TenantContext (sem
  // empresaIdInicial explicito), o carregamento dos combos disparava em
  // paralelo com _carregarEmpresas() no initState -- rodava ANTES do id
  // ser resolvido, entao ia sem filtro nenhum de empresa.
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
            body: ImportacaoSintegraCard(
              baseUrl: 'http://localhost',
              carregarEmpresas: () async => [
                {'id': '7', 'nome': 'Empresa do Tenant'},
              ],
              carregarContasBancarias: (empresaId, parceiroId) async {
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

  // Bug real reportado pelo usuario: o combo de conta bancaria trazia TODOS
  // os parceiros da empresa ("Conta Padrao do Parceiro" repetido varias
  // vezes) em vez de so as contas do parceiro do proprio arquivo. Verifica
  // que, ao identificar o parceiro (via CNPJ do arquivo), o combo de conta
  // bancaria e' recarregado com esse parceiroId -- centro de custo continua
  // so por empresa (nao tem campo parceiro no schema).
  testWidgets(
    'identifica o parceiro do arquivo e filtra o combo de conta bancaria por ele',
    (tester) async {
      final idsParceiroRecebidosConta = <String?>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportacaoSintegraCard(
              baseUrl: 'http://localhost',
              empresaIdInicial: '1',
              carregarEmpresas: () async => [
                {'id': '1', 'nome': 'Empresa Smoke Test'},
              ],
              identificarParceiro: (empresaId, arquivo) async => {
                'parceiroId': '55',
                'parceiroNome': 'Fornecedor Lana',
              },
              carregarContasBancarias: (empresaId, parceiroId) async {
                idsParceiroRecebidosConta.add(parceiroId);
                return [
                  {'id': '10', 'nome': 'Conta do parceiro 55'},
                ];
              },
              carregarCentrosCusto: (empresaId) async => [
                {'id': '20', 'nome': 'Centro qualquer'},
              ],
              arquivoInicial: PlatformFile(
                name: 'sintegra.txt',
                size: 3,
                bytes: Uint8List.fromList([49, 48, 32]),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(idsParceiroRecebidosConta, contains('55'));
      expect(
        find.byKey(const Key('importacao-sintegra-parceiro-identificado')),
        findsOneWidget,
      );
      expect(find.textContaining('Fornecedor Lana'), findsOneWidget);
    },
  );
}
