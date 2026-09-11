import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/widgets/searchable_dropdown.dart';

void main() {
  group('SearchableDropdownField - Ordem Alfabetica e Busca Paginada', () {
    testWidgets('ordena itens estaticos em ordem alfabetica no popup', (tester) async {
      final items = [
        {'id': '3', 'nome': 'Zebra Comercio'},
        {'id': '1', 'nome': 'Alfa Academia'},
        {'id': '2', 'nome': 'Beta Servicos'},
      ];

      String? selecionado;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchableDropdownField(
              label: 'Parceiro',
              items: items,
              valueField: 'id',
              displayField: 'nome',
              value: selecionado,
              onChanged: (v) => selecionado = v,
            ),
          ),
        ),
      );

      // Clica para abrir o dialog de busca
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      // Verifica se o dialog abriu
      expect(find.text('Parceiro'), findsWidgets);

      // Encontra todos os ListTiles e verifica a ordem alfabetica
      final tiles = find.byType(ListTile);
      expect(tiles, findsNWidgets(3));

      expect(find.descendant(of: tiles.at(0), matching: find.text('Alfa Academia')), findsOneWidget);
      expect(find.descendant(of: tiles.at(1), matching: find.text('Beta Servicos')), findsOneWidget);
      expect(find.descendant(of: tiles.at(2), matching: find.text('Zebra Comercio')), findsOneWidget);
    });

    testWidgets('carrega dados de 20 em 20 via loadPage e suporta busca remota', (tester) async {
      final todasEmpresas = <Map<String, dynamic>>[];
      for (int i = 1; i <= 50; i++) {
        final numStr = i < 10 ? '0' + i.toString() : i.toString();
        todasEmpresas.add({
          'id': i.toString(),
          'nome': 'Empresa ' + numStr,
        });
      }

      Future<PaginaDropdown> fakeLoadPage({String? busca, required int pagina}) async {
        var filtrados = todasEmpresas;
        if (busca != null && busca.isNotEmpty) {
          filtrados = todasEmpresas
              .where((e) => e['nome'].toString().toLowerCase().contains(busca.toLowerCase()))
              .toList();
        }
        final inicio = pagina * 20;
        final fim = (inicio + 20).clamp(0, filtrados.length);
        final sublista = inicio < filtrados.length ? filtrados.sublist(inicio, fim) : <Map<String, dynamic>>[];
        return PaginaDropdown(sublista, filtrados.length);
      }

      String? selecionado;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchableDropdownField(
              label: 'Empresa',
              valueField: 'id',
              displayField: 'nome',
              value: selecionado,
              loadPage: fakeLoadPage,
              onChanged: (v) => selecionado = v,
            ),
          ),
        ),
      );

      // Abre o dialog
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      // Inicialmente carrega os 20 primeiros
      expect(find.text('20 de 50 resultado(s)'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Empresa 01'), findsOneWidget);

      // Digita no campo de busca para filtrar por LIKE
      await tester.enterText(find.byType(TextField), 'Empresa 30');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Registros correspondentes a 'Empresa 30'
      expect(find.text('1 de 1 resultado(s)'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Empresa 30'), findsOneWidget);

      // Seleciona o item
      await tester.tap(find.widgetWithText(ListTile, 'Empresa 30'));
      await tester.pumpAndSettle();

      expect(selecionado, '30');
    });
  });
}
