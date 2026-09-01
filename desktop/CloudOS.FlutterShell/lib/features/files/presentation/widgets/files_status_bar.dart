import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';

class FilesStatusBar extends StatelessWidget {
  const FilesStatusBar({
    required this.itemCount,
    required this.selectedPath,
    super.key,
  });

  final int itemCount;
  final String? selectedPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
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
          if (selectedPath != null) ...<Widget>[
            const SizedBox(width: 8),
            const Text('•', style: TextStyle(color: CloudOSColors.caption)),
            const SizedBox(width: 8),
            const Text(
              '1 item selecionado',
              style: TextStyle(
                color: CloudOSColors.accent,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const Spacer(),
          const Icon(
            Icons.cloud_done_rounded,
            size: 13,
            color: CloudOSColors.success,
          ),
          const SizedBox(width: 5),
          const Text(
            'Sistema de arquivos unificado e sincronizado',
            style: TextStyle(color: CloudOSColors.caption, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}
