import 'package:flutter/material.dart';

import '../utils/planilha_tenant.dart';

/// Empresa e parceiro do login, sempre bloqueados, em relatorios e graficos: o servidor ja filtra os dados por eles.
class CamposDoTenant extends StatelessWidget {
  final SessaoTenant? sessao;

  const CamposDoTenant({super.key, this.sessao});

  @override
  Widget build(BuildContext context) {
    final valores = (sessao ?? SessaoTenant.doLogin()).valores;
    if (valores.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final e in valores.entries)
        SizedBox(
          width: 150,
          child: TextFormField(
            key: ValueKey('tenant-${e.key}'),
            initialValue: e.value,
            enabled: false,
            decoration: InputDecoration(labelText: e.key == kColunaEmpresa ? 'Empresa' : 'Parceiro', isDense: true),
          ),
        ),
    ]);
  }
}
