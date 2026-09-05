import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';

class FilesStatusBar extends StatelessWidget {
  const FilesStatusBar({
    required this.itemCount,
    this.selectedPath,
    this.selectedCount = 0,
    this.selectedSizeFormatted,
    this.activeOperationTitle,
    this.operationProgress,
    this.onCancelOperation,
    super.key,
  });

  final int itemCount;
  final String? selectedPath;
  final int selectedCount;
  final String? selectedSizeFormatted;
  final String? activeOperationTitle;
  final double? operationProgress; // 0.0 - 1.0
  final VoidCallback? onCancelOperation;

  @override
  Widget build(BuildContext context) {
    final effectiveSelectedCount = selectedCount > 0
        ? selectedCount
        : (selectedPath != null ? 1 : 0);

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0x350D151E),
        border: Border(top: BorderSide(color: CloudOSColors.border)),
      ),
      child: Row(
        children: <Widget>[
          Text(
            '$itemCount itens',
            style: const TextStyle(color: CloudOSColors.caption, fontSize: 10.5),
          ),
          if (effectiveSelectedCount > 0) ...<Widget>[
            const SizedBox(width: 8),
            const Text('•', style: TextStyle(color: CloudOSColors.caption)),
            const SizedBox(width: 8),
            Text(
              effectiveSelectedCount == 1
                  ? '1 item selecionado${selectedSizeFormatted != null ? " ($selectedSizeFormatted)" : ""}'
                  : '$effectiveSelectedCount itens selecionados${selectedSizeFormatted != null ? " ($selectedSizeFormatted)" : ""}',
              style: const TextStyle(
                color: CloudOSColors.accent,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (activeOperationTitle != null) ...<Widget>[
            const SizedBox(width: 12),
            const VerticalDivider(width: 1, indent: 4, endIndent: 4),
            const SizedBox(width: 12),
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: operationProgress,
                color: CloudOSColors.accent,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              activeOperationTitle!,
              style: const TextStyle(color: CloudOSColors.accent, fontSize: 10.5),
            ),
            if (onCancelOperation != null) ...<Widget>[
              const SizedBox(width: 6),
              InkWell(
                onTap: onCancelOperation,
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(
                      color: CloudOSColors.danger,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ],
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: CloudOSColors.accentSoft,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: CloudOSColors.accent.withValues(alpha: 0.4),
                width: 0.5,
              ),
            ),
            child: const Text(
              'Windows + Linux (WSL2)',
              style: TextStyle(
                color: CloudOSColors.accent,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.cloud_done_rounded,
            size: 13,
            color: CloudOSColors.success,
          ),
          const SizedBox(width: 5),
          const Text(
            'Sincronizado',
            style: TextStyle(color: CloudOSColors.caption, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}
