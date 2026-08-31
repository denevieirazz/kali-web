import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';
import '../models/shell_models.dart';
import 'glass_surface.dart';

class QuickSettingsPanel extends StatefulWidget {
  const QuickSettingsPanel({
    required this.snapshot,
    this.onOpenSettings,
    super.key,
  });

  final CloudSystemSnapshot snapshot;
  final VoidCallback? onOpenSettings;

  @override
  State<QuickSettingsPanel> createState() => _QuickSettingsPanelState();
}

class _QuickSettingsPanelState extends State<QuickSettingsPanel> {
  late double volume = widget.snapshot.volume;
  late double brightness = widget.snapshot.brightness;
  bool wifi = true;
  bool bluetooth = true;
  bool nightLight = false;
  bool focus = false;
  bool powerSaver = false;
  bool wslgDisplay = true;

  @override
  Widget build(BuildContext context) {
    final volPct = (volume * 100).round();
    final briPct = (brightness * 100).round();

    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 16, 68),
        child: SizedBox(
          width: 380,
          child: GlassSurface(
            borderRadius: 16,
            blur: 24,
            color: const Color(0xF4121A25),
            borderColor: CloudOSColors.borderStrong,
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Text(
                      'Configurações Rápidas',
                      style: TextStyle(
                        color: CloudOSColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const Spacer(),
                    Tooltip(
                      message: 'Abrir Painel Completo',
                      child: InkWell(
                        onTap: widget.onOpenSettings,
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.settings_rounded, size: 18, color: CloudOSColors.secondary),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  childAspectRatio: 2.35,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: <Widget>[
                    _ToggleTile(
                      label: 'Wi‑Fi 6',
                      subtitle: wifi ? widget.snapshot.networkName : 'Desativado',
                      icon: Icons.wifi_rounded,
                      active: wifi,
                      onTap: () => setState(() => wifi = !wifi),
                    ),
                    _ToggleTile(
                      label: 'Bluetooth',
                      subtitle: bluetooth ? 'Conectado' : 'Desativado',
                      icon: Icons.bluetooth_rounded,
                      active: bluetooth,
                      onTap: () => setState(() => bluetooth = !bluetooth),
                    ),
                    _ToggleTile(
                      label: 'Luz Noturna',
                      subtitle: nightLight ? 'Ativada (Quente)' : 'Desativada',
                      icon: Icons.nightlight_round,
                      active: nightLight,
                      onTap: () => setState(() => nightLight = !nightLight),
                    ),
                    _ToggleTile(
                      label: 'Modo Foco',
                      subtitle: focus ? 'Silencioso' : 'Desligado',
                      icon: Icons.do_not_disturb_on_rounded,
                      active: focus,
                      onTap: () => setState(() => focus = !focus),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SliderRow(
                  icon: volume == 0
                      ? Icons.volume_off_rounded
                      : volume < 0.5
                          ? Icons.volume_down_rounded
                          : Icons.volume_up_rounded,
                  percentage: '$volPct%',
                  value: volume,
                  onChanged: (val) => setState(() => volume = val),
                ),
                const SizedBox(height: 8),
                _SliderRow(
                  icon: Icons.brightness_6_rounded,
                  percentage: '$briPct%',
                  value: brightness,
                  onChanged: (val) => setState(() => brightness = val),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: CloudOSColors.elevated.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: CloudOSColors.border),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.battery_charging_full_rounded, color: CloudOSColors.success, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '${widget.snapshot.batteryPercent}% • Carregando',
                              style: const TextStyle(
                                color: CloudOSColors.text,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              widget.snapshot.wslAvailable
                                  ? 'WSL2: ${widget.snapshot.distros.join(', ')}'
                                  : 'Windows Desktop Standalone',
                              style: const TextStyle(color: CloudOSColors.caption, fontSize: 10),
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
                          style: TextStyle(color: CloudOSColors.linux, fontSize: 9.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? CloudOSColors.accentSoft : CloudOSColors.elevated.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? CloudOSColors.accent : CloudOSColors.border,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              color: active ? CloudOSColors.accent : CloudOSColors.secondary,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CloudOSColors.text,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: CloudOSColors.caption, fontSize: 9.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.icon,
    required this.percentage,
    required this.value,
    required this.onChanged,
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
