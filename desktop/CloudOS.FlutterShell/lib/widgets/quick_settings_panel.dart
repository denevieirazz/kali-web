import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';
import '../models/shell_models.dart';
import 'glass_surface.dart';

class QuickSettingsPanel extends StatefulWidget {
  const QuickSettingsPanel({
    required this.snapshot,
    this.onOpenSettings,
    this.onVolumeChanged,
    this.onBrightnessChanged,
    super.key,
  });

  final CloudSystemSnapshot snapshot;
  final VoidCallback? onOpenSettings;
  final ValueChanged<double>? onVolumeChanged;
  final ValueChanged<double>? onBrightnessChanged;

  @override
  State<QuickSettingsPanel> createState() => _QuickSettingsPanelState();
}

class _QuickSettingsPanelState extends State<QuickSettingsPanel> {
  late double volume = widget.snapshot.volume;
  late double brightness = widget.snapshot.brightness;

  @override
  void didUpdateWidget(covariant QuickSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.volume != widget.snapshot.volume) {
      volume = widget.snapshot.volume;
    }
    if (oldWidget.snapshot.brightness != widget.snapshot.brightness) {
      brightness = widget.snapshot.brightness;
    }
  }

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
                      message: 'Abrir Configurações do Windows',
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
                      label: 'Rede',
                      subtitle: widget.snapshot.networkAvailable
                          ? widget.snapshot.networkName
                          : 'Sem conexão detectada',
                      icon: widget.snapshot.networkAvailable
                          ? Icons.wifi_rounded
                          : Icons.wifi_off_rounded,
                      active: widget.snapshot.networkAvailable,
                    ),
                    const _ToggleTile(
                      label: 'Bluetooth',
                      subtitle: 'Backend ainda não exposto',
                      icon: Icons.bluetooth_rounded,
                      active: false,
                    ),
                    const _ToggleTile(
                      label: 'Luz Noturna',
                      subtitle: 'Backend ainda não exposto',
                      icon: Icons.nightlight_round,
                      active: false,
                    ),
                    const _ToggleTile(
                      label: 'Modo Foco',
                      subtitle: 'Backend ainda não exposto',
                      icon: Icons.do_not_disturb_on_rounded,
                      active: false,
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
                  percentage: widget.snapshot.volumeAvailable ? '$volPct%' : 'N/D',
                  value: volume,
                  enabled: widget.snapshot.volumeAvailable,
                  onChanged: (val) => setState(() => volume = val),
                  onChangeEnd: widget.onVolumeChanged,
                ),
                const SizedBox(height: 8),
                _SliderRow(
                  icon: Icons.brightness_6_rounded,
                  percentage: widget.snapshot.brightnessAvailable ? '$briPct%' : 'N/D',
                  value: brightness,
                  enabled: widget.snapshot.brightnessAvailable,
                  onChanged: (val) => setState(() => brightness = val),
                  onChangeEnd: widget.onBrightnessChanged,
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
                      Icon(
                        widget.snapshot.batteryAvailable
                            ? Icons.battery_5_bar_rounded
                            : Icons.desktop_windows_rounded,
                        color: widget.snapshot.batteryAvailable
                            ? CloudOSColors.success
                            : CloudOSColors.secondary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              widget.snapshot.batteryAvailable
                                  ? '${widget.snapshot.batteryPercent}% de bateria'
                                  : 'Energia do desktop',
                              style: const TextStyle(
                                color: CloudOSColors.text,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              widget.snapshot.wslAvailable
                                  ? widget.snapshot.distros.isEmpty
                                      ? 'WSL instalado • nenhuma distro registrada'
                                      : 'WSL: ${widget.snapshot.distros.join(', ')}'
                                  : 'WSL não disponível',
                              style: const TextStyle(color: CloudOSColors.caption, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      if (widget.snapshot.wslAvailable)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: CloudOSColors.linuxSoft,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'WSL',
                            style: TextStyle(
                              color: CloudOSColors.linux,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
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
    this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;

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
    required this.enabled,
    required this.onChanged,
    this.onChangeEnd,
  });

  final IconData icon;
  final String percentage;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(
          icon,
          size: 18,
          color: enabled ? CloudOSColors.secondary : CloudOSColors.caption,
        ),
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
              onChanged: enabled ? onChanged : null,
              onChangeEnd: enabled ? onChangeEnd : null,
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
