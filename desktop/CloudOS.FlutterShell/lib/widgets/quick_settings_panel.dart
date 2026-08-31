import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';
import '../models/shell_models.dart';
import 'glass_surface.dart';

class QuickSettingsPanel extends StatefulWidget {
  const QuickSettingsPanel({required this.snapshot, super.key});

  final CloudSystemSnapshot snapshot;

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

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 18, 76),
        child: SizedBox(
          width: 380,
          child: GlassSurface(
            borderRadius: 24,
            blur: 30,
            color: const Color(0xF014202B),
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Configurações rápidas',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const Icon(Icons.tune_rounded, color: CloudOSColors.caption, size: 20),
                  ],
                ),
                const SizedBox(height: 14),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  childAspectRatio: 2.3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: <Widget>[
                    _ToggleTile(
                      label: 'Wi‑Fi',
                      subtitle: widget.snapshot.networkName,
                      icon: Icons.wifi_rounded,
                      active: wifi,
                      onTap: () => setState(() => wifi = !wifi),
                    ),
                    _ToggleTile(
                      label: 'Bluetooth',
                      subtitle: bluetooth ? 'Ativado' : 'Desativado',
                      icon: Icons.bluetooth_rounded,
                      active: bluetooth,
                      onTap: () => setState(() => bluetooth = !bluetooth),
                    ),
                    _ToggleTile(
                      label: 'Luz noturna',
                      subtitle: nightLight ? 'Ativada' : 'Desativada',
                      icon: Icons.nightlight_round,
                      active: nightLight,
                      onTap: () => setState(() => nightLight = !nightLight),
                    ),
                    _ToggleTile(
                      label: 'Foco',
                      subtitle: focus ? 'Ligado' : 'Desligado',
                      icon: Icons.do_not_disturb_on_rounded,
                      active: focus,
                      onTap: () => setState(() => focus = !focus),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SliderRow(
                  icon: Icons.volume_up_rounded,
                  value: volume,
                  onChanged: (value) => setState(() => volume = value),
                ),
                const SizedBox(height: 8),
                _SliderRow(
                  icon: Icons.brightness_6_rounded,
                  value: brightness,
                  onChanged: (value) => setState(() => brightness = value),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    const Icon(Icons.terminal_rounded, color: CloudOSColors.linux, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.snapshot.wslAvailable
                            ? 'WSL ativo • ${widget.snapshot.distros.join(', ')}'
                            : 'WSL indisponível',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      '${widget.snapshot.batteryPercent}%',
                      style: const TextStyle(color: CloudOSColors.secondary, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.battery_5_bar_rounded, size: 18, color: CloudOSColors.success),
                  ],
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
      borderRadius: BorderRadius.circular(13),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: active ? CloudOSColors.accentSoft : CloudOSColors.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: active ? CloudOSColors.accent : CloudOSColors.border,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              color: active ? CloudOSColors.accent : CloudOSColors.secondary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: CloudOSColors.text, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: CloudOSColors.caption, fontSize: 9),
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
  const _SliderRow({required this.icon, required this.value, required this.onChanged});

  final IconData icon;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: CloudOSColors.secondary),
        const SizedBox(width: 10),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, 1.0),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
