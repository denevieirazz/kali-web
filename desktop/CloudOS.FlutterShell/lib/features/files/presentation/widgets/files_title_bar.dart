import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';

class FilesTitleBar extends StatelessWidget {
  const FilesTitleBar({
    super.key,
    required this.title,
    required this.onClose,
    required this.onMinimize,
    required this.onDrag,
  });

  final String title;
  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) => onDrag(details.delta),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: <Widget>[
            const Icon(Icons.folder_rounded, color: CloudOSColors.accent, size: 18),
            const SizedBox(width: 8),
            Text(
              'Arquivos • $title',
              style: const TextStyle(
                color: CloudOSColors.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 10),
            const _SourceBadge(
              label: 'Windows + Linux (WSL2)',
              color: CloudOSColors.accent,
            ),
            const Spacer(),
            _WindowButton(
              icon: Icons.remove_rounded,
              tooltip: 'Minimizar',
              onPressed: onMinimize,
            ),
            const SizedBox(width: 4),
            _WindowButton(
              icon: Icons.crop_square_rounded,
              tooltip: 'Maximizar',
              onPressed: () {},
            ),
            const SizedBox(width: 4),
            _WindowButton(
              icon: Icons.close_rounded,
              tooltip: 'Fechar (Esc)',
              isClose: true,
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isClose = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isClose;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 28,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 15,
            color: isClose ? CloudOSColors.danger : CloudOSColors.secondary,
          ),
        ),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}
