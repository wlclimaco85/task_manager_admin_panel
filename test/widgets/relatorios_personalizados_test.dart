import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/models/network_response.dart';
import 'package:task_manager_admin_panel/services/dashboard_personalizado_service.dart';
import 'package:task_manager_admin_panel/services/modulo_java_service.dart';
import 'package:task_manager_admin_panel/services/relatorio_personalizado_service.dart';
import 'package:task_manager_admin_panel/widgets/relatorio_construtor_view.dart';
import 'package:task_manager_admin_panel/widgets/relatorios_personalizados_view.dart';

class _ServicoFalso extends RelatorioPersonalizadoService {
  List<RelatorioPersonalizado> lista;
  Map<String, dynamic>? parametrosPdf;
  int? idPdf;
  bool falhaPdf = false;
  bool falhaListagem = false;
  final List<RelatorioPersonalizado> salvos = [];
  final List<int> excluidos = [];
  String? erroTeste;

  _ServicoFalso({this.lista = const []});

  @override
  Future<List<RelatorioPersonalizado>> ativos() async {
    if (falhaListagem) throw const ModuloJavaException('Empresa nao identificada');
    return lista;
  }

  @override
  Future<List<RelatorioPersonalizado>> todos() async {
    if (falhaListagem) throw const ModuloJavaException('Somente o usuário MASTER pode alterar relatórios.');
    return lista;
  }

  @override
  Future<RelatorioPersonalizado> buscarComSql(int id) async => lista.firstWhere((r) => r.id == id);

  @override
  Future<PdfRelatorio> gerarPdf(int id, Map<String, dynamic> parametros, {String nomePadrao = 'relatorio.pdf'}) async {
    if (falhaPdf) throw const ModuloJavaException('Valor invalido para o filtro "Quantidade minima"');
    idPdf = id;
    parametrosPdf = parametros;
    return PdfRelatorio(Uint8List.fromList([0x25, 0x50, 0x44, 0x46]), 'Itens.pdf');
  }

  @override
  Future<RelatorioPersonalizado> salvar(RelatorioPersonalizado r) async {
    salvos.add(r);
    return r;
  }

  @override
  Future<void> excluir(int id) async => excluidos.add(id);

  @override
  Future<ResultadoDash> testarSql(String sql, Map<String, dynamic> parametros) async {
    if (erroTeste != null) throw ModuloJavaException(erroTeste!);
    return const ResultadoDash(tipo: 'TABELA', titulo: 'Prévia', colunas: ['nome', 'qtd'], linhas: [['Camisa', 3]]);
  }
}

const _rel = RelatorioPersonalizado(
  id: 5,
  titulo: 'Itens em estoque',
  grupo: 'Estoque',
  descricao: 'Lista de itens',
  filtros: [DashFiltro(nome: 'minimo', descricao: 'Quantidade mínima', tipo: 'INTEIRO', padrao: '0')],
);

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('modelos e utilitarios', () {
    test('nome do arquivo vem do Content-Disposition (inclusive codificado) ou do padrao', () {
      expect(nomeArquivoDoCabecalho('attachment; filename="Itens_em_estoque.pdf"', 'x.pdf'), 'Itens_em_estoque.pdf');
      expect(nomeArquivoDoCabecalho("attachment; filename*=UTF-8''Relat%C3%B3rio.pdf", 'x.pdf'), 'Relatório.pdf');
      expect(nomeArquivoDoCabecalho(null, 'x.pdf'), 'x.pdf');
      expect(nomeArquivoDoCabecalho('inline', 'x.pdf'), 'x.pdf');
    });

    test('relatorio le e escreve o contrato (lista vem como {data:[...]})', () {
      final r = NetworkResponse(true, 200, [
        {
          'id': 5, 'titulo': 'T', 'ativo': true,
          'parametros': [{'nome': 'a', 'descricao': 'A', 'tipo': 'data', 'padrao': 'HOJE'}],
          'config': {'orientacao': 'paisagem', 'agruparPor': 'cat', 'colunas': [{'nome': 'qtd', 'rotulo': 'Q', 'formato': 'numero', 'total': true}]},
        },
      ]);
      final rel = listaDeResposta(r).map(RelatorioPersonalizado.fromJson).single;
      expect(rel.config.orientacao, 'PAISAGEM');
      expect(rel.config.colunas.single.formato, 'NUMERO');
      expect(rel.config.colunas.single.total, isTrue);
      expect(rel.filtros.single.tipo, 'DATA');
      final json = rel.toJson();
      expect((json['config'] as Map)['agruparPor'], 'cat');
      expect((json['parametros'] as List), isNotEmpty);
    });
  });

  group('RelatoriosPersonalizadosView', () {
    testWidgets('lista, abre, envia os filtros ao gerar e entrega o PDF recebido', (t) async {
      final s = _ServicoFalso(lista: const [_rel]);
      PdfRelatorio? entregue;
      await t.pumpWidget(_app(RelatoriosPersonalizadosView(servico: s, salvar: (p) async => entregue = p)));
      await t.pumpAndSettle();

      expect(find.text('Itens em estoque'), findsOneWidget);
      await t.tap(find.text('Itens em estoque'));
      await t.pumpAndSettle();
      expect(find.text('Quantidade mínima'), findsOneWidget);

      await t.enterText(find.widgetWithText(TextField, 'Quantidade mínima'), '4');
      await t.tap(find.text('Gerar PDF'));
      await t.pumpAndSettle();

      expect(s.idPdf, 5);
      expect(s.parametrosPdf, {'minimo': '4'});
      expect(entregue?.nomeArquivo, 'Itens.pdf');
      expect(find.textContaining('Relatório gerado: Itens.pdf'), findsOneWidget);

      await t.tap(find.byTooltip('Voltar'));
      await t.pumpAndSettle();
      expect(find.text('Relatórios'), findsOneWidget);
    });

    testWidgets('erro do servidor ao gerar aparece e nada e entregue', (t) async {
      final s = _ServicoFalso(lista: const [_rel])..falhaPdf = true;
      PdfRelatorio? entregue;
      await t.pumpWidget(_app(RelatoriosPersonalizadosView(servico: s, salvar: (p) async => entregue = p)));
      await t.pumpAndSettle();
      await t.tap(find.text('Itens em estoque'));
      await t.pumpAndSettle();
      await t.tap(find.text('Gerar PDF'));
      await t.pumpAndSettle();

      expect(find.textContaining('Valor invalido para o filtro'), findsOneWidget);
      expect(entregue, isNull);
    });

    testWidgets('erro ao listar aparece em vez de lista vazia', (t) async {
      await t.pumpWidget(_app(RelatoriosPersonalizadosView(servico: _ServicoFalso()..falhaListagem = true)));
      await t.pumpAndSettle();
      expect(find.text('Empresa nao identificada'), findsOneWidget);
    });
  });

  group('RelatorioConstrutorView', () {
    testWidgets('lista, exclui com confirmacao e mostra erro de permissao', (t) async {
      final s = _ServicoFalso(lista: const [_rel]);
      await t.pumpWidget(_app(RelatorioConstrutorView(servico: s)));
      await t.pumpAndSettle();
      expect(find.text('Estoque'), findsOneWidget);
      await t.tap(find.byTooltip('Excluir'));
      await t.pumpAndSettle();
      await t.tap(find.text('Excluir').last);
      await t.pumpAndSettle();
      expect(s.excluidos, [5]);

      await t.pumpWidget(_app(RelatorioConstrutorView(key: const ValueKey('erro'), servico: _ServicoFalso()..falhaListagem = true)));
      await t.pumpAndSettle();
      expect(find.textContaining('Somente o usuário MASTER'), findsOneWidget);
    });

    testWidgets('novo relatorio: valida, testa (erro e previa), carrega colunas, configura e salva', (t) async {
      t.view.physicalSize = const Size(1500, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final s = _ServicoFalso();
      await t.pumpWidget(_app(RelatorioConstrutorView(servico: s)));
      await t.pumpAndSettle();

      await t.tap(find.text('Novo relatório'));
      await t.pumpAndSettle();
      await t.tap(find.text('Salvar'));
      await t.pumpAndSettle();
      expect(find.text('Informe o título'), findsOneWidget);
      expect(find.text('Informe o SQL'), findsOneWidget);
      expect(s.salvos, isEmpty);

      await t.enterText(find.widgetWithText(TextFormField, 'Título *'), 'Estoque');
      await t.enterText(find.widgetWithText(TextFormField, 'SQL (SELECT) *'), 'SELECT nome, qtd FROM item WHERE empresa_id = :empresaId');

      s.erroTeste = 'Palavra/funcao nao permitida no SQL: delete';
      await t.tap(find.text('Testar'));
      await t.pumpAndSettle();
      expect(find.text('Palavra/funcao nao permitida no SQL: delete'), findsOneWidget);

      s.erroTeste = null;
      await t.tap(find.text('Testar'));
      await t.pumpAndSettle();
      expect(find.text('Camisa'), findsOneWidget);
      await t.tap(find.text('Carregar colunas'));
      await t.pumpAndSettle();
      expect(find.text('Formato'), findsNWidgets(2), reason: 'uma linha de configuracao por coluna do SQL');

      await t.tap(find.text('Somar').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Salvar'));
      await t.pumpAndSettle();

      final r = s.salvos.single;
      expect(r.titulo, 'Estoque');
      expect(r.sql, 'SELECT nome, qtd FROM item WHERE empresa_id = :empresaId');
      expect(r.config.orientacao, 'RETRATO');
      expect(r.config.colunas.map((c) => c.nome), ['nome', 'qtd']);
      expect(r.config.colunas.first.rotulo, 'Nome');
      expect(r.config.colunas.last.total, isTrue);
      expect(r.config.colunas.first.total, isFalse);
    });

  testWidgets('modo Avancado: exige colunas, abre o designer, aplica o layout e salva com modo e layout', (t) async {
    t.view.physicalSize = const Size(1700, 3200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = _ServicoFalso();
    await t.pumpWidget(_app(RelatorioConstrutorView(servico: s)));
    await t.pumpAndSettle();
    await t.tap(find.text('Novo relatório'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextFormField, 'Título *'), 'Estoque');
    await t.enterText(find.widgetWithText(TextFormField, 'SQL (SELECT) *'), 'SELECT nome, qtd FROM item WHERE empresa_id = :empresaId');

    await t.tap(find.text('Avançado (designer)'));
    await t.pumpAndSettle();
    await t.tap(find.text('Abrir designer'));
    await t.pumpAndSettle();
    expect(find.text('Use Testar e Carregar colunas antes de abrir o designer.'), findsOneWidget);
    await t.pump(const Duration(seconds: 6)); // deixa o aviso sair do caminho
    await t.pumpAndSettle();

    await t.tap(find.text('Testar'));
    await t.pumpAndSettle();
    await t.tap(find.text('Carregar colunas'));
    await t.pumpAndSettle();
    await t.tap(find.text('Abrir designer'));
    await t.pumpAndSettle();
    expect(find.text('Designer do relatório'), findsOneWidget);
    await t.tap(find.text('Layout inicial'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Aplicar layout'));
    await t.pumpAndSettle();
    expect(find.text('Designer do relatório'), findsNothing, reason: 'o designer fecha ao aplicar');
    expect(find.text('Layout definido'), findsOneWidget);

    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    final r = s.salvos.single;
    expect(r.config.modo, 'AVANCADO');
    expect(r.config.layout!.detalhe.elementos.map((e) => e.campo), ['nome', 'qtd']);
    expect(r.config.layout!.cabecalhoPagina!.elementos.length, 2);
  });
  });
}
