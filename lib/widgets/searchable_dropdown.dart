import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/grid_colors.dart';

/// Modelo de pagina retornada por loaders de dropdown paginados/remotos.
class PaginaDropdown {
  final List<Map<String, dynamic>> items;
  final int total;
  final String? erro;

  const PaginaDropdown(this.items, this.total, {this.erro});
}

/// Reusable searchable dropdown widget.
///
/// Suporta:
/// 1. Lista estatica ([items]): lista carregada em memoria, ordenada
///    alfabeticamente por padrao, com busca local.
/// 2. Busca paginada remota ([loadPage]): popup/dialog com lazy load
///    (infinite scroll de 20 em 20) e busca por LIKE no backend a cada
///    digitacao com debounce.
class SearchableDropdownField extends StatefulWidget {
  final String label;

  /// Currently selected value — the string representation of [valueField].
  final String? value;

  /// The full list of options (usado quando [loadPage] nao e fornecido).
  final List<Map<String, dynamic>> items;

  /// Key inside each map that holds the option\'s unique identifier.
  final String valueField;

  /// Key inside each map that holds the human-readable label.
  final String displayField;

  /// Called whenever the user picks a new item (or clears the selection).
  /// Receives [null] only when [nullable] is true and the user taps "Limpar".
  final ValueChanged<String?> onChanged;

  final bool enabled;
  final bool isRequired;

  /// When [true] a "Limpar selecao" button is shown inside the dialog,
  /// allowing the user to set the value back to [null].
  final bool nullable;

  /// Label shown for the clear-selection button (only relevant when
  /// [nullable] is [true]).
  final String nullLabel;

  /// Placeholder text shown when no item is selected.
  final String? hintText;

  /// Optional validator — receives the current string value and returns an
  /// error message or [null] if valid. Integrates with [Form] / [FormState].
  final String? Function(String?)? validator;

  /// Optional server-side search callback simplificado.
  final Future<List<Map<String, dynamic>>> Function(String query)? onSearch;

  /// Loader paginado server-side (lazy loading / infinite scroll de 20 em 20).
  /// Quando fornecido, abre o popup com scroll infinito e busca remota com LIKE.
  final Future<PaginaDropdown> Function({String? busca, required int pagina})? loadPage;

  /// Funcao assincrona para resolver o rotulo de exibicao quando [value] esta
  /// preenchido mas o item correspondente nao esta carregado em memoria.
  final Future<String?> Function(String id)? labelResolver;

  /// Called with the full selected item map (or `null` on clear) whenever
  /// a selection is made.
  final ValueChanged<Map<String, dynamic>?>? onItemSelected;

  /// Icone opcional exibido no inicio do campo (prefixIcon).
  final IconData? prefixIcon;

  /// Quando [true], a busca abre como um overlay/autocomplete ancorado
  /// logo abaixo do campo em vez de um [Dialog] modal centralizado.
  final bool inline;

  const SearchableDropdownField({
    super.key,
    required this.label,
    this.items = const [],
    required this.valueField,
    required this.displayField,
    required this.onChanged,
    this.value,
    this.enabled = true,
    this.isRequired = false,
    this.nullable = false,
    this.nullLabel = '— Nenhum —',
    this.hintText,
    this.validator,
    this.onSearch,
    this.loadPage,
    this.labelResolver,
    this.onItemSelected,
    this.prefixIcon,
    this.inline = false,
  });

  @override
  State<SearchableDropdownField> createState() =>
      _SearchableDropdownFieldState();
}

class _SearchableDropdownFieldState extends State<SearchableDropdownField> {
  static _SearchableDropdownFieldState? _instanciaComOverlayAberto;

  String? _displayLabel;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  String? _lastResolvedValue;

  @override
  void initState() {
    super.initState();
    _resolveLabel(widget.value);
  }

  @override
  void didUpdateWidget(SearchableDropdownField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == _lastResolvedValue && _displayLabel != null) return;
    if (oldWidget.value != widget.value || oldWidget.items != widget.items) {
      setState(() => _resolveLabel(widget.value));
    }
  }

  void _resolveLabel(String? val) {
    _lastResolvedValue = val;
    if (val == null || val.isEmpty) {
      _displayLabel = null;
      return;
    }
    for (final item in widget.items) {
      if (item[widget.valueField]?.toString() == val) {
        _displayLabel = item[widget.displayField]?.toString();
        return;
      }
    }
    if (widget.labelResolver != null) {
      widget.labelResolver!(val).then((lbl) {
        if (mounted && _lastResolvedValue == val && lbl != null && lbl.isNotEmpty) {
          setState(() => _displayLabel = lbl);
        }
      });
    }
  }

  @override
  void dispose() {
    _closeOverlay();
    super.dispose();
  }

  Future<void> _openSearch() async {
    if (!widget.enabled) return;
    if (widget.inline && widget.loadPage == null) {
      _openInlineOverlay();
      return;
    }
    final result = await showDialog<_DropResult>(
      context: context,
      builder: (_) => _SearchDialog(
        title: widget.label,
        items: widget.items,
        valueField: widget.valueField,
        displayField: widget.displayField,
        currentValue: widget.value,
        nullable: widget.nullable,
        nullLabel: widget.nullLabel,
        onSearch: widget.onSearch,
        loadPage: widget.loadPage,
      ),
    );
    if (result == null) return;
    _aplicarResultado(result);
  }

  void _aplicarResultado(_DropResult result) {
    setState(() {
      if (result.item != null) {
        _displayLabel = result.item![widget.displayField]?.toString() ??
            result.item!['nome']?.toString() ??
            result.item!['razaoSocial']?.toString() ??
            result.value;
        _lastResolvedValue = result.value;
      } else {
        _resolveLabel(result.value);
      }
    });
    widget.onChanged(result.value);
    widget.onItemSelected?.call(result.item);
  }

  void _closeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (identical(_instanciaComOverlayAberto, this)) {
      _instanciaComOverlayAberto = null;
    }
  }

  void _openInlineOverlay() {
    final overlayAberto = _instanciaComOverlayAberto;
    if (overlayAberto != null && !identical(overlayAberto, this)) {
      overlayAberto._closeOverlay();
      if (overlayAberto.mounted) overlayAberto.setState(() {});
    }
    final renderBox = context.findRenderObject() as RenderBox?;
    final fieldWidth = renderBox?.size.width ?? 320.0;
    final fieldSize = renderBox?.size ?? Size.zero;
    final fieldTopLeft =
        renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final screenHeight = MediaQuery.of(context).size.height;

    const margin = 8.0;
    const minUsableHeight = 120.0;
    const preferredMaxHeight = 340.0;

    final spaceBelow =
        screenHeight - (fieldTopLeft.dy + fieldSize.height) - margin;
    final spaceAbove = fieldTopLeft.dy - margin;

    final openUpward = spaceBelow < minUsableHeight && spaceAbove > spaceBelow;
    final availableHeight = openUpward ? spaceAbove : spaceBelow;
    final popoverMaxHeight =
        availableHeight.clamp(minUsableHeight, preferredMaxHeight);

    _closeOverlay();
    _overlayEntry = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                _closeOverlay();
                if (mounted) setState(() {});
              },
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, openUpward ? -4 : 4),
            targetAnchor:
                openUpward ? Alignment.topLeft : Alignment.bottomLeft,
            followerAnchor:
                openUpward ? Alignment.bottomLeft : Alignment.topLeft,
            child: _InlineSearchPopover(
              width: fieldWidth.clamp(280.0, 420.0),
              maxHeight: popoverMaxHeight.toDouble(),
              title: widget.label,
              items: widget.items,
              valueField: widget.valueField,
              displayField: widget.displayField,
              currentValue: widget.value,
              nullable: widget.nullable,
              nullLabel: widget.nullLabel,
              onSearch: widget.onSearch,
              onSelected: (result) {
                _closeOverlay();
                if (mounted) _aplicarResultado(result);
              },
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
    _instanciaComOverlayAberto = this;
  }

  @override
  Widget build(BuildContext context) {
    final primary = GridColors.primary;
    final labelText = widget.label + (widget.isRequired ? ' *' : '');
    final displayText = _displayLabel ?? '';
    final isEmpty = displayText.isEmpty;
    final isDisabled = !widget.enabled;

    return FormField<String>(
      initialValue: widget.value,
      validator: (v) {
        if (widget.validator != null) return widget.validator!(widget.value);
        if (widget.isRequired && (widget.value == null || widget.value!.isEmpty)) {
          return '${widget.label} é obrigatório';
        }
        return null;
      },
      builder: (state) => CompositedTransformTarget(
        link: _layerLink,
        child: InkWell(
          onTap: isDisabled ? null : _openSearch,
          borderRadius: BorderRadius.circular(6),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: labelText,
              labelStyle: const TextStyle(fontSize: 13),
              filled: true,
              fillColor: isDisabled ? const Color(0xFFF5F5F5) : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: primary, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: primary, width: 1.5),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: GridColors.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: primary, width: 2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Colors.red, width: 1.5),
              ),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              prefixIcon: widget.prefixIcon != null
                  ? Icon(widget.prefixIcon, size: 18, color: primary)
                  : null,
              suffixIcon: isDisabled
                  ? const Icon(Icons.lock_outline, size: 16, color: Colors.grey)
                  : Icon(Icons.search, size: 18, color: primary),
              errorText: state.errorText,
            ),
            child: Text(
              isEmpty ? (widget.hintText ?? '— Selecione —') : displayText,
              style: TextStyle(
                fontSize: 13,
                color: isEmpty
                    ? Colors.grey.shade500
                    : isDisabled
                        ? Colors.grey
                        : const Color(0xFF212121),
                overflow: TextOverflow.ellipsis,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

class _DropResult {
  final String? value;
  final Map<String, dynamic>? item;

  const _DropResult(this.value, [this.item]);
}

class _InlineSearchPopover extends StatefulWidget {
  final double width;
  final double maxHeight;
  final String title;
  final List<Map<String, dynamic>> items;
  final String valueField;
  final String displayField;
  final String? currentValue;
  final bool nullable;
  final String nullLabel;
  final Future<List<Map<String, dynamic>>> Function(String query)? onSearch;
  final ValueChanged<_DropResult> onSelected;

  const _InlineSearchPopover({
    required this.width,
    required this.title,
    required this.items,
    required this.valueField,
    required this.displayField,
    required this.onSelected,
    this.maxHeight = 340.0,
    this.currentValue,
    this.nullable = false,
    this.nullLabel = '— Nenhum —',
    this.onSearch,
  });

  @override
  State<_InlineSearchPopover> createState() => _InlineSearchPopoverState();
}

class _InlineSearchPopoverState extends State<_InlineSearchPopover> {
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  List<Map<String, dynamic>> _filtered = [];
  Timer? _debounce;
  bool _loading = false;
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _filtered = List<Map<String, dynamic>>.from(widget.items);
    _ordenarAlfabetico(_filtered);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _ordenarAlfabetico(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      final valA = (a[widget.displayField] ?? a['nome'] ?? '').toString().toLowerCase();
      final valB = (b[widget.displayField] ?? b['nome'] ?? '').toString().toLowerCase();
      return valA.compareTo(valB);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    if (widget.onSearch != null) {
      _onSearchRemote(q);
      return;
    }
    final query = q.toLowerCase().trim();
    setState(() {
      final res = query.isEmpty
          ? List<Map<String, dynamic>>.from(widget.items)
          : widget.items.where((o) {
              final lbl = (o[widget.displayField]?.toString() ?? '').toLowerCase();
              final val = (o[widget.valueField]?.toString() ?? '').toLowerCase();
              final nome = (o['nome']?.toString() ?? '').toLowerCase();
              final razao = (o['razaoSocial']?.toString() ?? '').toLowerCase();
              final cnpj = (o['cnpj']?.toString() ?? o['cpf']?.toString() ?? '').toLowerCase();
              return lbl.contains(query) ||
                  val.contains(query) ||
                  nome.contains(query) ||
                  razao.contains(query) ||
                  cnpj.contains(query);
            }).toList();
      _ordenarAlfabetico(res);
      _filtered = res;
    });
  }

  void _onSearchRemote(String q) {
    final query = q.trim();
    _debounce?.cancel();
    if (query.isEmpty) {
      _searchToken++;
      setState(() {
        _loading = false;
        _filtered = List<Map<String, dynamic>>.from(widget.items);
        _ordenarAlfabetico(_filtered);
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final token = ++_searchToken;
      try {
        final resultado = await widget.onSearch!(query);
        if (!mounted || token != _searchToken) return;
        _ordenarAlfabetico(resultado);
        setState(() {
          _loading = false;
          _filtered = resultado;
        });
      } catch (_) {
        if (!mounted || token != _searchToken) return;
        setState(() {
          _loading = false;
          _filtered = [];
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final primary = GridColors.primary;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      color: Colors.white,
      child: Container(
        width: widget.width,
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: primary.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: TextField(
                controller: _searchCtrl,
                focusNode: _focusNode,
                autofocus: true,
                onChanged: _onSearch,
                decoration: InputDecoration(
                  hintText: 'Buscar ${widget.title.toLowerCase()}...',
                  prefixIcon: Icon(Icons.search, size: 18, color: primary),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: primary),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                ),
              ),
            ),
            if (widget.nullable)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: TextButton(
                    onPressed: () =>
                        widget.onSelected(const _DropResult(null)),
                    child: Text(widget.nullLabel,
                        style: const TextStyle(fontSize: 11)),
                  ),
                ),
              ),
            const Divider(height: 1),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                          child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2))),
                    )
                  : _filtered.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Nenhum resultado',
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 12)),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final o = _filtered[i];
                            final val = o[widget.valueField]?.toString();
                            final lbl =
                                o[widget.displayField]?.toString() ??
                                    o['nome']?.toString() ??
                                    val ??
                                    '';
                            final isSelected = val == widget.currentValue;
                            return ListTile(
                              dense: true,
                              selected: isSelected,
                              selectedTileColor:
                                  primary.withValues(alpha: 0.08),
                              leading: Icon(
                                  isSelected
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: isSelected ? primary : Colors.grey,
                                  size: 16,
                                  semanticLabel:
                                      isSelected ? 'Selecionado' : null),
                              title: Text(lbl,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: isSelected
                                          ? primary
                                          : const Color(0xFF212121))),
                              onTap: () =>
                                  widget.onSelected(_DropResult(val, o)),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Search dialog (Modal com suporte a busca remota paginada de 20 em 20) ────

class _SearchDialog extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> items;
  final String valueField;
  final String displayField;
  final String? currentValue;
  final bool nullable;
  final String nullLabel;
  final Future<List<Map<String, dynamic>>> Function(String query)? onSearch;
  final Future<PaginaDropdown> Function({String? busca, required int pagina})? loadPage;

  const _SearchDialog({
    required this.title,
    required this.items,
    required this.valueField,
    required this.displayField,
    this.currentValue,
    this.nullable = false,
    this.nullLabel = '— Nenhum —',
    this.onSearch,
    this.loadPage,
  });

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<Map<String, dynamic>> _filtered = [];
  Timer? _debounce;
  bool _loading = false;
  bool _loadingMore = false;
  int _searchToken = 0;

  int _pagina = 0;
  int _total = 0;
  String _termoAtual = '';
  String? _erro;

  bool get _isPaginated => widget.loadPage != null;

  @override
  void initState() {
    super.initState();
    if (_isPaginated) {
      _scrollCtrl.addListener(_onScroll);
      _carregarPrimeiraPagina();
    } else {
      _filtered = List<Map<String, dynamic>>.from(widget.items);
      _ordenarAlfabetico(_filtered);
    }
  }

  void _ordenarAlfabetico(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      final valA = (a[widget.displayField] ?? a['nome'] ?? '').toString().toLowerCase();
      final valB = (b[widget.displayField] ?? b['nome'] ?? '').toString().toLowerCase();
      return valA.compareTo(valB);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_isPaginated) return;
    if (_loading || _loadingMore) return;
    if (_filtered.length >= _total) return;
    if (!_scrollCtrl.hasClients) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 80) {
      _carregarProximaPagina();
    }
  }

  Future<void> _carregarPrimeiraPagina() async {
    final token = ++_searchToken;
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final pagina = await widget.loadPage!(
        busca: _termoAtual.isEmpty ? null : _termoAtual,
        pagina: 0,
      );
      if (!mounted || token != _searchToken) return;
      setState(() {
        _filtered = List<Map<String, dynamic>>.from(pagina.items);
        _total = pagina.total;
        _pagina = 0;
        _loading = false;
        _erro = pagina.erro;
      });
    } catch (e) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _loading = false;
        _filtered = [];
        _total = 0;
        _erro = 'Erro ao buscar: $e';
      });
    }
  }

  Future<void> _carregarProximaPagina() async {
    final token = ++_searchToken;
    setState(() => _loadingMore = true);
    final proximaPagina = _pagina + 1;
    try {
      final pagina = await widget.loadPage!(
        busca: _termoAtual.isEmpty ? null : _termoAtual,
        pagina: proximaPagina,
      );
      if (!mounted || token != _searchToken) return;
      setState(() {
        _filtered.addAll(pagina.items);
        _total = pagina.total;
        _pagina = proximaPagina;
        _loadingMore = false;
        _erro = pagina.erro;
      });
    } catch (e) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _loadingMore = false;
        _erro = 'Erro ao carregar mais dados: $e';
      });
    }
  }

  void _onSearch(String q) {
    if (_isPaginated) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 350), () {
        _termoAtual = q.trim();
        _carregarPrimeiraPagina();
      });
      return;
    }

    if (widget.onSearch != null) {
      _onSearchRemote(q);
      return;
    }

    final query = q.toLowerCase().trim();
    setState(() {
      final res = query.isEmpty
          ? List<Map<String, dynamic>>.from(widget.items)
          : widget.items.where((o) {
              final lbl = (o[widget.displayField]?.toString() ?? '').toLowerCase();
              final val = (o[widget.valueField]?.toString() ?? '').toLowerCase();
              final nome = (o['nome']?.toString() ?? '').toLowerCase();
              final razao = (o['razaoSocial']?.toString() ?? '').toLowerCase();
              final cnpj = (o['cnpj']?.toString() ?? o['cpf']?.toString() ?? '').toLowerCase();
              return lbl.contains(query) ||
                  val.contains(query) ||
                  nome.contains(query) ||
                  razao.contains(query) ||
                  cnpj.contains(query);
            }).toList();
      _ordenarAlfabetico(res);
      _filtered = res;
    });
  }

  void _onSearchRemote(String q) {
    final query = q.trim();
    _debounce?.cancel();

    if (query.isEmpty) {
      _searchToken++;
      setState(() {
        _loading = false;
        _filtered = List<Map<String, dynamic>>.from(widget.items);
        _ordenarAlfabetico(_filtered);
      });
      return;
    }

    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final token = ++_searchToken;
      try {
        final resultado = await widget.onSearch!(query);
        if (!mounted || token != _searchToken) return;
        _ordenarAlfabetico(resultado);
        setState(() {
          _loading = false;
          _filtered = resultado;
        });
      } catch (_) {
        if (!mounted || token != _searchToken) return;
        setState(() {
          _loading = false;
          _filtered = [];
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final primary = GridColors.primary;

    final contadorTexto = _loading
        ? 'Buscando...'
        : _isPaginated
            ? '${_filtered.length} de $_total resultado(s)'
            : '${_filtered.length} resultado(s)';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 540),
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // ── Search field ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: _onSearch,
                decoration: InputDecoration(
                  hintText: 'Buscar ${widget.title.toLowerCase()}...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchCtrl.clear();
                            _onSearch('');
                          },
                        )
                      : null,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: primary),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: primary, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),
            ),

            // ── Count + optional clear button ────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    contadorTexto,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const Spacer(),
                  if (widget.nullable || _isPaginated)
                    TextButton(
                      onPressed: () => Navigator.of(context)
                          .pop(const _DropResult(null)),
                      child: Text(
                        widget.nullLabel,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),

            // ── Results list ─────────────────────────────────────────────
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _erro ?? 'Nenhum resultado',
                              style: TextStyle(
                                color: _erro != null ? GridColors.error : Colors.grey,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollCtrl,
                          itemCount: _filtered.length + (_loadingMore ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i >= _filtered.length) {
                              return const Padding(
                                padding: EdgeInsets.all(12),
                                child: Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                              );
                            }
                            final o = _filtered[i];
                            final val = o[widget.valueField]?.toString();
                            final lbl =
                                o[widget.displayField]?.toString() ??
                                    o['nome']?.toString() ??
                                    val ??
                                    '';
                            final isSelected = val == widget.currentValue;
                            return ListTile(
                              dense: true,
                              selected: isSelected,
                              selectedTileColor: primary.withValues(alpha: 0.08),
                              leading: isSelected
                                  ? Icon(Icons.check_circle,
                                      color: primary, size: 18)
                                  : const Icon(Icons.radio_button_unchecked,
                                      color: Colors.grey, size: 18),
                              title: Text(
                                lbl,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? primary
                                      : const Color(0xFF212121),
                                ),
                              ),
                              onTap: () => Navigator.of(context)
                                  .pop(_DropResult(val, o)),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
