import 'package:flutter/material.dart';

import '../../../core/cloudos_theme.dart';
import '../../../core/responsive/cloud_responsive_layout.dart';
import '../../../models/cloud_system_snapshot.dart';
import '../../../services/cloudos_bridge.dart';
import '../../../widgets/glass_surface.dart';
import 'widgets/quick_slider_row.dart';
import 'widgets/quick_system_summary.dart';
import 'widgets/quick_toggle_tile.dart';

class QuickSettingsPanel extends StatefulWidget {
  const QuickSettingsPanel({
    required this.snapshot,
    this.performanceProfile,
    this.onSetPerformanceProfile,
    this.onOpenSettings,
    this.onOpenNetworkSettings,
    this.onOpenBluetoothSettings,
    this.onOpenNightLightSettings,
    this.onOpenFocusSettings,
    this.onSetVolume,
    this.onSetBrightness,
    super.key,
  });

  final CloudSystemSnapshot snapshot;
  final PerformanceProfileInfo? performanceProfile;
  final Future<void> Function(String profile)? onSetPerformanceProfile;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenNetworkSettings;
  final VoidCallback? onOpenBluetoothSettings;
  final VoidCallback? onOpenNightLightSettings;
  final VoidCallback? onOpenFocusSettings;
  final Future<bool> Function(double value)? onSetVolume;
  final Future<bool> Function(double value)? onSetBrightness;

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

  Future<void> _commitVolume(double value) async {
    if (!widget.snapshot.volumeAvailable) return;
    final succeeded = await widget.onSetVolume?.call(value) ?? true;
    if (!succeeded && mounted) {
      setState(() => volume = widget.snapshot.volume);
    }
  }

  Future<void> _commitBrightness(double value) async {
    if (!widget.snapshot.brightnessAvailable) return;
    final succeeded = await widget.onSetBrightness?.call(value) ?? true;
    if (!succeeded && mounted) {
      setState(() => brightness = widget.snapshot.brightness);
    }
  }

  @override
  Widget build(BuildContext context) {
    final volPct = (volume * 100).round();
    final briPct = (brightness * 100).round();
    final metrics = context.cloudMetrics;
    final panelWidth = metrics.quickSettingsWidth;
    final bottomPadding = metrics.taskbarHeight + 12.0;

    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: EdgeInsets.fromLTRB(0, 0, 16, bottomPadding),
        child: SizedBox(
          width: panelWidth,
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
                _QuickSettingsHeader(onOpenSettings: widget.onOpenSettings),
                const SizedBox(height: 12),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  childAspectRatio: 2.35,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: <Widget>[
                    QuickToggleTile(
                      label: 'Rede',
                      subtitle: widget.snapshot.networkAvailable
                          ? widget.snapshot.networkName
                          : 'Abrir Wi-Fi',
                      icon: widget.snapshot.networkAvailable
                          ? Icons.wifi_rounded
                          : Icons.wifi_off_rounded,
                      active: widget.snapshot.networkAvailable,
                      onTap: widget.onOpenNetworkSettings,
                    ),
                    QuickToggleTile(
                      label: 'Bluetooth',
                      subtitle: 'Abrir dispositivos',
                      icon: Icons.bluetooth_rounded,
                      active: false,
                      onTap: widget.onOpenBluetoothSettings,
                    ),
                    QuickToggleTile(
                      label: 'Luz Noturna',
                      subtitle: 'Abrir configuração',
                      icon: Icons.nightlight_round,
                      active: false,
                      onTap: widget.onOpenNightLightSettings,
                    ),
                    QuickToggleTile(
                      label: 'Modo Foco',
                      subtitle: 'Abrir configuração',
                      icon: Icons.do_not_disturb_on_rounded,
                      active: false,
                      onTap: widget.onOpenFocusSettings,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                QuickSliderRow(
                  icon: volume == 0
                      ? Icons.volume_off_rounded
                      : volume < 0.5
                          ? Icons.volume_down_rounded
                          : Icons.volume_up_rounded,
                  percentage: '$volPct%',
                  value: volume,
                  enabled: widget.snapshot.volumeAvailable,
                  onChanged: (value) => setState(() => volume = value),
                  onChangeEnd: (value) async => _commitVolume(value),
                ),
                const SizedBox(height: 8),
                QuickSliderRow(
                  icon: Icons.brightness_6_rounded,
                  percentage: '$briPct%',
                  value: brightness,
                  enabled: widget.snapshot.brightnessAvailable,
                  onChanged: (value) => setState(() => brightness = value),
                  onChangeEnd: (value) async => _commitBrightness(value),
                ),
                const SizedBox(height: 12),
                if (widget.performanceProfile != null) ...[
                  _PerformanceProfileRow(
                    profile: widget.performanceProfile!,
                    onSelect: widget.onSetPerformanceProfile,
                  ),
                  const SizedBox(height: 12),
                ],
                const Divider(height: 1),
                const SizedBox(height: 12),
                QuickSystemSummary(snapshot: widget.snapshot),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickSettingsHeader extends StatelessWidget {
  const _QuickSettingsHeader({this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
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
            onTap: onOpenSettings,
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
      ],
    );
  }
}

class _PerformanceProfileRow extends StatelessWidget {
  const _PerformanceProfileRow({
    required this.profile,
    this.onSelect,
  });

  final PerformanceProfileInfo profile;
  final Future<void> Function(String profile)? onSelect;

  @override
  Widget build(BuildContext context) {
    final isEco = profile.profile == 'economy';
    final isPerf = profile.profile == 'performance';
    final label = isEco
        ? 'Econômico (Sem Blur)'
        : isPerf
            ? 'Desempenho Máximo'
            : 'Balanceado';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: CloudOSColors.elevated.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CloudOSColors.border),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            isEco ? Icons.eco_rounded : Icons.bolt_rounded,
            size: 18,
            color: isEco ? CloudOSColors.success : CloudOSColors.accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: const TextStyle(
                    color: CloudOSColors.text,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  profile.isLowEndHardware
                      ? 'Hardware modesto detectado'
                      : 'Otimização de energia e recursos',
                  style: const TextStyle(
                    color: CloudOSColors.caption,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () {
              final next = isEco
                  ? 'balanced'
                  : isPerf
                      ? 'economy'
                      : 'performance';
              onSelect?.call(next);
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: CloudOSColors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: CloudOSColors.accent.withValues(alpha: 0.3),
                ),
              ),
              child: const Text(
                'Alternar',
                style: TextStyle(
                  color: CloudOSColors.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
