import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:task_manager_admin_panel/core/theme/app_theme.dart';
import 'package:task_manager_admin_panel/models/sistema_log_model.dart';
import 'package:task_manager_admin_panel/screens/monitoramento/sistema_logs_screen.dart';
import 'package:task_manager_admin_panel/services/sistema_log_service.dart';
import 'package:task_manager_admin_panel/utils/app_context.dart';
import 'package:task_manager_admin_panel/widgets/app_selector.dart';

/// Registra o appTipo recebido em cada consulta de logs.
class _SpyLogService extends SistemaLogService {
  final consultas = <String?>[];

  @override
  Future<SistemaLogMetricasModel?> obterMetricas() async => null;

  @override
  Future<List<SistemaLogModel>> listarLogs({
    String? nivel,
    String? origem,
    String? busca,
    int? empresaId,
    int? parceiroId,
    String? usuario,
    String? plataforma,
    String? appTipo,
    DateTime? dataInicio,
    DateTime? dataFim,
    int page = 0,
    int size = 50,
  }) async {
    consultas.add(appTipo);
    return [];
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppContext.resetar();
  });

  test('AppContext comeca em Todos (nunca pre-selecionado) e persiste a escolha', () async {
    expect(AppContext.selecionado.value, isNull);
    expect(AppContext.rotuloDe(null), 'Todos os apps');

    await AppContext.selecionar('APP_ALUNO');
    AppContext.resetar();
    await AppContext.carregar();

    expect(AppContext.selecionado.value, 'APP_ALUNO');
  });

  test('AppContext ignora valor salvo que nao e um app conhecido', () async {
    SharedPreferences.setMockInitialValues({'admin_panel_app_selecionado': 'APP_INEXISTENTE'});
    await AppContext.carregar();
    expect(AppContext.selecionado.value, isNull);
  });

  test('codigos do painel cobrem os apps novos do LoginEnum', () {
    final codigos = AppContext.apps.map((a) => a.codigo);
    expect(codigos, containsAll(['APP_CONTA_PROPRIA', 'APP_DANIEL', 'APP_PDV']));
  });

  testWidgets('trocar o app no seletor recarrega os logs filtrando por esse app', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final spy = _SpyLogService();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: SistemaLogsScreen(service: spy),
    ));
    await tester.pumpAndSettle();
    expect(spy.consultas, [null]);

    await tester.tap(find.byType(AppSelector));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conta Própria').last);
    await tester.pumpAndSettle();

    expect(AppContext.selecionado.value, 'APP_CONTA_PROPRIA');
    expect(spy.consultas.last, 'APP_CONTA_PROPRIA');
  });
}
