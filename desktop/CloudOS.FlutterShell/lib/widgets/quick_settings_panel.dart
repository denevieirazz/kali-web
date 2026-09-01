import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';
import '../models/shell_models.dart';
import '../services/cloudos_bridge.dart';
import 'glass_surface.dart';

class QuickSettingsPanel extends StatefulWidget {
  const QuickSettingsPanel({
    required this.snapshot,
    this.onVolumeChanged,
    this.onBrightnessChanged,
    this.bridge,
    this.onClose,
    this.onOpenSettings,
    super.key,
  }) : assert(
         bridge != null ||
             (onVolumeChanged != null && onBrightnessChanged != null),
         'QuickSettingsPanel requires either a CloudOSBridge or both control callbacks.',
       );

  final CloudSystemSnapshot snapshot;
  final Future<bool> Function(double value)? onVolumeChanged;
  final Future<bool> Function(double value)? onBrightnessChanged;
  final CloudOSBridge? bridge;
  final VoidCallback? onClose;
  final VoidCallback? onOpenSettings;

  @override
  State<QuickSettingsPanel> createState() => _QuickSettingsPanelState();
}

class _QuickSettingsPanelState extends State<QuickSettingsPanel> {
  late double volume = widget.snapshot.volume;
  late double brightness = widget.snapshot.brightness;

  Future<void> _setVolume(double value) async {
    final previous = volume;
    setState(() => volume = value);
    final handler = widget.onVolumeChanged ?? widget.bridge?.setVolume;
    final updated = handler != null && await handler(value);
    if (!mounted) return;
    if (!updated) {
      setState(() => volume = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O controle de volume não está disponível.'),
        ),
      );
    }
  }

  Future<void> _setBrightness(double value) async {
    final previous = brightness;
    setState(() => brightness = value);
    final handler =
        widget.onBrightnessChanged ?? widget.bridge?.setBrightness;
    final updated = handler != null && await handler(value);
    if (!mounted) return;
    if (!updated) {
      setState(() => brightness = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O monitor não expõe controle de brilho compatível.'),
        ),
      );
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
                    if (widget.onOpenSettings != null)
                      Tooltip(
                        message: 'Abrir Painel Completo',
                        child: InkWell(
                          onTap: widget.onOpenSettings,
                          borderRadius: BorderRadius.circular(6),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.settings_rounded,
                              size: 18,
                              color: CloudOSColors.secondary,
                            ),
                          ),
                        ),
                      ),
                    if (widget.onClose != null) ...<Widget>[
                      const SizedBox(width: 4),
                      Tooltip(
                        message: 'Fechar (Esc)',
                        child: InkWell(
                          onTap: widget.onClose,
                          borderRadius: BorderRadius.circular(6),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: CloudOSColors.secondary,
                            ),
                          ),
                        ),
                      ),
                    ],
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
                          ? (widget.snapshot.networkName.isEmpty
                                ? 'Conectada'
                                : widget.snapshot.networkName)
                          : 'Indisponível',
                      icon: Icons.wifi_rounded,
                      active: widget.snapshot.networkAvailable,
                    ),
                    const _ToggleTile(
                      label: 'Bluetooth',
                      subtitle: 'Somente no painel do Windows',
                      icon: Icons.bluetooth_rounded,
                      active: false,
                    ),
                    const _ToggleTile(
                      label: 'Luz Noturna',
                      subtitle: 'Somente no painel do Windows',
                      icon: Icons.nightlight_round,
                      active: false,
                    ),
                    const _ToggleTile(
                      label: 'Modo Foco',
                      subtitle: 'Somente no painel do Windows',
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
                  percentage: '$volPct%',
                  value: volume,
                  enabled: widget.snapshot.volumeAvailable,
                  onChanged: _setVolume,
                ),
                const SizedBox(height: 8),
                _SliderRow(
                  icon: Icons.brightness_6_rounded,
                  percentage: '$briPct%',
                  value: brightness,
                  enabled: widget.snapshot.brightnessAvailable,
                  onChanged: _setBrightness,
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: CloudOSColors.elevated.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: CloudOSColors.border),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        widget.snapshot.batteryAvailable
                            ? Icons.battery_charging_full_rounded
                            : Icons.power_rounded,
                        color: widget.snapshot.batteryAvailable
                            ? CloudOSColors.success
                            : CloudOSColors.textSecondary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              widget.snapshot.batteryAvailable
                                  ? '${widget.snapshot.batteryPercent}%'
                                  : 'Bateria não detectada',
                              style: const TextStyle(
                                color: CloudOSColors.text,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              widget.snapshot.wslAvailable
                                  ? (widget.snapshot.distros.isEmpty
                                        ? 'WSL disponível · sem distro configurada'
                                        : 'WSL2: ${widget.snapshot.distros.join(', ')}')
                                  : 'WSL indisponível',
                              style: const TextStyle(
                                color: CloudOSColors.caption,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.snapshot.wslAvailable)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: CloudOSColors.linuxSoft,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'WSL disponível',
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
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: active
            ? CloudOSColors.accentSoft
            : CloudOSColors.elevated.withValues(alpha: 0.4),
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
                  style: const TextStyle(
                    color: CloudOSColors.caption,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
        ],
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
    this.enabled = true,
  });

  final IconData icon;
  final String percentage;
  final double value;
  final ValueChanged<double> onChanged;
  final bool enabled;

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
              onChanged: enabled ? onChanged : null,
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
