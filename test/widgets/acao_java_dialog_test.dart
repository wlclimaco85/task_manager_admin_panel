import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/models/network_response.dart';
import 'package:task_manager_admin_panel/services/acao_java_service.dart';
import 'package:task_manager_admin_panel/services/modulo_java_service.dart';
import 'package:task_manager_admin_panel/widgets/acao_java_dialog.dart';

class _ServicoFalso extends AcaoJavaService {
  int? acaoId;
  List<Object?>? idsRecebidos;
  Map<String, dynamic>? parametrosRecebidos;
  AcaoJavaResultado resposta =
      const AcaoJavaResultado(sucesso: true, mensagem: 'Feito', recarregar: true);
  bool falha = false;

  @override
  Future<AcaoJavaResultado> executar(
      int acaoId, List<Object?> ids, Map<String, dynamic> parametros) async {
    if (falha) throw const ModuloJavaException('Falha do servidor');
    this.acaoId = acaoId;
    idsRecebidos = ids;
    parametrosRecebidos = parametros;
    return resposta;
  }
}

const _acaoComParams = AcaoJava(
  id: 5,
  telaNome: 'produto',
  label: 'Renomear',
  moduloJavaId: 8,
  classe: 'a.B',
  tabelaNome: 'produto',
  params: [
    AcaoJavaParam(descricao: 'Novo nome', nome: 'novoNome', obrigatorio: true),
    AcaoJavaParam(descricao: 'Quantidade', nome: 'qtd', tipo: 'INTEIRO'),
  ],
);

Future<bool?> _abrir(WidgetTester tester, AcaoJava acao, _ServicoFalso s,
    {List<Map<String, dynamic>>? linhas}) async {
  bool? resultado;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async => resultado = await executarAcaoJava(
              context, acao, linhas ?? [{'id': 1}, {'id': 2}],
              servico: s),
          child: const Text('abrir'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return resultado;
}

void main() {
  group('modelos e respostas', () {
    test('lista JSON do servidor chega como {data: [...]} e e reconstruida', () {
      final r = NetworkResponse(true, 200, [
        {'id': 1, 'label': 'A', 'telaNome': 't', 'params': [{'nome': 'x', 'descricao': 'X', 'tipo': 'lista', 'opcoes': 'a; b;c'}]},
      ]);
      final acoes = listaDeResposta(r).map(AcaoJava.fromJson).toList();

      expect(acoes.single.label, 'A');
      expect(acoes.single.params.single.tipo, 'LISTA');
      expect(acoes.single.params.single.listaOpcoes, ['a', 'b', 'c']);
      expect(listaDeResposta(NetworkResponse(true, 200, null)), isEmpty);
    });

    test('mensagem de erro do servidor e lida de message ou error', () {
      expect(mensagemDeResposta(NetworkResponse(false, 400, {'message': 'Selecione ao menos um registro'})),
          'Selecione ao menos um registro');
      expect(mensagemDeResposta(NetworkResponse(false, 500, {'error': 'x'})), 'x');
      expect(mensagemDeResposta(NetworkResponse(false, 500, null)), isNull);
    });

    test('acao e evento serializam o contrato do backend', () {
      final json = _acaoComParams.toJson();
      expect(json['classe'], 'a.B');
      expect((json['params'] as List).length, 2);
      final e = EventoJava.fromJson({
        'id': 1, 'tabelaNome': 'produto', 'descricao': 'd', 'momento': 'DEPOIS',
        'operacao': 'UPDATE', 'moduloJavaId': 8, 'classe': 'c', 'abortaEmErro': false,
      });
      expect(e.abortaEmErro, isFalse);
      expect(e.toJson()['momento'], 'DEPOIS');
    });
  });

  group('validarParametroAcaoJava', () {
    test('obrigatorio, inteiro, decimal, data e lista', () {
      const obrig = AcaoJavaParam(descricao: 'Nome', nome: 'n', obrigatorio: true);
      expect(validarParametroAcaoJava(obrig, ' '), 'Informe Nome');
      expect(validarParametroAcaoJava(obrig, 'x'), isNull);
      const inteiro = AcaoJavaParam(descricao: 'Q', nome: 'q', tipo: 'INTEIRO');
      expect(validarParametroAcaoJava(inteiro, '12'), isNull);
      expect(validarParametroAcaoJava(inteiro, '1,5'), 'Número inteiro inválido');
      expect(validarParametroAcaoJava(inteiro, ''), isNull);
      const dec = AcaoJavaParam(descricao: 'V', nome: 'v', tipo: 'DECIMAL');
      expect(validarParametroAcaoJava(dec, '10,50'), isNull);
      expect(validarParametroAcaoJava(dec, 'abc'), 'Número inválido');
      const data = AcaoJavaParam(descricao: 'D', nome: 'd', tipo: 'DATA');
      expect(validarParametroAcaoJava(data, '2026-11-10'), isNull);
      expect(validarParametroAcaoJava(data, '10/11/2026'), 'Use a data no formato AAAA-MM-DD');
      const lista = AcaoJavaParam(descricao: 'L', nome: 'l', tipo: 'LISTA', opcoes: 'A;B');
      expect(validarParametroAcaoJava(lista, 'B'), isNull);
      expect(validarParametroAcaoJava(lista, 'C'), 'Escolha uma opção da lista');
    });
  });

  group('executarAcaoJava', () {
    testWidgets('pede os parametros, valida, envia ids e parametros e pede recarga', (tester) async {
      final s = _ServicoFalso();
      bool? recarregar;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => recarregar = await executarAcaoJava(
                  context, _acaoComParams, [{'id': 1}, {'id': 2}], servico: s),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('2 registro(s) selecionado(s)'), findsOneWidget);
      await tester.tap(find.text('Executar'));
      await tester.pumpAndSettle();
      expect(find.text('Informe Novo nome'), findsOneWidget, reason: 'obrigatorio vazio nao envia');
      expect(s.acaoId, isNull);

      await tester.enterText(find.widgetWithText(TextFormField, 'Novo nome *'), 'Camisa');
      await tester.tap(find.text('Executar'));
      await tester.pumpAndSettle();

      expect(s.acaoId, 5);
      expect(s.idsRecebidos, [1, 2]);
      expect(s.parametrosRecebidos, {'novoNome': 'Camisa'});
      expect(recarregar, isTrue);
      expect(find.text('Feito'), findsOneWidget);
    });

    testWidgets('acao sem parametros so confirma; cancelar nao chama o servidor', (tester) async {
      final s = _ServicoFalso();
      const simples = AcaoJava(id: 6, telaNome: 't', label: 'Gerar nota', classe: 'a.B');
      await _abrir(tester, simples, s);

      expect(find.text('Executar "Gerar nota" em 2 registro(s)?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(s.acaoId, isNull);
    });

    testWidgets('erro do servidor aparece na tela e nao recarrega', (tester) async {
      final s = _ServicoFalso()..falha = true;
      const simples = AcaoJava(id: 6, telaNome: 't', label: 'Gerar nota', classe: 'a.B');
      await _abrir(tester, simples, s);
      await tester.tap(find.text('Executar'));
      await tester.pumpAndSettle();

      expect(find.text('Falha do servidor'), findsOneWidget);
    });

    testWidgets('falha da rotina (sucesso=false) mostra a mensagem e nao recarrega a grid', (tester) async {
      final s = _ServicoFalso()
        ..resposta = const AcaoJavaResultado(sucesso: false, mensagem: 'Registro 9 nao encontrado', recarregar: true);
      const simples = AcaoJava(id: 6, telaNome: 't', label: 'Gerar nota', classe: 'a.B');
      await _abrir(tester, simples, s);
      await tester.tap(find.text('Executar'));
      await tester.pumpAndSettle();

      expect(find.text('Registro 9 nao encontrado'), findsOneWidget);
    });
  });
}
