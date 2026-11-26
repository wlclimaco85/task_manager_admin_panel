import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/services/acao_java_service.dart';
import 'package:task_manager_admin_panel/services/planilha_service.dart';
import 'package:task_manager_admin_panel/utils/planilha_acao.dart';
import 'package:task_manager_admin_panel/widgets/planilha_view.dart';

class _Planilhas extends PlanilhaService {
  List<Map<String, dynamic>>? enviadas;
  int? acaoChamada;

  @override
  Future<List<PlanilhaResumo>> listar() async => const [PlanilhaResumo(1, 'Clientes')];

  @override
  Future<PlanilhaDados> abrir(int id) async =>
      const PlanilhaDados(id: 1, nome: 'Clientes', celulas: {'A1': 'Nome', 'A2': 'Ana', 'A3': 'Bia'});

  @override
  Future<Map<String, dynamic>> executarBotao(
      int planilhaId, int acaoId, List<Map<String, dynamic>> linhas, Map<String, dynamic> parametros) async {
    acaoChamada = acaoId;
    enviadas = linhas;
    return {
      'sucesso': true,
      'mensagem': 'ok',
      'alteracoes': [
        {'linha': 3, 'coluna': 'Situação', 'valor': '=1+1'}
      ]
    };
  }
}

class _Acoes extends AcaoJavaService {
  @override
  Future<List<AcaoJava>> listarAtivas(String telaNome) async => telaNome == 'planilha:1'
      ? const [AcaoJava(id: 9, telaNome: 'planilha:1', label: 'Conferir', tabelaNome: 'planilha')]
      : const [];
}

void main() {
  test('linhas para a acao, codigos e aplicacao das alteracoes', () {
    const celulas = {'A1': 'Código', 'B1': 'Nome', 'A2': '7', 'B2': 'Ana', 'B4': '=1+1'};
    final linhas = linhasParaAcao(celulas);
    expect(linhas, [
      {'_linha': 2, 'Código': '7', 'Nome': 'Ana'},
      {'_linha': 4, 'Código': '', 'Nome': '2'},
    ]);
    expect(linhasParaAcao(celulas, linha: 2), hasLength(1));
    expect(codigosDaColuna(linhas, 'id'), ['7']);
    expect(codigosDaColuna(linhas, 'cnpj'), isNull);

    final r = aplicarAlteracoes(celulas, const [
      AlteracaoDeCelula(2, 'nome', 'Ana Maria'),
      AlteracaoDeCelula(4, 'Situação', 'OK'),
      AlteracaoDeCelula(1, 'Nome', 'nao altera titulo'),
    ])!;
    expect((r['B2'], r['C1'], r['C4'], r['B1']), ('Ana Maria', 'Situação', 'OK', 'Nome'));
  });

  testWidgets('botao envia as linhas e preenche a celula sem virar formula', (t) async {
    t.view.physicalSize = const Size(1800, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = _Planilhas();
    await t.pumpWidget(MaterialApp(
        home: Scaffold(body: PlanilhaView(servico: s, acoes: _Acoes(), podeConsultar: false))));
    await t.pumpAndSettle();
    await t.tap(find.byType(DropdownButtonFormField<int>));
    await t.pumpAndSettle();
    await t.tap(find.text('Clientes').last);
    await t.pumpAndSettle();
    expect(find.text('Botões'), findsNothing, reason: 'so o MASTER cadastra');

    await t.ensureVisible(find.text('Conferir'));
    await t.tap(find.text('Conferir'));
    await t.pumpAndSettle();
    await t.tap(find.text('Todas as linhas com dados'));
    await t.pumpAndSettle();
    await t.tap(find.text('Executar'));
    await t.pumpAndSettle();

    expect(s.acaoChamada, 9);
    expect(s.enviadas, [
      {'_linha': 2, 'Nome': 'Ana'},
      {'_linha': 3, 'Nome': 'Bia'},
    ]);
    expect(find.text('Situação'), findsOneWidget);
    expect(find.text('=1+1'), findsOneWidget, reason: 'texto da rotina nunca vira formula');
  });
}
