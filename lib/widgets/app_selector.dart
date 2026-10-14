import 'package:flutter/material.dart';
import '../utils/app_context.dart';

/// Seletor global de app do Painel do Dono. Altera [AppContext.selecionado].
/// Largura contida e texto com reticencias para caber em AppBar estreito.
class AppSelector extends StatelessWidget {
  const AppSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final estreito = MediaQuery.sizeOf(context).width < 600;
    return ValueListenableBuilder<String?>(
      valueListenable: AppContext.selecionado,
      builder: (context, atual, _) {
        return SizedBox(
          width: estreito ? 96 : 190,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              key: const Key('app_selector_dropdown'),
              value: atual,
              isExpanded: true,
              icon: const Icon(Icons.apps_outlined, size: 18),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Todos os apps', overflow: TextOverflow.ellipsis),
                ),
                for (final app in AppContext.apps)
                  DropdownMenuItem<String?>(
                    value: app.codigo,
                    child: Text(app.rotulo, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: AppContext.selecionar,
            ),
          ),
        );
      },
    );
  }
}
