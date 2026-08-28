// ignore_for_file: no_leading_underscores_for_local_identifiers
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/login_model.dart';

/// Decodifica um JWT e verifica se ja expirou, sem biblioteca externa.
/// Mesma logica do app cliente (task_manager_flutter/lib/models/auth_utility.dart).
bool isJwtExpired(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return true;
    String payload = parts[1];
    final rem = payload.length % 4;
    if (rem != 0) payload += '=' * (4 - rem);
    final decoded = utf8.decode(base64Url.decode(payload));
    final json = jsonDecode(decoded) as Map<String, dynamic>;
    final exp = json['exp'];
    if (exp == null) return false;
    final expDate = DateTime.fromMillisecondsSinceEpoch((exp as int) * 1000);
    return DateTime.now().isAfter(expDate);
  } catch (_) {
    return true;
  }
}

/// Gerencia a sessao do usuario logado (persistencia local + estado em
/// memoria). Versao enxuta do AuthUtility do app cliente: sem
/// PermissionService (menu dinamico) nem AlertaPollingService (push
/// notifications) — fora do escopo do admin panel na Fase 1.
class AuthUtility {
  AuthUtility._();

  static LoginModel? userInfo;

  static const _storageKey = 'admin_panel_user_data';

  static bool get isLoggedIn {
    final u = userInfo;
    if (u == null) return false;
    final hasToken = u.token != null && u.token!.isNotEmpty;
    final hasLoginId = (u.login?.id ?? 0) > 0;
    return hasToken || hasLoginId;
  }

  static Future<void> setUserInfo(LoginModel model) async {
    userInfo = model;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(model.toJson()));
  }

  static Future<LoginModel?> getUserInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_storageKey);
      if (value == null) return null;
      final json = jsonDecode(value) as Map<String, dynamic>;
      return LoginModel.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    userInfo = null;
  }

  static Future<LoginModel?> obterLogin() async {
    if (userInfo != null) return userInfo;
    return getUserInfo();
  }

  /// `true` se ha sessao valida (token presente e nao expirado). Limpa a
  /// sessao automaticamente se o token estiver expirado.
  static Future<bool> isUserLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final hasStoredSession = prefs.containsKey(_storageKey);
    if (!hasStoredSession) return false;

    userInfo = await getUserInfo();
    if (userInfo?.token != null && isJwtExpired(userInfo!.token!)) {
      await clearUserInfo();
      return false;
    }
    return userInfo != null;
  }
}
