import 'package:cloudos_flutter_shell/features/quick_settings/presentation/quick_settings_panel.dart';
import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeQuickSettingsBridge extends CloudOSBridge {
  const _FakeQuickSettingsBridge();

  @override
  Future<CloudQuickSettingsState> getQuickSettingsState() async {
    return const CloudQuickSettingsState(
      audio: CloudAudioState(
        available: true,
        volume: 0.66,
        isMuted: true,
        defaultDevice: 'Speakers',
      ),
      power: CloudPowerStatus(),
      bluetooth: CloudBluetoothStatus(
        available: true,
        enabled: true,
        radioName: 'Bluetooth Radio',
      ),
      personalization: CloudPersonalizationSettings(),
      performanceProfile: 'performance',
    );
  }

  @override
  Future<List<CloudNetworkInterface>> getNetworkInterfaces() async {
    return const <CloudNetworkInterface>[
      CloudNetworkInterface(
        id: 'eth0',
        name: 'Intel Ethernet Controller',
        friendlyName: 'Ethernet principal',
        type: 'Ethernet',
        status: 'Up',
        ipv4: '192.168.1.20',
        ipv6: '',
        gateway: '192.168.1.1',
        dns: '1.1.1.1',
        isInternetConnected: true,
      ),
    ];
  }
}

void main() {
  testWidgets('renders authoritative state instead of hardcoded quick tiles',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: QuickSettingsPanel(
            snapshot: CloudOSBridge.previewSnapshot,
            bridge: _FakeQuickSettingsBridge(),
            performanceProfile: PerformanceProfileInfo(
              profile: 'performance',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ethernet'), findsOneWidget);
    expect(find.text('Ethernet principal'), findsOneWidget);
    expect(find.text('Ligado • Dispositivos'), findsOneWidget);
    expect(find.text('Desempenho Máximo'), findsOneWidget);
    expect(find.byTooltip('Ativar som'), findsOneWidget);
    expect(find.text('66%'), findsOneWidget);
  });
}
