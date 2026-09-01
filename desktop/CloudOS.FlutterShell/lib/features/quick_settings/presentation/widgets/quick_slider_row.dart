import 'package:flutter/material.dart';

import '../../../../core/cloudos_theme.dart';

class QuickSliderRow extends StatelessWidget {
  const QuickSliderRow({
    required this.icon,
    required this.percentage,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final IconData icon;
  final String percentage;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: CloudOSColors.secondary),
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
            ),
            child: Slider(
              value: value.clamp(0.0, 1.0).toDouble(),
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            percentage,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: CloudOSColors.secondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
