import 'package:flutter/material.dart';
import '../../../config/api_links.dart';
import '../../../widgets/importacao_sintegra_card.dart';
import '../../../widgets/importacao_sped_card.dart';

class ImportacaoFiscalScreen extends StatelessWidget {
  const ImportacaoFiscalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Importacao Fiscal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ImportacaoSintegraCard(baseUrl: ApiLinks.baseUrl),
          const SizedBox(height: 12),
          ImportacaoSpedCard(baseUrl: ApiLinks.baseUrl),
        ],
      ),
    );
  }
}
