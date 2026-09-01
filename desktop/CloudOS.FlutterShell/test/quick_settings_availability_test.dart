import 'package:cloudos_flutter_shell/features/quick_settings/presentation/quick_settings_panel.dart';
import 'package:cloudos_flutter_shell/models/cloud_system_snapshot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('unavailable native controls disable their sliders', (tester) async {
    const snapshot = CloudSystemSnapshot(
      deviceName: 'TEST',
      networkName: 'Offline',
      volumeAvailable: false,
      volume: 0,
      brightnessAvailable: false,
      brightness: 0,
      batteryPercent: 100,
      wslAvailable: false,
      distros: <String>[],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: QuickSettingsPanel(snapshot: snapshot),
        ),
      ),
    );

    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders, hasLength(2));
    expect(sliders[0].onChanged, isNull);
    expect(sliders[1].onChanged, isNull);
    expect(find.text('N/D'), findsNWidgets(2));
  });
}
