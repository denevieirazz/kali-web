import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';

class TaskbarWorkspaceSwitcher extends StatelessWidget {
  const TaskbarWorkspaceSwitcher({
    required this.currentWorkspace,
    this.onWorkspaceChanged,
    super.key,
  });

  final int currentWorkspace;
  final ValueChanged<int>? onWorkspaceChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 1; i <= 4; i++) ...<Widget>[
          _WorkspacePill(
            index: i,
            selected: currentWorkspace == i,
            onTap: () => onWorkspaceChanged?.call(i),
          ),
          if (i < 4) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

class _WorkspacePill extends StatelessWidget {
  const _WorkspacePill({
    required this.index,
    this.selected = false,
    this.onTap,
  });

  final int index;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Área de Trabalho $index (Ctrl+Alt+$index)',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: selected ? 28 : 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? CloudOSColors.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? CloudOSColors.accent : CloudOSColors.border,
            ),
          ),
          child: Text(
            '$index',
            style: TextStyle(
              color: selected ? CloudOSColors.text : CloudOSColors.caption,
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
