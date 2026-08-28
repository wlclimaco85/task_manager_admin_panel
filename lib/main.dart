import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_utility.dart';
import 'utils/tenant_context.dart';

void main() {
  runApp(const AdminPanelApp());
}

class AdminPanelApp extends StatelessWidget {
  const AdminPanelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Painel do Dono - App Academia',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: const _SessionGate(),
    );
  }
}

/// Decide a rota inicial conforme haja (ou nao) sessao persistida valida.
class _SessionGate extends StatefulWidget {
  const _SessionGate();

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  late final Future<bool> _hasAdminSession = _checkAdminSession();

  /// Restaura a sessao persistida e exige que seja uma sessao admin — mesmo
  /// gate aplicado no login (achado de code-review: uma sessao restaurada
  /// de um login nao-admin nao pode cair direto no HomeScreen).
  Future<bool> _checkAdminSession() async {
    final loggedIn = await AuthUtility.isUserLoggedIn();
    if (!loggedIn) return false;
    if (!TenantContext.isAdmin) {
      await AuthUtility.clearUserInfo();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasAdminSession,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data == true ? const HomeScreen() : const LoginScreen();
      },
    );
  }
}
