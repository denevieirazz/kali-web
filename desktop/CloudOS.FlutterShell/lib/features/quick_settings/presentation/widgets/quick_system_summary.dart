import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';
import '../../../../models/shell_models.dart';

class QuickSystemSummary extends StatelessWidget {
  const QuickSystemSummary({required this.snapshot, super.key});

  final CloudSystemSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: CloudOSColors.elevated.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CloudOSColors.border),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.battery_charging_full_rounded,
            color: CloudOSColors.success,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${snapshot.batteryPercent}% • Carregando',
                  style: const TextStyle(
                    color: CloudOSColors.text,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  snapshot.wslAvailable
                      ? 'WSL2: ${snapshot.distros.join(', ')}'
                      : 'Windows Desktop Standalone',
                  style: const TextStyle(
                    color: CloudOSColors.caption,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: CloudOSColors.linuxSoft,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'WSLg Ativo',
              style: TextStyle(
                color: CloudOSColors.linux,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
