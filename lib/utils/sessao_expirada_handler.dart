import 'package:flutter/material.dart';

import '../screens/login_screen.dart';
import '../services/auth_utility.dart';
import '../services/network_caller.dart';
import 'app_logger.dart';

/// Chaves globais do MaterialApp: permitem navegar/avisar fora de um
/// BuildContext (o 401 chega dentro do NetworkCaller, sem contexto de tela).
final GlobalKey<NavigatorState> adminNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> adminMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

bool _tratandoSessaoExpirada = false;

/// Registra o tratamento global de 401 (token expirado/revogado/sessao
/// encerrada): limpa a sessao local e leva o usuario ao login, em vez de
/// deixar as telas exibindo "(401)" e listas vazias.
void registrarTratamentoSessaoExpirada() {
  NetworkCaller.globalOnUnauthorized = tratarSessaoExpirada;
}

Future<void> tratarSessaoExpirada() async {
  // Sem sessao ativa (ja tratada por outra requisicao paralela): nada a fazer.
  if (_tratandoSessaoExpirada || AuthUtility.userInfo == null) return;
  _tratandoSessaoExpirada = true;
  try {
    AppLogger.i.warn('Sessao expirada/revogada (HTTP 401): encaminhando ao login.');
    await AuthUtility.clearUserInfo();
    final navigator = adminNavigatorKey.currentState;
    if (navigator != null) {
      navigator.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
    adminMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Sua sessão expirou. Entre novamente para continuar.'),
      ));
  } catch (e, st) {
    AppLogger.i.error('Falha ao tratar sessao expirada: $e', st);
  } finally {
    _tratandoSessaoExpirada = false;
  }
}
