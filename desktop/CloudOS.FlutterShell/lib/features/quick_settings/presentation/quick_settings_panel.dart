import 'package:flutter/material.dart';

import '../../../core/cloudos_theme.dart';
import '../../../models/cloud_system_snapshot.dart';
import '../../../widgets/glass_surface.dart';
import 'widgets/quick_slider_row.dart';
import 'widgets/quick_system_summary.dart';
import 'widgets/quick_toggle_tile.dart';

class QuickSettingsPanel extends StatefulWidget {
  const QuickSettingsPanel({
    required this.snapshot,
    this.onOpenSettings,
    this.onSetVolume,
    this.onSetBrightness,
    super.key,
  });

  final CloudSystemSnapshot snapshot;
  final VoidCallback? onOpenSettings;
  final Future<bool> Function(double value)? onSetVolume;
  final Future<bool> Function(double value)? onSetBrightness;

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
    final succeeded = await widget.onSetVolume?.call(value) ?? true;
    if (!succeeded && mounted) {
      setState(() => volume = widget.snapshot.volume);
    }
  }

  Future<void> _commitBrightness(double value) async {
    final succeeded = await widget.onSetBrightness?.call(value) ?? true;
    if (!succeeded && mounted) {
      setState(() => brightness = widget.snapshot.brightness);
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
                      label: 'Wi‑Fi 6',
                      subtitle: wifi ? widget.snapshot.networkName : 'Desativado',
                      icon: Icons.wifi_rounded,
                      active: wifi,
                      onTap: () => setState(() => wifi = !wifi),
                    ),
                    QuickToggleTile(
                      label: 'Bluetooth',
                      subtitle: bluetooth ? 'Conectado' : 'Desativado',
                      icon: Icons.bluetooth_rounded,
                      active: bluetooth,
                      onTap: () => setState(() => bluetooth = !bluetooth),
                    ),
                    QuickToggleTile(
                      label: 'Luz Noturna',
                      subtitle: nightLight ? 'Ativada (Quente)' : 'Desativada',
                      icon: Icons.nightlight_round,
                      active: nightLight,
                      onTap: () => setState(() => nightLight = !nightLight),
                    ),
                    QuickToggleTile(
                      label: 'Modo Foco',
                      subtitle: focus ? 'Silencioso' : 'Desligado',
                      icon: Icons.do_not_disturb_on_rounded,
                      active: focus,
                      onTap: () => setState(() => focus = !focus),
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
                  onChanged: (value) => setState(() => volume = value),
                  onChangeEnd: (value) async => _commitVolume(value),
                ),
                const SizedBox(height: 8),
                QuickSliderRow(
                  icon: Icons.brightness_6_rounded,
                  percentage: '$briPct%',
                  value: brightness,
                  onChanged: (value) => setState(() => brightness = value),
                  onChangeEnd: (value) async => _commitBrightness(value),
                ),
                const SizedBox(height: 12),
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
