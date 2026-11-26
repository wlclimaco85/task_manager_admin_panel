import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/services/planilha_service.dart';
import 'package:task_manager_admin_panel/widgets/planilha_view.dart';

class _Falso extends PlanilhaService {
  PlanilhaDados? salvo;
  String? sql;

  @override
  Future<List<FontePlanilha>> fontes() async => const [FontePlanilha('produto', 'Produtos')];

  @override
  Future<Map<String, String>> campos(String tabela) async => const {'id': 'Código', 'nome': 'Nome do produto'};

  @override
  Future<ConsultaPlanilha> consultar(String consulta) async {
    sql = consulta;
    return const ConsultaPlanilha(['nome'], [
      ['=Café']
    ], false);
  }

  @override
  Future<List<PlanilhaResumo>> listar() async => const [];

  @override
  Future<PlanilhaDados> salvar(PlanilhaDados p) async {
    salvo = p;
    return PlanilhaDados(id: 1, nome: p.nome, celulas: p.celulas);
  }
}

void main() {
  Future<void> montar(WidgetTester t, _Falso s, {required bool master}) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: PlanilhaView(servico: s, podeConsultar: master))));
    await t.pumpAndSettle();
  }

  testWidgets('digita, calcula formula e salva', (t) async {
    final s = _Falso();
    await montar(t, s, master: false);
    await t.enterText(find.byKey(const ValueKey('editor-A1')), '40');
    await t.tap(find.byKey(const ValueKey('B1')));
    await t.pump();
    await t.enterText(find.byKey(const Key('barra-formula')), '=A1+2');
    await t.tap(find.byKey(const ValueKey('C1')));
    await t.pump();
    expect(find.text('42'), findsOneWidget);
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    expect(s.salvo!.celulas, {'A1': '40', 'B1': '=A1+2'});
    expect(find.text('Dados do sistema'), findsNothing);
  });

  testWidgets('dados do sistema: monta o SELECT e usa os rotulos do dicionario', (t) async {
    final s = _Falso();
    await montar(t, s, master: true);
    await t.tap(find.text('Dados do sistema'));
    await t.pumpAndSettle();
    await t.tap(find.byType(DropdownMenu<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('Produtos (produto)').last);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilterChip, 'Código'));
    await t.pump();
    await t.tap(find.text('Consultar'));
    await t.pumpAndSettle();
    expect(s.sql, 'SELECT nome\nFROM produto\nWHERE empresa_id = :empresaId');
    await t.tap(find.text('Inserir na célula'));
    await t.pumpAndSettle();
    expect(find.text('Nome do produto'), findsWidgets); // A1 selecionada: aparece na celula e na barra
    expect(find.text('=Café'), findsOneWidget);
  });

  testWidgets('cabe em tela de celular sem estouro', (t) async {
    await montar(t, _Falso(), master: true);
    t.view.physicalSize = const Size(375, 740);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('MASTER ve os dados do sistema', (t) async {
    await montar(t, _Falso(), master: true);
    expect(find.text('Dados do sistema'), findsOneWidget);
  });
}
