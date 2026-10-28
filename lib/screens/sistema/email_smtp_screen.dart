import 'package:flutter/material.dart';

import '../../utils/dropdown_helpers.dart';
import '../../widgets/smtp_config_tab.dart';

/// Sistema > E-mail (SMTP): o dono escolhe a empresa e configura o SMTP usado nos e-mails do sistema dos logins
/// dessa empresa (codigo de redefinicao de senha, boas-vindas). Mesma configuracao da aba "POP/Mail" do detalhe de
/// Empresa no app do cliente (Abraço): endpoint /api/smtp-config/empresa/{id}.
class EmailSmtpScreen extends StatefulWidget {
  /// Carregador de empresas (injetavel nos testes). Padrao: GET /api/empresa.
  final Future<List<Map<String, dynamic>>> Function()? carregarEmpresas;

  const EmailSmtpScreen({super.key, this.carregarEmpresas});

  @override
  State<EmailSmtpScreen> createState() => _EmailSmtpScreenState();
}

class _EmailSmtpScreenState extends State<EmailSmtpScreen> {
  List<Map<String, dynamic>> _empresas = [];
  bool _carregando = true;
  Map<String, dynamic>? _selecionada;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final lista = await (widget.carregarEmpresas ?? DropdownHelpers.empresas)();
    if (!mounted) return;
    setState(() {
      _empresas = lista;
      _carregando = false;
    });
  }

  int? _idDe(Map<String, dynamic> empresa) =>
      int.tryParse('${empresa['value'] ?? empresa['id']}');

  String _nomeDe(Map<String, dynamic> empresa) =>
      '${empresa['label'] ?? empresa['nome'] ?? empresa['id']}';

  @override
  Widget build(BuildContext context) {
    final id = _selecionada == null ? null : _idDe(_selecionada!);
    return Scaffold(
      appBar: AppBar(title: const Text('E-mail (SMTP)')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<Map<String, dynamic>>(
                  key: const Key('email_smtp_empresa'),
                  initialValue: _selecionada,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Empresa',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final e in _empresas)
                      DropdownMenuItem(value: e, child: Text(_nomeDe(e), overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (e) => setState(() => _selecionada = e),
                ),
                const SizedBox(height: 16),
                if (id == null)
                  const Text('Escolha a empresa para configurar o e-mail de envio.')
                else
                  SmtpConfigTab(
                    key: ValueKey('smtp_empresa_$id'),
                    scope: SmtpConfigScope.empresa,
                    id: id,
                    nome: _nomeDe(_selecionada!),
                  ),
              ],
            ),
    );
  }
}
