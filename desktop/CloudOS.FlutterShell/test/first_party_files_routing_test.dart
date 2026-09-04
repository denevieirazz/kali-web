import 'dart:io';

import 'package:cloudos_flutter_shell/features/files/presentation/files_window.dart';
import 'package:cloudos_flutter_shell/models/cloud_file_item.dart';
import 'package:cloudos_flutter_shell/services/cloudos_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RootRecordingBridge extends CloudOSBridge {
  final List<String> locations = <String>[];

  @override
  Future<List<CloudFileItem>> loadFiles(String location) async {
    locations.add(location);
    return const <CloudFileItem>[];
  }
}

Widget _filesHarness({
  required CloudOSBridge bridge,
  required String root,
}) {
  return MaterialApp(
    home: Scaffold(
      body: FilesWindow(
        bridge: bridge,
        initialRootId: root,
        onClose: () {},
        onMinimize: () {},
        onDrag: (_) {},
      ),
    ),
  );
}

void main() {
  testWidgets('CloudOS Drive starts Files on the allowlisted cloud-drive root', (
    tester,
  ) async {
    final bridge = _RootRecordingBridge();
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _filesHarness(bridge: bridge, root: 'cloud-drive'),
    );
    await tester.pumpAndSettle();

    expect(bridge.locations, <String>['cloud-drive']);
    expect(find.text('CloudOS Drive'), findsWidgets);
  });

  testWidgets('changing the requested first-party root reloads Files safely', (
    tester,
  ) async {
    final bridge = _RootRecordingBridge();
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_filesHarness(bridge: bridge, root: 'home'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _filesHarness(bridge: bridge, root: 'cloud-drive'),
    );
    await tester.pumpAndSettle();

    expect(bridge.locations, <String>['home', 'cloud-drive']);
  });

  testWidgets('Trash fails closed instead of requesting a broker Files location', (
    tester,
  ) async {
    final bridge = _RootRecordingBridge();
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_filesHarness(bridge: bridge, root: 'home'));
    await tester.pumpAndSettle();
    expect(bridge.locations, <String>['home']);

    await tester.tap(find.text('Lixeira'));
    await tester.pump();

    expect(bridge.locations, <String>['home']);
    expect(
      find.textContaining('Explorer do Windows não será aberto'),
      findsOneWidget,
    );
  });

  test('Broker cannot dispatch first-party Drive or Trash to Windows Shell', () {
    final source = File(
      '../CloudOS.SystemBroker/src/app_service_v21.cpp',
    ).readAsStringSync();
    final launchStart = source.indexOf('bool AppServiceV21::LaunchApp');
    expect(launchStart, greaterThanOrEqualTo(0));
    final launchSource = source.substring(launchStart);

    expect(
      launchSource,
      isNot(contains('GetEnvironmentVariableW(L"USERPROFILE"')),
    );
    expect(launchSource, isNot(contains('shell:RecycleBinFolder')));
    expect(
      launchSource,
      contains('CloudOS Drive is a first-party Files location'),
    );
    expect(
      launchSource,
      contains('CloudOS Trash has no approved first-party surface yet'),
    );
  });

  test('Flutter shell consumes Drive and Trash before generic broker launch', () {
    final source = File('lib/shell/cloudos_shell.dart').readAsStringSync();
    final launchStart = source.indexOf('Future<void> _launchApp(CloudApp app)');
    final spotlightStart = source.indexOf(
      'List<SpotlightItem> get _spotlightItems',
      launchStart,
    );
    expect(launchStart, greaterThanOrEqualTo(0));
    expect(spotlightStart, greaterThan(launchStart));
    final launchSource = source.substring(launchStart, spotlightStart);

    final driveIndex = launchSource.indexOf("app.id == 'cloudos:drive'");
    final trashIndex = launchSource.indexOf("app.id == 'cloudos:trash'");
    final brokerIndex = launchSource.indexOf('widget.bridge.launchApp(app.id)');
    expect(driveIndex, greaterThanOrEqualTo(0));
    expect(trashIndex, greaterThan(driveIndex));
    expect(brokerIndex, greaterThan(trashIndex));
    expect(launchSource, contains("_openFilesRoot('cloud-drive')"));
  });
}
