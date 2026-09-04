import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';

void main() {
  group('DropdownOption', () {
    test('constroi com value e label', () {
      const option = {'value': 1, 'label': 'Um'};

      expect(option.value, 1);
      expect(option.label, 'Um');
    });
  });

  group('FieldConfig - campos novos da Fase 3', () {
    test('fieldType: FieldType.date com dateTime:true expoe dateTime == true', () {
      const field = FieldConfigWindows(
        fieldName: 'dataAbertura',
        label: 'Data de abertura',
        fieldType: FieldType.date,
        dateTime: true,
      );

      expect(field.type, FieldType.date);
      expect(field.dateTime, isTrue);
    });

    test('dateTime tem default false quando nao informado', () {
      const field = FieldConfigWindows(
        fieldName: 'dataVencimento',
        label: 'Data de vencimento',
        fieldType: FieldType.date,
      );

      expect(field.dateTime, isFalse);
    });

    test('fieldType: FieldType.dropdown com options fixas sincronas', () {
      const field = FieldConfigWindows(
        fieldName: 'status',
        label: 'Status',
        fieldType: FieldType.dropdown,
        dropdownOptions: [
          {'value': 'ABERTO', 'label': 'Aberto'},
          {'value': 'FECHADO', 'label': 'Fechado'},
        ],
      );

      expect(field.type, FieldType.dropdown);
      expect(field.options, hasLength(2));
      expect(field.options!.first.label, 'Aberto');
      expect(field.optionsLoader, isNull);
    });

    test('optionsLoader opcional aceita funcao assincrona de carregamento',
        () {
      const field = FieldConfigWindows(
        fieldName: 'empresa',
        label: 'Empresa',
        fieldType: FieldType.dropdown,
        optionsLoader: _loaderFalso,
      );

      expect(field.optionsLoader, isNotNull);
      expect(field.options, isNull);
    });
  });
}

Future<List<DropdownOption>> _loaderFalso(NetworkCaller caller) async =>
    const [];
