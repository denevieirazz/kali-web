import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';

class StartHeader extends StatelessWidget {
  const StartHeader({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: CloudOSColors.accentSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.cloud_rounded,
            color: CloudOSColors.accent,
            size: 20,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'CloudOS Start',
                style: TextStyle(
                  color: CloudOSColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              Text(
                'Ambiente unificado Windows + Linux',
                style: TextStyle(color: CloudOSColors.caption, fontSize: 11),
              ),
            ],
          ),
        ),
        Tooltip(
          message: 'Fechar (Esc)',
          child: IconButton(
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ),
      ],
    );
  }
}
