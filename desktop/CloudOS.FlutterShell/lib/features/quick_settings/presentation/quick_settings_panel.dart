import 'dart:async';

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
    this.bridge,
    this.performanceProfile,
    this.onSetPerformanceProfile,
    this.onOpenSettings,
    this.onOpenNetworkSettings,
    this.onOpenBluetoothSettings,
    this.onOpenNightLightSettings,
    this.onOpenFocusSettings,
    this.onSetVolume,
    this.onSetBrightness,
    this.onSetMute,
    super.key,
  });

  final CloudSystemSnapshot snapshot;
  final CloudOSBridge? bridge;
  final PerformanceProfileInfo? performanceProfile;
  final Future<void> Function(String profile)? onSetPerformanceProfile;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenNetworkSettings;
  final VoidCallback? onOpenBluetoothSettings;
  final VoidCallback? onOpenNightLightSettings;
  final VoidCallback? onOpenFocusSettings;
  final Future<bool> Function(double value)? onSetVolume;
  final Future<bool> Function(double value)? onSetBrightness;
  final Future<bool> Function(bool muted)? onSetMute;

  @override
  State<QuickSettingsPanel> createState() => _QuickSettingsPanelState();
}

class _QuickSettingsPanelState extends State<QuickSettingsPanel> {
  late final CloudOSBridge _bridge = widget.bridge ?? const CloudOSBridge();
  late double volume = widget.snapshot.volume;
  late double brightness = widget.snapshot.brightness;

  CloudQuickSettingsState? _authoritativeState;
  List<CloudNetworkInterface> _networkInterfaces = const <CloudNetworkInterface>[];
  bool _refreshing = false;
  bool _volumeBusy = false;
  bool _muteBusy = false;
  bool _profileBusy = false;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshAuthoritativeState());
  }

  @override
  void didUpdateWidget(covariant QuickSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.volume != widget.snapshot.volume && !_volumeBusy) {
      volume = widget.snapshot.volume;
    }
    if (oldWidget.snapshot.brightness != widget.snapshot.brightness) {
      brightness = widget.snapshot.brightness;
    }
  }

  Future<void> _refreshAuthoritativeState() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final stateFuture = _bridge.getQuickSettingsState();
      final networkFuture = _bridge.getNetworkInterfaces();
      final state = await stateFuture;
      final interfaces = await networkFuture;
      if (!mounted) return;

      setState(() {
        _authoritativeState = state;
        _networkInterfaces = interfaces;
        if (state.audio.available) {
          volume = state.audio.volume.clamp(0.0, 1.0).toDouble();
        }
        _lastError = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _lastError = 'Não foi possível atualizar o estado do sistema.';
        });
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _commitVolume(double value) async {
    if (!_volumeAvailable || _volumeBusy) return;
    setState(() => _volumeBusy = true);
    final previous = _effectiveAudioVolume;
    var succeeded = false;
    try {
      if (widget.onSetVolume != null) {
        succeeded = await widget.onSetVolume!.call(value);
      } else {
        succeeded = await _bridge.setMasterVolume(value);
      }
      if (succeeded) {
        await _refreshAuthoritativeState();
      }
    } finally {
      if (!mounted) return;
      setState(() {
        _volumeBusy = false;
        if (!succeeded) {
          volume = previous;
          _lastError = 'Não foi possível alterar o volume.';
        }
      });
    }
  }

  Future<void> _toggleMute() async {
    if (!_volumeAvailable || _muteBusy) return;
    final target = !_isMuted;
    setState(() => _muteBusy = true);
    var succeeded = false;
    try {
      if (widget.onSetMute != null) {
        succeeded = await widget.onSetMute!.call(target);
      } else {
        succeeded = await _bridge.setMasterMute(target);
      }
      if (succeeded) {
        await _refreshAuthoritativeState();
      }
    } finally {
      if (!mounted) return;
      setState(() {
        _muteBusy = false;
        if (!succeeded) {
          _lastError = target
              ? 'Não foi possível silenciar o áudio.'
              : 'Não foi possível reativar o áudio.';
        }
      });
    }
  }

  Future<void> _commitBrightness(double value) async {
    if (!widget.snapshot.brightnessAvailable) return;
    final succeeded = await widget.onSetBrightness?.call(value) ??
        await _bridge.setBrightness(value);
    if (!succeeded && mounted) {
      setState(() {
        brightness = widget.snapshot.brightness;
        _lastError = 'Não foi possível alterar o brilho neste monitor.';
      });
    }
  }

  Future<void> _setPerformanceProfile(String profile) async {
    if (_profileBusy) return;
    setState(() => _profileBusy = true);
    var succeeded = false;
    try {
      if (widget.onSetPerformanceProfile != null) {
        await widget.onSetPerformanceProfile!.call(profile);
        succeeded = true;
      } else {
        succeeded = await _bridge.setPerformanceProfile(profile);
      }
      if (succeeded) {
        await _refreshAuthoritativeState();
      }
    } finally {
      if (!mounted) return;
      setState(() {
        _profileBusy = false;
        if (!succeeded) {
          _lastError = 'Não foi possível alterar o perfil de desempenho.';
        }
      });
    }
  }

  CloudNetworkInterface? get _primaryNetwork {
    for (final interface in _networkInterfaces) {
      if (interface.status.toLowerCase() == 'up' && interface.isInternetConnected) {
        return interface;
      }
    }
    for (final interface in _networkInterfaces) {
      if (interface.status.toLowerCase() == 'up') return interface;
    }
    return null;
  }

  bool get _networkActive =>
      _primaryNetwork != null || widget.snapshot.networkAvailable;

  String get _networkLabel {
    final type = _primaryNetwork?.type.trim();
    if (type != null && type.isNotEmpty && type.toLowerCase().contains('wi')) {
      return 'Wi‑Fi';
    }
    if (type != null && type.isNotEmpty && type.toLowerCase().contains('ethernet')) {
      return 'Ethernet';
    }
    return 'Rede';
  }

  String get _networkSubtitle {
    final interface = _primaryNetwork;
    if (interface != null) {
      final friendly = interface.friendlyName.trim();
      if (friendly.isNotEmpty) return friendly;
      final name = interface.name.trim();
      if (name.isNotEmpty) return name;
      return interface.isInternetConnected ? 'Conectado' : 'Ativo';
    }
    if (widget.snapshot.networkAvailable) {
      return widget.snapshot.networkName.isNotEmpty
          ? widget.snapshot.networkName
          : 'Conectado';
    }
    return 'Sem conexão';
  }

  CloudBluetoothStatus get _bluetooth =>
      _authoritativeState?.bluetooth ?? const CloudBluetoothStatus();

  bool get _volumeAvailable =>
      (_authoritativeState?.audio.available ?? false) ||
      widget.snapshot.volumeAvailable;

  double get _effectiveAudioVolume =>
      (_authoritativeState?.audio.available ?? false)
          ? _authoritativeState!.audio.volume.clamp(0.0, 1.0).toDouble()
          : widget.snapshot.volume.clamp(0.0, 1.0).toDouble();

  bool get _isMuted => _authoritativeState?.audio.isMuted ?? false;

  String get _performanceProfileName =>
      _authoritativeState?.performanceProfile ??
      widget.performanceProfile?.profile ??
      'balanced';

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
                _QuickSettingsHeader(
                  onOpenSettings: widget.onOpenSettings,
                  refreshing: _refreshing,
                  onRefresh: _refreshAuthoritativeState,
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
                    QuickToggleTile(
                      label: _networkLabel,
                      subtitle: _networkSubtitle,
                      icon: _networkActive
                          ? Icons.wifi_rounded
                          : Icons.wifi_off_rounded,
                      active: _networkActive,
                      showChevron: true,
                      onTap: widget.onOpenNetworkSettings,
                    ),
                    QuickToggleTile(
                      label: 'Bluetooth',
                      subtitle: !_bluetooth.available
                          ? 'Indisponível'
                          : _bluetooth.enabled
                              ? 'Ligado • Dispositivos'
                              : 'Desligado • Dispositivos',
                      icon: Icons.bluetooth_rounded,
                      active: _bluetooth.available && _bluetooth.enabled,
                      enabled: _bluetooth.available ||
                          widget.onOpenBluetoothSettings != null,
                      showChevron: true,
                      onTap: widget.onOpenBluetoothSettings,
                    ),
                    QuickToggleTile(
                      label: 'Luz Noturna',
                      subtitle: 'Configurar no CloudOS',
                      icon: Icons.nightlight_round,
                      active: false,
                      showChevron: true,
                      onTap: widget.onOpenNightLightSettings,
                    ),
                    QuickToggleTile(
                      label: 'Modo Foco',
                      subtitle: 'Configurar no CloudOS',
                      icon: Icons.do_not_disturb_on_rounded,
                      active: false,
                      showChevron: true,
                      onTap: widget.onOpenFocusSettings,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                QuickSliderRow(
                  icon: _isMuted
                      ? Icons.volume_off_rounded
                      : volume == 0
                          ? Icons.volume_off_rounded
                          : volume < 0.5
                              ? Icons.volume_down_rounded
                              : Icons.volume_up_rounded,
                  percentage: _volumeAvailable ? '$volPct%' : 'N/D',
                  value: volume,
                  enabled: _volumeAvailable && !_volumeBusy,
                  onIconTap: _volumeAvailable && !_muteBusy
                      ? () => unawaited(_toggleMute())
                      : null,
                  iconTooltip: _isMuted ? 'Ativar som' : 'Silenciar',
                  onChanged: (value) => setState(() => volume = value),
                  onChangeEnd: (value) async => _commitVolume(value),
                ),
                const SizedBox(height: 8),
                QuickSliderRow(
                  icon: Icons.brightness_6_rounded,
                  percentage: widget.snapshot.brightnessAvailable
                      ? '$briPct%'
                      : 'N/D',
                  value: brightness,
                  enabled: widget.snapshot.brightnessAvailable,
                  onChanged: (value) => setState(() => brightness = value),
                  onChangeEnd: (value) async => _commitBrightness(value),
                ),
                const SizedBox(height: 12),
                if (widget.performanceProfile != null ||
                    _authoritativeState != null) ...[
                  _PerformanceProfileRow(
                    profile: widget.performanceProfile ??
                        PerformanceProfileInfo(
                          profile: _performanceProfileName,
                        ),
                    authoritativeProfile: _performanceProfileName,
                    busy: _profileBusy,
                    onSelect: _setPerformanceProfile,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_lastError != null) ...[
                  _InlineError(
                    message: _lastError!,
                    onDismiss: () => setState(() => _lastError = null),
                  ),
                  const SizedBox(height: 10),
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
  const _QuickSettingsHeader({
    this.onOpenSettings,
    required this.refreshing,
    required this.onRefresh,
  });

  final VoidCallback? onOpenSettings;
  final bool refreshing;
  final Future<void> Function() onRefresh;

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
          message: 'Atualizar estado',
          child: InkWell(
            onTap: refreshing ? null : () => unawaited(onRefresh()),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: refreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.refresh_rounded,
                      size: 18,
                      color: CloudOSColors.secondary,
                    ),
            ),
          ),
        ),
        const SizedBox(width: 4),
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

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: CloudOSColors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CloudOSColors.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline_rounded,
              size: 16, color: CloudOSColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: CloudOSColors.secondary,
                fontSize: 10,
              ),
            ),
          ),
          InkWell(
            onTap: onDismiss,
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.close_rounded,
                  size: 14, color: CloudOSColors.caption),
            ),
          ),
        ],
      ),
    );
  }
}

class _PerformanceProfileRow extends StatelessWidget {
  const _PerformanceProfileRow({
    required this.profile,
    required this.authoritativeProfile,
    required this.busy,
    this.onSelect,
  });

  final PerformanceProfileInfo profile;
  final String authoritativeProfile;
  final bool busy;
  final Future<void> Function(String profile)? onSelect;

  @override
  Widget build(BuildContext context) {
    final normalized = authoritativeProfile.toLowerCase();
    final isEco = normalized == 'economy';
    final isPerf = normalized == 'performance';
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
            onTap: busy
                ? null
                : () {
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
              child: Text(
                busy ? 'Aplicando…' : 'Alternar',
                style: const TextStyle(
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
