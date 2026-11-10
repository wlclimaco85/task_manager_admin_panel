import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/services/modulo_java_service.dart';
import 'package:task_manager_admin_panel/widgets/modulo_java_view.dart';

class _ServicoFalso extends ModuloJavaService {
  final List<ModuloJava> modulos;
  final bool falha;

  _ServicoFalso(this.modulos, {this.falha = false});

  @override
  Future<List<ModuloJava>> listar() async {
    if (falha) throw const ModuloJavaException('Somente o usuário MASTER pode gerenciar módulos Java.');
    return modulos;
  }

  @override
  Future<List<ModuloJavaArquivo>> listarArquivos(int moduloId) async => [
        const ModuloJavaArquivo(
            id: 1,
            nomeArquivo: 'dhara-agro-cobrancainterna-1.0.0.jar',
            sha256: 'abcdef0123456789',
            tamanho: 2048,
            versao: 1,
            classes: ['br.com.dhara.CobrancaAcao (ACAO)']),
      ];
}

Widget _app(ModuloJavaService s, {double largura = 1200}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(largura, 800)),
        child: Scaffold(body: ModuloJavaView(servico: s)),
      ),
    );

void main() {
  group('ModuloJavaService', () {
    test('valida extensao, vazio e tamanho maximo no cliente', () {
      expect(ModuloJavaService.validarArquivo('a.jar', 10), isNull);
      expect(ModuloJavaService.validarArquivo('A.JAR', 10), isNull);
      expect(ModuloJavaService.validarArquivo('a.zip', 10), 'Selecione um arquivo .jar.');
      expect(ModuloJavaService.validarArquivo('a.jar', 0), 'O arquivo está vazio.');
      expect(ModuloJavaService.validarArquivo('a.jar', kModuloJavaTamanhoMaximoBytes + 1),
          'O arquivo excede o tamanho máximo de 10 MB.');
    });

    test('inventario de classes vira texto legivel e tolera JSON invalido', () {
      expect(
          ModuloJavaArquivo.classesDeJson('[{"nome":"a.B","tipo":"ACAO"},{"nome":"a.C","tipo":"EVENTO"}]'),
          ['a.B (ACAO)', 'a.C (EVENTO)']);
      expect(ModuloJavaArquivo.classesDeJson(null), isEmpty);
      expect(ModuloJavaArquivo.classesDeJson('isso nao e json'), isEmpty);
    });

    test('modelo le e escreve o contrato do backend', () {
      final m = ModuloJava.fromJson({'id': 8, 'identificador': 'x-1.0.0', 'descricao': 'D', 'ativo': false});
      expect(m.id, 8);
      expect(m.ativo, isFalse);
      expect(m.toJson(), {'identificador': 'x-1.0.0', 'descricao': 'D', 'ativo': false});
    });
  });

  group('ModuloJavaView', () {
    testWidgets('lista modulos e abre o detalhe com as abas Geral e Arquivo Modulo (Jar)', (tester) async {
      final s = _ServicoFalso(const [
        ModuloJava(id: 8, identificador: 'dhara-agro-cobrancainterna-1.0.0', descricao: 'Cobrança Interna entre Fazendas'),
      ]);
      await tester.pumpWidget(_app(s));
      await tester.pumpAndSettle();

      expect(find.text('Cobrança Interna entre Fazendas'), findsOneWidget);
      await tester.tap(find.text('Cobrança Interna entre Fazendas'));
      await tester.pumpAndSettle();

      expect(find.text('Geral'), findsOneWidget);
      expect(find.text('Arquivo Módulo (Jar)'), findsOneWidget);
      await tester.tap(find.text('Arquivo Módulo (Jar)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('dhara-agro-cobrancainterna-1.0.0.jar'), findsOneWidget);
      expect(find.text('Enviar .jar'), findsOneWidget);
    });

    testWidgets('erro do servidor aparece na tela (nao fica em branco nem girando)', (tester) async {
      await tester.pumpWidget(_app(_ServicoFalso(const [], falha: true)));
      await tester.pumpAndSettle();

      expect(find.textContaining('Somente o usuário MASTER'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('novo modulo exige descricao e identificador valido', (tester) async {
      await tester.pumpWidget(_app(_ServicoFalso(const [])));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Novo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(find.text('Informe a descrição'), findsOneWidget);
      expect(find.text('Informe o identificador'), findsOneWidget);

      await tester.tap(find.text('Arquivo Módulo (Jar)'));
      await tester.pumpAndSettle();
      expect(find.text('Salve o módulo para enviar arquivos .jar.'), findsOneWidget);
    });

    testWidgets('em largura de celular a lista e o detalhe se alternam', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = _ServicoFalso(const [
        ModuloJava(id: 8, identificador: 'x-1.0.0', descricao: 'Modulo Mobile'),
      ]);
      await tester.pumpWidget(_app(s, largura: 400));
      await tester.pumpAndSettle();

      expect(find.text('Selecione um módulo ou crie um novo.'), findsNothing);
      await tester.tap(find.text('Modulo Mobile'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Voltar'), findsOneWidget);
    });
  });
}
