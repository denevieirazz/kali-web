import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/cloudos_theme.dart';
import '../../../widgets/glass_surface.dart';
import '../domain/spotlight_item.dart';

class SpotlightPalette extends StatefulWidget {
  const SpotlightPalette({
    required this.items,
    required this.onClose,
    super.key,
  });

  final List<SpotlightItem> items;
  final VoidCallback onClose;

  @override
  State<SpotlightPalette> createState() => _SpotlightPaletteState();
}

class _SpotlightPaletteState extends State<SpotlightPalette> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<SpotlightItem> get _filteredItems {
    final query = _controller.text.trim();
    final calculation = SpotlightMathEvaluator.tryEvaluate(query);

    final results = <SpotlightItem>[];

    if (calculation != null) {
      final formattedResult = calculation % 1 == 0
          ? calculation.toInt().toString()
          : calculation.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
      results.add(
        SpotlightItem(
          id: 'calc_result',
          title: '= $formattedResult',
          subtitle: 'Resultado de: $query (Enter para copiar)',
          icon: Icons.calculate_rounded,
          kind: SpotlightItemKind.calculation,
          badge: 'Cálculo',
          onSelect: () {
            Clipboard.setData(ClipboardData(text: formattedResult));
            widget.onClose();
          },
        ),
      );
    }

    if (query.isEmpty) {
      results.addAll(widget.items.take(8));
      return results;
    }

    final normalized = query.toLowerCase();
    final matched = widget.items.where((item) {
      return item.title.toLowerCase().contains(normalized) ||
          item.subtitle.toLowerCase().contains(normalized) ||
          (item.badge != null && item.badge!.toLowerCase().contains(normalized));
    }).toList(growable: false);

    results.addAll(matched);
    return results;
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final items = _filteredItems;
    if (items.isEmpty) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        widget.onClose();
      }
      return;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1) % items.length;
      });
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1 + items.length) % items.length;
      });
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_selectedIndex >= 0 && _selectedIndex < items.length) {
        items[_selectedIndex].onSelect();
      }
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;
    final clampedIndex = items.isEmpty ? 0 : _selectedIndex.clamp(0, items.length - 1);

    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: _handleKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onClose,
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: 100),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {}, // Prevent closing when tapping inside the palette
            child: SizedBox(
              width: 620,
              child: GlassSurface(
                borderRadius: 16,
                borderColor: CloudOSColors.accent.withValues(alpha: 0.4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildSearchBar(),
                    const Divider(height: 1, color: CloudOSColors.border),
                    if (items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(28.0),
                        child: Center(
                          child: Text(
                            'Nenhum resultado encontrado.',
                            style: TextStyle(
                              color: CloudOSColors.caption,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 380),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: items.length,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              final isSelected = index == clampedIndex;
                              return _buildItemTile(item, isSelected);
                            },
                          ),
                        ),
                      ),
                    _buildFooter(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.search_rounded,
            color: CloudOSColors.accent,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: (_) => setState(() => _selectedIndex = 0),
              style: const TextStyle(
                color: CloudOSColors.text,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              decoration: const InputDecoration(
                hintText: 'Buscar apps, arquivos ou calcular (ex: 128 * 4)...',
                hintStyle: TextStyle(
                  color: CloudOSColors.caption,
                  fontSize: 15,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_rounded, size: 18, color: CloudOSColors.caption),
              onPressed: () {
                _controller.clear();
                setState(() => _selectedIndex = 0);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildItemTile(SpotlightItem item, bool isSelected) {
    return InkWell(
      onTap: item.onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: isSelected
            ? CloudOSColors.accent.withValues(alpha: 0.18)
            : Colors.transparent,
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected
                    ? CloudOSColors.accent.withValues(alpha: 0.25)
                    : CloudOSColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? CloudOSColors.accent : CloudOSColors.border,
                ),
              ),
              child: Icon(
                item.icon,
                color: isSelected ? CloudOSColors.accent : CloudOSColors.text,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : CloudOSColors.text,
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    style: const TextStyle(
                      color: CloudOSColors.caption,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (item.badge != null) ...<Widget>[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: CloudOSColors.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: CloudOSColors.border),
                ),
                child: Text(
                  item.badge!,
                  style: const TextStyle(
                    color: CloudOSColors.caption,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0x30000000),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        border: Border(top: BorderSide(color: CloudOSColors.border)),
      ),
      child: const Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'Central de Comando CloudOS',
              style: TextStyle(
                color: CloudOSColors.caption,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              '↑↓ Navegar  •  Enter Abrir  •  Esc Sair',
              style: TextStyle(
                color: CloudOSColors.caption,
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
