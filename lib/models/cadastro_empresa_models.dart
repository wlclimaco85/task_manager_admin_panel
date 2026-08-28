// Modelos de apoio ao `CadastroEmpresaService` (SIS-02, wizard "Cadastro
// Empresa"). Adaptados de `task_manager_flutter/lib/web/screens/
// cadastro_empresa_wizard.dart` (classes internas `_CreatedEntity`,
// `_LogEntry`, `_CadastroException`), tornados publicos e sem estado de
// widget para viabilizar reuso pela logica pura do `CadastroEmpresaService`.

/// Referencia minima a uma empresa ja criada, usada para propagar o id nos
/// payloads das etapas seguintes do wizard (`{'id': empresaId}`).
class EmpresaRef {
  final int id;

  const EmpresaRef(this.id);

  Map<String, dynamic> toJson() => {'id': id};
}

/// Entidade criada durante a execucao do wizard, guardada para permitir
/// rollback LIFO (`DELETE $url/$id`) em caso de falha em qualquer etapa
/// posterior.
class CreatedEntity {
  final String tipo;
  final int id;
  final String Function(String id) deleteUrl;

  const CreatedEntity({
    required this.tipo,
    required this.id,
    required this.deleteUrl,
  });
}

/// Linha de log incremental emitida pelo `CadastroEmpresaService` via
/// callback, para a UI (P04) plotar progresso sem acoplamento a
/// `StatefulWidget`.
class LogEntry {
  final DateTime timestamp;
  final String mensagem;
  final bool sucesso;

  LogEntry({
    required this.mensagem,
    required this.sucesso,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Erro de negocio lancado quando uma etapa do wizard falha (id nulo na
/// resposta do backend). Interrompe a execucao e dispara o rollback.
class CadastroException implements Exception {
  final String mensagem;

  const CadastroException(this.mensagem);

  @override
  String toString() => mensagem;
}
