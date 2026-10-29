import 'package:flutter/material.dart';

import '../services/network_caller.dart';
import '../config/api_links.dart';
import '../utils/app_logger.dart';

enum SmtpConfigScope { empresa, parceiro }

class SmtpConfigTab extends StatefulWidget {
  final SmtpConfigScope scope;
  final int id;
  final String? nome;

  const SmtpConfigTab({
    super.key,
    required this.scope,
    required this.id,
    this.nome,
  });

  @override
  State<SmtpConfigTab> createState() => _SmtpConfigTabState();
}

class _SmtpConfigTabState extends State<SmtpConfigTab> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _portaController = TextEditingController(text: '587');
  final _usuarioController = TextEditingController();
  final _senhaController = TextEditingController();
  final _remetenteEmailController = TextEditingController();
  final _remetenteNomeController = TextEditingController();
  final _timeoutController = TextEditingController(text: '10000');

  bool _ativo = false;
  bool _testando = false;
  bool _auth = true;
  bool _starttls = true;
  bool _ssl = false;
  bool _senhaConfigurada = false;
  bool _loading = true;
  bool _saving = false;
  bool _removing = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    if (widget.id <= 0) {
      _loading = false;
    } else {
      _carregar();
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portaController.dispose();
    _usuarioController.dispose();
    _senhaController.dispose();
    _remetenteEmailController.dispose();
    _remetenteNomeController.dispose();
    _timeoutController.dispose();
    super.dispose();
  }

  String get _endpoint => widget.scope == SmtpConfigScope.empresa
      ? ApiLinks.smtpConfigEmpresa(widget.id)
      : ApiLinks.smtpConfigParceiro(widget.id);

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erro = null;
    });

    final response = await NetworkCaller().getRequest(_endpoint);
    if (!mounted) return;

    if (response.isSuccess && response.body is Map<String, dynamic>) {
      _preencher(response.body as Map<String, dynamic>);
    } else if (!response.isSuccess && response.statusCode != 204) {
      _erro = 'Nao foi possivel carregar SMTP (HTTP ${response.statusCode}).';
    }

    setState(() => _loading = false);
  }

  void _preencher(Map<String, dynamic> json) {
    _ativo = json['ativo'] == true;
    _hostController.text = json['host']?.toString() ?? '';
    _portaController.text = json['porta']?.toString() ?? '587';
    _usuarioController.text = json['usuario']?.toString() ?? '';
    _senhaController.clear();
    _senhaConfigurada = json['senhaConfigurada'] == true;
    _remetenteEmailController.text = json['remetenteEmail']?.toString() ?? '';
    _remetenteNomeController.text = json['remetenteNome']?.toString() ?? '';
    _auth = json['auth'] != false;
    _starttls = json['starttls'] != false;
    _ssl = json['ssl'] == true;
    _timeoutController.text = json['timeoutMs']?.toString() ?? '10000';
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _erro = null;
    });

    final body = <String, dynamic>{
      'ativo': _ativo,
      'host': _hostController.text.trim(),
      'porta': int.tryParse(_portaController.text.trim()),
      'usuario': _usuarioController.text.trim(),
      'remetenteEmail': _remetenteEmailController.text.trim(),
      'remetenteNome': _remetenteNomeController.text.trim(),
      'auth': _auth,
      'starttls': _starttls,
      'ssl': _ssl,
      'timeoutMs': int.tryParse(_timeoutController.text.trim()) ?? 10000,
    };
    if (_senhaController.text.trim().isNotEmpty) {
      body['senha'] = _senhaController.text.trim();
    }

    final response = await NetworkCaller().putRequest(_endpoint, body);
    if (!mounted) return;

    if (response.isSuccess && response.body is Map<String, dynamic>) {
      _preencher(response.body as Map<String, dynamic>);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuracao SMTP salva.')),
      );
    } else {
      _erro = 'Nao foi possivel salvar SMTP (HTTP ${response.statusCode}).';
    }

    setState(() => _saving = false);
  }

  /// Envia um e-mail de teste, com a configuracao SALVA, para o e-mail de quem esta logado.
  Future<void> _testar() async {
    setState(() {
      _testando = true;
      _erro = null;
    });

    String mensagem;
    try {
      final response = await NetworkCaller().postRequest('$_endpoint/testar', {});
      final texto = response.body?['mensagem']?.toString();
      mensagem = response.isSuccess
          ? (texto ?? 'Teste concluido.')
          : 'Nao foi possivel testar (HTTP ${response.statusCode}).';
    } catch (e, st) {
      AppLogger.i.error('SmtpConfigTab: erro ao testar SMTP: $e', st);
      mensagem = 'Nao foi possivel testar: $e';
    }
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        duration: const Duration(seconds: 8),
      ),
    );
    setState(() => _testando = false);
  }

  Future<void> _remover() async {
    setState(() {
      _removing = true;
      _erro = null;
    });

    final response = await NetworkCaller().deleteRequest(_endpoint);
    if (!mounted) return;

    if (response.isSuccess) {
      _limpar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuracao SMTP removida.')),
      );
    } else {
      _erro = 'Nao foi possivel remover SMTP (HTTP ${response.statusCode}).';
    }

    setState(() => _removing = false);
  }

  void _limpar() {
    _ativo = false;
    _hostController.clear();
    _portaController.text = '587';
    _usuarioController.clear();
    _senhaController.clear();
    _senhaConfigurada = false;
    _remetenteEmailController.clear();
    _remetenteNomeController.clear();
    _auth = true;
    _starttls = true;
    _ssl = false;
    _timeoutController.text = '10000';
  }

  String? _validarObrigatorio(String? value, String label) {
    if (!_ativo) return null;
    if (value == null || value.trim().isEmpty) return '$label e obrigatorio.';
    return null;
  }

  String? _validarPorta(String? value) {
    if (!_ativo) return null;
    final porta = int.tryParse(value?.trim() ?? '');
    if (porta == null || porta < 1 || porta > 65535) {
      return 'Porta SMTP invalida.';
    }
    return null;
  }

  String? _validarTimeout(String? value) {
    final timeout = int.tryParse(value?.trim() ?? '');
    if (timeout == null || timeout < 1000 || timeout > 60000) {
      return 'Timeout deve ficar entre 1000 e 60000 ms.';
    }
    return null;
  }

  String? _validarEmail(String? value) {
    if (!_ativo) return null;
    final email = value?.trim() ?? '';
    if (email.isEmpty || !email.contains('@'))
      return 'Email remetente invalido.';
    return null;
  }

  String? _validarSenha(String? value) {
    if (!_ativo || !_auth || _senhaConfigurada) return null;
    if (value == null || value.trim().isEmpty) {
      return 'Senha SMTP e obrigatoria para autenticacao.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.mail_outline),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'SMTP ${widget.nome == null ? '' : '- ${widget.nome}'}',
                      style: Theme.of(context).textTheme.titleLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Recarregar',
                    onPressed: _carregar,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_erro != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_erro!,
                      style: TextStyle(color: Colors.red.shade800)),
                ),
                const SizedBox(height: 16),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('SMTP ativo'),
                value: _ativo,
                onChanged: (value) => setState(() => _ativo = value),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _field(_hostController, 'Host SMTP',
                      validator: (v) => _validarObrigatorio(v, 'Host SMTP')),
                  _field(_portaController, 'Porta',
                      keyboardType: TextInputType.number,
                      validator: _validarPorta),
                  _field(_usuarioController, 'Usuario',
                      validator: (v) => _validarObrigatorio(v, 'Usuario SMTP')),
                  _field(
                    _senhaController,
                    _senhaConfigurada ? 'Senha (manter atual)' : 'Senha',
                    obscureText: true,
                    validator: _validarSenha,
                  ),
                  _field(_remetenteEmailController, 'Email remetente',
                      validator: _validarEmail),
                  _field(_remetenteNomeController, 'Nome remetente'),
                  _field(_timeoutController, 'Timeout ms',
                      keyboardType: TextInputType.number,
                      validator: _validarTimeout),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Autenticacao'),
                    selected: _auth,
                    onSelected: (value) => setState(() => _auth = value),
                  ),
                  FilterChip(
                    label: const Text('STARTTLS'),
                    selected: _starttls,
                    onSelected: (value) {
                      setState(() {
                        _starttls = value;
                        if (value) _ssl = false;
                      });
                    },
                  ),
                  FilterChip(
                    label: const Text('SSL'),
                    selected: _ssl,
                    onSelected: (value) {
                      setState(() {
                        _ssl = value;
                        if (value) _starttls = false;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _saving ? null : _salvar,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Salvar SMTP'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _removing ? null : _remover,
                    icon: _removing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline),
                    label: const Text('Remover'),
                  ),
                  if (widget.scope == SmtpConfigScope.empresa) ...[
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      key: const Key('smtp_testar'),
                      onPressed: _testando ? null : _testar,
                      icon: _testando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.forward_to_inbox_outlined),
                      label: const Text('Testar'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool obscureText = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return SizedBox(
      width: 300,
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          isDense: true,
        ),
      ),
    );
  }
}
