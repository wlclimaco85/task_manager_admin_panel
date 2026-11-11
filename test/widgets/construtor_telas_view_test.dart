import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/models/network_response.dart';
import 'package:task_manager_admin_panel/services/construtor_telas_service.dart';
import 'package:task_manager_admin_panel/services/modulo_java_service.dart';
import 'package:task_manager_admin_panel/widgets/construtor_telas_view.dart';

class _ServicoFalso extends ConstrutorTelasService {
  List<TelaConstruida> telas;
  final List<TabelaDisponivel> tabelasDisp;
  final List<List<String>> criadas = [];
  final List<int> excluidas = [];
  final List<List<Object>> alternadas = [];
  bool falhaListagem = false;
  bool falhaCriar = false;

  _ServicoFalso({this.telas = const [], this.tabelasDisp = const []});

  @override
  Future<List<TelaConstruida>> todas() async {
    if (falhaListagem) throw const ModuloJavaException('Somente o usuário MASTER pode usar o Construtor de Telas.');
    return telas;
  }

  @override
  Future<List<TelaConstruida>> ativas() async => telas.where((t) => t.ativo).toList();

  @override
  Future<List<TabelaDisponivel>> tabelas() async => tabelasDisp;

  @override
  Future<TelaConstruida> criar(String tabela, String titulo) async {
    if (falhaCriar) throw const ModuloJavaException('Ja existe uma tela para esta tabela');
    criadas.add([tabela, titulo]);
    final t = TelaConstruida(id: 9, telaNome: 'c7_$tabela', tabelaNome: tabela, titulo: titulo);
    telas = [...telas, t];
    return t;
  }

  @override
  Future<TelaConstruida> atualizar(int id, {String? titulo, bool? ativo}) async {
    alternadas.add([id, ativo ?? false]);
    telas = [for (final t in telas) t.id == id ? TelaConstruida(id: t.id, telaNome: t.telaNome, tabelaNome: t.tabelaNome, titulo: t.titulo, ativo: ativo ?? t.ativo) : t];
    return telas.firstWhere((t) => t.id == id);
  }

  @override
  Future<void> excluir(int id) async {
    excluidas.add(id);
    telas = telas.where((t) => t.id != id).toList();
  }
}

const _tela = TelaConstruida(id: 1, telaNome: 'c7_item', tabelaNome: 'item', titulo: 'Itens');

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  test('modelos leem o contrato do backend; lista JSON vem como {data:[...]}', () {
    final r = NetworkResponse(true, 200, [
      {'id': 4, 'telaNome': 'c7_item', 'tabelaNome': 'item', 'titulo': 'Itens', 'ativo': false},
    ]);
    final t = listaDeResposta(r).map(TelaConstruida.fromJson).single;
    expect(t.telaNome, 'c7_item');
    expect(t.ativo, isFalse);
    expect(TabelaDisponivel.fromJson({'nome': 'item', 'colunas': 7}).colunas, 7);
  });

  testWidgets('lista as telas, abre, desativa e exclui com confirmacao', (tester) async {
    final s = _ServicoFalso(telas: const [_tela]);
    TelaConstruida? aberta;
    await tester.pumpWidget(_app(ConstrutorTelasView(servico: s, abrir: (c, t) => aberta = t)));
    await tester.pumpAndSettle();

    expect(find.text('Itens'), findsOneWidget);
    expect(find.text('Tabela item'), findsOneWidget);
    await tester.tap(find.byTooltip('Abrir'));
    expect(aberta?.telaNome, 'c7_item');

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(s.alternadas.single, [1, false]);
    expect(find.textContaining('desativada'), findsOneWidget);
    expect(find.byTooltip('Abrir'), findsNothing, reason: 'tela desativada nao abre');

    await tester.tap(find.byTooltip('Excluir'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Os dados da tabela item não são apagados'), findsOneWidget);
    await tester.tap(find.text('Excluir').last);
    await tester.pumpAndSettle();
    expect(s.excluidas, [1]);
    expect(find.text('Nenhuma tela criada ainda.'), findsOneWidget);
  });

  testWidgets('nova tela: exige tabela e titulo, sugere o titulo, cria e mostra erro do servidor', (tester) async {
    final s = _ServicoFalso(tabelasDisp: const [TabelaDisponivel('item', 7), TabelaDisponivel('cliente_obs', 4)]);
    await tester.pumpWidget(_app(ConstrutorTelasView(servico: s)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nova tela'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Criar'));
    await tester.pumpAndSettle();
    expect(find.text('Escolha a tabela.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Buscar tabela'), 'obs');
    await tester.pumpAndSettle();
    expect(find.text('item'), findsNothing);
    await tester.tap(find.text('cliente_obs'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Título da tela *'), findsOneWidget);
    expect((tester.widget<TextField>(find.widgetWithText(TextField, 'Título da tela *')).controller!).text, 'Cliente obs');

    s.falhaCriar = true;
    await tester.tap(find.text('Criar'));
    await tester.pumpAndSettle();
    expect(find.text('Ja existe uma tela para esta tabela'), findsOneWidget);
    expect(s.criadas, isEmpty);

    s.falhaCriar = false;
    await tester.tap(find.text('Nova tela'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Criar'));
    await tester.pumpAndSettle();
    expect(s.criadas.single, ['item', 'Item']);
    expect(find.textContaining('Tela criada'), findsOneWidget);
  });

  testWidgets('erro de permissao do servidor aparece em vez de lista vazia', (tester) async {
    await tester.pumpWidget(_app(ConstrutorTelasView(servico: _ServicoFalso()..falhaListagem = true)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Somente o usuário MASTER'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Telas Personalizadas lista so as ativas e abre a escolhida', (tester) async {
    final s = _ServicoFalso(telas: const [
      _tela,
      TelaConstruida(id: 2, telaNome: 'c7_off', tabelaNome: 'off', titulo: 'Desligada', ativo: false),
    ]);
    TelaConstruida? aberta;
    await tester.pumpWidget(_app(TelasPersonalizadasView(servico: s, abrir: (c, t) => aberta = t)));
    await tester.pumpAndSettle();

    expect(find.text('Desligada'), findsNothing);
    await tester.tap(find.text('Itens'));
    expect(aberta?.tabelaNome, 'item');
  });
}
