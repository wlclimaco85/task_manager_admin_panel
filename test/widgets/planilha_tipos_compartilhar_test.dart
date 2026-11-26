import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/services/planilha_service.dart';
import 'package:task_manager_admin_panel/utils/planilha_tipos.dart';
import 'package:task_manager_admin_panel/widgets/planilha_view.dart';

class _Falso extends PlanilhaService {
  _Falso(this.aberta);

  final PlanilhaDados aberta;
  PlanilhaDados? salvo;
  CompartilhamentoPlanilha? compartilhado;

  @override
  Future<List<PlanilhaResumo>> listar() async => const [PlanilhaResumo(1, 'Parceiros')];

  @override
  Future<PlanilhaDados> abrir(int id) async => aberta;

  @override
  Future<PlanilhaDados> salvar(PlanilhaDados p) async {
    salvo = p;
    return PlanilhaDados(id: 2, nome: p.nome, celulas: p.celulas, colunas: p.colunas, versao: 5);
  }

  @override
  Future<List<UsuarioCompartilhar>> usuarios() async =>
      const [UsuarioCompartilhar(10, 'Bia', 'bia@x'), UsuarioCompartilhar(11, 'Caio', 'caio@x')];

  @override
  Future<CompartilhamentoPlanilha> compartilhamento(int id) async =>
      const CompartilhamentoPlanilha(usuarios: {99: true});

  @override
  Future<CompartilhamentoPlanilha> compartilhar(int id, CompartilhamentoPlanilha c) async => compartilhado = c;
}

const _dados = PlanilhaDados(
  id: 1,
  nome: 'Parceiros',
  versao: 4,
  celulas: {'A1': 'Nome', 'B1': 'Ativo', 'C1': 'Situação', 'D1': 'Valor', 'A2': 'Ana', 'D2': '1.500', 'D3': '=D2+0.5'},
  colunas: {
    'B': ColunaPlanilha('check'),
    'C': ColunaPlanilha('lista', opcoes: ['Nova', 'Paga']),
    'D': ColunaPlanilha('soma'),
  },
);

void main() {
  Future<_Falso> abrir(WidgetTester t, PlanilhaDados d, {Size tela = const Size(1600, 900)}) async {
    t.view.physicalSize = tela;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = _Falso(d);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: PlanilhaView(servico: s, podeConsultar: false))));
    await t.pumpAndSettle();
    await t.tap(find.byType(DropdownButtonFormField<int>));
    await t.pumpAndSettle();
    await t.tap(find.text('Parceiros').last);
    await t.pumpAndSettle();
    return s;
  }

  test('valores do banco entram no formato da coluna', () {
    const lista = TipoDaFonte(ColunaPlanilha('lista', opcoes: ['Ativo']), {'A': 'Ativo'});
    expect(valorDaFonte('A', lista), 'Ativo');
    expect(valorDaFonte(true, const TipoDaFonte(ColunaPlanilha('check'))), 'Sim');
    expect(valorDaFonte('2026-11-26T10:00:00', const TipoDaFonte(ColunaPlanilha('data'))), '26/11/2026');
    expect(valorDaFonte('=1+1', null), '=1+1');
  });

  testWidgets('caixa de marcar, lista e soma funcionam e sao salvas com a versao', (t) async {
    final s = await abrir(t, _dados);
    expect(find.text('3000,5'), findsOneWidget, reason: 'soma de 1.500 e 1500,5');
    expect(find.byKey(const ValueKey('check-B1')), findsNothing, reason: 'linha 1 e titulo');

    await t.tap(find.byKey(const ValueKey('check-B2')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('C2')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('escolher-C2')));
    await t.pumpAndSettle();
    await t.tap(find.text('Paga'));
    await t.pumpAndSettle();
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();

    expect(s.salvo!.celulas['B2'], 'Sim');
    expect(s.salvo!.celulas['C2'], 'Paga');
    expect(s.salvo!.versao, 4);
    expect(s.salvo!.id, 1);
    expect(s.salvo!.colunas.keys, containsAll(['B', 'C', 'D']));
  });

  testWidgets('compartilhada so para consulta: salva copia, sem excluir nem compartilhar', (t) async {
    final s = await abrir(
        t,
        const PlanilhaDados(
            id: 1, nome: 'Parceiros', versao: 4, celulas: {'A1': 'N'}, dono: false, podeEditar: false));
    expect(find.text('Compartilhada com você: só consulta'), findsOneWidget);
    expect(find.text('Compartilhar'), findsNothing);
    expect(t.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.delete_outline)).onPressed, isNull);
    await t.tap(find.text('Salvar cópia'));
    await t.pumpAndSettle();
    expect(s.salvo!.id, isNull);
    expect(s.salvo!.versao, isNull);
  });

  testWidgets('compartilhar com um usuario que edita; usuario inexistente sai da lista', (t) async {
    final s = await abrir(t, _dados);
    await t.ensureVisible(find.text('Compartilhar'));
    await t.tap(find.text('Compartilhar'));
    await t.pumpAndSettle();
    await t.tap(find.byType(Checkbox).last); // Caio
    await t.pumpAndSettle();
    await t.tap(find.text('Só ver').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Editar').last);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Salvar').last);
    await t.pumpAndSettle();
    expect(s.compartilhado!.todos, isNull);
    expect(s.compartilhado!.usuarios, {11: true});
  });

  testWidgets('cabe no celular com colunas tipadas', (t) async {
    await abrir(t, _dados, tela: const Size(375, 740));
    expect(t.takeException(), isNull);
  });
}
