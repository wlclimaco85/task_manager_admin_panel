import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/utils/dropdown_helpers.dart';

void main() {
  group('DropdownHelpers.buildParceirosBuscaQuery', () {
    test('inclui pagina e tamanho sempre, sem busca quando termo vazio', () {
      final query =
          DropdownHelpers.buildParceirosBuscaQuery(busca: null, pagina: 0);
      expect(query, '?pagina=0&tamanho=20');
    });

    test('inclui busca quando ha termo digitado', () {
      final query =
          DropdownHelpers.buildParceirosBuscaQuery(busca: 'ed', pagina: 0);
      expect(query, contains('busca=ed'));
    });

    test('ignora termo so com espacos (trim)', () {
      final query =
          DropdownHelpers.buildParceirosBuscaQuery(busca: '   ', pagina: 0);
      expect(query, isNot(contains('busca=')));
    });

    test('escapa caracteres especiais do termo de busca na URL', () {
      final query = DropdownHelpers.buildParceirosBuscaQuery(
          busca: 'a&b c', pagina: 0);
      expect(query, isNot(contains('busca=a&b c')));
      expect(query, contains('busca=a%26b+c'));
    });

    test('inclui empresaId quando fornecido', () {
      final query = DropdownHelpers.buildParceirosBuscaQuery(
          busca: null, pagina: 0, empresaId: '20001');
      expect(query, contains('empresaId=20001'));
    });

    test('nao inclui empresaId quando nulo ou vazio', () {
      final semEmpresa =
          DropdownHelpers.buildParceirosBuscaQuery(busca: null, pagina: 0);
      final empresaVazia = DropdownHelpers.buildParceirosBuscaQuery(
          busca: null, pagina: 0, empresaId: '');
      expect(semEmpresa, isNot(contains('empresaId')));
      expect(empresaVazia, isNot(contains('empresaId')));
    });

    test('inclui tipoParceiro quando fornecido', () {
      final query = DropdownHelpers.buildParceirosBuscaQuery(
          busca: null, pagina: 0, tipoParceiro: 'Fornecedor');
      expect(query, contains('tipoParceiro=Fornecedor'));
    });

    test('avanca a pagina ao rolar a lista (scroll pagination)', () {
      final pagina0 =
          DropdownHelpers.buildParceirosBuscaQuery(busca: null, pagina: 0);
      final pagina1 =
          DropdownHelpers.buildParceirosBuscaQuery(busca: null, pagina: 1);
      expect(pagina0, '?pagina=0&tamanho=20');
      expect(pagina1, '?pagina=1&tamanho=20');
    });
  });

  group('DropdownHelpers.parsePaginaDropdown', () {
    test('extrai items e total do corpo {data: {dados, totalElements}}', () {
      final body = {
        'data': {
          'dados': [
            {'id': 1, 'nome': 'Editora Alfa'},
            {'id': 2, 'nome': 'Fornecedor CNPJ'},
          ],
          'totalElements': 35,
        },
      };

      final pagina = DropdownHelpers.parsePaginaDropdown(body);

      expect(pagina.total, 35);
      expect(pagina.items.length, 2);
      expect(pagina.items[0]['nome'], 'Editora Alfa');
    });

    test('preenche nome com razaoSocial quando nome vem vazio', () {
      final body = {
        'data': {
          'dados': [
            {'id': 1, 'nome': '', 'razaoSocial': 'Distribuidora Zebra Ltda'},
          ],
          'totalElements': 1,
        },
      };

      final pagina = DropdownHelpers.parsePaginaDropdown(body);

      expect(pagina.items[0]['nome'], 'Distribuidora Zebra Ltda');
    });

    test('corpo malformado retorna pagina vazia sem lancar excecao', () {
      expect(DropdownHelpers.parsePaginaDropdown(null).items, isEmpty);
      expect(DropdownHelpers.parsePaginaDropdown('texto').items, isEmpty);
      expect(DropdownHelpers.parsePaginaDropdown({'data': 'x'}).items, isEmpty);
      expect(DropdownHelpers.parsePaginaDropdown({}).total, 0);
    });
  });

  group('DropdownHelpers.parseParceiroLabel', () {
    test('usa nome quando presente', () {
      final label = DropdownHelpers.parseParceiroLabel({
        'data': {'nome': 'ANAP SERVICOS MEDICOS LTDA'},
      });
      expect(label, 'ANAP SERVICOS MEDICOS LTDA');
    });

    test('cai para razaoSocial quando nome vazio', () {
      final label = DropdownHelpers.parseParceiroLabel({
        'data': {'nome': '', 'razaoSocial': 'Razao Social Ltda'},
      });
      expect(label, 'Razao Social Ltda');
    });

    test('cai para email quando nome e razaoSocial vazios', () {
      final label = DropdownHelpers.parseParceiroLabel({
        'data': {'nome': '', 'razaoSocial': '', 'email': 'contato@teste.com'},
      });
      expect(label, 'contato@teste.com');
    });

    test('corpo malformado retorna null sem lancar excecao', () {
      expect(DropdownHelpers.parseParceiroLabel(null), isNull);
      expect(DropdownHelpers.parseParceiroLabel({'data': null}), isNull);
    });
  });

  group('DropdownHelpers.buildEmpresasBuscaQuery', () {
    test('inclui pagina e tamanho sempre, sem busca quando termo vazio', () {
      final query =
          DropdownHelpers.buildEmpresasBuscaQuery(busca: null, pagina: 0);
      expect(query, '?pagina=0&tamanho=20');
    });

    test('inclui busca quando ha termo digitado', () {
      final query =
          DropdownHelpers.buildEmpresasBuscaQuery(busca: 'abraco', pagina: 0);
      expect(query, '?pagina=0&tamanho=20&busca=abraco');
    });

    test('ignora termo so com espacos (trim)', () {
      final query =
          DropdownHelpers.buildEmpresasBuscaQuery(busca: '   ', pagina: 0);
      expect(query, '?pagina=0&tamanho=20');
    });

    test('escapa caracteres especiais do termo de busca na URL', () {
      final query = DropdownHelpers.buildEmpresasBuscaQuery(
          busca: 'a&b c', pagina: 0);
      expect(query, isNot(contains('busca=a&b c')));
      expect(query, contains('busca=a%26b+c'));
    });
  });

  group('DropdownHelpers.parseEmpresaLabel', () {
    test('usa nome quando presente', () {
      final label = DropdownHelpers.parseEmpresaLabel({'nome': 'Empresa X'});
      expect(label, 'Empresa X');
    });

    test('cai para razaoSocial quando nome vazio', () {
      final label = DropdownHelpers.parseEmpresaLabel(
          {'nome': '', 'razaoSocial': 'Razao Social Ltda'});
      expect(label, 'Razao Social Ltda');
    });

    test('corpo malformado retorna null sem lancar excecao', () {
      expect(DropdownHelpers.parseEmpresaLabel(null), isNull);
      expect(DropdownHelpers.parseEmpresaLabel('texto'), isNull);
    });
  });
}
