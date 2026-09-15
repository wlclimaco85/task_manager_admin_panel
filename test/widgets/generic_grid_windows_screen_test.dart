import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/widgets/generic_grid_windows_screen.dart';

void main() {
  group('GenericGridWindowsScreen.extractRows', () {
    test('deve extrair dados de uma lista direta', () {
      final input = [{'id': 1, 'nome': 'Teste'}];
      final rows = GenericGridWindowsScreen.extractRows(input);
      expect(rows, isNotEmpty);
      expect(rows.first['nome'], 'Teste');
    });

    test('deve extrair dados de { "data": [...] }', () {
      final input = {
        'data': [{'id': 2, 'nome': 'Teste 2'}]
      };
      final rows = GenericGridWindowsScreen.extractRows(input);
      expect(rows, isNotEmpty);
      expect(rows.first['nome'], 'Teste 2');
    });

    test('deve extrair dados de { "data": { "dados": [...] } }', () {
      final input = {
        'data': {
          'dados': [{'id': 3, 'nome': 'Teste 3'}],
          'totalElements': 1
        }
      };
      final rows = GenericGridWindowsScreen.extractRows(input);
      expect(rows, isNotEmpty);
      expect(rows.first['nome'], 'Teste 3');
    });

    test('deve retornar lista vazia para formato invalido', () {
      final input = {'invalid': 'format'};
      final rows = GenericGridWindowsScreen.extractRows(input);
      expect(rows, isEmpty);
    });
  });
}
