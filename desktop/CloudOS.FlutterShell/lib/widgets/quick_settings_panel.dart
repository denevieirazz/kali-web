import 'dart:io';

import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';
import '../models/shell_models.dart';
import '../services/cloudos_bridge.dart';
import '../services/system_tray_state_service.dart';
import 'glass_surface.dart';

class QuickSettingsPanel extends StatefulWidget {
  const QuickSettingsPanel({
    required this.snapshot,
    this.onVolumeChanged,
    this.onBrightnessChanged,
    this.bridge,
    this.systemStateService,
    this.onClose,
    this.onOpenSettings,
    super.key,
  }) : assert(
         bridge != null ||
             systemStateService != null ||
             (onVolumeChanged != null && onBrightnessChanged != null),
         'QuickSettingsPanel requires a bridge, a live system service, or both control callbacks.',
       );

  final CloudSystemSnapshot snapshot;
  final Future<bool> Function(double value)? onVolumeChanged;
  final Future<bool> Function(double value)? onBrightnessChanged;
  final CloudOSBridge? bridge;
  final SystemTrayStateService? systemStateService;
  final VoidCallback? onClose;
  final VoidCallback? onOpenSettings;

  @override
  State<QuickSettingsPanel> createState() => _QuickSettingsPanelState();
}

class _QuickSettingsPanelState extends State<QuickSettingsPanel> {
  late double volume = widget.snapshot.normalized().volume;
  late double brightness = widget.snapshot.normalized().brightness;
  SystemTrayStateService? _systemState;
  bool _ownsSystemState = false;
  late final bool _nativeRuntimeEnabled;

  CloudSystemSnapshot get _visibleSnapshot {
    final service = _systemState;
    if (service == null || service.lastRefreshAt == null) {
      return widget.snapshot.normalized();
    }
    return service.snapshot.normalized();
  }

  @override
  void initState() {
    super.initState();
    _nativeRuntimeEnabled = !Platform.environment.containsKey('FLUTTER_TEST');
    _bindSystemState();
  }

  @override
  void didUpdateWidget(covariant QuickSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.systemStateService, widget.systemStateService) ||
        !identical(oldWidget.bridge, widget.bridge)) {
      _unbindSystemState();
      _bindSystemState();
      return;
    }

    if (oldWidget.snapshot != widget.snapshot &&
        (_systemState == null || _systemState!.lastRefreshAt == null)) {
      _syncControls(widget.snapshot.normalized(), notify: true);
    }
  }

  void _bindSystemState() {
    final shouldBind = widget.systemStateService != null || _nativeRuntimeEnabled;
    if (!shouldBind) {
      _systemState = null;
      _ownsSystemState = false;
      _syncControls(widget.snapshot.normalized(), notify: false);
      return;
    }

    _ownsSystemState = widget.systemStateService == null;
    _systemState = widget.systemStateService ??
        SystemTrayStateService(
          bridge: widget.bridge ?? const CloudOSBridge(),
        );
    _systemState!.addListener(_onSystemStateChanged);
    _systemState!.start();

    if (_systemState!.lastRefreshAt != null) {
      _syncControls(_systemState!.snapshot.normalized(), notify: false);
    } else {
      _syncControls(widget.snapshot.normalized(), notify: false);
    }
  }

  void _unbindSystemState() {
    final service = _systemState;
    if (service == null) return;
    service.removeListener(_onSystemStateChanged);
    if (_ownsSystemState) service.dispose();
    _systemState = null;
    _ownsSystemState = false;
  }

  void _onSystemStateChanged() {
    if (!mounted || _systemState == null) return;
    final service = _systemState!;
    if (service.lastRefreshAt == null) return;
    _syncControls(service.snapshot.normalized(), notify: true);
  }

  void _syncControls(CloudSystemSnapshot snapshot, {required bool notify}) {
    final nextVolume = snapshot.volume;
    final nextBrightness = snapshot.brightness;
    if (volume == nextVolume && brightness == nextBrightness) return;
    if (notify && mounted) {
      setState(() {
        volume = nextVolume;
        brightness = nextBrightness;
      });
    } else {
      volume = nextVolume;
      brightness = nextBrightness;
    }
  }

  @override
  void dispose() {
    _unbindSystemState();
    super.dispose();
  }

  Future<void> _setVolume(double value) async {
    final previous = volume;
    setState(() => volume = value);
    final callback = widget.onVolumeChanged;
    final service = _systemState;
    final updated = callback != null
        ? await callback(value)
        : service != null
        ? await service.setVolume(value)
        : await widget.bridge?.setVolume(value) ?? false;
    if (!mounted) return;
    if (!updated) {
      setState(() => volume = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O controle de volume não está disponível.'),
        ),
      );
      return;
    }
    if (service != null && callback != null) {
      // The callback already confirmed the native write. Keep this shared
      // presentation state in sync even if the audio driver emits no event.
      service.acceptConfirmedVolume(value);
    }
  }

  Future<void> _setBrightness(double value) async {
    final previous = brightness;
    setState(() => brightness = value);
    final callback = widget.onBrightnessChanged;
    final service = _systemState;
    final updated = callback != null
        ? await callback(value)
        : service != null
        ? await service.setBrightness(value)
        : await widget.bridge?.setBrightness(value) ?? false;
    if (!mounted) return;
    if (!updated) {
      setState(() => brightness = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O monitor não expõe controle de brilho compatível.'),
        ),
      );
      return;
    }
    if (service != null && callback != null) {
      service.acceptConfirmedBrightness(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _visibleSnapshot;
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
                      subtitle: snapshot.networkAvailable
                          ? (snapshot.networkName.isEmpty
                                ? 'Conectada'
                                : snapshot.networkName)
                          : 'Indisponível',
                      icon: snapshot.networkAvailable
                          ? Icons.wifi_rounded
                          : Icons.signal_wifi_off_rounded,
                      active: snapshot.networkAvailable,
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
                  icon: !snapshot.volumeAvailable || volume == 0
                      ? Icons.volume_off_rounded
                      : volume < 0.5
                      ? Icons.volume_down_rounded
                      : Icons.volume_up_rounded,
                  percentage: snapshot.volumeAvailable ? '$volPct%' : '—',
                  value: volume,
                  enabled: snapshot.volumeAvailable,
                  onChanged: _setVolume,
                ),
                const SizedBox(height: 8),
                _SliderRow(
                  icon: Icons.brightness_6_rounded,
                  percentage: snapshot.brightnessAvailable ? '$briPct%' : '—',
                  value: brightness,
                  enabled: snapshot.brightnessAvailable,
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
                        snapshot.batteryAvailable
                            ? Icons.battery_full_rounded
                            : Icons.power_rounded,
                        color: snapshot.batteryAvailable
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
                              snapshot.batteryAvailable
                                  ? '${snapshot.batteryPercent}%'
                                  : 'Bateria não detectada',
                              style: const TextStyle(
                                color: CloudOSColors.text,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              snapshot.wslAvailable
                                  ? (snapshot.distros.isEmpty
                                        ? 'WSL disponível · sem distro configurada'
                                        : 'WSL2: ${snapshot.distros.join(', ')}')
                                  : 'WSL indisponível',
                              style: const TextStyle(
                                color: CloudOSColors.caption,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (snapshot.wslAvailable)
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
