import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';

class QuickSliderRow extends StatelessWidget {
  const QuickSliderRow({
    required this.icon,
    required this.percentage,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.enabled = true,
    super.key,
  });

  final IconData icon;
  final String percentage;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final contentColor =
        enabled ? CloudOSColors.secondary : CloudOSColors.secondary.withValues(alpha: 0.45);

    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: contentColor),
        const SizedBox(width: 6),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: CloudOSColors.accent,
              inactiveTrackColor: CloudOSColors.borderStrong,
              thumbColor: Colors.white,
              disabledActiveTrackColor: CloudOSColors.borderStrong,
              disabledInactiveTrackColor: CloudOSColors.borderStrong,
              disabledThumbColor: CloudOSColors.secondary,
            ),
            child: Slider(
              value: value.clamp(0.0, 1.0).toDouble(),
              onChanged: enabled ? onChanged : null,
              onChangeEnd: enabled ? onChangeEnd : null,
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            enabled ? percentage : 'N/D',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: contentColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
