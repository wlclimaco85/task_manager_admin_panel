import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/models/telas_model.dart';
import 'package:task_manager_admin_panel/services/planilha_service.dart';
import 'package:task_manager_admin_panel/utils/campo_tela_tenant.dart';
import 'package:task_manager_admin_panel/utils/planilha_tenant.dart';
import 'package:task_manager_admin_panel/widgets/campos_do_tenant.dart';
import 'package:task_manager_admin_panel/widgets/planilha_view.dart';

class _Falso extends PlanilhaService {
  PlanilhaDados? salvo;

  @override
  Future<List<PlanilhaResumo>> listar() async => const [];

  @override
  Future<PlanilhaDados> salvar(PlanilhaDados p) async {
    salvo = p;
    return PlanilhaDados(id: 1, nome: p.nome, celulas: p.celulas);
  }
}

const _cliente = SessaoTenant(empresa: 7, parceiro: 55);

void main() {
  test('colunas que faltam entram no fim; valor forjado e trocado pelo do login', () {
    final r = fixarTenant({'A1': 'Nome', 'A2': 'Ana'}, _cliente);
    expect(r, {'A1': 'Nome', 'A2': 'Ana', 'B1': 'empresa_id', 'C1': 'parceiro_id', 'B2': '7', 'C2': '55'});
    final f = fixarTenant({'A1': 'empresa_id', 'B1': 'Nome', 'A2': '999', 'B2': 'Ana', 'A3': '999'},
        const SessaoTenant(empresa: 7));
    expect((f['A2'], f['A3'], f.containsValue('parceiro_id')), ('7', null, false));
  });

  test('MASTER so tem os campos vazios preenchidos', () {
    final r = fixarTenant(
        {'A1': 'empresa_id', 'B1': 'Nome', 'A2': '999', 'B2': 'Ana', 'B3': 'Bia'},
        const SessaoTenant(empresa: 7, master: true));
    expect((r['A2'], r['A3']), ('999', '7'));
  });

  Future<_Falso> montar(WidgetTester t, SessaoTenant sessao) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = _Falso();
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: PlanilhaView(servico: s, podeConsultar: false, sessao: sessao))));
    await t.pumpAndSettle();
    return s;
  }

  testWidgets('planilha nova nasce com empresa e parceiro bloqueados e preenchidos', (t) async {
    final s = await montar(t, _cliente);
    // comeca na primeira coluna livre
    await t.enterText(find.byKey(const ValueKey('editor-C1')), 'Nome');
    await t.tap(find.byKey(const ValueKey('C2')));
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('editor-C2')), 'Ana');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('A2')));
    await t.pump();
    final editor = t.widget<TextField>(find.byKey(const ValueKey('editor-A2')));
    expect(editor.readOnly, isTrue);
    expect(t.widget<TextField>(find.byKey(const Key('barra-formula'))).readOnly, isTrue);
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    expect(s.salvo!.celulas,
        {'A1': 'empresa_id', 'B1': 'parceiro_id', 'C1': 'Nome', 'C2': 'Ana', 'A2': '7', 'B2': '55'});
  });

  testWidgets('MASTER pode editar os campos', (t) async {
    await montar(t, const SessaoTenant(empresa: 7, master: true));
    await t.tap(find.byKey(const ValueKey('A1')));
    await t.pump();
    expect(t.widget<TextField>(find.byKey(const ValueKey('editor-A1'))).readOnly, isFalse);
  });

  testWidgets('relatorios e graficos mostram empresa e parceiro bloqueados', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: CamposDoTenant(sessao: _cliente))));
    for (final chave in ['tenant-empresa_id', 'tenant-parceiro_id']) {
      expect(t.widget<TextFormField>(find.byKey(ValueKey(chave))).enabled, isFalse);
    }
  });

  test('campo de parceiro bloqueado em tela recebe o parceiro do login', () {
    TelaField campo(String nome, bool enabled) =>
        TelaField.fromJson({'fieldName': nome, 'label': nome, 'enabled': enabled});
    expect(valorPadraoDoCampo(campo('parceiro_id', false), sessao: _cliente), '55');
    expect(valorPadraoDoCampo(campo('parceiro_id', true), sessao: _cliente), isNull);
    expect(valorPadraoDoCampo(campo('nome', false), sessao: _cliente), isNull);
  });
}
