import 'package:flutter/material.dart';

import '../services/relatorio_personalizado_service.dart';

/// Rótulos amigáveis das bandas do relatório avançado.
const Map<String, String> kNomesBandas = {
  'titulo': 'Título (1ª página)',
  'cabecalhoPagina': 'Cabeçalho de página',
  'detalhe': 'Detalhe (1 por linha)',
  'resumo': 'Resumo (final)',
  'rodapePagina': 'Rodapé de página',
};

const _formatos = ['TEXTO', 'NUMERO', 'MOEDA', 'PERCENTUAL', 'DATA'];
const _agregados = ['SOMA', 'CONTAGEM', 'MEDIA', 'MINIMO', 'MAXIMO'];
const double kMargemLateral = 28;

/// Largura útil da página (pontos) para a orientação.
double larguraUtil(String orientacao) => (orientacao == 'PAISAGEM' ? 842.0 : 595.0) - 2 * kMargemLateral;

/// Layout inicial a partir das colunas do SQL: título, cabeçalho com os nomes, detalhe com os campos lado a lado,
/// resumo com a soma das colunas marcadas e rodapé com a página.
RelLayout layoutInicial(String titulo, List<RelColuna> colunas, String orientacao) {
  final util = larguraUtil(orientacao);
  final n = colunas.isEmpty ? 1 : colunas.length;
  final larg = (util / n).floorToDouble();
  final cab = <RelElemento>[];
  final det = <RelElemento>[];
  final res = <RelElemento>[];
  for (var i = 0; i < colunas.length; i++) {
    final c = colunas[i];
    final num = c.formato != 'TEXTO' && c.formato != 'DATA';
    final x = i * larg;
    cab.add(RelElemento(tipo: 'TEXTO', x: x, y: 2, largura: larg - 4, altura: 14, texto: c.rotulo, negrito: true, tamanho: 9,
        alinhamento: num ? 'DIREITA' : 'ESQUERDA', fundo: '#E8F5E9'));
    det.add(RelElemento(tipo: 'CAMPO', x: x, y: 1, largura: larg - 4, altura: 14, campo: c.nome, formato: c.formato,
        tamanho: 9, alinhamento: num ? 'DIREITA' : 'ESQUERDA'));
    if (c.total) {
      res.add(RelElemento(tipo: 'CAMPO', x: x, y: 6, largura: larg - 4, altura: 14, campo: c.nome, formato: c.formato,
          agregado: 'SOMA', negrito: true, tamanho: 9, alinhamento: 'DIREITA'));
    }
  }
  return RelLayout(
    titulo: RelBanda(altura: 40, elementos: [
      RelElemento(tipo: 'TEXTO', x: 0, y: 2, largura: util, altura: 22, texto: titulo.isEmpty ? r'${TITULO}' : titulo, negrito: true, tamanho: 16),
      const RelElemento(tipo: 'TEXTO', x: 0, y: 26, largura: 300, altura: 12, texto: r'Gerado em ${DATA}', tamanho: 8, cor: '#666666'),
    ]),
    cabecalhoPagina: RelBanda(altura: 20, elementos: cab),
    detalhe: RelBanda(altura: 16, elementos: det),
    resumo: res.isEmpty ? null : RelBanda(altura: 26, elementos: [
      RelElemento(tipo: 'LINHA', x: 0, y: 1, largura: util, altura: 1),
      ...res,
    ]),
    rodapePagina: RelBanda(altura: 16, elementos: [
      RelElemento(tipo: 'PAGINA', x: util - 100, y: 2, largura: 100, altura: 12, tamanho: 8, alinhamento: 'DIREITA'),
    ]),
  );
}

/// Designer visual do relatório avançado: bandas empilhadas, elementos que se arrastam (mover), redimensionam
/// (alça no canto) e recebem colunas arrastadas da paleta. O resultado ([onAplicar]) é o [RelLayout] a salvar.
class RelatorioDesignerView extends StatefulWidget {
  final RelLayout layout;
  final List<String> colunas;
  final String orientacao;
  final String titulo;
  final List<RelColuna> configColunas;
  final void Function(RelLayout layout) onAplicar;
  final VoidCallback onCancelar;
  final Future<void> Function(RelLayout layout)? onPrevia;

  const RelatorioDesignerView({
    super.key,
    required this.layout,
    required this.colunas,
    required this.orientacao,
    required this.titulo,
    this.configColunas = const [],
    required this.onAplicar,
    required this.onCancelar,
    this.onPrevia,
  });

  @override
  State<RelatorioDesignerView> createState() => _RelatorioDesignerViewState();
}

class _RelatorioDesignerViewState extends State<RelatorioDesignerView> {
  late RelLayout _layout = widget.layout;
  String _bandaSel = 'detalhe';
  int? _elSel;
  final Map<String, GlobalKey> _chaves = {for (final n in RelLayout.nomes) n: GlobalKey()};

  double get _util => larguraUtil(widget.orientacao);

  RelBanda _banda(String nome) => _layout.banda(nome) ?? const RelBanda(altura: 24);

  RelElemento? get _selecionado {
    final b = _layout.banda(_bandaSel);
    if (b == null || _elSel == null || _elSel! >= b.elementos.length) return null;
    return b.elementos[_elSel!];
  }

  void _setBanda(String nome, RelBanda b) => setState(() => _layout = _layout.comBanda(nome, b));

  void _atualizarElemento(String banda, int i, RelElemento novo) {
    final b = _banda(banda);
    final els = [...b.elementos]..[i] = novo;
    _setBanda(banda, b.copiar(elementos: els));
  }

  void _adicionar(String tipo, {String? campo, double? x, double? y}) {
    final nome = _bandaSel;
    final b = _banda(nome);
    final proximo = switch (tipo) {
      'TEXTO' => const RelElemento(tipo: 'TEXTO', largura: 140, altura: 14, texto: 'Texto'),
      'CAMPO' => RelElemento(tipo: 'CAMPO', largura: 120, altura: 14, campo: campo ?? (widget.colunas.isEmpty ? null : widget.colunas.first)),
      'LINHA' => RelElemento(tipo: 'LINHA', largura: _util, altura: 1),
      'RETANGULO' => const RelElemento(tipo: 'RETANGULO', largura: 120, altura: 14),
      _ => const RelElemento(tipo: 'PAGINA', largura: 100, altura: 12),
    };
    final posicionado = proximo.copiar(
      x: (x ?? 0).clamp(0, (_util - proximo.largura).clamp(0, _util)).toDouble(),
      y: (y ?? 0).clamp(0, (b.altura - proximo.altura).clamp(0, b.altura)).toDouble(),
    );
    setState(() {
      _layout = _layout.comBanda(nome, b.copiar(elementos: [...b.elementos, posicionado]));
      _elSel = b.elementos.length;
    });
  }

  void _remover() {
    final b = _banda(_bandaSel);
    if (_elSel == null || _elSel! >= b.elementos.length) return;
    final els = [...b.elementos]..removeAt(_elSel!);
    setState(() {
      _layout = _layout.comBanda(_bandaSel, b.copiar(elementos: els));
      _elSel = null;
    });
  }

  void _ligarBanda(String nome, bool ligada) {
    if (nome == 'detalhe') return;
    setState(() {
      _layout = _layout.comBanda(nome, ligada ? const RelBanda(altura: 24) : null);
      if (!ligada && _bandaSel == nome) {
        _bandaSel = 'detalhe';
        _elSel = null;
      }
    });
  }

  void _gerarInicial() {
    final cols = widget.colunas.map((nome) {
      final cfg = widget.configColunas.where((c) => c.nome.toLowerCase() == nome.toLowerCase());
      return cfg.isNotEmpty ? cfg.first : RelColuna(nome: nome, rotulo: nome);
    }).toList();
    setState(() {
      _layout = layoutInicial(widget.titulo, cols, widget.orientacao);
      _elSel = null;
      _bandaSel = 'detalhe';
    });
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selecionado;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Banda: ${kNomesBandas[_bandaSel]}', style: const TextStyle(fontWeight: FontWeight.w600)),
          for (final t in const [('TEXTO', 'Texto'), ('CAMPO', 'Campo'), ('LINHA', 'Linha'), ('RETANGULO', 'Retângulo'), ('PAGINA', 'Página')])
            OutlinedButton(onPressed: () => _adicionar(t.$1), child: Text('+ ${t.$2}')),
          TextButton.icon(onPressed: _gerarInicial, icon: const Icon(Icons.auto_fix_high), label: const Text('Layout inicial')),
          if (widget.onPrevia != null)
            TextButton.icon(onPressed: () => widget.onPrevia!(_layout), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Prévia PDF')),
        ]),
      ),
      if (widget.colunas.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('Arraste uma coluna para a banda:', style: TextStyle(fontSize: 12)),
            for (final c in widget.colunas)
              Draggable<String>(
                data: c,
                feedback: Material(child: Chip(label: Text(c))),
                child: Chip(key: Key('coluna_$c'), label: Text(c), avatar: const Icon(Icons.drag_indicator, size: 16)),
              ),
          ]),
        ),
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final nome in RelLayout.nomes) _bandaWidget(nome),
                ]),
              ),
            ),
          ),
          SizedBox(width: 250, child: _painel(sel)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.all(8),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: widget.onCancelar, child: const Text('Cancelar')),
          const SizedBox(width: 8),
          FilledButton(onPressed: () => widget.onAplicar(_layout), child: const Text('Aplicar layout')),
        ]),
      ),
    ]);
  }

  // ------------------------------------------------------------------ bandas e elementos

  Widget _bandaWidget(String nome) {
    final b = _layout.banda(nome);
    final ligada = b != null;
    final selecionada = _bandaSel == nome;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (nome != 'detalhe')
            Checkbox(
                key: Key('banda_$nome'),
                value: ligada,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => _ligarBanda(nome, v ?? false)),
          Text(kNomesBandas[nome]!, style: TextStyle(fontWeight: selecionada ? FontWeight.bold : FontWeight.normal)),
          if (ligada) ...[
            const SizedBox(width: 12),
            const Text('altura', style: TextStyle(fontSize: 12)),
            SizedBox(
              width: 70,
              child: TextFormField(
                key: Key('altura_$nome'),
                initialValue: b.altura.toStringAsFixed(0),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(isDense: true),
                onChanged: (v) {
                  final h = double.tryParse(v);
                  if (h != null && h >= 5 && h <= 400) _setBanda(nome, b.copiar(altura: h));
                },
              ),
            ),
          ],
        ]),
        if (ligada)
          DragTarget<String>(
            onAcceptWithDetails: (d) {
              final caixa = _chaves[nome]!.currentContext?.findRenderObject() as RenderBox?;
              final local = caixa?.globalToLocal(d.offset) ?? Offset.zero;
              setState(() => _bandaSel = nome);
              _adicionar('CAMPO', campo: d.data, x: local.dx, y: local.dy);
            },
            builder: (context, candidatos, _) => GestureDetector(
              onTap: () => setState(() {
                _bandaSel = nome;
                _elSel = null;
              }),
              child: Container(
                key: _chaves[nome],
                width: _util,
                height: b.altura,
                decoration: BoxDecoration(
                  color: candidatos.isNotEmpty ? Colors.green.shade50 : Colors.white,
                  border: Border.all(color: selecionada ? Theme.of(context).colorScheme.primary : Colors.grey.shade400, width: selecionada ? 2 : 1),
                ),
                child: Stack(clipBehavior: Clip.none, children: [
                  for (var i = 0; i < b.elementos.length; i++) _elementoWidget(nome, b, i),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _elementoWidget(String banda, RelBanda b, int i) {
    final e = b.elementos[i];
    final selecionado = _bandaSel == banda && _elSel == i;
    return Positioned(
      left: e.x,
      top: e.y,
      width: e.largura,
      height: e.altura,
      child: GestureDetector(
        key: Key('el_${banda}_$i'),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _bandaSel = banda;
          _elSel = i;
        }),
        onPanStart: (_) => setState(() {
          _bandaSel = banda;
          _elSel = i;
        }),
        onPanUpdate: (d) {
          final nx = (e.x + d.delta.dx).clamp(0, (_util - e.largura).clamp(0, _util)).toDouble();
          final ny = (e.y + d.delta.dy).clamp(0, (b.altura - e.altura).clamp(0, b.altura)).toDouble();
          _atualizarElemento(banda, i, e.copiar(x: nx, y: ny));
        },
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: _conteudo(e, selecionado)),
          if (selecionado)
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                key: Key('alca_${banda}_$i'),
                onPanUpdate: (d) {
                  final nl = (e.largura + d.delta.dx).clamp(4, _util - e.x).toDouble();
                  final na = (e.altura + d.delta.dy).clamp(1, b.altura - e.y).toDouble();
                  _atualizarElemento(banda, i, e.copiar(largura: nl, altura: na));
                },
                child: Container(width: 12, height: 12, color: Theme.of(context).colorScheme.primary),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _conteudo(RelElemento e, bool selecionado) {
    final borda = selecionado ? Border.all(color: Theme.of(context).colorScheme.primary, width: 1.5) : Border.all(color: Colors.black12);
    Widget corpo;
    switch (e.tipo) {
      case 'LINHA':
        corpo = Center(child: Container(height: e.altura.clamp(1, 6), color: _cor(e.cor) ?? Colors.black));
      case 'RETANGULO':
        corpo = Container(decoration: BoxDecoration(color: _cor(e.fundo), border: Border.all(color: _cor(e.cor) ?? Colors.black)));
      default:
        final texto = switch (e.tipo) {
          'PAGINA' => 'Página N',
          'CAMPO' => e.agregado != null ? '${e.agregado}(${e.campo ?? '?'})' : '[${e.campo ?? '?'}]',
          _ => e.texto ?? '',
        };
        corpo = Container(
          color: _cor(e.fundo),
          alignment: switch (e.alinhamento) {
            'DIREITA' => Alignment.centerRight,
            'CENTRO' => Alignment.center,
            _ => Alignment.centerLeft,
          },
          child: Text(texto,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(fontSize: e.tamanho.clamp(4, 40), fontWeight: e.negrito ? FontWeight.bold : FontWeight.normal, color: _cor(e.cor) ?? Colors.black)),
        );
    }
    return DecoratedBox(decoration: BoxDecoration(border: borda), child: corpo);
  }

  static Color? _cor(String? hex) {
    if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }

  // ------------------------------------------------------------------ painel de propriedades

  Widget _painel(RelElemento? e) {
    if (e == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Toque num elemento para editar. Arraste para mover e use a alça do canto para redimensionar.\n\n'
            'Texto aceita \${campo}, \${PAGINA}, \${DATA}, \${TITULO} e \${FILTROS}. Em Título, Resumo e Rodapé, '
            'um Campo pode agregar (Soma, Contagem, Média...).'),
      );
    }
    final i = _elSel!;
    void mudar(RelElemento novo) => _atualizarElemento(_bandaSel, i, novo);
    Widget num(String rotulo, double valor, void Function(double) f, {Key? key}) => SizedBox(
          width: 100,
          child: TextFormField(
            key: key ?? ValueKey('$rotulo-${_bandaSel}_$i-$valor'),
            initialValue: valor.toStringAsFixed(valor == valor.roundToDouble() ? 0 : 1),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: rotulo, isDense: true),
            onChanged: (v) {
              final d = double.tryParse(v.replaceAll(',', '.'));
              if (d != null) f(d);
            },
          ),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Elemento ${e.tipo}', style: const TextStyle(fontWeight: FontWeight.w600))),
          IconButton(key: const Key('remover_elemento'), tooltip: 'Remover elemento', onPressed: _remover, icon: const Icon(Icons.delete_outline)),
        ]),
        Wrap(spacing: 8, runSpacing: 6, children: [
          num('X', e.x, (v) => mudar(e.copiar(x: v.clamp(0, _util - e.largura).toDouble()))),
          num('Y', e.y, (v) => mudar(e.copiar(y: v < 0 ? 0 : v))),
          num('Largura', e.largura, (v) => mudar(e.copiar(largura: v < 1 ? 1 : v))),
          num('Altura', e.altura, (v) => mudar(e.copiar(altura: v < 1 ? 1 : v))),
        ]),
        if (e.tipo == 'TEXTO')
          TextFormField(
            key: ValueKey('texto-${_bandaSel}_$i'),
            initialValue: e.texto ?? '',
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Texto'),
            onChanged: (v) => mudar(e.copiar(texto: v)),
          ),
        if (e.tipo == 'CAMPO') ...[
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: widget.colunas.contains(e.campo) ? e.campo : null,
            decoration: const InputDecoration(labelText: 'Coluna'),
            items: [for (final c in widget.colunas) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => mudar(e.copiar(campo: v)),
          ),
          DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: e.formato,
            decoration: const InputDecoration(labelText: 'Formato'),
            items: [const DropdownMenuItem<String?>(value: null, child: Text('Automático')), for (final f in _formatos) DropdownMenuItem<String?>(value: f, child: Text(f))],
            onChanged: (v) => mudar(e.copiar(formato: v)),
          ),
          if (_bandaSel != 'detalhe')
            DropdownButtonFormField<String?>(
              isExpanded: true,
              initialValue: e.agregado,
              decoration: const InputDecoration(labelText: 'Agregação'),
              items: [const DropdownMenuItem<String?>(value: null, child: Text('Valor da 1ª linha')), for (final a in _agregados) DropdownMenuItem<String?>(value: a, child: Text(a))],
              onChanged: (v) => mudar(e.copiar(agregado: v)),
            ),
        ],
        if (e.tipo == 'TEXTO' || e.tipo == 'CAMPO' || e.tipo == 'PAGINA') ...[
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            num('Fonte', e.tamanho, (v) => mudar(e.copiar(tamanho: v.clamp(4, 72).toDouble()))),
            FilterChip(label: const Text('Negrito'), selected: e.negrito, onSelected: (v) => mudar(e.copiar(negrito: v))),
          ]),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'ESQUERDA', icon: Icon(Icons.format_align_left)),
              ButtonSegment(value: 'CENTRO', icon: Icon(Icons.format_align_center)),
              ButtonSegment(value: 'DIREITA', icon: Icon(Icons.format_align_right)),
            ],
            selected: {e.alinhamento},
            onSelectionChanged: (s) => mudar(e.copiar(alinhamento: s.first)),
          ),
        ],
        const SizedBox(height: 6),
        _seletorCor('Cor', e.cor, (c) => mudar(e.copiar(cor: c))),
        if (e.tipo != 'LINHA') _seletorCor('Fundo', e.fundo, (c) => mudar(e.copiar(fundo: c))),
      ]),
    );
  }

  Widget _seletorCor(String rotulo, String? atual, void Function(String?) f) {
    const cores = ['#000000', '#666666', '#2E7D32', '#1565C0', '#C62828', '#E8F5E9', '#EEEEEE', '#FFF9C4'];
    return Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text('$rotulo:', style: const TextStyle(fontSize: 12)),
      for (final c in cores)
        InkWell(
          key: Key('cor_${rotulo}_$c'),
          onTap: () => f(c),
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(color: _cor(c), border: Border.all(color: atual == c ? Colors.black : Colors.black26, width: atual == c ? 2 : 1)),
          ),
        ),
      IconButton(tooltip: 'Sem $rotulo'.toLowerCase(), visualDensity: VisualDensity.compact, onPressed: () => f(null), icon: const Icon(Icons.block, size: 16)),
    ]);
  }
}
