import 'package:flutter/material.dart';

import '../core/cloudos_theme.dart';
import '../models/file_models.dart';
import '../models/shell_models.dart';
import '../services/cloudos_bridge.dart';
import '../services/cloudos_logger.dart';
import '../services/search_settings_catalog.dart';

class SettingsWindow extends StatefulWidget {
  const SettingsWindow({
    super.key,
    required this.bridge,
    this.initialPageId,
  });

  final CloudOSBridge bridge;
  final String? initialPageId;

  @override
  State<SettingsWindow> createState() => _SettingsWindowState();
}

class _SettingsWindowState extends State<SettingsWindow> {
  late int _selectedPageIndex;
  CloudSystemSnapshot _snapshot = CloudOSBridge.unavailableSnapshot;
  List<DriveInfoModel> _drives = const <DriveInfoModel>[];
  Map<String, Object?> _bridgeInfo = const <String, Object?>{};
  double _volume = 0;
  double _brightness = 0;
  bool _volumeBusy = false;
  bool _brightnessBusy = false;

  @override
  void initState() {
    super.initState();
    _selectedPageIndex = SearchSettingsCatalog.pageIndex(
      widget.initialPageId ?? 'system',
    );
    _loadData();
  }

  @override
  void didUpdateWidget(covariant SettingsWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPageId != widget.initialPageId) {
      final next = SearchSettingsCatalog.pageIndex(
        widget.initialPageId ?? 'system',
      );
      if (next != _selectedPageIndex) {
        setState(() => _selectedPageIndex = next);
      }
    }
    if (!identical(oldWidget.bridge, widget.bridge)) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    CloudSystemSnapshot snapshot = CloudOSBridge.unavailableSnapshot;
    List<DriveInfoModel> drives = const <DriveInfoModel>[];
    Map<String, Object?> bridgeInfo = const <String, Object?>{};

    try {
      snapshot = await widget.bridge.loadSystemSnapshot();
    } catch (error, stackTrace) {
      CloudOSLogger.error(
        'SettingsWindow',
        'loadSystemSnapshot',
        error,
        stackTrace,
      );
    }

    try {
      drives = await widget.bridge.getDrives();
    } catch (error, stackTrace) {
      CloudOSLogger.error('SettingsWindow', 'getDrives', error, stackTrace);
    }

    try {
      bridgeInfo = await widget.bridge.getBridgeInfo();
    } catch (error, stackTrace) {
      CloudOSLogger.error('SettingsWindow', 'getBridgeInfo', error, stackTrace);
    }

    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _drives = drives;
      _bridgeInfo = bridgeInfo;
      _volume = snapshot.volume.clamp(0.0, 1.0).toDouble();
      _brightness = snapshot.brightness.clamp(0.0, 1.0).toDouble();
    });
  }

  String get _brokerState {
    if (_bridgeInfo['brokerConnected'] == true) return 'Conectado';
    final raw = _bridgeInfo['brokerState'];
    if (raw is String && raw.trim().isNotEmpty) return raw;
    return 'Indisponível';
  }

  Future<void> _setVolume(double value) async {
    if (_volumeBusy || !_snapshot.volumeAvailable) return;
    final previous = _volume;
    setState(() {
      _volumeBusy = true;
      _volume = value;
    });
    final ok = await widget.bridge.setVolume(value);
    if (!mounted) return;
    setState(() {
      _volumeBusy = false;
      if (!ok) _volume = previous;
    });
    if (!ok) {
      _showUnavailable('O controle de volume não confirmou a alteração.');
    }
  }

  Future<void> _setBrightness(double value) async {
    if (_brightnessBusy || !_snapshot.brightnessAvailable) return;
    final previous = _brightness;
    setState(() {
      _brightnessBusy = true;
      _brightness = value;
    });
    final ok = await widget.bridge.setBrightness(value);
    if (!mounted) return;
    setState(() {
      _brightnessBusy = false;
      if (!ok) _brightness = previous;
    });
    if (!ok) {
      _showUnavailable('O monitor não confirmou a alteração de brilho.');
    }
  }

  void _showUnavailable(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = SearchSettingsCatalog.pages;
    return Row(
      children: <Widget>[
        Container(
          width: 220,
          color: const Color(0xFF131620),
          child: Column(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(16),
                alignment: Alignment.centerLeft,
                child: const Text(
                  'Configurações',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: pages.length,
                  itemBuilder: (context, index) {
                    final page = pages[index];
                    final selected = index == _selectedPageIndex;
                    return InkWell(
                      key: ValueKey<String>('settings-page-${page.id}'),
                      onTap: () => setState(() => _selectedPageIndex = index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? CloudOSColors.accent.withValues(alpha: 0.18)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: selected
                              ? Border.all(
                                  color: CloudOSColors.accent.withValues(
                                    alpha: 0.4,
                                  ),
                                )
                              : null,
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              page.icon,
                              size: 17,
                              color: selected
                                  ? CloudOSColors.accent
                                  : Colors.white60,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                page.title,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: selected
                                      ? Colors.white
                                      : Colors.white70,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: const Color(0xFF171A26),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              key: ValueKey<int>(_selectedPageIndex),
              child: _buildPageContent(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPageContent() {
    return switch (_selectedPageIndex) {
      0 => _buildSystemPage(),
      1 => _buildDisplayPage(),
      2 => _buildSoundPage(),
      3 => _buildNetworkPage(),
      4 => _buildBluetoothPage(),
      5 => _buildPowerPage(),
      6 => _buildStoragePage(),
      7 => _buildPersonalizationPage(),
      8 => _buildWslPage(),
      _ => _buildAboutPage(),
    };
  }

  Widget _buildCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2232),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildSystemPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildCard(
          title: 'Estado do Sistema',
          child: Column(
            children: <Widget>[
              _buildInfoRow(
                'Nome do Computador',
                _snapshot.deviceName.trim().isEmpty
                    ? 'Indisponível'
                    : _snapshot.deviceName,
              ),
              _buildInfoRow('System Broker', _brokerState),
              _buildInfoRow(
                'Workspace CloudOS',
                _snapshot.currentWorkspace.toString(),
              ),
              _buildInfoRow('Protocolo', 'V21 Named Pipe'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDisplayPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildCard(
          title: 'Tela',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildInfoRow(
                'Resolução / escala do Windows',
                'Ainda não exposta pelo Broker',
              ),
              const SizedBox(height: 8),
              if (_snapshot.brightnessAvailable)
                _buildSlider(
                  label: _brightnessBusy
                      ? 'Brilho: aplicando...'
                      : 'Brilho: ${(_brightness * 100).round()}%',
                  value: _brightness,
                  enabled: !_brightnessBusy,
                  onChanged: _setBrightness,
                )
              else
                const _UnavailableFeature(
                  title: 'Brilho',
                  message:
                      'Este monitor não expõe controle de brilho compatível ao CloudOS.',
                ),
              const SizedBox(height: 10),
              const _UnavailableFeature(
                title: 'Luz Noturna',
                message:
                    'Ainda não existe backend seguro para alterar Luz Noturna.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSoundPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildCard(
          title: 'Saída de Áudio do Sistema',
          child: _snapshot.volumeAvailable
              ? _buildSlider(
                  label: _volumeBusy
                      ? 'Volume: aplicando...'
                      : 'Volume: ${(_volume * 100).round()}%',
                  value: _volume,
                  enabled: !_volumeBusy,
                  onChanged: _setVolume,
                )
              : const _UnavailableFeature(
                  title: 'Volume',
                  message:
                      'O endpoint de áudio padrão não está disponível para controle.',
                ),
        ),
      ],
    );
  }

  Widget _buildNetworkPage() {
    final networkName = _snapshot.networkName.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildCard(
          title: 'Status da Conexão',
          child: Column(
            children: <Widget>[
              _buildInfoRow(
                'Interface ativa',
                _snapshot.networkAvailable
                    ? (networkName.isEmpty ? 'Detectada' : networkName)
                    : 'Indisponível',
              ),
              _buildInfoRow(
                'Estado',
                _snapshot.networkAvailable
                    ? 'Adaptador de rede ativo'
                    : 'Nenhum adaptador ativo confirmado',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBluetoothPage() {
    return const _UnavailableFeature(
      title: 'Bluetooth',
      message:
          'O System Broker ainda não expõe inventário ou controle Bluetooth. Nenhum estado é inventado.',
    );
  }

  Widget _buildPowerPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildCard(
          title: 'Bateria e Energia',
          child: Column(
            children: <Widget>[
              _buildInfoRow(
                'Bateria',
                _snapshot.batteryAvailable && _snapshot.batteryPercent >= 0
                    ? '${_snapshot.batteryPercent}%'
                    : 'Não detectada / indisponível',
              ),
              _buildInfoRow(
                'Fonte AC / carregamento',
                'Ainda não exposta pelo Broker',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStoragePage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildCard(
          title: 'Unidades de Armazenamento',
          child: _drives.isEmpty
              ? const Text(
                  'Nenhuma unidade foi retornada pelo Broker.',
                  style: TextStyle(color: Colors.white60),
                )
              : Column(
                  children: _drives.map((drive) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: <Widget>[
                          const Icon(
                            Icons.storage_rounded,
                            size: 22,
                            color: CloudOSColors.accent,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '${drive.label} (${drive.letter})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'Livre: ${drive.freeFormatted} de ${drive.totalFormatted} · ${drive.filesystem}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.white60,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildPersonalizationPage() {
    return const _UnavailableFeature(
      title: 'Personalização',
      message:
          'Tema, transparência e wallpaper ainda não possuem persistência/configuração central concluída. Os controles permanecem desabilitados para não simular alterações.',
    );
  }

  Widget _buildWslPage() {
    final defaultDistro = _snapshot.defaultDistro.trim();
    final uncDistro = defaultDistro.isNotEmpty
        ? defaultDistro
        : (_snapshot.distros.isEmpty ? '' : _snapshot.distros.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildCard(
          title: 'Subsistema Windows para Linux (WSL)',
          child: Column(
            children: <Widget>[
              _buildInfoRow(
                'WSL detectado',
                _snapshot.wslAvailable ? 'Sim' : 'Não',
              ),
              _buildInfoRow(
                'Distribuições',
                _snapshot.distros.isEmpty
                    ? 'Nenhuma configurada'
                    : _snapshot.distros.join(', '),
              ),
              _buildInfoRow(
                'Distribuição padrão',
                defaultDistro.isEmpty ? 'Não informada' : defaultDistro,
              ),
              _buildInfoRow(
                'Acesso UNC',
                uncDistro.isEmpty
                    ? r'\\wsl.localhost'
                    : r'\\wsl.localhost\' + uncDistro,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAboutPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildCard(
          title: 'CloudOS Desktop V23',
          child: Column(
            children: <Widget>[
              _buildInfoRow('Linha da aplicação', '23.x validation'),
              _buildInfoRow('Broker IPC', 'V21 Named Pipe restrito'),
              _buildInfoRow(
                'Arquitetura',
                'Flutter Windows + núcleo nativo C++',
              ),
              _buildInfoRow(
                'Busca / continuidade',
                'Search V23 + Session V3 + WindowManager V23',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required bool enabled,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Slider(
            value: value.clamp(0.0, 1.0).toDouble(),
            min: 0,
            max: 1,
            activeColor: CloudOSColors.accent,
            onChanged: enabled ? onChanged : null,
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 130,
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: Colors.white60),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnavailableFeature extends StatelessWidget {
  const _UnavailableFeature({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2232),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: Colors.white54,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11.5,
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
