import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';

/// Plataforma do acesso enviada no login: WEB, WINDOWS ou MOBILE.
String plataformaDoAcesso() {
  if (kIsWeb) return 'WEB';
  if (Platform.isWindows) return 'WINDOWS';
  return 'MOBILE';
}

/// Campos extras do login que alimentam o registro de acessos do painel do dono.
Future<Map<String, String>> dadosDeAcessoLogin() async {
  String versao = 'desconhecida';
  try {
    final info = await PackageInfo.fromPlatform();
    versao = '${info.version}+${info.buildNumber}';
  } catch (_) {
    // Sem versao legivel o login segue; o registro usa o padrao.
  }
  return {
    'aplicacao': 'PAINEL_DONO',
    'plataforma': plataformaDoAcesso(),
    'versaoApp': versao,
  };
}
