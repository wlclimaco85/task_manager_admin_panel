// test/config/api_links_test.dart
//
// Testes automatizados para validar as URLs base e endpoints do ApiLinks
// no Painel do Dono (task_manager_admin_panel).

import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager_admin_panel/config/api_links.dart';

void main() {
  group('ApiLinks — Contrato de URLs e Context-Path', () {
    test('baseUrl contém o context-path /boletobancos', () {
      expect(ApiLinks.baseUrl, contains('/boletobancos'));
    });

    test('login aponta para o endpoint correto de autenticacao', () {
      expect(ApiLinks.login, contains('/boletobancos/rest/auth/login'));
      expect(Uri.parse(ApiLinks.login).hasAuthority, isTrue);
    });

    test('sistemaLogs aponta para /api/sistema-logs', () {
      expect(ApiLinks.sistemaLogs, contains('/api/sistema-logs'));
      expect(ApiLinks.sistemaLogs, contains('/boletobancos'));
    });

    test('allEmpresas e allParceiros usam endpoints no context-path', () {
      expect(ApiLinks.allEmpresas, contains('/api/empresa'));
      expect(ApiLinks.allParceiros, contains('/api/parceiro'));
    });

    test('todas as URLs de API sao absolutas com host valido', () {
      expect(Uri.parse(ApiLinks.baseUrl).hasAuthority, isTrue);
      expect(Uri.parse(ApiLinks.allEmpresas).hasAuthority, isTrue);
      expect(Uri.parse(ApiLinks.allParceiros).hasAuthority, isTrue);
    });
  });
}
