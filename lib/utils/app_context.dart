import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App do ecossistema (valor do `LoginEnum` do backend + rotulo de exibicao).
class AppOpcao {
  const AppOpcao(this.codigo, this.rotulo);
  final String codigo;
  final String rotulo;
}

/// App selecionado no Painel do Dono (Fase 4.1b). `null` = Todos os apps.
///
/// A selecao e' sempre explicita do usuario: nunca vem preenchida a partir do
/// login. O isolamento real continua no backend (MASTER pode filtrar por app).
class AppContext {
  AppContext._();

  static const _chavePrefs = 'admin_panel_app_selecionado';

  /// Apps gerenciaveis. Os codigos precisam bater com `LoginEnum` do backend.
  static const List<AppOpcao> apps = [
    AppOpcao('APP_ABRACO', 'Abraço (cliente)'),
    AppOpcao('APP_CONTABILIDADE', 'Contabilidade / White-label'),
    AppOpcao('APP_CONTA_PROPRIA', 'Conta Própria'),
    AppOpcao('APP_ALUNO', 'Aluno'),
    AppOpcao('APP_PERSONAL', 'Personal'),
    AppOpcao('APP_ACADEMIA', 'Academia'),
    AppOpcao('APP_NUTRICIONISTA', 'Nutricionista'),
    AppOpcao('APP_SITE_JOAO', 'Site João'),
    AppOpcao('APP_DANIEL', 'Daniel'),
    AppOpcao('APP_PDV', 'PDV Windows'),
  ];

  static final ValueNotifier<String?> selecionado = ValueNotifier<String?>(null);

  static String rotuloDe(String? codigo) {
    if (codigo == null) return 'Todos os apps';
    for (final a in apps) {
      if (a.codigo == codigo) return a.rotulo;
    }
    return codigo;
  }

  /// Restaura a ultima selecao. Falha silenciosa: sem prefs, segue em "Todos".
  static Future<void> carregar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final salvo = prefs.getString(_chavePrefs);
      if (salvo != null && apps.any((a) => a.codigo == salvo)) {
        selecionado.value = salvo;
      }
    } catch (_) {}
  }

  static Future<void> selecionar(String? codigo) async {
    selecionado.value = codigo;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (codigo == null) {
        await prefs.remove(_chavePrefs);
      } else {
        await prefs.setString(_chavePrefs, codigo);
      }
    } catch (_) {}
  }

  @visibleForTesting
  static void resetar() => selecionado.value = null;
}
