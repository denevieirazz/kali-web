import 'package:flutter/material.dart';

import '../../core/cloudos_theme.dart';
import '../../models/shell_models.dart';

class DesktopStatus extends StatelessWidget {
  const DesktopStatus({
    super.key,
    required this.snapshot,
    required this.currentWorkspace,
  });

  final CloudSystemSnapshot snapshot;
  final int currentWorkspace;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: CloudOSColors.elevated.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CloudOSColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.cloud_done_rounded, size: 15, color: CloudOSColors.success),
          const SizedBox(width: 6),
          const Text(
            'CloudOS V21',
            style: TextStyle(color: CloudOSColors.text, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 12, color: CloudOSColors.border),
          const SizedBox(width: 8),
          Text(
            'Área $currentWorkspace',
            style: const TextStyle(color: CloudOSColors.secondary, fontSize: 11),
          ),
          if (snapshot.wslAvailable) ...<Widget>[
            const SizedBox(width: 8),
            Container(width: 1, height: 12, color: CloudOSColors.border),
            const SizedBox(width: 8),
            const Icon(Icons.terminal_rounded, size: 14, color: CloudOSColors.linux),
            const SizedBox(width: 4),
            Text(
              snapshot.distros.isEmpty ? 'WSL2' : snapshot.distros.first,
              style: const TextStyle(color: CloudOSColors.caption, fontSize: 10.5),
            ),
          ],
        ],
      ),
    );
  }
}
