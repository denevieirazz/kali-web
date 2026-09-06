import 'dart:io';
import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';

class StartFooter extends StatelessWidget {
  const StartFooter({
    this.onLockSession,
    this.onPowerOptions,
    super.key,
  });

  final VoidCallback? onLockSession;
  final VoidCallback? onPowerOptions;

  @override
  Widget build(BuildContext context) {
    final userName = Platform.environment['USERNAME'] ?? 'Usuário';

    return Row(
      children: <Widget>[
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: CloudOSColors.accentSoft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: CloudOSColors.accent.withValues(alpha: 0.4),
            ),
          ),
          child: const Icon(
            Icons.person_rounded,
            size: 18,
            color: CloudOSColors.accent,
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              userName,
              style: const TextStyle(
                color: CloudOSColors.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Text(
              'Administrador • Sessão Ativa',
              style: TextStyle(color: CloudOSColors.caption, fontSize: 10),
            ),
          ],
        ),
        const Spacer(),
        _FooterAction(
          key: const ValueKey<String>('start-footer-lock'),
          icon: Icons.lock_outline_rounded,
          tooltip: 'Bloquear Sessão',
          onPressed: onLockSession ?? () {},
        ),
        const SizedBox(width: 4),
        _FooterAction(
          key: const ValueKey<String>('start-footer-power'),
          icon: Icons.power_settings_new_rounded,
          tooltip: 'Opções de Energia',
          onPressed: onPowerOptions ?? () {},
        ),
      ],
    );
  }
}

class _FooterAction extends StatelessWidget {
  const _FooterAction({
    super.key,
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
        icon: Icon(icon, size: 17),
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: CloudOSColors.elevated.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
