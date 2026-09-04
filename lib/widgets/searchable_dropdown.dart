import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/grid_colors.dart';

/// Reusable searchable dropdown widget.
///
/// Opens a dialog with a text search field so users can quickly filter
/// through long option lists.  Works with any [List<Map<String, dynamic>>]
/// where each map has a [valueField] key (unique ID) and a [displayField]
/// key (human-readable label).
///
/// ```dart
/// SearchableDropdownField(
///   label: 'Empresa',
///   value: _selectedId,
///   items: _empresas,          // [{'id': '1', 'nome': 'Empresa A'}, ...]
///   valueField: 'id',
///   displayField: 'nome',
///   onChanged: (v) => setState(() => _selectedId = v),
/// )
/// ```
class SearchableDropdownField extends StatefulWidget {
  final String label;

  /// Currently selected value — the string representation of [valueField].
  final String? value;

  /// The full list of options.
  final List<Map<String, dynamic>> items;

  /// Key inside each map that holds the option's unique identifier.
  final String valueField;

  /// Key inside each map that holds the human-readable label.
  final String displayField;

  /// Called whenever the user picks a new item (or clears the selection).
  /// Receives [null] only when [nullable] is true and the user taps "Limpar".
  final ValueChanged<String?> onChanged;

  final bool enabled;
  final bool isRequired;

  /// When [true] a "Limpar seleção" button is shown inside the dialog,
  /// allowing the user to set the value back to [null].
  final bool nullable;

  /// Label shown for the clear-selection button (only relevant when
  /// [nullable] is [true]).
  final String nullLabel;

  /// Placeholder text shown when no item is selected.
  final String? hintText;

  /// Optional validator — receives the current string value and returns an
  /// error message or [null] if valid.  Integrates with [Form] / [FormState].
  final String? Function(String?)? validator;

  /// Optional server-side search callback. When provided, typing in the
  /// dialog's search field debounces and calls this instead of filtering
  /// [items] locally — necessary for lists too large to load entirely on
  /// the client (ex: as cidades do IBGE, 5571 registros). While the query
  /// is empty, [items] is still shown (useful for a small initial batch).
  final Future<List<Map<String, dynamic>>> Function(String query)? onSearch;

  /// Called with the full selected item map (or `null` on clear) whenever
  /// a selection is made — including items that came from [onSearch] and
  /// therefore are not present in [items]. Use this (instead of looking the
  /// value back up in [items]) to read extra fields from the selected
  /// record, since a remotely-searched item may not exist in the local list.
  final ValueChanged<Map<String, dynamic>?>? onItemSelected;

  /// Ícone opcional exibido no início do campo (prefixIcon), usado para
  /// diferenciar visualmente campos de natureza específica (ex: municipal)
  /// dos demais campos genéricos do formulário.
  final IconData? prefixIcon;

  /// Quando [true], a busca abre como um overlay/autocomplete ancorado
  /// logo abaixo do campo (via [CompositedTransformFollower]) em vez de um
  /// [Dialog] modal centralizado. Usado em formulários onde um modal grande
  /// cobrindo a tela prejudica a usabilidade (ex: telas de detalhe/edição
  /// com múltiplos campos de busca). O comportamento padrão (Dialog) é
  /// mantido em todos os demais usos do widget para não alterar telas que
  /// já dependem do popup centralizado.
  final bool inline;

  const SearchableDropdownField({
    super.key,
    required this.label,
    required this.items,
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
    this.onItemSelected,
    this.prefixIcon,
    this.inline = false,
  });

  @override
  State<SearchableDropdownField> createState() =>
      _SearchableDropdownFieldState();
}

class _SearchableDropdownFieldState extends State<SearchableDropdownField> {
  /// Instância dona do popover inline atualmente aberto (no máximo um por
  /// vez, entre todos os [SearchableDropdownField] com `inline: true` na
  /// árvore) — evita depender apenas do comportamento incidental de
  /// hit-testing do barrier translúcido para fechar um popover quando outro
  /// campo é tocado diretamente (achado WR-02 do code review do card
  /// 6F94hyxf). Ao abrir um novo overlay inline, qualquer overlay anterior
  /// de outra instância é fechado explicitamente primeiro.
  static _SearchableDropdownFieldState? _instanciaComOverlayAberto;

  String? _displayLabel;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  /// Último valor para o qual [_displayLabel] foi resolvido — inclui
  /// resoluções feitas fora de [widget.items] (ex: item vindo de
  /// [SearchableDropdownField.onSearch] em [_openSearch]). Evita que
  /// [didUpdateWidget] sobrescreva um label recém-selecionado com `null`
  /// só porque esse item ainda não está em [widget.items] — cenário comum
  /// quando o callback onChanged do pai dispara um rebuild logo em seguida.
  String? _lastResolvedValue;

  @override
  void initState() {
    super.initState();
    _resolveLabel(widget.value);
  }

  @override
  void didUpdateWidget(SearchableDropdownField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Só pula a re-resolução quando já existe um label resolvido para esse
    // valor (ex: seleção recente via busca remota, ainda fora de widget.items).
    // Se o label ainda está null (ex: value setado antes de items carregar —
    // caso comum de tela de edição com dropdown assíncrono), precisa tentar
    // resolver de novo quando widget.items mudar.
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
    _displayLabel = null;
  }

  @override
  void dispose() {
    _closeOverlay();
    super.dispose();
  }

  Future<void> _openSearch() async {
    if (!widget.enabled) return;
    if (widget.inline) {
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
      ),
    );
    if (result == null) return; // dialog dismissed — no change
    _aplicarResultado(result);
  }

  void _aplicarResultado(_DropResult result) {
    setState(() {
      // Quando o item completo veio junto (seleção local ou via onSearch),
      // usa o label dele diretamente — evita depender de widget.items conter
      // o item (o que não é garantido para resultados de busca remota).
      if (result.item != null) {
        _displayLabel = result.item![widget.displayField]?.toString();
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

  /// Abre a busca como autocomplete inline, ancorado logo abaixo do campo,
  /// via [OverlayEntry] + [CompositedTransformFollower] — sem [Dialog] e
  /// sem scrim cobrindo o restante da tela. Um barrier transparente captura
  /// toques fora do popover para fechá-lo (clique-fora), preservando o
  /// restante do formulário visível e interativo.
  ///
  /// Faz "flip" para cima quando não há espaço suficiente abaixo do campo
  /// (ex: campo próximo do rodapé da janela/viewport) e limita a altura do
  /// popover ao espaço realmente disponível no lado escolhido, para nunca
  /// renderizar parcialmente fora da tela.
  void _openInlineOverlay() {
    // Fecha explicitamente qualquer popover inline de OUTRA instância que
    // ainda esteja aberto — não depende do barrier translúcido conseguir
    // interceptar o toque que abre este campo (WR-02 do code review).
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

    // Abre para cima somente quando não sobra espaço utilizável abaixo e há
    // mais espaço acima — caso contrário mantém o padrão (abrir para baixo).
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

// ─── Internal result wrapper ──────────────────────────────────────────────────
// Distinguishes "dialog dismissed (no change)" from "user explicitly cleared".

class _DropResult {
  final String? value;

  /// Item completo selecionado (nulo quando o usuário limpou a seleção).
  /// Carregado mesmo quando o item veio de [SearchableDropdownField.onSearch]
  /// — nesse caso ele não está necessariamente em [SearchableDropdownField.items].
  final Map<String, dynamic>? item;

  const _DropResult(this.value, [this.item]);
}

// ─── Inline search popover (autocomplete ancorado, sem Dialog) ─────────────────

/// Popover de busca ancorado ao campo — usado quando
/// [SearchableDropdownField.inline] é `true`. Reaproveita a mesma lógica de
/// filtro local/remoto de [_SearchDialog], mas renderiza como um
/// [Material] flutuante posicionado pelo [CompositedTransformFollower] do
/// campo, e não como [Dialog] (sem scrim cobrindo o formulário).
class _InlineSearchPopover extends StatefulWidget {
  final double width;

  /// Altura máxima já calculada pelo chamador com base no espaço realmente
  /// disponível na tela/janela (acima ou abaixo do campo) — evita que o
  /// popover renderize parcialmente fora da viewport quando o campo está
  /// perto da borda.
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
    _filtered = widget.items;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
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
      _filtered = query.isEmpty
          ? widget.items
          : widget.items
              .where((o) => (o[widget.displayField]?.toString() ?? '')
                  .toLowerCase()
                  .contains(query))
              .toList();
    });
  }

  void _onSearchRemote(String q) {
    final query = q.trim();
    _debounce?.cancel();
    if (query.isEmpty) {
      _searchToken++;
      setState(() {
        _loading = false;
        _filtered = widget.items;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final token = ++_searchToken;
      try {
        final resultado = await widget.onSearch!(query);
        if (!mounted || token != _searchToken) return;
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

// ─── Search dialog ────────────────────────────────────────────────────────────

class _SearchDialog extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> items;
  final String valueField;
  final String displayField;
  final String? currentValue;
  final bool nullable;
  final String nullLabel;
  final Future<List<Map<String, dynamic>>> Function(String query)? onSearch;

  const _SearchDialog({
    required this.title,
    required this.items,
    required this.valueField,
    required this.displayField,
    this.currentValue,
    this.nullable = false,
    this.nullLabel = '— Nenhum —',
    this.onSearch,
  });

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _filtered = [];
  Timer? _debounce;
  bool _loading = false;
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _filtered = widget.items;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    if (widget.onSearch != null) {
      _onSearchRemote(q);
      return;
    }
    final query = q.toLowerCase().trim();
    setState(() {
      _filtered = query.isEmpty
          ? widget.items
          : widget.items
              .where((o) => (o[widget.displayField]?.toString() ?? '')
                  .toLowerCase()
                  .contains(query))
              .toList();
    });
  }

  /// Busca server-side com debounce — usada quando a lista completa é
  /// grande demais para carregar/filtrar no cliente (ex: popup de
  /// Município, 5571 cidades do seed IBGE).
  void _onSearchRemote(String q) {
    final query = q.trim();
    _debounce?.cancel();

    if (query.isEmpty) {
      // Invalida qualquer busca em andamento — sem isso, uma resposta tardia
      // da busca anterior poderia sobrescrever a lista já limpa pelo usuário.
      _searchToken++;
      setState(() {
        _loading = false;
        _filtered = widget.items;
      });
      return;
    }

    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final token = ++_searchToken;
      try {
        final resultado = await widget.onSearch!(query);
        if (!mounted || token != _searchToken) return;
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
                    _loading ? 'Buscando...' : '${_filtered.length} resultado(s)',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const Spacer(),
                  if (widget.nullable)
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
                  ? const Center(
                      child: Text('Nenhum resultado',
                          style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) {
                        final o = _filtered[i];
                        final val = o[widget.valueField]?.toString();
                        final lbl =
                            o[widget.displayField]?.toString() ?? val ?? '';
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
