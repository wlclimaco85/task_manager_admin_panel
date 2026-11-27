import '../models/telas_model.dart';
import 'planilha_tenant.dart';

/// Valor inicial do campo de uma tela. Campo de parceiro BLOQUEADO (telas do Construtor) recebe o parceiro do login;
/// a empresa ja vem do servidor, porque a tela pertence a ela. Os demais campos nao mudam.
String? valorPadraoDoCampo(TelaField f, {SessaoTenant? sessao}) {
  if (f.enabled || f.fieldName != kColunaParceiro) return f.defaultValue;
  final parceiro = (sessao ?? SessaoTenant.doLogin()).parceiro;
  return parceiro == null ? f.defaultValue : '$parceiro';
}
