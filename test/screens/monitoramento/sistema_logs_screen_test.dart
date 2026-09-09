import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/models/sistema_log_model.dart';
import 'package:task_manager_admin_panel/screens/monitoramento/sistema_logs_screen.dart';
import 'package:task_manager_admin_panel/services/sistema_log_service.dart';

class FakeSistemaLogService extends SistemaLogService {
  @override
  Future<SistemaLogMetricasModel?> obterMetricas() async {
    return SistemaLogMetricasModel(
      totalErros24h: 12,
      totalWarnings24h: 5,
      totalErrosBackend24h: 8,
      totalErrosApp24h: 4,
      totalLogs7dias: 150,
    );
  }

  @override
  Future<List<SistemaLogModel>> listarLogs({
    String? nivel,
    String? origem,
    String? busca,
    int? empresaId,
    int? parceiroId,
    String? usuario,
    String? plataforma,
    DateTime? dataInicio,
    DateTime? dataFim,
    int page = 0,
    int size = 50,
  }) async {
    return [
      SistemaLogModel(
        id: 1,
        timestamp: DateTime.now(),
        nivel: 'ERROR',
        origem: 'BACKEND',
        mensagem: 'NullPointerException em PedidoService',
        classeOuRota: 'POST /api/pedidos',
        usuario: 'admin',
        detalhes: 'java.lang.NullPointerException\n  at br.com.appAcademia.PedidoService.save(PedidoService.java:42)',
      ),
      SistemaLogModel(
        id: 2,
        timestamp: DateTime.now(),
        nivel: 'WARN',
        origem: 'APP_FLUTTER',
        mensagem: 'Timeout de conexao com servidor',
        classeOuRota: '/tela-financeiro',
        usuario: 'cliente1',
        detalhes: 'DioException [connection timeout]',
      ),
    ];
  }
}

void main() {
  testWidgets('SistemaLogsScreen renderiza metricas e lista de logs corretamente', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: SistemaLogsScreen(service: FakeSistemaLogService()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Logs & Monitoramento'), findsOneWidget);
    expect(find.text('Erros (24h)'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Warnings (24h)'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);

    expect(find.text('NullPointerException em PedidoService'), findsOneWidget);
    expect(find.text('Timeout de conexao com servidor'), findsOneWidget);
    expect(find.text('ERROR'), findsWidgets);
    expect(find.text('WARN'), findsWidgets);

    // Valida botao Copiar Erros e novos filtros
    expect(find.text('Copiar Erros'), findsOneWidget);
    expect(find.text('Empresa ID'), findsOneWidget);
    expect(find.text('Parceiro ID'), findsOneWidget);
    expect(find.text('Usuário'), findsOneWidget);
    expect(find.text('Plataforma: Todas'), findsOneWidget);
  });
}
