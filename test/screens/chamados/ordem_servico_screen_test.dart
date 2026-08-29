import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager_admin_panel/config/api_links.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/screens/chamados/ordem_servico_screen.dart';
import 'package:task_manager_admin_panel/services/network_caller.dart';
import 'package:task_manager_admin_panel/widgets/generic/generic_grid_screen.dart';

void main() {
  group('transformChamadoPayload', () {
    test('create (isEditing=false): parceiro plano vira parceiroId, sem chave parceiro', () {
      final result = transformChamadoPayload({'parceiro': 5, 'titulo': 'X'}, false);

      expect(result, {'titulo': 'X', 'parceiroId': 5});
      expect(result.containsKey('parceiro'), isFalse);
    });

    test('edicao (isEditing=true): parceiro plano vira {id: valor} aninhado', () {
      final result = transformChamadoPayload({'parceiro': 5, 'titulo': 'X'}, true);

      expect(result, {
        'titulo': 'X',
        'parceiro': {'id': 5},
      });
    });

    test('create: empresa e setor planos viram aninhados {id: valor}', () {
      final result = transformChamadoPayload(
        {'empresa': 3, 'setor': 9, 'titulo': 'Y'},
        false,
      );

      expect(result, {
        'titulo': 'Y',
        'empresa': {'id': 3},
        'setor': {'id': 9},
      });
    });

    test('campos ausentes nao aparecem no resultado', () {
      final result = transformChamadoPayload({'titulo': 'Z'}, true);

      expect(result, {'titulo': 'Z'});
    });
  });

  testWidgets(
      'OrdemServicoScreen monta GenericGridScreen com contrato Chamado e dropdown de status em portugues',
      (tester) async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode([
          {
            'id': 1,
            'titulo': 'Chamado teste',
            'status': 'ABERTO',
            'prioridade': 'ALTA',
          },
        ]),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final caller = NetworkCaller(client: client);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: const OrdemServicoScreen(),
    ));
    await tester.pump();

    final grid = tester.widget<GenericGridScreen>(
      find.byType(GenericGridScreen),
    );

    expect(grid.title, 'Ordem de Servico');
    expect(grid.listUrl, ApiLinks.allChamadosOS);
    expect(grid.createUrl, ApiLinks.createChamado);
    expect(grid.updateUrl('1'), ApiLinks.updateChamadoOS('1'));
    expect(grid.deleteUrl?.call('1'), ApiLinks.deleteChamado('1'));
    expect(grid.transformPayload, transformChamadoPayload);
    expect(
      grid.fields.map((f) => f.key),
      [
        'titulo',
        'descricao',
        'status',
        'prioridade',
        'empresa',
        'parceiro',
        'setor',
        'dataAbertura',
        'dataFechamento',
        'dataVencimentoObrigacao',
      ],
    );

    final statusField = grid.fields.firstWhere((f) => f.key == 'status');
    expect(
      statusField.options?.map((o) => o.label).toList(),
      [
        'Aberto',
        'Em andamento',
        'Fechado',
        'Cancelado',
        'Aguardando cliente',
        'Bloqueado',
      ],
    );

    // Reconstroi a tela injetando o NetworkCaller mockado para confirmar
    // que a grid renderiza com os labels em portugues (nao o texto placeholder
    // getDescricao() do backend) e que status/prioridade aparecem como colunas.
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: GenericGridScreen(
          title: 'Ordem de Servico',
          listUrl: ApiLinks.allChamadosOS,
          createUrl: ApiLinks.createChamado,
          updateUrl: ApiLinks.updateChamadoOS,
          deleteUrl: ApiLinks.deleteChamado,
          fields: grid.fields,
          networkCaller: caller,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Aberto'), findsOneWidget);
    expect(find.text('Alta'), findsOneWidget);
  });
}
