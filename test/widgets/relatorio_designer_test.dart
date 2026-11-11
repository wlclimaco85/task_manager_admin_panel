import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/services/relatorio_personalizado_service.dart';
import 'package:task_manager_admin_panel/widgets/relatorio_designer_view.dart';

const _colunas = ['nome', 'qtd', 'valor'];

RelLayout _base() => const RelLayout(
      detalhe: RelBanda(altura: 30, elementos: [
        RelElemento(tipo: 'CAMPO', x: 10, y: 5, largura: 100, altura: 14, campo: 'nome'),
      ]),
    );

Future<RelLayout?> _abrir(WidgetTester t, {RelLayout? layout, List<RelColuna> cfg = const [], String orientacao = 'RETRATO'}) async {
  t.view.physicalSize = const Size(1700, 1500);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  RelLayout? aplicado;
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RelatorioDesignerView(
        layout: layout ?? _base(),
        colunas: _colunas,
        orientacao: orientacao,
        titulo: 'Estoque',
        configColunas: cfg,
        onAplicar: (l) => aplicado = l,
        onCancelar: () {},
      ),
    ),
  ));
  await t.pumpAndSettle();
  // devolve via closure: o chamador chama aplicar depois
  _ultimo = () => aplicado;
  return null;
}

RelLayout? Function()? _ultimo;

Future<RelLayout> _aplicar(WidgetTester t) async {
  await t.tap(find.text('Aplicar layout'));
  await t.pumpAndSettle();
  return _ultimo!()!;
}

void main() {
  test('layout inicial: titulo, cabecalho, detalhe com campos, resumo so com colunas somadas e rodape de pagina', () {
    final l = layoutInicial('Estoque', const [
      RelColuna(nome: 'nome', rotulo: 'Produto'),
      RelColuna(nome: 'valor', rotulo: 'Valor', formato: 'MOEDA', total: true),
    ], 'RETRATO');

    expect(l.titulo!.elementos.first.texto, 'Estoque');
    expect(l.cabecalhoPagina!.elementos.map((e) => e.texto), ['Produto', 'Valor']);
    expect(l.detalhe.elementos.map((e) => e.campo), ['nome', 'valor']);
    expect(l.detalhe.elementos.last.alinhamento, 'DIREITA', reason: 'moeda alinha a direita');
    expect(l.resumo!.elementos.where((e) => e.tipo == 'CAMPO').single.agregado, 'SOMA');
    expect(l.rodapePagina!.elementos.single.tipo, 'PAGINA');
    // tudo cabe na largura util (567) e dentro das bandas
    for (final n in RelLayout.nomes) {
      final b = l.banda(n);
      if (b == null) continue;
      for (final e in b.elementos) {
        expect(e.x + e.largura, lessThanOrEqualTo(larguraUtil('RETRATO') + 0.5), reason: '$n/${e.tipo}');
        expect(e.y + e.altura, lessThanOrEqualTo(b.altura + 0.5), reason: '$n/${e.tipo}');
      }
    }
    expect(layoutInicial('x', const [], 'PAISAGEM').resumo, isNull);
    expect(larguraUtil('PAISAGEM'), 786);
  });

  test('modelos serializam ida e volta preservando o layout', () {
    final l = layoutInicial('T', const [RelColuna(nome: 'a', rotulo: 'A', total: true)], 'RETRATO');
    final volta = RelLayout.fromJson(l.toJson());
    expect(volta.detalhe.elementos.single.campo, 'a');
    expect(volta.resumo!.elementos.length, l.resumo!.elementos.length);
    final cfg = RelConfig.fromJson(RelConfig(modo: 'AVANCADO', layout: l).toJson());
    expect(cfg.avancado, isTrue);
    expect(cfg.layout!.titulo!.altura, 40);
    expect(RelConfig.fromJson(null).avancado, isFalse);
    final e = const RelElemento(tipo: 'TEXTO', cor: '#000000').copiar(cor: null, texto: 'oi');
    expect(e.cor, isNull);
    expect(e.texto, 'oi');
  });

  testWidgets('arrastar um elemento move dentro da banda sem sair dela', (t) async {
    await _abrir(t);
    await t.drag(find.byKey(const Key('el_detalhe_0')), const Offset(80, 40));
    await t.pumpAndSettle();
    var l = await _aplicar(t);
    // o reconhecedor de arrasto descarta os primeiros pixels (folga de toque): o movimento e proporcional, nao exato
    expect(l.detalhe.elementos.single.x, allOf(greaterThan(40), lessThan(90)));
    expect(l.detalhe.elementos.single.y, greaterThan(5));

    await t.drag(find.byKey(const Key('el_detalhe_0')), const Offset(2000, 500));
    await t.pumpAndSettle();
    l = await _aplicar(t);
    final e = l.detalhe.elementos.single;
    expect(e.x + e.largura, lessThanOrEqualTo(larguraUtil('RETRATO') + 0.5), reason: 'nao sai pela direita');
    expect(e.y + e.altura, lessThanOrEqualTo(30.5), reason: 'nao sai pela base da banda');
  });

  testWidgets('a alca redimensiona o elemento selecionado', (t) async {
    await _abrir(t);
    await t.tap(find.byKey(const Key('el_detalhe_0')));
    await t.pumpAndSettle();
    await t.drag(find.byKey(const Key('alca_detalhe_0')), const Offset(80, 40));
    await t.pumpAndSettle();
    final e = (await _aplicar(t)).detalhe.elementos.single;
    expect(e.largura, allOf(greaterThan(130), lessThan(190)));
    expect(e.altura, greaterThan(14));
  });

  testWidgets('arrastar uma coluna da paleta para a banda cria um Campo naquela posicao', (t) async {
    await _abrir(t);
    final destino = t.getTopLeft(find.byKey(const Key('altura_detalhe'))); // ancora so para ter referencia
    expect(destino, isNotNull);
    final banda = find.byWidgetPredicate((w) => w is Container && w.constraints?.maxHeight == 30);
    await t.drag(find.byKey(const Key('coluna_valor')), t.getCenter(banda.first) - t.getCenter(find.byKey(const Key('coluna_valor'))));
    await t.pumpAndSettle();

    final els = (await _aplicar(t)).detalhe.elementos;
    expect(els.length, 2);
    expect(els.last.tipo, 'CAMPO');
    expect(els.last.campo, 'valor');
  });

  testWidgets('botoes adicionam elementos na banda selecionada; propriedades editam e remover apaga', (t) async {
    await _abrir(t);
    await t.tap(find.text('+ Texto'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextFormField, 'Texto'), r'Total ${DATA}');
    await t.pumpAndSettle();
    await t.tap(find.text('Negrito'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('cor_Cor_#C62828')));
    await t.pumpAndSettle();

    var l = await _aplicar(t);
    final txt = l.detalhe.elementos.last;
    expect(txt.tipo, 'TEXTO');
    expect(txt.texto, r'Total ${DATA}');
    expect(txt.negrito, isTrue);
    expect(txt.cor, '#C62828');

    await t.tap(find.byKey(const Key('remover_elemento')));
    await t.pumpAndSettle();
    l = await _aplicar(t);
    expect(l.detalhe.elementos.length, 1);
  });

  testWidgets('bandas opcionais ligam e desligam; altura da banda e editavel; layout inicial usa as colunas', (t) async {
    await _abrir(t);
    await t.tap(find.byKey(const Key('banda_titulo')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('altura_titulo')), findsOneWidget);
    await t.enterText(find.byKey(const Key('altura_detalhe')), '40');
    await t.pumpAndSettle();

    var l = await _aplicar(t);
    expect(l.titulo, isNotNull);
    expect(l.detalhe.altura, 40);

    await t.tap(find.byKey(const Key('banda_titulo')));
    await t.pumpAndSettle();
    await t.tap(find.text('Layout inicial'));
    await t.pumpAndSettle();
    l = await _aplicar(t);
    expect(l.detalhe.elementos.map((e) => e.campo), _colunas);
    expect(l.cabecalhoPagina, isNotNull);
    expect(l.rodapePagina, isNotNull);
  });

  testWidgets('largura acima da area util e alca nao lancam excecao; digitar varios digitos mantem o campo', (t) async {
    await _abrir(t);
    await t.tap(find.byKey(const Key('el_detalhe_0')));
    await t.pumpAndSettle();
    final campo = find.widgetWithText(TextFormField, 'Largura');
    await t.enterText(campo, '9');
    await t.pump();
    await t.enterText(campo, '99');
    await t.pump();
    await t.enterText(campo, '9999');
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.drag(find.byKey(const Key('alca_detalhe_0')), const Offset(30, 10));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull, reason: 'clamp com limite abaixo do minimo nao pode lancar');
    final e = (await _aplicar(t)).detalhe.elementos.single;
    expect(e.largura, lessThanOrEqualTo(larguraUtil('RETRATO') + 0.5));
  });
}
