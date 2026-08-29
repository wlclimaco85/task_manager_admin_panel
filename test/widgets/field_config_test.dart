import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';
import 'package:task_manager_admin_panel/widgets/generic/field_config.dart';

void main() {
  group('DropdownOption', () {
    test('constroi com value e label', () {
      const option = DropdownOption(value: 1, label: 'Um');

      expect(option.value, 1);
      expect(option.label, 'Um');
    });
  });

  group('FieldConfig - campos novos da Fase 3', () {
    test('type: FieldType.date com dateTime:true expoe dateTime == true', () {
      const field = FieldConfig(
        key: 'dataAbertura',
        label: 'Data de abertura',
        type: FieldType.date,
        dateTime: true,
      );

      expect(field.type, FieldType.date);
      expect(field.dateTime, isTrue);
    });

    test('dateTime tem default false quando nao informado', () {
      const field = FieldConfig(
        key: 'dataVencimento',
        label: 'Data de vencimento',
        type: FieldType.date,
      );

      expect(field.dateTime, isFalse);
    });

    test('type: FieldType.dropdown com options fixas sincronas', () {
      const field = FieldConfig(
        key: 'status',
        label: 'Status',
        type: FieldType.dropdown,
        options: [
          DropdownOption(value: 'ABERTO', label: 'Aberto'),
          DropdownOption(value: 'FECHADO', label: 'Fechado'),
        ],
      );

      expect(field.type, FieldType.dropdown);
      expect(field.options, hasLength(2));
      expect(field.options!.first.label, 'Aberto');
      expect(field.optionsLoader, isNull);
    });

    test('optionsLoader opcional aceita funcao assincrona de carregamento',
        () {
      const field = FieldConfig(
        key: 'empresa',
        label: 'Empresa',
        type: FieldType.dropdown,
        optionsLoader: _loaderFalso,
      );

      expect(field.optionsLoader, isNotNull);
      expect(field.options, isNull);
    });
  });
}

Future<List<DropdownOption>> _loaderFalso(NetworkCaller caller) async =>
    const [];
