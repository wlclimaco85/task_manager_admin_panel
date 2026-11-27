import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/acao_java_service.dart';
import '../services/planilha_service.dart';
import '../utils/app_logger.dart';
import 'package:file_saver/file_saver.dart';
import '../utils/grid_colors.dart';
import '../utils/planilha_acao.dart';
import '../utils/planilha_acrescentar.dart';
import '../utils/planilha_formula.dart';
import '../utils/planilha_tenant.dart';
import '../utils/planilha_tipos.dart';
import '../utils/tenant_context.dart';
import 'coluna_planilha_dialogs.dart';
import 'compartilhar_planilha_dialog.dart';
import 'importar_planilha_dialog.dart';
import 'planilha_botoes.dart';

/// Planilha tipo Excel: celulas com formulas, colar do Excel, importar/exportar .xlsx, salvar por empresa/parceiro e
/// (MASTER) trazer dados do sistema com SELECT. Cores somente pelos tokens GridColors do proprio app.
class PlanilhaView extends StatefulWidget {
  final PlanilhaService? servico;
  final AcaoJavaService? acoes;
  final SessaoTenant? sessao;
  final bool? podeConsultar;

  const PlanilhaView({super.key, this.servico, this.podeConsultar, this.acoes, this.sessao});

  @override
  State<PlanilhaView> createState() => _PlanilhaViewState();
}

class _PlanilhaViewState extends State<PlanilhaView> {
  static const double _alturaLinha = 44;
  static const double _larguraColuna = 120;
  static const double _larguraIndice = 52;

  late final PlanilhaService _svc = widget.servico ?? PlanilhaService();
  late final AcaoJavaService _acoesSvc = widget.acoes ?? AcaoJavaService();
  late final bool _podeConsultar = widget.podeConsultar ?? TenantContext.isMaster;

  final _nome = TextEditingController(text: 'Nova planilha');
  final _barra = TextEditingController();
  final _celula = TextEditingController();

  List<PlanilhaResumo> _salvas = const [];
  int? _id;
  Map<String, String> _celulas = {};
  late PlanilhaCalculo _calculo = PlanilhaCalculo(_celulas);
  int _linha = 0;
  int _coluna = 0;
  bool _alterada = false;
  bool _ocupado = false;

  Map<String, ColunaPlanilha> _colunas = {};
  int? _versao;
  bool _dono = true;
  bool _podeEditar = true;

  /// Botoes de Modulo Java desta planilha (so planilha salva).
  List<AcaoJava> _botoes = const [];

  /// Tipos e compartilhamento pertencem a planilha do usuario; modelos publicados nao os guardam.
  bool get _planilhaDoUsuario => true;

  String get _selecionada => endereco(_linha, _coluna);

  late final SessaoTenant _sessao = widget.sessao ?? SessaoTenant.doLogin();

  Map<String, String> _comTenant(Map<String, String> celulas) =>
      _planilhaDoUsuario ? fixarTenant(celulas, _sessao) : celulas;

  bool _ehColunaDeTenant(int coluna) => _planilhaDoUsuario && colunasDeTenant(_celulas).containsKey(coluna);

  /// empresa_id e parceiro_id sao bloqueados para todos menos o MASTER.
  bool _bloqueada(int coluna) => !_sessao.master && _sessao.empresa != null && _ehColunaDeTenant(coluna);

  @override
  void initState() {
    super.initState();
    // planilha nova ja nasce com a empresa do login
    _celulas = cabecalhosDoTenant(_sessao);
    _calculo = PlanilhaCalculo(_celulas);
    _coluna = _celulas.length;
    _sincronizar();
    _executar('carregar as planilhas', () async => _salvas = await _svc.listar());
  }

  @override
  void dispose() {
    _nome.dispose();
    _barra.dispose();
    _celula.dispose();
    super.dispose();
  }

  Future<void> _executar(String acao, Future<void> Function() tarefa) async {
    setState(() => _ocupado = true);
    try {
      await tarefa();
    } catch (e, s) {
      AppLogger.i.warn('PlanilhaView: erro ao $acao: $e | $s');
      _avisar(e is PlanilhaException ? e.mensagem : 'Não foi possível $acao.', erro: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _avisar(String texto, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(texto), backgroundColor: erro ? GridColors.error : null));
  }

  Future<bool> _confirmar(String pergunta) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(content: Text(pergunta), actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continuar')),
        ]),
      ) ==
      true;

  Future<bool> _podeDescartar() async =>
      !_alterada || await _confirmar('Há alterações não salvas. Descartar?');

  // ------------------------------------------------------------------ celulas

  void _aposMudanca({bool fixar = true}) {
    _alterada = true;
    if (fixar) _celulas = _comTenant(_celulas);
    _calculo = PlanilhaCalculo(_celulas);
  }

  void _editar(String valor) {
    if (_bloqueada(_coluna)) return;
    // MASTER digitando na propria coluna de empresa/parceiro: nao repreencher no meio da digitacao
    final editandoTenant = _ehColunaDeTenant(_coluna);
    setState(() {
      if (valor.isEmpty) {
        _celulas.remove(_selecionada);
      } else {
        _celulas[_selecionada] = valor;
      }
      _aposMudanca(fixar: !editandoTenant);
    });
  }

  void _selecionar(int linha, int coluna) {
    setState(() {
      _linha = linha.clamp(0, kPlanilhaMaxLinhas - 1);
      _coluna = coluna.clamp(0, kPlanilhaMaxColunas - 1);
      _sincronizar();
    });
  }

  void _sincronizar() {
    final v = _celulas[_selecionada] ?? '';
    _celula.text = v;
    _barra.text = v;
  }

  /// Troca a planilha aberta (conteudo, tipos de coluna, versao e permissoes).
  void _substituir(Map<String, String> celulas, {int? id, String? nome, PlanilhaDados? de}) {
    setState(() {
      final nova = _planilhaDoUsuario && celulas.isEmpty;
      _celulas = nova ? cabecalhosDoTenant(_sessao) : _comTenant(Map.of(celulas));
      _calculo = PlanilhaCalculo(_celulas);
      _id = id;
      _colunas = Map.of(de?.colunas ?? const {});
      _versao = de?.versao;
      _dono = de?.dono ?? true;
      _podeEditar = de?.podeEditar ?? true;
      _botoes = const [];
      if (nome != null) _nome.text = nome;
      _linha = 0;
      _coluna = nova ? _celulas.length : 0;
      _alterada = false;
      _sincronizar();
    });
  }

  // ------------------------------------------------------------------ tipos de coluna e compartilhamento

  Future<void> _tipoDaColuna() async {
    final letra = nomeColuna(_coluna);
    final nova = await showDialog<ColunaPlanilha>(
        context: context, builder: (_) => TipoDeColunaDialog(letra: letra, atual: _colunas[letra]));
    if (nova == null) return;
    setState(() {
      if (nova.tipo == 'texto') {
        _colunas.remove(letra);
      } else {
        _colunas[letra] = nova;
      }
      _alterada = true;
    });
  }

  /// Linha 1 e' o titulo; formula continua aparecendo como formula.
  ColunaPlanilha? _tipoDaCelula(int linha, int coluna) {
    if (linha == 0) return null;
    final tipo = _colunas[nomeColuna(coluna)];
    return (_celulas[endereco(linha, coluna)] ?? '').startsWith('=') ? null : tipo;
  }

  void _definirCelula(int linha, int coluna, String valor) {
    _selecionar(linha, coluna);
    _editar(valor);
    setState(_sincronizar);
  }

  Future<void> _escolherValor(int linha, int coluna, ColunaPlanilha tipo) async {
    _selecionar(linha, coluna);
    final v = await showDialog<String>(
        context: context, builder: (_) => EscolherValorDialog(coluna: tipo, servico: _svc));
    if (v != null && mounted) _definirCelula(linha, coluna, v.isEmpty ? '' : celulaDeValor(v));
  }

  Future<void> _compartilhar() async {
    final id = _id;
    if (id == null) {
      _avisar('Salve a planilha antes de compartilhar.', erro: true);
      return;
    }
    final salvou = await showDialog<bool>(
        context: context, builder: (_) => CompartilharPlanilhaDialog(servico: _svc, planilhaId: id));
    if (salvou == true) _avisar('Compartilhamento salvo.');
  }

  // ------------------------------------------------------------------ botoes de Modulo Java

  /// Falha aqui nao atrapalha a planilha: so fica sem os botoes (e vai para o log).
  Future<void> _carregarBotoes() async {
    final id = _id;
    if (id == null || !_planilhaDoUsuario) return;
    try {
      final r = [
        ...await _acoesSvc.listarAtivas(kTabelaPlanilha),
        ...await _acoesSvc.listarAtivas('$kTabelaPlanilha:$id'),
      ];
      if (mounted && _id == id) setState(() => _botoes = r);
    } catch (e) {
      AppLogger.i.warn('PlanilhaView: erro ao carregar botoes: $e');
    }
  }

  // sem a barra de "ocupado" de _executar: o fluxo abre dialogos e ela ficaria girando atras deles
  Future<void> _executarBotao(AcaoJava acao) async {
    final id = _id;
    if (id == null) return;
    try {
      final novas = await executarBotaoDaPlanilha(context,
          acao: acao,
          planilhaId: id,
          celulas: Map.of(_celulas),
          linhaAtual: _linha + 1,
          servico: _svc,
          acoes: widget.acoes);
      if (novas == null || !mounted || _id != id) return;
      setState(() {
        _celulas = novas;
        _aposMudanca();
        _sincronizar();
      });
    } catch (e, s) {
      AppLogger.i.warn('PlanilhaView: erro no botao ${acao.label}: $e | $s');
      _avisar('Não foi possível executar a ação.', erro: true);
    }
  }

  Future<void> _gerirBotoes() async {
    final id = _id;
    if (id == null) {
      _avisar('Salve a planilha antes de criar botões.', erro: true);
      return;
    }
    await showDialog<void>(
        context: context, builder: (_) => BotoesDaPlanilhaDialog(planilhaId: id, acoes: widget.acoes));
    await _carregarBotoes();
  }

  Future<bool> _gravarBloco(List<List<String>> bloco) async {
    final ocupadas = [
      for (var l = 0; l < bloco.length; l++)
        for (var c = 0; c < bloco[l].length; c++)
          if (_celulas.containsKey(endereco(_linha + l, _coluna + c))) 1
    ].length;
    if (ocupadas > 1 && !await _confirmar('$ocupadas células preenchidas serão substituídas. Continuar?')) {
      return false;
    }
    if (!inserirBloco(_celulas, _linha, _coluna, bloco)) {
      _avisar('Os dados passam do limite de $kPlanilhaMaxLinhas linhas e $kPlanilhaMaxColunas colunas.', erro: true);
      return false;
    }
    setState(() {
      _aposMudanca();
      _sincronizar();
    });
    return true;
  }

  Future<void> _colar() => _executar('colar', () async {
        final texto = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
        if (texto.isEmpty) {
          _avisar('A área de transferência está vazia.');
          return;
        }
        await _gravarBloco(blocoDeTextoColado(texto));
      });

  // ------------------------------------------------------------------ arquivo

  Future<void> _nova() async {
    if (await _podeDescartar()) _substituir({}, nome: 'Nova planilha');
  }

  Future<void> _abrir(int? id) async {
    if (id == null || !await _podeDescartar()) return;
    await _executar('abrir a planilha', () async {
      final p = await _svc.abrir(id);
      _substituir(p.celulas, id: p.id, nome: p.nome, de: p);
      await _carregarBotoes();
    });
  }

  /// Compartilhada so para consulta: salvar cria uma copia do proprio usuario.
  PlanilhaDados get _atual => PlanilhaDados(
      id: _podeEditar ? _id : null,
      nome: _nome.text.trim(),
      celulas: _celulas,
      colunas: _colunas,
      versao: _podeEditar ? _versao : null);

  Future<void> _salvar() => _executar('salvar a planilha', () async {
        final p = await _svc.salvar(_atual);
        _id = p.id;
        _versao = p.versao;
        _dono = p.dono;
        _podeEditar = p.podeEditar;
        _alterada = false;
        _salvas = await _svc.listar();
        await _carregarBotoes();
        _avisar('Planilha salva.');
      });

  Future<void> _excluir() async {
    final id = _id;
    if (id == null || !await _confirmar('Excluir a planilha "${_nome.text}"? Não é possível desfazer.')) return;
    await _executar('excluir a planilha', () async {
      await _svc.excluir(id);
      _substituir({}, nome: 'Nova planilha');
      _salvas = await _svc.listar();
    });
  }

  Future<void> _importar() => _executar('importar o Excel', () async {
        final escolha = await FilePicker.platform.pickFiles(
            type: FileType.custom, allowedExtensions: const ['xlsx', 'xls'], withData: true);
        final arquivo = escolha?.files.firstOrNull;
        if (arquivo?.bytes == null) return;
        await _aplicarImportacao(await _svc.importar(arquivo!.bytes!, arquivo.name));
      });

  /// Planilha vazia recebe o arquivo direto; com dados, o usuario escolhe acrescentar ou substituir.
  Future<void> _aplicarImportacao(Map<String, String> arquivo) async {
    if (!mounted) return;
    var celulas = arquivo;
    String? resumo;
    if (!soCabecalhosDoTenant(_celulas)) {
      final escolha = await showDialog<EscolhaImportacao>(
          context: context, builder: (_) => ImportarPlanilhaDialog(atual: _celulas, arquivo: arquivo));
      if (escolha == null) return;
      if (!escolha.substituir) {
        try {
          final r = acrescentarLinhas(_celulas, arquivo,
              colunaChave: escolha.colunaChave, repetida: escolha.repetida);
          celulas = r.celulas;
          resumo = '${r.novas} linha(s) nova(s), ${r.atualizadas} atualizada(s), ${r.ignoradas} ignorada(s).';
        } on AcrescentarException catch (e) {
          _avisar(e.mensagem, erro: true);
          return;
        }
      }
    }
    // so o conteudo muda: tipos de coluna, versao e permissoes sao os da planilha aberta
    setState(() {
      _celulas = Map.of(celulas);
      _linha = 0;
      _coluna = 0;
      _aposMudanca();
      _sincronizar();
    });
    if (resumo != null) _avisar(resumo);
  }

  Future<void> _exportar() => _executar('exportar para Excel', () async {
        final bytes = await _svc.exportar(_atual);
        final nome = _nome.text.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final destino = await FileSaver.instance.saveFile(
            name: nome.isEmpty ? 'planilha' : nome,
            bytes: Uint8List.fromList(bytes),
            fileExtension: 'xlsx',
            mimeType: MimeType.other);
        _avisar('Excel gerado: $destino');
      });

  Future<void> _dadosDoSistema() async {
    final r = await showDialog<ConsultaPlanilha>(context: context, builder: (_) => DadosSistemaDialog(servico: _svc));
    if (r == null) return;
    final linhaInicial = _linha, colunaInicial = _coluna;
    final gravou = await _gravarBloco([
      [for (final c in r.colunas) celulaDeValor(c)],
      for (final l in r.linhas) [for (final v in l) celulaDeValor(v)],
    ]);
    // o tipo vale para a coluna inteira, entao so e' aplicado quando os titulos caem na linha 1
    if (gravou && linhaInicial == 0 && r.tipos.isNotEmpty) {
      setState(() {
        for (final t in r.tipos.entries) {
          _colunas[nomeColuna(colunaInicial + t.key)] = t.value;
        }
      });
    }
    if (r.truncado) _avisar('A consulta foi limitada às primeiras ${r.linhas.length} linhas.');
  }

  // ------------------------------------------------------------------ tela

  // o painel admin tem cartao escuro: a cor do texto segue o brilho do GridColors.card do app
  static bool get _escuro => ThemeData.estimateBrightnessForColor(GridColors.card) == Brightness.dark;
  static Color get _tinta => _escuro ? Colors.white : Colors.black87;
  static Color get _tintaSuave => _escuro ? Colors.white70 : Colors.black54;

  static OutlineInputBorder _borda(Color cor, [double largura = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cor, width: largura));

  static BoxDecoration _cartao() => BoxDecoration(
        color: GridColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GridColors.divider),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
      );

  @override
  Widget build(BuildContext context) {
    var ultimaLinha = 0, ultimaColuna = 0;
    for (final ref in _celulas.keys) {
      final p = posicao(ref);
      if (p == null) continue;
      if (p.$1 > ultimaLinha) ultimaLinha = p.$1;
      if (p.$2 > ultimaColuna) ultimaColuna = p.$2;
    }
    final linhas = (ultimaLinha + 30).clamp(100, kPlanilhaMaxLinhas);
    final colunas = (ultimaColuna + 4).clamp(26, kPlanilhaMaxColunas);

    final base = Theme.of(context);
    // Tema local claro com os tokens do app: a grade fica legivel qualquer que seja o tema global.
    final tema = base.copyWith(
      colorScheme: (_escuro ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
        primary: GridColors.primary,
        secondary: GridColors.secondary,
        surface: GridColors.card,
        onSurface: _tinta,
        error: GridColors.error,
      ),
      textTheme: base.textTheme.apply(bodyColor: _tinta, displayColor: _tinta),
      textSelectionTheme: const TextSelectionThemeData(cursorColor: GridColors.primary),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: GridColors.card,
        isDense: true,
        labelStyle: TextStyle(color: _tintaSuave),
        hintStyle: TextStyle(color: _tintaSuave),
        enabledBorder: _borda(GridColors.divider),
        focusedBorder: _borda(GridColors.primary, 1.6),
      ),
    );

    return Theme(
      data: tema,
      child: Material(
        color: GridColors.background,
        child: Column(children: [
          SizedBox(height: 3, child: _ocupado ? const LinearProgressIndicator(color: GridColors.primary) : null),
          Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 8), child: _cabecalho()),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              clipBehavior: Clip.antiAlias,
              decoration: _cartao(),
              child: Column(children: [
                _barraFormula(),
                Expanded(child: _grade(linhas, colunas)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _cabecalho() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: _cartao(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: GridColors.primarySoft, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.grid_on, color: GridColors.primary),
            ),
            SizedBox(
              width: 260,
              child: TextField(
                controller: _nome,
                maxLength: 150,
                onChanged: (_) {
                  if (!_alterada) setState(() => _alterada = true);
                },
                style: TextStyle(fontWeight: FontWeight.w600, color: _tinta),
                decoration: const InputDecoration(labelText: 'Nome da planilha', counterText: ''),
              ),
            ),
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<int>(
                key: ValueKey('salvas-$_id-${_salvas.length}'),
                initialValue: _salvas.any((p) => p.id == _id) ? _id : null,
                isExpanded: true,
                dropdownColor: GridColors.card,
                decoration: const InputDecoration(labelText: 'Abrir planilha salva'),
                items: [
                  for (final p in _salvas)
                    DropdownMenuItem(value: p.id, child: Text(p.nome, overflow: TextOverflow.ellipsis))
                ],
                onChanged: _ocupado ? null : _abrir,
              ),
            ),
            _situacao(),
          ]),
          const SizedBox(height: 10),
          // rolagem horizontal: no celular as acoes nao empurram a grade para fora da tela
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              FilledButton.icon(
                onPressed: _ocupado ? null : _salvar,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(!_podeEditar ? 'Salvar cópia' : 'Salvar'),
                style: FilledButton.styleFrom(
                    backgroundColor: GridColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(44, 44)),
              ),
              _botao(Icons.note_add_outlined, 'Nova', _nova),
              _separador(),
              _botao(Icons.upload_file, 'Importar Excel', _importar),
              _botao(Icons.download, 'Exportar Excel', _exportar),
              _botao(Icons.content_paste, 'Colar', _colar),
              if (_podeConsultar) ...[
                _separador(),
                FilledButton.icon(
                  onPressed: _ocupado ? null : _dadosDoSistema,
                  icon: const Icon(Icons.storage, size: 18),
                  label: const Text('Dados do sistema'),
                  style: FilledButton.styleFrom(
                      backgroundColor: GridColors.secondarySoft,
                      foregroundColor: GridColors.secondary,
                      minimumSize: const Size(44, 44)),
                ),
              ],
              if (_planilhaDoUsuario) ...[
                _botao(Icons.view_column_outlined, 'Tipo da coluna', _tipoDaColuna),
                if (_dono) _botao(Icons.group_add_outlined, 'Compartilhar', _compartilhar),
                if (_podeConsultar) _botao(Icons.smart_button, 'Botões', _gerirBotoes),
                if (_botoes.isNotEmpty) _separador(),
                for (final a in _botoes) _botao(Icons.bolt, a.label, () => _executarBotao(a)),
              ],
              _separador(),
              IconButton(
                tooltip: 'Excluir planilha',
                onPressed: _id == null || _ocupado || !_dono ? null : _excluir,
                color: GridColors.error,
                icon: const Icon(Icons.delete_outline),
              ),
            ]),
          ),
        ]),
      );

  Widget _situacao() {
    final (texto, icone, cor) = _alterada
        ? ('Alterações não salvas', Icons.edit_outlined, GridColors.primary)
        : !_dono
            ? (
                _podeEditar ? 'Compartilhada com você: pode editar' : 'Compartilhada com você: só consulta',
                Icons.group_outlined,
                _tintaSuave
              )
        : _id != null
            ? ('Salva', Icons.check_circle_outline, GridColors.success)
            : ('Ainda não salva', Icons.fiber_new_outlined, _tintaSuave);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icone, size: 18, color: cor),
      const SizedBox(width: 4),
      Text(texto, style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _separador() => Container(
      width: 1, height: 28, margin: const EdgeInsets.symmetric(horizontal: 8), color: GridColors.divider);

  Widget _botao(IconData icone, String texto, VoidCallback aoTocar) => Padding(
        padding: const EdgeInsets.only(left: 8),
        child: OutlinedButton.icon(
          onPressed: _ocupado ? null : aoTocar,
          icon: Icon(icone, size: 18),
          label: Text(texto),
          style: OutlinedButton.styleFrom(
              foregroundColor: GridColors.primary,
              side: const BorderSide(color: GridColors.divider),
              minimumSize: const Size(44, 44)),
        ),
      );

  Widget _barraFormula() => Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: GridColors.divider))),
        child: Row(children: [
          Container(
            width: 64,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: GridColors.primarySoft, borderRadius: BorderRadius.circular(8)),
            child: Text(_selecionada, style: const TextStyle(color: GridColors.primary, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const Key('barra-formula'),
              controller: _barra,
              readOnly: _bloqueada(_coluna),
              style: TextStyle(color: _tinta),
              onChanged: (v) {
                _celula.text = v;
                _editar(v);
              },
              onSubmitted: (_) => _selecionar(_linha + 1, _coluna),
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.functions, size: 18, color: GridColors.primary),
                  hintText: 'Valor ou fórmula, ex.: =SOMA(A1:A10)'),
            ),
          ),
        ]),
      );

  Widget _grade(int linhas, int colunas) {
    const borda = BorderSide(color: GridColors.divider, width: 0.8);
    Widget caixa(double largura, Widget filho,
            {Color? fundo, Border? contorno, Alignment alinhamento = Alignment.centerLeft}) =>
        Container(
          width: largura,
          height: _alturaLinha,
          alignment: alinhamento,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: fundo, border: contorno ?? const Border(right: borda, bottom: borda)),
          child: filho,
        );
    // cabecalho de linha/coluna da celula selecionada fica destacado, como no Excel
    Widget titulo(double largura, String texto, bool ativo) => caixa(
          largura,
          Text(texto,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: ativo ? GridColors.primary : _tintaSuave)),
          fundo: ativo ? GridColors.primarySoft : GridColors.surfaceMuted,
          alinhamento: Alignment.center,
        );
    Widget valor(String ref) {
      final texto = _calculo.exibir(ref);
      final erro = texto.startsWith('#') && (_celulas[ref] ?? '').startsWith('=');
      return caixa(
        _larguraColuna,
        Text(texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: erro ? GridColors.error : _tinta)),
        alinhamento: lerNumero(texto) != null ? Alignment.centerRight : Alignment.centerLeft,
      );
    }

    // caixa de marcar so aparece em linha com dados (ou na selecionada), para nao encher a grade vazia
    final linhasComDados = <int>{for (final ref in _celulas.keys) posicao(ref)?.$1 ?? -1};

    // celula de coluna com tipo; null = celula comum
    Widget? tipada(int l, int c) {
      final tipo = _tipoDaCelula(l, c);
      if (tipo == null) return null;
      final ref = endereco(l, c);
      final selecionada = l == _linha && c == _coluna;
      final texto = _calculo.exibir(ref);
      final contorno = selecionada ? Border.all(color: GridColors.primary, width: 2) : null;
      if (tipo.tipo == 'check') {
        if (!selecionada && !linhasComDados.contains(l)) return null;
        return caixa(
          _larguraColuna,
          Checkbox(
              key: ValueKey('check-$ref'),
              value: marcado(texto),
              activeColor: GridColors.primary,
              onChanged: (v) => _definirCelula(l, c, textoDaCaixa(v == true))),
          contorno: contorno,
          alinhamento: Alignment.center,
        );
      }
      if ((tipo.tipo == 'lista' || tipo.tipo == 'pesquisa') && selecionada) {
        return InkWell(
          key: ValueKey('escolher-$ref'),
          onTap: () => _escolherValor(l, c, tipo),
          child: caixa(
            _larguraColuna,
            Row(children: [
              Expanded(
                  child: Text(texto,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: _tinta))),
              Icon(tipo.tipo == 'lista' ? Icons.arrow_drop_down : Icons.search,
                  size: 18, color: GridColors.primary),
            ]),
            contorno: contorno,
          ),
        );
      }
      return null;
    }

    final temSoma = _colunas.values.any((t) => t.tipo == 'soma');

    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _larguraIndice + colunas * _larguraColuna,
          child: Column(children: [
            Row(children: [
              titulo(_larguraIndice, '', false),
              for (var c = 0; c < colunas; c++) titulo(_larguraColuna, nomeColuna(c), c == _coluna),
            ]),
            Expanded(
              child: ListView.builder(
                itemExtent: _alturaLinha,
                itemCount: linhas,
                itemBuilder: (_, l) => Row(children: [
                  titulo(_larguraIndice, '${l + 1}', l == _linha),
                  for (var c = 0; c < colunas; c++)
                    if (tipada(l, c) case final Widget especial)
                      especial
                    else if (l == _linha && c == _coluna)
                      caixa(
                        _larguraColuna,
                        TextField(
                          key: ValueKey('editor-${endereco(l, c)}'),
                          controller: _celula,
                          readOnly: _bloqueada(c),
                          autofocus: true,
                          style: TextStyle(fontSize: 13, color: _tinta),
                          onChanged: (v) {
                            _barra.text = v;
                            _editar(v);
                          },
                          onSubmitted: (_) => _selecionar(l + 1, c),
                          decoration: const InputDecoration(
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isCollapsed: true,
                          ),
                        ),
                        contorno: Border.all(color: GridColors.primary, width: 2),
                      )
                    else
                      GestureDetector(
                        key: ValueKey(endereco(l, c)),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _selecionar(l, c),
                        child: valor(endereco(l, c)),
                      ),
                ]),
              ),
            ),
            if (temSoma)
              Row(children: [
                titulo(_larguraIndice, 'Σ', false),
                for (var c = 0; c < colunas; c++)
                  caixa(
                    _larguraColuna,
                    Text(
                        _colunas[nomeColuna(c)]?.tipo == 'soma'
                            ? formatarNumero(somaDaColuna(_celulas, _calculo, c))
                            : '',
                        key: ValueKey('soma-${nomeColuna(c)}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _tinta)),
                    fundo: GridColors.surfaceMuted,
                    alinhamento: Alignment.centerRight,
                  ),
              ]),
          ]),
        ),
      ),
    );
  }
}

/// Parte avancada: escolhe a tabela (nomes e rotulos do Dicionario de Dados) e as colunas, ou escreve a consulta,
/// ve a previa e insere na planilha.
class DadosSistemaDialog extends StatefulWidget {
  final PlanilhaService servico;
  const DadosSistemaDialog({super.key, required this.servico});

  @override
  State<DadosSistemaDialog> createState() => _DadosSistemaDialogState();
}

class _DadosSistemaDialogState extends State<DadosSistemaDialog> {
  final _sql = TextEditingController();
  List<FontePlanilha> _fontes = const [];
  String? _tabela;
  Map<String, String> _campos = const {};
  final Set<String> _marcados = {};
  ConsultaPlanilha? _resultado;
  String? _erro;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _executar(() async => _fontes = await widget.servico.fontes());
  }

  @override
  void dispose() {
    _sql.dispose();
    super.dispose();
  }

  Future<void> _executar(Future<void> Function() tarefa) async {
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    try {
      await tarefa();
    } catch (e, s) {
      AppLogger.i.warn('DadosSistemaDialog: $e | $s');
      _erro = '$e';
    }
    if (mounted) setState(() => _ocupado = false);
  }

  Future<void> _escolherTabela(String tabela) => _executar(() async {
        _campos = await widget.servico.campos(tabela);
        _tabela = tabela;
        _marcados
          ..clear()
          ..addAll(_campos.keys);
        _montarSql();
      });

  void _montarSql() {
    final colunas = _campos.keys.where(_marcados.contains);
    // a lista de fontes so tem tabelas com empresa_id, entao o filtro de empresa sempre vale
    _sql.text =
        colunas.isEmpty ? '' : 'SELECT ${colunas.join(', ')}\nFROM $_tabela\nWHERE empresa_id = :empresaId';
    _resultado = null;
  }

  /// Cabecalhos com o rotulo do dicionario quando a coluna veio da tabela escolhida.
  ConsultaPlanilha _comRotulos(ConsultaPlanilha r) {
    final tabela = _tabela;
    final daFonte = tabela == null ? const <String, TipoDaFonte>{} : widget.servico.tiposDe(tabela);
    final tipos = [for (final c in r.colunas) daFonte[c]];
    return ConsultaPlanilha(
        [for (final c in r.colunas) ehColunaDeTenant(c) ? c : _campos[c] ?? c],
        [
          for (final l in r.linhas) [for (var i = 0; i < l.length; i++) valorDaFonte(l[i], tipos[i])]
        ],
        r.truncado,
        sql: _sql.text,
        rotulos: Map.of(_campos),
        tipos: {
          for (var i = 0; i < tipos.length; i++)
            if (tipos[i] != null) i: tipos[i]!.coluna
        });
  }

  Future<void> _consultar() => _executar(() async {
        _resultado = null;
        _resultado = await widget.servico.consultar(_sql.text);
      });

  @override
  Widget build(BuildContext context) {
    final r = _resultado;
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.storage, color: GridColors.primary),
        SizedBox(width: 8),
        Flexible(child: Text('Dados do sistema')),
      ]),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            DropdownMenu<String>(
              expandedInsets: EdgeInsets.zero,
              enableFilter: true,
              requestFocusOnTap: true,
              menuHeight: 300,
              label: const Text('Tabela (Dicionário de Dados)'),
              leadingIcon: const Icon(Icons.table_view),
              dropdownMenuEntries: [
                for (final f in _fontes)
                  DropdownMenuEntry(
                      value: f.tabela, label: f.titulo == f.tabela ? f.tabela : '${f.titulo} (${f.tabela})')
              ],
              onSelected: (t) {
                if (t != null) _escolherTabela(t);
              },
            ),
            if (_campos.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Colunas', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                child: SingleChildScrollView(
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final c in _campos.entries)
                      FilterChip(
                        label: Text(c.value),
                        tooltip: c.key,
                        selected: _marcados.contains(c.key),
                        onSelected: (v) => setState(() {
                          v ? _marcados.add(c.key) : _marcados.remove(c.key);
                          _montarSql();
                        }),
                      )
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              key: const Key('sql'),
              controller: _sql,
              minLines: 5,
              maxLines: 12,
              style: const TextStyle(fontFamily: 'monospace'),
              onChanged: (_) => setState(() => _resultado = null),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Consulta SELECT (avançado)',
                helperText: 'Somente leitura. Filtre a empresa com :empresaId (e :parceiroId se precisar).',
                helperMaxLines: 2,
              ),
            ),
            if (_ocupado) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
            if (_erro != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_erro!, style: const TextStyle(color: GridColors.error)),
              ),
            if (r != null) ...[
              const SizedBox(height: 8),
              Text('${r.linhas.length} linha(s)${r.truncado ? ' (limite atingido)' : ''}. Prévia:'),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [for (final c in r.colunas) DataColumn(label: Text(_campos[c] ?? c))],
                  rows: [
                    for (final l in r.linhas.take(5))
                      DataRow(cells: [for (final v in l) DataCell(Text('${v ?? ''}'))])
                  ],
                ),
              ),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
        OutlinedButton(onPressed: _ocupado ? null : _consultar, child: const Text('Consultar')),
        FilledButton(
          onPressed: r == null || _ocupado ? null : () => Navigator.pop(context, _comRotulos(r)),
          child: const Text('Inserir na célula'),
        ),
      ],
    );
  }
}
