import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/services/acao_java_service.dart';
import 'package:task_manager_admin_panel/services/planilha_service.dart';
import 'package:task_manager_admin_panel/utils/planilha_acrescentar.dart';
import 'package:task_manager_admin_panel/utils/planilha_tenant.dart';
import 'package:task_manager_admin_panel/widgets/planilha_view.dart';

class _Planilhas extends PlanilhaService {
  final resposta = Completer<Map<String, dynamic>>();
  int chamadas = 0;

  @override
  Future<List<PlanilhaResumo>> listar() async => const [PlanilhaResumo(1, 'Clientes')];

  @override
  Future<PlanilhaDados> abrir(int id) async =>
      const PlanilhaDados(id: 1, nome: 'Clientes', celulas: {'A1': 'Nome', 'A2': 'Ana'});

  @override
  Future<Map<String, dynamic>> executarBotao(
      int planilhaId, int acaoId, List<Map<String, dynamic>> linhas, Map<String, dynamic> parametros) {
    chamadas++;
    return resposta.future;
  }
}

class _Acoes extends AcaoJavaService {
  @override
  Future<List<AcaoJava>> listarAtivas(String telaNome) async => telaNome == 'planilha:1'
      ? const [AcaoJava(id: 9, telaNome: 'planilha:1', label: 'Conferir', tabelaNome: 'planilha', exigeSelecao: false)]
      : const [];
}

void main() {
  test('importar acrescentando recusa dado sem titulo e titulo repetido', () {
    const atual = {'A1': 'Nome', 'A2': 'Ana'};
    for (final arquivo in const [
      {'A1': 'Nome', 'A2': 'Bia', 'B2': 'sem titulo'},
      {'A1': 'Nome', 'B1': 'nome', 'A2': 'Bia', 'B2': 'Bea'},
    ]) {
      expect(() => acrescentarLinhas(atual, arquivo), throwsA(isA<AcrescentarException>()));
    }
  });

  Future<void> montar(WidgetTester t, _Planilhas s, {SessaoTenant sessao = const SessaoTenant()}) async {
    t.view.physicalSize = const Size(1800, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(body: PlanilhaView(servico: s, acoes: _Acoes(), podeConsultar: false, sessao: sessao))));
    await t.pumpAndSettle();
  }

  testWidgets('digitar durante a execucao do botao nao se perde e o segundo clique e ignorado', (t) async {
    final s = _Planilhas();
    await montar(t, s);
    await t.tap(find.byType(DropdownButtonFormField<int>));
    await t.pumpAndSettle();
    await t.tap(find.text('Clientes').last);
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Conferir'));
    await t.tap(find.text('Conferir'));
    await t.pumpAndSettle();
    await t.tap(find.text('Executar'));
    await t.pumpAndSettle();
    await t.tap(find.text('Conferir'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('A3')));
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('editor-A3')), 'digitado');
    await t.pump();
    s.resposta.complete({
      'sucesso': true,
      'mensagem': 'ok',
      'alteracoes': [
        {'linha': 2, 'coluna': 'Situação', 'valor': 'OK'}
      ]
    });
    await t.pumpAndSettle();
    expect(s.chamadas, 1);
    expect(find.text('digitado'), findsWidgets);
    expect(find.text('OK'), findsOneWidget);
  });

  testWidgets('titulo de tenant em coluna com dados e recusado', (t) async {
    await montar(t, _Planilhas(), sessao: const SessaoTenant(empresa: 7));
    await t.tap(find.byKey(const ValueKey('B2')));
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('editor-B2')), 'valor meu');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('B1')));
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('editor-B1')), 'empresa_id');
    await t.pumpAndSettle();
    expect(find.text('valor meu'), findsOneWidget);
    expect(find.textContaining('já tem dados'), findsOneWidget);
  });
}
