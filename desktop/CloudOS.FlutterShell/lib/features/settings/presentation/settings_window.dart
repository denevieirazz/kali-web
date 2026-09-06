import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/cloudos_theme.dart';
import '../../../core/cloudos_version.dart';
import '../../../models/cloud_system_snapshot.dart';
import '../../../services/cloudos_bridge.dart';
import '../../../services/cloudos_preferences.dart';

enum SettingsCategoryGroup {
  system,
  connectivity,
  cloudos,
}

enum SettingsSection {
  // System
  overview('Visão Geral', Icons.space_dashboard_rounded, SettingsCategoryGroup.system),
  display('Tela & Display', Icons.monitor_rounded, SettingsCategoryGroup.system),
  sound('Áudio e Vídeo', Icons.volume_up_rounded, SettingsCategoryGroup.system),
  power('Energia & Bateria', Icons.battery_charging_full_rounded, SettingsCategoryGroup.system),
  storage('Armazenamento', Icons.storage_rounded, SettingsCategoryGroup.system),
  performance('Desempenho', Icons.speed_rounded, SettingsCategoryGroup.system),
  startup('Shell & Startup', Icons.terminal_sharp, SettingsCategoryGroup.system),

  // Connectivity
  network('Rede e Internet', Icons.wifi_rounded, SettingsCategoryGroup.connectivity),
  bluetooth('Bluetooth & Dispositivos', Icons.bluetooth_rounded, SettingsCategoryGroup.connectivity),

  // CloudOS
  personalization('Personalização', Icons.palette_rounded, SettingsCategoryGroup.cloudos),
  wsl('WSL e Linux', Icons.terminal_rounded, SettingsCategoryGroup.cloudos),
  recovery('Recuperação & Safe Mode', Icons.healing_rounded, SettingsCategoryGroup.cloudos),
  diagnostics('Diagnósticos', Icons.analytics_rounded, SettingsCategoryGroup.cloudos),
  about('Sobre o CloudOS', Icons.info_outline_rounded, SettingsCategoryGroup.cloudos);

  const SettingsSection(this.title, this.icon, this.group);
  final String title;
  final IconData icon;
  final SettingsCategoryGroup group;
}

class SettingsWindow extends StatefulWidget {
  const SettingsWindow({
    this.snapshot = CloudOSBridge.degradedSnapshot,
    this.bridge = const CloudOSBridge(),
    this.initialSection = SettingsSection.overview,
    super.key,
  });

  final CloudSystemSnapshot snapshot;
  final CloudOSBridge bridge;
  final SettingsSection initialSection;

  @override
  State<SettingsWindow> createState() => _SettingsWindowState();
}

class _SettingsWindowState extends State<SettingsWindow> {
  late SettingsSection _activeSection;

  // Audio state
  CloudAudioState _audioState = const CloudAudioState();
  double _volume = 0.5;
  bool _muted = false;

  // Display state
  List<CloudDisplayMonitor> _monitors = const [];
  List<CloudDisplayMode> _displayModes = const [];
  CloudDisplayMode? _selectedMode;
  int _selectedMonitorIndex = 0;
  bool _displayLoading = false;
  Timer? _revertTimer;
  int _revertCountdown = 15;

  // Storage state
  List<CloudStorageDrive> _storageDrives = const [];

  // Network & Bluetooth
  List<CloudNetworkInterface> _networkInterfaces = const [];
  List<CloudWifiNetwork> _wifiNetworks = const [];
  CloudBluetoothStatus _bluetoothStatus = const CloudBluetoothStatus();

  // Performance & Power
  PerformanceProfileInfo _performanceProfile = PerformanceProfileInfo.defaultBalanced;
  CloudPowerStatus _powerStatus = const CloudPowerStatus();
  CloudHardwareMetrics? _hardwareMetrics;

  // Personalization
  CloudPersonalizationSettings _personalization = const CloudPersonalizationSettings();

  // WSL
  List<WslDistroInfo> _wslDistros = const [];

  // Recovery & Diagnostics
  CloudOSRecoveryStatus? _recoveryStatus;

  // Startup & Shell
  CloudStartupStatus _startupStatus = const CloudStartupStatus();
  bool _startupUpdating = false;
  CloudShellStatus _shellStatus = const CloudShellStatus();
  bool _shellUpdating = false;

  @override
  void initState() {
    super.initState();
    _activeSection = widget.initialSection;
    _volume = widget.snapshot.volume;
    _loadInitialData();
  }

  @override
  void didUpdateWidget(covariant SettingsWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) {
      setState(() {
        _activeSection = widget.initialSection;
      });
    }
  }

  Future<void> _selectMonitor(int index) async {
    if (index < 0 || index >= _monitors.length) return;
    setState(() {
      _selectedMonitorIndex = index;
      _displayLoading = true;
    });
    try {
      final modes = await widget.bridge.getDisplayModes(_monitors[index].deviceName);
      if (mounted) {
        setState(() {
          _displayModes = modes;
          if (modes.isNotEmpty) {
            _selectedMode = modes.firstWhere(
              (m) => m.width == _monitors[index].width && m.height == _monitors[index].height,
              orElse: () => modes.first,
            );
          }
        });
      }
    } finally {
      if (mounted) setState(() => _displayLoading = false);
    }
  }

  Future<void> _loadInitialData() async {
    // Audio
    try {
      final audio = await widget.bridge.getAudioState();
      if (mounted) {
        setState(() {
          _audioState = audio;
          _volume = audio.volume;
          _muted = audio.isMuted;
        });
      }
    } catch (_) {}

    // Display
    try {
      final monitors = await widget.bridge.getDisplayMonitors();
      if (mounted && monitors.isNotEmpty) {
        if (_selectedMonitorIndex >= monitors.length) {
          _selectedMonitorIndex = 0;
        }
        setState(() => _monitors = monitors);
        final curMon = monitors[_selectedMonitorIndex];
        final modes = await widget.bridge.getDisplayModes(curMon.deviceName);
        if (mounted) {
          setState(() {
            _displayModes = modes;
            if (modes.isNotEmpty) {
              _selectedMode = modes.firstWhere(
                (m) => m.width == curMon.width && m.height == curMon.height,
                orElse: () => modes.first,
              );
            }
          });
        }
      }
    } catch (_) {}

    // Storage
    try {
      final drives = await widget.bridge.getStorageDrives();
      if (mounted) setState(() => _storageDrives = drives);
    } catch (_) {}

    // Network & Wi-Fi
    try {
      final interfaces = await widget.bridge.getNetworkInterfaces();
      final wifi = await widget.bridge.getWifiNetworks();
      if (mounted) {
        setState(() {
          _networkInterfaces = interfaces;
          _wifiNetworks = wifi;
        });
      }
    } catch (_) {}

    // Bluetooth
    try {
      final bt = await widget.bridge.getBluetoothStatus();
      if (mounted) setState(() => _bluetoothStatus = bt);
    } catch (_) {}

    // Performance & Power
    try {
      final profile = await widget.bridge.loadPerformanceProfile();
      final power = await widget.bridge.getPowerStatus();
      final hw = await widget.bridge.getHardwareMetrics();
      if (mounted) {
        setState(() {
          _performanceProfile = profile;
          _powerStatus = power;
          _hardwareMetrics = hw;
        });
      }
    } catch (_) {}

    // Personalization
    try {
      final pers = await widget.bridge.getPersonalizationSettings();
      if (mounted) {
        setState(() => _personalization = pers);
        final parsedColor = _parseColorHex(pers.accentColor);
        cloudThemeNotifier.value = cloudThemeNotifier.value.copyWith(
          accentColor: parsedColor,
          themeMode: pers.theme,
          transparency: pers.transparencyEnabled,
          animations: pers.animationsEnabled,
        );
      }
    } catch (_) {}

    // WSL
    try {
      final distros = await widget.bridge.listWslDistros();
      if (mounted) setState(() => _wslDistros = distros);
    } catch (_) {}

    // Recovery & Diagnostics
    try {
      final rec = await widget.bridge.getRecoveryStatus();
      if (mounted) {
        setState(() {
          _recoveryStatus = rec;
        });
      }
    } catch (_) {}

    // Shell & Startup
    try {
      final st = await widget.bridge.getStartupStatus();
      final sh = await widget.bridge.getShellStatus();
      if (mounted) {
        setState(() {
          _startupStatus = st;
          _shellStatus = sh;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _revertTimer?.cancel();
    super.dispose();
  }

  void navigateTo(SettingsSection section) {
    setState(() => _activeSection = section);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CloudThemeConfig>(
      valueListenable: cloudThemeNotifier,
      builder: (context, themeConfig, _) {
        final isDark = themeConfig.isDark;
        final currentAccent = themeConfig.accentColor;
        return Container(
          color: isDark ? const Color(0xFF10141D) : const Color(0xFFF8FAFC),
          child: Row(
            children: <Widget>[
              _buildSidebar(isDark, currentAccent),
              VerticalDivider(
                width: 1,
                color: isDark ? CloudOSColors.border : const Color(0xFFE2E8F0),
              ),
              Expanded(
                child: _buildMainContent(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebar(bool isDark, Color currentAccent) {
    return Container(
      width: 230,
      color: isDark ? const Color(0xFF131822) : const Color(0xFFF1F5F9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDark ? CloudOSColors.border : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.settings_suggest_rounded, color: currentAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Configurações',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _buildGroupHeader('Sistema', isDark),
                  _buildNavItem(SettingsSection.display, isDark, currentAccent),
                  _buildNavItem(SettingsSection.sound, isDark, currentAccent),
                  _buildNavItem(SettingsSection.power, isDark, currentAccent),
                  _buildNavItem(SettingsSection.storage, isDark, currentAccent),
                  _buildNavItem(SettingsSection.performance, isDark, currentAccent),
                  _buildNavItem(SettingsSection.startup, isDark, currentAccent),

                  const SizedBox(height: 8),
                  _buildGroupHeader('CONECTIVIDADE', isDark),
                  _buildNavItem(SettingsSection.network, isDark, currentAccent),
                  _buildNavItem(SettingsSection.bluetooth, isDark, currentAccent),

                  const SizedBox(height: 8),
                  _buildGroupHeader('CLOUDOS', isDark),
                  _buildNavItem(SettingsSection.personalization, isDark, currentAccent),
                  _buildNavItem(SettingsSection.wsl, isDark, currentAccent),
                  _buildNavItem(SettingsSection.recovery, isDark, currentAccent),
                  _buildNavItem(SettingsSection.diagnostics, isDark, currentAccent),
                  _buildNavItem(SettingsSection.about, isDark, currentAccent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          color: isDark ? CloudOSColors.caption : const Color(0xFF64748B),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildNavItem(SettingsSection section, bool isDark, Color currentAccent) {
    final isSelected = _activeSection == section;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _activeSection = section),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7.5),
          decoration: BoxDecoration(
            color: isSelected
                ? currentAccent.withValues(alpha: isDark ? 0.22 : 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? currentAccent.withValues(alpha: isDark ? 0.4 : 0.5)
                  : Colors.transparent,
              width: 0.8,
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                section.icon,
                size: 17,
                color: isSelected
                    ? currentAccent
                    : (isDark ? CloudOSColors.caption : const Color(0xFF64748B)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  section.title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? (isDark ? Colors.white : currentAccent)
                        : (isDark ? CloudOSColors.secondary : const Color(0xFF475569)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return switch (_activeSection) {
      SettingsSection.overview => _buildOverviewSection(),
      SettingsSection.display => _buildDisplaySection(),
      SettingsSection.sound => _buildSoundSection(),
      SettingsSection.power => _buildPowerSection(),
      SettingsSection.storage => _buildStorageSection(),
      SettingsSection.performance => _buildPerformanceSection(),
      SettingsSection.startup => _buildStartupSection(),
      SettingsSection.network => _buildNetworkSection(),
      SettingsSection.bluetooth => _buildBluetoothSection(),
      SettingsSection.personalization => _buildPersonalizationSection(),
      SettingsSection.wsl => _buildWslSection(),
      SettingsSection.recovery => _buildRecoverySection(),
      SettingsSection.diagnostics => _buildDiagnosticsSection(),
      SettingsSection.about => _buildAboutSection(),
    };
  }

  // --- SECTIONS ---

  Widget _buildOverviewSection() {
    final resolutionText = _monitors.isNotEmpty && _selectedMonitorIndex < _monitors.length
        ? '${_monitors[_selectedMonitorIndex].width}x${_monitors[_selectedMonitorIndex].height} @ ${_monitors[_selectedMonitorIndex].frequency}Hz'
        : 'Display Principal Ativo';

    final soundText = _muted
        ? 'Silenciado'
        : 'Volume ${(_volume * 100).toInt()}%';

    final netText = widget.snapshot.networkAvailable
        ? (widget.snapshot.networkName.isNotEmpty ? widget.snapshot.networkName : 'Rede Conectada')
        : 'Conexão Indisponível';

    final powerText = widget.snapshot.batteryAvailable
        ? '${widget.snapshot.batteryPercent}% • ${_performanceProfile.label}'
        : 'Rede Elétrica • ${_performanceProfile.label}';

    final wslText = widget.snapshot.wslAvailable
        ? '${widget.snapshot.distros.length} distribuição(ões) ativa(s)'
        : 'WSL Desativado';

    final shellText = _shellStatus.status == ShellModeEnum.cloudosActive
        ? 'CloudOS Ativo'
        : 'Explorer Ativo (Gate 0 Seguro)';

    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        _buildSectionHeader(
          'Central de Configurações CloudOS',
          'Painel de controle unificado para vídeo, áudio, rede, subsistema Linux e preferências do sistema.',
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 580;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: <Widget>[
                _buildOverviewCard(
                  title: 'Tela & Resolução',
                  status: resolutionText,
                  icon: Icons.monitor_rounded,
                  color: const Color(0xFF38BDF8),
                  width: isWide ? (constraints.maxWidth - 14) / 2 : constraints.maxWidth,
                  onTap: () => setState(() => _activeSection = SettingsSection.display),
                ),
                _buildOverviewCard(
                  title: 'Áudio & Volume',
                  status: soundText,
                  icon: Icons.volume_up_rounded,
                  color: const Color(0xFF10B981),
                  width: isWide ? (constraints.maxWidth - 14) / 2 : constraints.maxWidth,
                  onTap: () => setState(() => _activeSection = SettingsSection.sound),
                ),
                _buildOverviewCard(
                  title: 'Rede & Internet',
                  status: netText,
                  icon: Icons.wifi_rounded,
                  color: const Color(0xFF6366F1),
                  width: isWide ? (constraints.maxWidth - 14) / 2 : constraints.maxWidth,
                  onTap: () => setState(() => _activeSection = SettingsSection.network),
                ),
                _buildOverviewCard(
                  title: 'Energia & Desempenho',
                  status: powerText,
                  icon: Icons.battery_charging_full_rounded,
                  color: const Color(0xFFF59E0B),
                  width: isWide ? (constraints.maxWidth - 14) / 2 : constraints.maxWidth,
                  onTap: () => setState(() => _activeSection = SettingsSection.power),
                ),
                _buildOverviewCard(
                  title: 'Linux (WSL2)',
                  status: wslText,
                  icon: Icons.terminal_rounded,
                  color: const Color(0xFFEC4899),
                  width: isWide ? (constraints.maxWidth - 14) / 2 : constraints.maxWidth,
                  onTap: () => setState(() => _activeSection = SettingsSection.wsl),
                ),
                _buildOverviewCard(
                  title: 'Shell & Segurança',
                  status: shellText,
                  icon: Icons.shield_rounded,
                  color: const Color(0xFF14B8A6),
                  width: isWide ? (constraints.maxWidth - 14) / 2 : constraints.maxWidth,
                  onTap: () => setState(() => _activeSection = SettingsSection.startup),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        _buildCard(
          title: 'Ações Rápidas de Sistema',
          icon: Icons.tune_rounded,
          child: Column(
            children: <Widget>[
              InkWell(
                onTap: () => setState(() => _activeSection = SettingsSection.personalization),
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.palette_rounded, color: CloudOSColors.accent, size: 22),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('Personalizar Tema e Cores', style: TextStyle(color: CloudOSColors.text, fontSize: 13, fontWeight: FontWeight.w600)),
                            SizedBox(height: 2),
                            Text('Alternar modo escuro/claro e cores de destaque', style: TextStyle(color: CloudOSColors.caption, fontSize: 11)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: CloudOSColors.caption, size: 18),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              InkWell(
                onTap: () => setState(() => _activeSection = SettingsSection.about),
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.info_outline_rounded, color: CloudOSColors.secondary, size: 22),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('Sobre o CloudOS & Exportar Configurações', style: TextStyle(color: CloudOSColors.text, fontSize: 13, fontWeight: FontWeight.w600)),
                            SizedBox(height: 2),
                            Text('Informações de versão, arquitetura e backup de preferências', style: TextStyle(color: CloudOSColors.caption, fontSize: 11)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: CloudOSColors.caption, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewCard({
    required String title,
    required String status,
    required IconData icon,
    required Color color,
    required double width,
    required VoidCallback onTap,
  }) {
    final isDark = cloudThemeNotifier.value.isDark;
    return SizedBox(
      width: width,
      child: Material(
        color: isDark ? const Color(0xFF16202E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? CloudOSColors.border : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        status,
                        style: TextStyle(
                          color: isDark ? CloudOSColors.secondary : const Color(0xFF64748B),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 20, color: CloudOSColors.caption),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDisplaySection() {
    final monitor = _monitors.isNotEmpty && _selectedMonitorIndex < _monitors.length
        ? _monitors[_selectedMonitorIndex]
        : (_monitors.isNotEmpty ? _monitors.first : null);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        _buildSectionHeader('Tela & Monitores', 'Resolução, taxa de atualização, DPI e orientação dos monitores.'),
        const SizedBox(height: 16),
        if (_monitors.length > 1) ...[
          _buildCard(
            title: 'Selecionar Monitor (${_monitors.length} detectados)',
            icon: Icons.monitor_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Escolha o monitor que deseja configurar:',
                  style: TextStyle(color: CloudOSColors.secondary, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(_monitors.length, (idx) {
                    final m = _monitors[idx];
                    final isSel = idx == _selectedMonitorIndex;
                    return ChoiceChip(
                      label: Text('${m.friendlyName} (${m.deviceName})'),
                      selected: isSel,
                      onSelected: (selected) {
                        if (selected) _selectMonitor(idx);
                      },
                      selectedColor: CloudOSColors.accent,
                      labelStyle: TextStyle(
                        color: isSel ? Colors.white : CloudOSColors.secondary,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                      ),
                      backgroundColor: const Color(0xFF1B2333),
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (monitor != null) ...[
          _buildCard(
            title: monitor.isPrimary ? 'Monitor Principal' : 'Monitor Secundário',
            icon: Icons.desktop_windows_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _buildDetailRow('Dispositivo', monitor.deviceName),
                _buildDetailRow('Nome do Monitor', monitor.friendlyName),
                _buildDetailRow('Resolução Atual', '${monitor.width} x ${monitor.height}'),
                _buildDetailRow('Frequência Atual', '${monitor.frequency} Hz'),
                _buildDetailRow('DPI / Escala', '${monitor.dpiX} DPI (${(monitor.scale * 100).round()}%)'),
                _buildDetailRow('Monitor Primário', monitor.isPrimary ? 'Sim' : 'Não'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildCard(
            title: 'Configurações de Resolução',
            icon: Icons.tune_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Selecione uma resolução suportada para aplicar:',
                  style: TextStyle(color: CloudOSColors.secondary, fontSize: 12),
                ),
                const SizedBox(height: 10),
                if (_displayModes.isNotEmpty) ...[
                  DropdownButtonFormField<CloudDisplayMode>(
                    key: ValueKey(_selectedMode),
                    initialValue: _selectedMode,
                    dropdownColor: const Color(0xFF1B2333),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF141C2B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: CloudOSColors.border),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    items: _displayModes.map((m) {
                      return DropdownMenuItem<CloudDisplayMode>(
                        value: m,
                        child: Text('${m.width} x ${m.height} (${m.frequency} Hz)'),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedMode = val),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      ElevatedButton.icon(
                        icon: const Icon(Icons.check_rounded, size: 16),
                        label: const Text('Aplicar Resolução'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CloudOSColors.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _displayLoading ? null : _applyDisplayMode,
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.restore_rounded, size: 16),
                        label: const Text('Restaurar Padrão'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: CloudOSColors.caption,
                          side: const BorderSide(color: CloudOSColors.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () async {
                          await widget.bridge.restoreDisplayMode();
                          _loadInitialData();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(color: CloudOSColors.border),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.settings_display_rounded, size: 16),
                          label: const Text('Abrir Configurações de Vídeo do Windows'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: cloudThemeNotifier.value.accentColor,
                            side: BorderSide(color: cloudThemeNotifier.value.accentColor),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () => widget.bridge.openWindowsSettings('ms-settings:display'),
                        ),
                      ),
                    ],
                  ),
                ] else
                  const Text('Nenhum modo de vídeo enumerado.', style: TextStyle(color: CloudOSColors.caption)),
              ],
            ),
          ),
        ] else
          const Center(child: Text('Nenhum monitor detectado pelo subsistema Win32.', style: TextStyle(color: CloudOSColors.caption))),
      ],
    );
  }

  Future<void> _applyDisplayMode() async {
    if (_selectedMode == null || _monitors.isEmpty) return;
    final curMon = _monitors.length > _selectedMonitorIndex
        ? _monitors[_selectedMonitorIndex]
        : _monitors.first;
    setState(() => _displayLoading = true);

    final success = await widget.bridge.setDisplayMode(
      deviceName: curMon.deviceName,
      width: _selectedMode!.width,
      height: _selectedMode!.height,
      frequency: _selectedMode!.frequency,
      orientation: _selectedMode!.orientation,
    );

    setState(() => _displayLoading = false);

    if (success && mounted) {
      _showRevertConfirmationDialog();
    } else if (mounted) {
      final isDark = cloudThemeNotifier.value.isDark;
      final accent = cloudThemeNotifier.value.accentColor;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: isDark ? const Color(0xFF1B2333) : Colors.white,
          content: Text(
            'O driver do Windows não permitiu alterar para ${_selectedMode!.width}x${_selectedMode!.height} diretamente via API neste monitor.',
            style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A)),
          ),
          action: SnackBarAction(
            label: 'Abrir no Windows',
            textColor: accent,
            onPressed: () => widget.bridge.openWindowsSettings('ms-settings:display'),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  void _showRevertConfirmationDialog() {
    _revertCountdown = 15;
    _revertTimer?.cancel();

    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            _revertTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
              if (_revertCountdown <= 1) {
                timer.cancel();
                widget.bridge.restoreDisplayMode();
                if (Navigator.canPop(ctx)) Navigator.pop(ctx, false);
              } else {
                setDialogState(() => _revertCountdown--);
              }
            });

            return AlertDialog(
              backgroundColor: const Color(0xFF131A27),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: CloudOSColors.borderStrong),
              ),
              title: const Text('Manter estas configurações de exibição?', style: TextStyle(color: Colors.white, fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'A resolução foi alterada com sucesso.\nRevertendo automaticamente para as configurações anteriores em $_revertCountdown segundos.',
                    style: const TextStyle(color: CloudOSColors.secondary, fontSize: 13),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    _revertTimer?.cancel();
                    widget.bridge.restoreDisplayMode();
                    Navigator.pop(ctx, false);
                  },
                  child: const Text('Reverter Agora', style: TextStyle(color: Colors.redAccent)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CloudOSColors.accent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    _revertTimer?.cancel();
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('Manter Alterações'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSoundSection() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        _buildSectionHeader('Som & Áudio', 'Dispositivos de reprodução e gravação via Core Audio APIs.'),
        const SizedBox(height: 16),
        _buildCard(
          title: 'Saída de Áudio',
          icon: Icons.speaker_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildDetailRow('Dispositivo de Saída', _audioState.defaultDevice.isNotEmpty ? _audioState.defaultDevice : 'Alto-falantes Padrão'),
              _buildDetailRow('Status', _audioState.available ? 'Ativo e Operacional' : 'Indisponível'),
              const SizedBox(height: 14),
              const Text('Volume Principal', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  IconButton(
                    icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: _muted ? Colors.redAccent : CloudOSColors.accent),
                    onPressed: () async {
                      final newMuted = !_muted;
                      setState(() => _muted = newMuted);
                      await widget.bridge.setMasterMute(newMuted);
                    },
                  ),
                  Expanded(
                    child: Slider(
                      value: _volume,
                      min: 0.0,
                      max: 1.0,
                      activeColor: CloudOSColors.accent,
                      onChanged: (v) {
                        setState(() => _volume = v);
                        widget.bridge.setMasterVolume(v);
                      },
                    ),
                  ),
                  Text('${(_volume * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(color: CloudOSColors.border),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.settings_voice_rounded, size: 16),
                      label: const Text('Abrir Configurações de Som do Windows'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: CloudOSColors.accent,
                        side: const BorderSide(color: CloudOSColors.accent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => widget.bridge.openWindowsSettings('ms-settings:sound'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildCard(
          title: 'Dispositivos de Áudio Conectados',
          icon: Icons.mic_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _audioState.endpoints.isNotEmpty
                ? _audioState.endpoints.map((ep) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: <Widget>[
                          Icon(ep.isInput ? Icons.mic_rounded : Icons.speaker_rounded, size: 16, color: CloudOSColors.caption),
                          const SizedBox(width: 8),
                          Expanded(child: Text(ep.name, style: const TextStyle(color: Colors.white, fontSize: 12.5))),
                          if (ep.isDefault)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: CloudOSColors.accentSoft, borderRadius: BorderRadius.circular(4)),
                              child: const Text('Padrão', style: TextStyle(color: CloudOSColors.accent, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                    );
                  }).toList()
                : [const Text('Nenhum endpoint de áudio reportado.', style: TextStyle(color: CloudOSColors.caption))],
          ),
        ),
      ],
    );
  }

  Widget _buildPowerSection() {
    final hasBattery = _powerStatus.batteryPresent || widget.snapshot.batteryAvailable;
    final pct = _powerStatus.batteryPercent >= 0 ? _powerStatus.batteryPercent : widget.snapshot.batteryPercent;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        _buildSectionHeader('Energia & Bateria', 'Status da alimentação CA, carga da bateria e modo de energia.'),
        const SizedBox(height: 16),
        _buildCard(
          title: 'Status de Alimentação',
          icon: Icons.power_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildDetailRow('Fonte de Alimentação', _powerStatus.acOnline ? 'Conectado à Tomada (Rede CA)' : 'Alimentação por Bateria'),
              _buildDetailRow('Presença de Bateria', hasBattery ? 'Detectada' : 'Nenhuma bateria presente (Desktop fixo)'),
              if (hasBattery) ...[
                _buildDetailRow('Nível da Bateria', '$pct%'),
                _buildDetailRow('Estado de Carregamento', _powerStatus.isCharging ? 'Carregando' : 'Em descarga / Totalmente Carregada'),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (pct / 100.0).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: const Color(0xFF222C40),
                    valueColor: AlwaysStoppedAnimation<Color>(pct < 20 ? Colors.redAccent : const Color(0xFF10B981)),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const Divider(color: CloudOSColors.border),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.battery_saver_rounded, size: 16),
                      label: const Text('Abrir Opções de Energia do Windows'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: CloudOSColors.accent,
                        side: const BorderSide(color: CloudOSColors.accent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => widget.bridge.openWindowsSettings('ms-settings:powersleep'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildCard(
          title: 'Perfil Ativo de Performance',
          icon: Icons.speed_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildDetailRow('Perfil Atual', _performanceProfile.profile.toUpperCase()),
              _buildDetailRow('Modo de Recursos', _performanceProfile.isEconomy ? 'Economia de Energia' : 'Equilibrado / Alto Desempenho'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStorageSection() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        _buildSectionHeader('Armazenamento', 'Discos locais, volumes montados e partições do subsistema WSL.'),
        const SizedBox(height: 16),
        _buildCard(
          title: 'Configurações de Armazenamento do Windows',
          icon: Icons.cleaning_services_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Gerencie o Sensor de Armazenamento, arquivos temporários e recomendações de limpeza do sistema host.',
                style: TextStyle(color: CloudOSColors.caption, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new_rounded, size: 15),
                label: const Text('Abrir Sensor de Armazenamento do Windows'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: CloudOSColors.accent,
                  side: const BorderSide(color: CloudOSColors.accent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => widget.bridge.openWindowsSettings('ms-settings:storagesense'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_storageDrives.isNotEmpty)
          for (final drive in _storageDrives)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              child: _buildCard(
                title: '${drive.volumeName.isNotEmpty ? drive.volumeName : "Disco Local"} (${drive.driveLetter})',
                icon: drive.isRemovable ? Icons.usb_rounded : Icons.storage_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _buildDetailRow('Sistema de Arquivos', drive.fileSystem),
                    _buildDetailRow('Tipo de Unidade', drive.isRemovable ? 'Armazenamento Removível' : 'Disco Rígido Fixo'),
                    _buildDetailRow('Capacidade Total', '${(drive.totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB'),
                    _buildDetailRow('Espaço Livre', '${(drive.freeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB livre'),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: drive.totalBytes > 0 ? (1.0 - (drive.freeBytes / drive.totalBytes)).clamp(0.0, 1.0) : 0.0,
                        minHeight: 6,
                        backgroundColor: const Color(0xFF222C40),
                        valueColor: const AlwaysStoppedAnimation<Color>(CloudOSColors.accent),
                      ),
                    ),
                  ],
                ),
              ),
            )
        else
          _buildCard(
            title: 'Disco do Sistema (C:)',
            icon: Icons.storage_rounded,
            child: const Text('Consultando armazenamento local do host Windows...', style: TextStyle(color: CloudOSColors.secondary)),
          ),
      ],
    );
  }

  Widget _buildPerformanceSection() {
    final hw = _hardwareMetrics;
    final prof = _performanceProfile;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        _buildSectionHeader('Desempenho & Recursos', 'Ajuste de perfis operacionais e métricas de hardware em tempo real.'),
        const SizedBox(height: 16),
        _buildCard(
          title: 'Perfil Operacional do CloudOS',
          icon: Icons.tune_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Selecione o perfil desejado:', style: TextStyle(color: CloudOSColors.secondary, fontSize: 12)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  _buildProfileButton('auto', 'Automático', Icons.auto_awesome_rounded),
                  _buildProfileButton('economy', 'Economia', Icons.eco_rounded),
                  _buildProfileButton('balanced', 'Equilibrado', Icons.balance_rounded),
                  _buildProfileButton('performance', 'Desempenho', Icons.bolt_rounded),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildCard(
          title: 'Métricas de Hardware em Tempo Real',
          icon: Icons.memory_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildDetailRow('Núcleos de CPU', '${prof.cpuCores} núcleos lógicos'),
              _buildDetailRow('Memória RAM Total', '${prof.totalRamMb} MB'),
              _buildDetailRow('Memória RAM Livre', '${prof.freeRamMb} MB'),
              _buildDetailRow('Carga de Memória', '${prof.memoryLoadPercent}%'),
              if (hw != null) ...[
                _buildDetailRow('Perfil de Recursos', hw.currentProfile.toUpperCase()),
                _buildDetailRow('Hardware Econômico', hw.isLowEndHardware ? 'Sim' : 'Não'),
              ],
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (prof.memoryLoadPercent / 100.0).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: const Color(0xFF222C40),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    prof.memoryLoadPercent > 85 ? Colors.redAccent : CloudOSColors.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfileButton(String id, String label, IconData icon) {
    final isSelected = _performanceProfile.profile.toLowerCase() == id;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final ok = await widget.bridge.setPerformanceProfile(id);
        if (ok) {
          final updated = await widget.bridge.loadPerformanceProfile();
          if (mounted) setState(() => _performanceProfile = updated);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? CloudOSColors.accent : const Color(0xFF1B2333),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? Colors.white : CloudOSColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 16, color: isSelected ? Colors.white : CloudOSColors.caption),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: isSelected ? Colors.white : CloudOSColors.text, fontWeight: FontWeight.w600, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkSection() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        _buildSectionHeader('Rede & Wi-Fi', 'Adaptadores de rede, conectividade IP e pontos de acesso sem fio.'),
        const SizedBox(height: 16),
        _buildCard(
          title: 'Conexão Atual',
          icon: Icons.wifi_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildDetailRow('Status Geral', widget.snapshot.networkAvailable ? 'Conectado à Internet' : 'Desconectado'),
              _buildDetailRow('Nome da Rede (SSID)', widget.snapshot.networkName),
              if (_networkInterfaces.isNotEmpty) ...[
                _buildDetailRow('Adaptador Ativo', _networkInterfaces.first.name),
                _buildDetailRow('Endereço IPv4', _networkInterfaces.first.ipv4),
                _buildDetailRow('Gateway Padrão', _networkInterfaces.first.gateway),
                _buildDetailRow('Servidor DNS', _networkInterfaces.first.dns),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildCard(
          title: 'Redes Wi-Fi Disponíveis',
          icon: Icons.network_wifi_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (_wifiNetworks.isNotEmpty)
                for (final net in _wifiNetworks)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF18202E),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.wifi_rounded, color: CloudOSColors.accent, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(net.ssid, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                        ),
                        Text('${net.signalQuality}%', style: const TextStyle(color: CloudOSColors.caption, fontSize: 11)),
                      ],
                    ),
                  )
              else
                const Text('Nenhuma rede Wi-Fi visível ou adaptador sem fio ausente.', style: TextStyle(color: CloudOSColors.caption)),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                    child: const Text('PARTIAL', style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Conexão a redes protegidas sem perfil salvo requer credencial.', style: TextStyle(color: CloudOSColors.caption, fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.settings_ethernet_rounded, size: 16),
                label: const Text('Abrir Configurações de Rede do Windows'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: CloudOSColors.accent,
                  side: const BorderSide(color: CloudOSColors.accent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => widget.bridge.openWindowsSettings('ms-settings:network'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBluetoothSection() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        _buildSectionHeader('Bluetooth & Dispositivos', 'Adaptador Bluetooth nativo e periféricos pareados.'),
        const SizedBox(height: 16),
        _buildCard(
          title: 'Adaptador Bluetooth',
          icon: Icons.bluetooth_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildDetailRow('Presença de Rádio', _bluetoothStatus.available ? 'Disponível' : 'Não detectado'),
              _buildDetailRow('Estado', _bluetoothStatus.enabled ? 'Ativado' : 'Desativado'),
              _buildDetailRow('Nome do Rádio', _bluetoothStatus.radioName.isNotEmpty ? _bluetoothStatus.radioName : 'Bluetooth Adapter'),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                    child: const Text('PARTIAL', style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Pareamento de novos periféricos depende do handshake do host.', style: TextStyle(color: CloudOSColors.caption, fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(color: CloudOSColors.border),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.bluetooth_searching_rounded, size: 16),
                      label: const Text('Abrir Configurações de Bluetooth do Windows'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: CloudOSColors.accent,
                        side: const BorderSide(color: CloudOSColors.accent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => widget.bridge.openWindowsSettings('ms-settings:bluetooth'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPersonalizationSection() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        _buildSectionHeader('Personalização', 'Aparência, paleta de cores, tema e efeitos visuais do CloudOS.'),
        const SizedBox(height: 16),
        _buildCard(
          title: 'Tema do Sistema',
          icon: Icons.dark_mode_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildDetailRow('Tema Ativo', _personalization.theme.toUpperCase()),
              _buildDetailRow('Cor de Destaque', _personalization.accentColor.toUpperCase()),
              _buildDetailRow('Transparência / Vidro', _personalization.transparencyEnabled ? 'Ativada' : 'Desativada'),
              _buildDetailRow('Animações de Janela', _personalization.animationsEnabled ? 'Ativadas' : 'Desativadas'),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                children: <Widget>[
                  _buildThemeOption('dark', 'Modo Escuro (Dark)', Icons.nightlight_rounded),
                  _buildThemeOption('light', 'Modo Claro (Light)', Icons.wb_sunny_rounded),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildCard(
          title: 'Paleta de Cores do Sistema (Flutter)',
          icon: Icons.palette_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Selecione uma cor para personalizar instantaneamente botões, destaques e a barra de tarefas do CloudOS:',
                style: TextStyle(color: CloudOSColors.secondary, fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  _buildColorSwatch('#4C9AFF', 'Azul CloudOS', const Color(0xFF4C9AFF)),
                  _buildColorSwatch('#2563EB', 'Azul Royal', const Color(0xFF2563EB)),
                  _buildColorSwatch('#8B5CF6', 'Roxo Cyber', const Color(0xFF8B5CF6)),
                  _buildColorSwatch('#10B981', 'Verde Esmeralda', const Color(0xFF10B981)),
                  _buildColorSwatch('#06B6D4', 'Ciano Elétrico', const Color(0xFF06B6D4)),
                  _buildColorSwatch('#F59E0B', 'Âmbar Dourado', const Color(0xFFF59E0B)),
                  _buildColorSwatch('#F97316', 'Laranja Sunset', const Color(0xFFF97316)),
                  _buildColorSwatch('#EC4899', 'Rosa Neon', const Color(0xFFEC4899)),
                  _buildColorSwatch('#EF4444', 'Vermelho Carmim', const Color(0xFFEF4444)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildColorSwatch(String hex, String label, Color color) {
    final currentHex = _personalization.accentColor.toUpperCase();
    final isSelected = currentHex == hex.toUpperCase();
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final updated = CloudPersonalizationSettings(
            wallpaperPath: _personalization.wallpaperPath,
            theme: _personalization.theme,
            accentColor: hex,
            transparencyEnabled: _personalization.transparencyEnabled,
            animationsEnabled: _personalization.animationsEnabled,
            taskbarAlignment: _personalization.taskbarAlignment,
          );
          cloudThemeNotifier.value = cloudThemeNotifier.value.copyWith(accentColor: color);
          final ok = await widget.bridge.setPersonalizationSettings(updated);
          if (ok && mounted) {
            setState(() => _personalization = updated);
            final isDark = cloudThemeNotifier.value.isDark;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: isDark ? const Color(0xFF18202E) : Colors.white,
                content: Text(
                  'Cor de destaque alterada para $label ($hex)!',
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? Colors.white : Colors.white24,
              width: isSelected ? 2.5 : 1.0,
            ),
            boxShadow: isSelected
                ? <BoxShadow>[
                    BoxShadow(
                      color: color.withValues(alpha: 0.55),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: isSelected
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
              : null,
        ),
      ),
    );
  }

  Color _parseColorHex(String hex) {
    final clean = hex.replaceAll('#', '').trim();
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    } else if (clean.length == 8) {
      return Color(int.parse(clean, radix: 16));
    }
    return const Color(0xFF4C9AFF);
  }

  Widget _buildThemeOption(String mode, String label, IconData icon) {
    final isDark = cloudThemeNotifier.value.isDark;
    final currentAccent = cloudThemeNotifier.value.accentColor;
    final isSel = _personalization.theme.toLowerCase() == mode;
    return OutlinedButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: isSel
            ? currentAccent
            : (isDark ? Colors.white70 : const Color(0xFF334155)),
        backgroundColor: isSel
            ? currentAccent.withValues(alpha: isDark ? 0.2 : 0.1)
            : (isDark ? Colors.transparent : const Color(0xFFF1F5F9)),
        side: BorderSide(
          color: isSel
              ? currentAccent
              : (isDark ? CloudOSColors.border : const Color(0xFFCBD5E1)),
          width: isSel ? 1.5 : 1.0,
        ),
      ),
      onPressed: () async {
        final updated = CloudPersonalizationSettings(
          wallpaperPath: _personalization.wallpaperPath,
          theme: mode,
          accentColor: _personalization.accentColor,
          transparencyEnabled: _personalization.transparencyEnabled,
          animationsEnabled: _personalization.animationsEnabled,
          taskbarAlignment: _personalization.taskbarAlignment,
        );
        cloudThemeNotifier.value = cloudThemeNotifier.value.copyWith(themeMode: mode);
        final ok = await widget.bridge.setPersonalizationSettings(updated);
        if (ok && mounted) setState(() => _personalization = updated);
      },
    );
  }

  Widget _buildWslSection() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        _buildSectionHeader('Subsistema Linux (WSL2)', 'Distribuições Linux registradas e integração WSLg.'),
        const SizedBox(height: 16),
        _buildCard(
          title: 'Status do Subsistema',
          icon: Icons.terminal_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildDetailRow('Suporte WSL', widget.snapshot.wslAvailable ? 'Ativo e Operacional' : 'Indisponível'),
              _buildDetailRow('Versão do Subsistema', 'WSL 2 (Hyper-V Container)'),
              _buildDetailRow('Suporte WSLg (Aplicações Gráficas)', 'Habilitado'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildCard(
          title: 'Solução de Problemas & Manutenção WSL',
          icon: Icons.build_circle_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Se o terminal WSL parar de responder ou travar com tela preta, o processo de virtualização vmmemWSL do Windows pode ter entrado em deadlock.',
                style: TextStyle(color: CloudOSColors.secondary, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1522),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: CloudOSColors.border),
                ),
                child: const Row(
                  children: <Widget>[
                    Icon(Icons.terminal_rounded, size: 16, color: Colors.amber),
                    SizedBox(width: 8),
                    Expanded(
                      child: SelectableText(
                        'wsl --shutdown',
                        style: TextStyle(fontFamily: 'Consolas', color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: <Widget>[
                  ElevatedButton.icon(
                    icon: const Icon(Icons.copy_rounded, size: 15),
                    label: const Text('Copiar Comando'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CloudOSColors.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      widget.bridge.setClipboardText('wsl --shutdown');
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Comando "wsl --shutdown" copiado! Cole no PowerShell Admin.')),
                      );
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.restart_alt_rounded, size: 15),
                    label: const Text('Executar Shutdown do WSL'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orangeAccent,
                      side: const BorderSide(color: Colors.orangeAccent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () async {
                      final ok = await widget.bridge.restartWsl();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(ok
                                ? 'Comando wsl --shutdown enviado ao Windows. Reinicie a aba do terminal WSL.'
                                : 'Não foi possível executar wsl --shutdown. Execute como Administrador.'),
                          ),
                        );
                        _loadInitialData();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildCard(
          title: 'Distribuições Registradas',
          icon: Icons.list_alt_rounded,
          child: Column(
            children: _wslDistros.isNotEmpty
                ? _wslDistros.map((d) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF18202E),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: CloudOSColors.border),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.terminal_rounded, color: CloudOSColors.linux, size: 22),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(d.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              Text('Versão ${d.version} • ${d.isRunning ? "Em Execução" : "Parada"}', style: const TextStyle(color: CloudOSColors.caption, fontSize: 11)),
                            ],
                          ),
                          const Spacer(),
                          TextButton.icon(
                            icon: const Icon(Icons.open_in_new_rounded, size: 14),
                            label: const Text('Terminal'),
                            style: TextButton.styleFrom(foregroundColor: CloudOSColors.accent),
                            onPressed: () => widget.bridge.launchApp('wsl:${d.name}:terminal'),
                          ),
                        ],
                      ),
                    );
                  }).toList()
                : [const Text('Nenhuma distribuição WSL registrada.', style: TextStyle(color: CloudOSColors.caption))],
          ),
        ),
      ],
    );
  }

  Widget _buildRecoverySection() {
    final rec = _recoveryStatus;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        _buildSectionHeader('Recuperação & Safe Mode', 'Monitoramento do Supervisor, integridade do Broker e modos de segurança.'),
        const SizedBox(height: 16),
        _buildCard(
          title: 'Integridade dos Serviços',
          icon: Icons.health_and_safety_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildDetailRow('Supervisor Watchdog', 'CloudOS.Supervisor.exe V11 (Operacional)'),
              _buildDetailRow('System Broker', 'CloudOS.SystemBroker.exe V21 (Conectado)'),
              if (rec != null) ...[
                _buildDetailRow('Contador de Falhas Anteriores', '${rec.failureCount} falhas registradas'),
                _buildDetailRow('Desligamento Incorreto Anterior', rec.previousUnclean ? 'Detectado' : 'Nenhum (Desligamento limpo)'),
                _buildDetailRow('Modo de Segurança (Safe Mode)', rec.isSafeMode ? 'ATIVO' : 'Inativo (Operação normal)'),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildCard(
          title: 'Ações de Recuperação',
          icon: Icons.restore_page_rounded,
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            children: <Widget>[
              ElevatedButton.icon(
                icon: const Icon(Icons.security_rounded, size: 16),
                label: const Text('Entrar em Safe Mode'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black87),
                onPressed: () async {
                  await widget.bridge.enterSafeMode();
                  _loadInitialData();
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Reiniciar Shell'),
                style: OutlinedButton.styleFrom(foregroundColor: CloudOSColors.accent, side: const BorderSide(color: CloudOSColors.border)),
                onPressed: () => _loadInitialData(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDiagnosticsSection() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        _buildSectionHeader('Diagnósticos do Sistema', 'Versões, SHAs, métricas nativas e exportação sanitizada.'),
        const SizedBox(height: 16),
        _buildCard(
          title: 'Identificação & Versões',
          icon: Icons.code_rounded,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const _DetailRow(label: 'CloudOS Versão', value: '${CloudOSVersion.productVersion} (${CloudOSVersion.releaseName})'),
              const _DetailRow(label: 'Git Commit SHA', value: '${CloudOSVersion.gitSha} (RC1.1 Release Engineering)'),
              const _DetailRow(label: 'Protocolo IPC Broker', value: 'Named Pipe v21 (Fail-Closed DACL)'),
              const _DetailRow(label: 'Supervisor Protocol', value: 'V11 Watchdog Active'),
              const _DetailRow(label: 'Flutter Embedder', value: 'Flutter 3.x Windows Runner'),
              const _DetailRow(label: 'ConPTY Engine', value: 'Windows Pseudoconsole API'),
              const _DetailRow(label: 'WebView2 Integration', value: 'Microsoft Edge Evergreen Runtime'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildCard(
          title: 'Recursos em Tempo Real',
          icon: Icons.analytics_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildDetailRow('RAM Carregamento', '${_performanceProfile.memoryLoadPercent}%'),
              _buildDetailRow('Núcleos Detectados', '${_performanceProfile.cpuCores} cores'),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  ElevatedButton.icon(
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copiar Diagnóstico Sanitizado'),
                    style: ElevatedButton.styleFrom(backgroundColor: CloudOSColors.accent, foregroundColor: Colors.white),
                    onPressed: _copySanitizedDiagnostics,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _copySanitizedDiagnostics() {
    final report = '''
CloudOS Diagnostics Report (Sanitized)
--------------------------------------
Timestamp: ${DateTime.now().toIso8601String()}
Version: ${CloudOSVersion.productVersion} (${CloudOSVersion.releaseName})
Git SHA: ${CloudOSVersion.gitSha}
Broker IPC: NamedPipe v21 (DACL protected)
Supervisor: V11 Active
Performance Profile: ${_performanceProfile.profile}
CPU Cores: ${_performanceProfile.cpuCores}
RAM: ${_performanceProfile.totalRamMb} MB (${_performanceProfile.memoryLoadPercent}% used)
Monitors: ${_monitors.length}
Audio Output: ${_audioState.defaultDevice}
Network Available: ${widget.snapshot.networkAvailable}
WSL Available: ${widget.snapshot.wslAvailable}
Safe Mode: ${_recoveryStatus?.isSafeMode ?? false}
[Note: Tokens, passwords and credentials strictly excluded]
''';
    widget.bridge.setClipboardText(report);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Relatório sanitizado copiado para a área de transferência!')),
    );
  }

  Widget _buildAboutSection() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: CloudOSColors.accentSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: CloudOSColors.accent, width: 1.5),
              ),
              child: const Icon(Icons.cloud_done_rounded, color: CloudOSColors.accent, size: 32),
            ),
            const SizedBox(width: 18),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('CloudOS Desktop', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                Text('Versão ${CloudOSVersion.productVersion} • ${CloudOSVersion.releaseName} (Build ${CloudOSVersion.buildNumber})', style: TextStyle(fontSize: 12.5, color: CloudOSColors.caption)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildCard(
          title: 'Preferências e Backup do Usuário',
          icon: Icons.settings_backup_restore_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'O CloudOS armazena suas configurações personalizadas (posições de ícones, tema, apps fixados e histórico) de forma isolada, sem alterar o Registro global do Windows.',
                style: TextStyle(color: CloudOSColors.secondary, fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: <Widget>[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.file_download_outlined, size: 16),
                    label: const Text('Exportar Configurações (JSON)'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: CloudOSColors.accent,
                      side: const BorderSide(color: CloudOSColors.accent),
                    ),
                    onPressed: () async {
                      final prefs = await CloudOSPreferences.load();
                      final jsonString = prefs.exportJson();
                      await widget.bridge.setClipboardText(jsonString);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Configurações exportadas e copiadas para a Área de Transferência com sucesso!',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: const Text('Redefinir Configurações'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: CloudOSColors.danger,
                      side: const BorderSide(color: CloudOSColors.danger),
                    ),
                    onPressed: _confirmResetPreferences,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildCard(
          title: 'Arquitetura e Princípios de Design',
          icon: Icons.architecture_rounded,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('• FLUTTER DESENHA: Apresentação única e responsiva.', style: TextStyle(color: Colors.white, fontSize: 12.5)),
              SizedBox(height: 4),
              Text('• C++ CONTROLA: Runtime e hospedeiro nativo Win32.', style: TextStyle(color: Colors.white, fontSize: 12.5)),
              SizedBox(height: 4),
              Text('• BROKER CONECTA: Named Pipe IPC v21 seguro.', style: TextStyle(color: Colors.white, fontSize: 12.5)),
              SizedBox(height: 4),
              Text('• WINDOWS FORNECE AS APIs: Sem substituição destrutiva do shell.', style: TextStyle(color: Colors.white, fontSize: 12.5)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildCard(
          title: 'Licença e Conformidade',
          icon: Icons.verified_user_rounded,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('CloudOS Provedor de Shell Autônomo para Windows.', style: TextStyle(color: Colors.white, fontSize: 12)),
              SizedBox(height: 4),
              Text('Explorer.exe e Winlogon preservados como fallbacks invioláveis de segurança.', style: TextStyle(color: CloudOSColors.caption, fontSize: 11.5)),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmResetPreferences() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16202E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: CloudOSColors.danger),
        ),
        title: const Row(
          children: <Widget>[
            Icon(Icons.warning_amber_rounded, color: CloudOSColors.danger, size: 24),
            SizedBox(width: 8),
            Text('Redefinir Configurações', style: TextStyle(color: CloudOSColors.text, fontSize: 16)),
          ],
        ),
        content: const Text(
          'Deseja redefinir todas as preferências do CloudOS para os padrões de fábrica?\n\nIsso restaurará os ícones da Área de Trabalho, tema visual e aplicativos fixados ao padrão inicial.\n\nSeus arquivos pessoais e o sistema Windows NÃO serão afetados.',
          style: TextStyle(color: CloudOSColors.secondary, fontSize: 13),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: CloudOSColors.caption)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CloudOSColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar Redefinição', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final prefs = await CloudOSPreferences.load();
      await prefs.resetToDefaults();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Preferências do CloudOS restauradas para os padrões de fábrica!',
            ),
          ),
        );
        setState(() {});
      }
    }
  }

  Widget _buildStartupSection() {
    final isDark = cloudThemeNotifier.value.isDark;
    final accent = cloudThemeNotifier.value.accentColor;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        _buildSectionHeader(
          'Shell do Sistema & Inicialização',
          'Controle de Shell Replacement, modo Canary de validação, recuperação rápida do Explorer e inicialização automática.',
        ),
        const SizedBox(height: 20),

        // CARD 1: MODO DE SHELL DO WINDOWS
        _buildCard(
          title: 'Modo de Shell do Windows',
          icon: Icons.dashboard_customize_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Status Atual do Shell:',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? CloudOSColors.caption : const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _shellStatus.status == ShellModeEnum.cloudosActive
                              ? const Color(0xFF16A34A).withValues(alpha: 0.15)
                              : (_shellStatus.status == ShellModeEnum.cloudosCanary
                                  ? const Color(0xFFEAB308).withValues(alpha: 0.15)
                                  : const Color(0xFF3B82F6).withValues(alpha: 0.15)),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _shellStatus.status == ShellModeEnum.cloudosActive
                                ? const Color(0xFF16A34A)
                                : (_shellStatus.status == ShellModeEnum.cloudosCanary
                                    ? const Color(0xFFEAB308)
                                    : const Color(0xFF3B82F6)),
                          ),
                        ),
                        child: Text(
                          _shellStatus.status.displayName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _shellStatus.status == ShellModeEnum.cloudosActive
                                ? const Color(0xFF22C55E)
                                : (_shellStatus.status == ShellModeEnum.cloudosCanary
                                    ? const Color(0xFFFACC15)
                                    : const Color(0xFF60A5FA)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      if (_shellUpdating)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        IconButton(
                          tooltip: 'Atualizar Diagnóstico de Shell',
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          onPressed: () async {
                            final sh = await widget.bridge.getShellStatus();
                            if (mounted) setState(() => _shellStatus = sh);
                          },
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Mecanismo Oficial: Custom User Interface Policy (WinLogon.admx)\n'
                'Edição do Sistema: ${_shellStatus.windowsEdition} (Build ${_shellStatus.windowsBuild})',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? CloudOSColors.caption : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  // CANARY MODE BUTTON
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.science_rounded, size: 16),
                    label: const Text('Executar Modo Canary (Sem Alterar Registro)'),
                    onPressed: () async {
                      setState(() => _shellUpdating = true);
                      try {
                        await widget.bridge.setShellMode('CANARY');
                        final sh = await widget.bridge.getShellStatus();
                        if (mounted) setState(() => _shellStatus = sh);
                      } finally {
                        if (mounted) setState(() => _shellUpdating = false);
                      }
                    },
                  ),

                  // RESTORE EXPLORER BUTTON
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF3B82F6),
                      side: const BorderSide(color: Color(0xFF3B82F6)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.restore_rounded, size: 16),
                    label: const Text('Restaurar Windows Explorer Shell'),
                    onPressed: () async {
                      setState(() => _shellUpdating = true);
                      try {
                        await widget.bridge.restoreExplorerShell();
                        final sh = await widget.bridge.getShellStatus();
                        if (mounted) {
                          setState(() => _shellStatus = sh);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Windows Explorer Shell restaurado com sucesso!')),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _shellUpdating = false);
                      }
                    },
                  ),

                  // PERSISTENT ACTIVATION (LOCKED BY GATE 0)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF334155),
                      foregroundColor: const Color(0xFF94A3B8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.lock_rounded, size: 16),
                    label: const Text('Ativar CloudOS como Shell (Gate 0 Bloqueado)'),
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: const Color(0xFF1E293B),
                          title: const Row(
                            children: <Widget>[
                              Icon(Icons.shield_rounded, color: Colors.orangeAccent),
                              SizedBox(width: 8),
                              Text('Trava de Segurança: Gate 0', style: TextStyle(color: Colors.white, fontSize: 16)),
                            ],
                          ),
                          content: const Text(
                            'A ativação permanente do Shell Replacement está travada até a confirmação do teste de login/reboot real da Etapa 10.\n\n'
                            'Para testar o comportamento de shell de forma segura sem risco de tela preta, utilize o botão "Executar Modo Canary".',
                            style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
                          ),
                          actions: <Widget>[
                            TextButton(
                              child: const Text('Entendido'),
                              onPressed: () => Navigator.of(ctx).pop(),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // CARD 2: DIAGNÓSTICO DO SHELL E RECOVERY
        _buildCard(
          title: 'Diagnósticos e Integridade do Shell',
          icon: Icons.analytics_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildDetailRow('Shell Configurado', _shellStatus.configuredShell.isEmpty ? 'explorer.exe (Padrão Oficial)' : _shellStatus.configuredShell),
              _buildDetailRow('Shell Efetivo', _shellStatus.effectiveShell),
              _buildDetailRow('Mecanismo de Shell', 'CustomShellPolicy (WinLogon.admx)'),
              _buildDetailRow('Userinit do Sistema', _shellStatus.userinitIntact ? 'C:\\WINDOWS\\system32\\userinit.exe (Intocado)' : 'Alerta'),
              _buildDetailRow('Winlogon do Sistema (HKLM)', _shellStatus.winlogonIntact ? 'explorer.exe (Preservado)' : 'Alerta'),
              _buildDetailRow('Processos Ativos', 'Bootstrap: ${_shellStatus.shellBootstrapPid} | Supervisor: ${_shellStatus.supervisorPid} | Broker: ${_shellStatus.brokerPid} | Flutter: ${_shellStatus.flutterPid}'),
              _buildDetailRow('Crash Budget (Tolerância)', '${_shellStatus.crashBudget} falhas em 60s antes de fallback automático'),
              _buildDetailRow('Backup de Recuperação', _shellStatus.backupExists ? '%LOCALAPPDATA%\\CloudOS\\Recovery\\shell-backup.json (Válido)' : 'Não localizado'),
              _buildDetailRow('Windows Explorer em Execução', _shellStatus.explorerRunning ? 'Sim (Ativo e responsivo)' : 'Não detectado'),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // CARD 3: INICIALIZAÇÃO AUTOMÁTICA (ETAPA 10)
        _buildCard(
          title: 'Inicialização Automática no Login',
          icon: Icons.rocket_launch_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Iniciar CloudOS ao fazer login no Windows',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Inicia o CloudOS em segundo plano após o login interativo do usuário.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? CloudOSColors.caption : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (_startupUpdating)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Switch(
                      value: _startupStatus.enabled,
                      activeThumbColor: accent,
                      onChanged: (bool enabled) async {
                        setState(() => _startupUpdating = true);
                        try {
                          final ok = await widget.bridge.setStartupEnabled(enabled);
                          if (ok) {
                            final updated = await widget.bridge.getStartupStatus();
                            if (mounted) setState(() => _startupStatus = updated);
                          }
                        } finally {
                          if (mounted) setState(() => _startupUpdating = false);
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _buildDetailRow(
                'Status do Startup',
                _startupStatus.enabled ? 'Ativado (HKCU\\Run)' : 'Desativado',
              ),
              _buildDetailRow(
                'Escopo de Permissões',
                'Padrão de Usuário (AsInvoker / Sem elevação UAC)',
              ),
              if (_startupStatus.command.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'Comando de inicialização registrado:',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? CloudOSColors.caption : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0B0F17) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    _startupStatus.command,
                    style: const TextStyle(fontSize: 11, fontFamily: 'Consolas'),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // CARD 4: CONTROLE DE SESSÃO E DESLIGAMENTO
        _buildCard(
          title: 'Controle de Sessão e Desligamento',
          icon: Icons.exit_to_app_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Deseja fechar o CloudOS e voltar à interface tradicional do Windows?',
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Ao sair, o CloudOS, Supervisor e Broker serão finalizados de forma limpa. O Windows Explorer continuará ativo sem nenhuma perda de dados.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? CloudOSColors.caption : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.power_settings_new_rounded, size: 18),
                label: const Text('Sair do CloudOS (Manter Windows Explorer)'),
                onPressed: () async {
                  await widget.bridge.closeCloudOS();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- COMMON WIDGET HELPERS ---

  Widget _buildSectionHeader(String title, String subtitle) {
    final isDark = cloudThemeNotifier.value.isDark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? CloudOSColors.caption : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildCard({required String title, required IconData icon, required Widget child}) {
    final isDark = cloudThemeNotifier.value.isDark;
    final accent = cloudThemeNotifier.value.accentColor;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141C2B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? CloudOSColors.border : const Color(0xFFE2E8F0),
        ),
        boxShadow: isDark
            ? null
            : const <BoxShadow>[
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return _DetailRow(label: label, value: value);
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isDark = cloudThemeNotifier.value.isDark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: isDark ? CloudOSColors.secondary : const Color(0xFF64748B),
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
