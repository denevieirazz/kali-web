import 'package:cloudos_flutter_shell/features/quick_settings/domain/quick_settings_route.dart';
import 'package:cloudos_flutter_shell/features/quick_settings/presentation/quick_settings_panel.dart';
import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Quick Settings routes are closed allowlisted CloudOS app IDs', () {
    expect(
      quickSettingsLaunchId(QuickSettingsRoute.root),
      'cloudos:settings',
    );
    expect(
      quickSettingsLaunchId(QuickSettingsRoute.wifi),
      'cloudos:settings:wifi',
    );
    expect(
      quickSettingsLaunchId(QuickSettingsRoute.bluetooth),
      'cloudos:settings:bluetooth',
    );
    expect(
      quickSettingsLaunchId(QuickSettingsRoute.nightLight),
      'cloudos:settings:nightlight',
    );
    expect(
      quickSettingsLaunchId(QuickSettingsRoute.focus),
      'cloudos:settings:focus',
    );
  });

  testWidgets('system tiles stay inside CloudOS and do not pretend false state',
      (tester) async {
    var root = 0;
    var wifi = 0;
    var bluetooth = 0;
    var nightLight = 0;
    var focus = 0;

    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickSettingsPanel(
            snapshot: CloudOSBridge.previewSnapshot,
            onOpenSettings: () => root++,
            onOpenNetworkSettings: () => wifi++,
            onOpenBluetoothSettings: () => bluetooth++,
            onOpenNightLightSettings: () => nightLight++,
            onOpenFocusSettings: () => focus++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Abrir Painel Completo'));
    await tester.tap(find.textContaining('Rede').first);
    await tester.tap(find.text('Bluetooth'));
    await tester.tap(find.text('Luz Noturna'));
    await tester.tap(find.text('Modo Foco'));
    await tester.pump();

    expect(root, 1);
    expect(wifi, 1);
    expect(bluetooth, 1);
    expect(nightLight, 1);
    expect(focus, 1);

    expect(find.text('Configurar no CloudOS'), findsNWidgets(2));
    expect(find.textContaining('Abrir configuração'), findsNothing);
    expect(find.textContaining('Abrir dispositivos'), findsNothing);
  });
}
