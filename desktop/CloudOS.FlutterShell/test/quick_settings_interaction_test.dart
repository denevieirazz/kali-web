import 'package:cloudos_flutter_shell/features/quick_settings/presentation/quick_settings_panel.dart';
import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('volume and brightness commit through native callbacks', (tester) async {
    double? committedVolume;
    double? committedBrightness;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickSettingsPanel(
            snapshot: CloudOSBridge.previewSnapshot,
            onSetVolume: (value) async {
              committedVolume = value;
              return true;
            },
            onSetBrightness: (value) async {
              committedBrightness = value;
              return true;
            },
          ),
        ),
      ),
    );

    var sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders, hasLength(2));

    sliders[0].onChanged?.call(0.42);
    await tester.pump();
    sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders[0].value, closeTo(0.42, 0.001));
    sliders[0].onChangeEnd?.call(0.42);
    await tester.pumpAndSettle();
    expect(committedVolume, closeTo(0.42, 0.001));

    sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    sliders[1].onChanged?.call(0.73);
    await tester.pump();
    sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders[1].value, closeTo(0.73, 0.001));
    sliders[1].onChangeEnd?.call(0.73);
    await tester.pumpAndSettle();
    expect(committedBrightness, closeTo(0.73, 0.001));
  });

  testWidgets('failed native commit rolls slider back to snapshot value', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickSettingsPanel(
            snapshot: CloudOSBridge.previewSnapshot,
            onSetVolume: (_) async => false,
          ),
        ),
      ),
    );

    var slider = tester.widgetList<Slider>(find.byType(Slider)).first;
    slider.onChanged?.call(0.11);
    await tester.pump();
    slider = tester.widgetList<Slider>(find.byType(Slider)).first;
    expect(slider.value, closeTo(0.11, 0.001));

    slider.onChangeEnd?.call(0.11);
    await tester.pumpAndSettle();
    slider = tester.widgetList<Slider>(find.byType(Slider)).first;
    expect(
      slider.value,
      closeTo(CloudOSBridge.previewSnapshot.volume, 0.001),
    );
  });
}
