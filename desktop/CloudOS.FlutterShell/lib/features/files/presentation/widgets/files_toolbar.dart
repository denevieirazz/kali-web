import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';

class FilesToolbar extends StatelessWidget {
  const FilesToolbar({
    super.key,
    required this.currentTitle,
    required this.isGridView,
    required this.onQueryChanged,
    required this.onToggleView,
  });

  final String currentTitle;
  final bool isGridView;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onToggleView;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: <Widget>[
          _NavButton(icon: Icons.arrow_back_rounded, tooltip: 'Voltar', onPressed: () {}),
          _NavButton(icon: Icons.arrow_forward_rounded, tooltip: 'Avançar', onPressed: () {}),
          _NavButton(icon: Icons.arrow_upward_rounded, tooltip: 'Subir Pasta', onPressed: () {}),
          _NavButton(icon: Icons.refresh_rounded, tooltip: 'Atualizar', onPressed: () {}),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: CloudOSColors.elevated.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: CloudOSColors.border),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.folder_open_rounded, size: 15, color: CloudOSColors.accent),
                  const SizedBox(width: 6),
                  const Text('CloudOS', style: TextStyle(fontSize: 11.5, color: CloudOSColors.caption)),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded, size: 14, color: CloudOSColors.caption),
                  const SizedBox(width: 4),
                  Text(
                    currentTitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: CloudOSColors.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 180,
            height: 32,
            child: TextField(
              onChanged: onQueryChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded, size: 16),
                hintText: 'Filtrar pasta...',
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: isGridView
                ? 'Mudar para exibição em lista'
                : 'Mudar para exibição em grade',
            child: IconButton(
              onPressed: onToggleView,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 16, color: CloudOSColors.secondary),
      ),
    );
  }
}
