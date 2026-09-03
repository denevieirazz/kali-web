import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const legacyFeatureExports = <String, String>{
    'lib/widgets/cloud_taskbar.dart':
        "export '../features/taskbar/presentation/cloud_taskbar.dart';",
    'lib/widgets/files_window.dart':
        "export '../features/files/presentation/files_window.dart';",
    'lib/widgets/notification_center.dart':
        "export '../features/notifications/presentation/notification_center_panel.dart';",
    'lib/widgets/quick_settings_panel.dart':
        "export '../features/quick_settings/presentation/quick_settings_panel.dart';",
    'lib/widgets/start_panel.dart':
        "export '../features/start/presentation/start_panel.dart';",
  };

  test('legacy feature paths stay thin compatibility exports', () {
    for (final entry in legacyFeatureExports.entries) {
      final source = File(entry.key).readAsStringSync();

      expect(source, contains(entry.value), reason: entry.key);
      expect(
        RegExp(r'\b(class|enum|mixin|extension)\s+').hasMatch(source),
        isFalse,
        reason: '${entry.key} must not regain implementation code',
      );

      final executableLines = source
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty && !line.startsWith('//'))
          .toList(growable: false);
      expect(executableLines, <String>[entry.value], reason: entry.key);
    }
  });

  test('production code does not depend on legacy feature paths', () {
    final legacyFragments = legacyFeatureExports.keys
        .map((path) => path.substring('lib/'.length))
        .toList(growable: false);

    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in dartFiles) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      if (legacyFeatureExports.containsKey(normalizedPath)) continue;

      final source = file.readAsStringSync();
      for (final fragment in legacyFragments) {
        expect(
          source.contains(fragment),
          isFalse,
          reason: '$normalizedPath must import the canonical feature, not $fragment',
        );
      }
    }
  });

  test('shell_models remains a compatibility-only barrel', () {
    final source = File('lib/models/shell_models.dart').readAsStringSync();
    const expectedExports = <String>{
      "export 'cloud_app.dart';",
      "export 'cloud_file_item.dart';",
      "export 'cloud_notification.dart';",
      "export 'cloud_system_snapshot.dart';",
    };

    final executableLines = source
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('//'))
        .toSet();

    expect(executableLines, expectedExports);
    expect(
      RegExp(r'\b(class|enum|mixin|extension)\s+').hasMatch(source),
      isFalse,
      reason: 'shell_models.dart must not regain model implementations',
    );
  });

  test('WSL app discovery stays passive and does not wake Linux', () {
    final appService = File(
      '../CloudOS.SystemBroker/src/app_service_v21.cpp',
    ).readAsStringSync();
    final refreshStart = appService.indexOf('void AppServiceV21::Refresh()');
    final launchStart = appService.indexOf('bool AppServiceV21::LaunchApp');

    expect(refreshStart, greaterThanOrEqualTo(0));
    expect(launchStart, greaterThan(refreshStart));

    final refreshSource = appService.substring(refreshStart, launchStart);
    expect(refreshSource, contains('GetDistributions()'));
    expect(
      refreshSource,
      isNot(contains('ShellExecuteW')),
      reason: 'catalog refresh must not launch wsl.exe or any application',
    );
    expect(
      refreshSource,
      isNot(contains('CreateProcessW')),
      reason: 'catalog refresh must remain passive',
    );
    expect(
      refreshSource,
      isNot(contains('IsWslCommandAvailable(')),
      reason: 'catalog refresh must not probe packages inside a WSL distro',
    );
  });

  test('WSL discovery never fabricates a fallback distro', () {
    final wslService = File(
      '../CloudOS.SystemBroker/src/wsl_service_v21.cpp',
    ).readAsStringSync();

    expect(
      wslService,
      isNot(contains('distros_.push_back("Ubuntu")')),
      reason: 'configured distros must come from Windows state, never fixtures',
    );
    expect(wslService, contains('DefaultDistribution'));
  });

  test('native degraded system snapshot never fabricates hardware state', () {
    final nativeBridge = File(
      'native_bridge/cloudos_flutter_bridge_v20.cpp',
    ).readAsStringSync();
    final brokerHeader = File(
      'native_bridge/cloudos_broker_client_v21.h',
    ).readAsStringSync();
    final brokerSource = File(
      'native_bridge/cloudos_broker_client_v21.cpp',
    ).readAsStringSync();
    final dartBridge = File(
      'lib/services/cloudos_bridge.dart',
    ).readAsStringSync();
    final quickSummary = File(
      'lib/features/quick_settings/presentation/widgets/quick_system_summary.dart',
    ).readAsStringSync();

    final fallbackStart = nativeBridge.indexOf(
      'void CloudOSFlutterBridgeV20::RefreshSystemSnapshot()',
    );
    expect(fallbackStart, greaterThanOrEqualTo(0));
    final fallbackSource = nativeBridge.substring(fallbackStart);

    for (final synthetic in <String>[
      'cached_snapshot_.network_available = true',
      'cached_snapshot_.volume_available = true',
      'cached_snapshot_.brightness_available = true',
      'cached_snapshot_.battery_percent = 100',
      'cached_snapshot_.wsl_available = true',
      'CloudOS Network • Wi-Fi 6',
    ]) {
      expect(
        fallbackSource,
        isNot(contains(synthetic)),
        reason: 'degraded Native Bridge must not fabricate: $synthetic',
      );
    }

    for (final synthetic in <String>[
      'battery_available{true}',
      'battery_percent{100}',
      'network_available{true}',
      'volume_available{true}',
      'double volume{0.72}',
      'brightness_available{true}',
      'double brightness{0.85}',
    ]) {
      expect(
        brokerHeader,
        isNot(contains(synthetic)),
        reason: 'Broker client defaults must be conservative: $synthetic',
      );
    }

    for (final synthetic in <String>[
      '"batteryAvailable", true',
      '"batteryPercent", 100',
      '"networkAvailable", true',
      '"volumeAvailable", true',
      '"volume", 0.72',
      '"brightnessAvailable", true',
      '"brightness", 0.85',
    ]) {
      expect(
        brokerSource,
        isNot(contains(synthetic)),
        reason: 'missing Broker fields must never become healthy defaults: $synthetic',
      );
    }

    expect(dartBridge, contains('static const degradedSnapshot'));
    expect(dartBridge, contains('batteryAvailable: false'));
    expect(
      dartBridge,
      anyOf(contains('return degradedSnapshot;'), contains('?? degradedSnapshot')),
      reason: 'loadSystemSnapshot must fallback to degradedSnapshot on failure',
    );
    expect(
      quickSummary,
      isNot(contains('Carregando')),
      reason: 'charging state is not part of the V21 snapshot contract',
    );
  });

  test('Browser and Terminal cannot regress to simulated surfaces', () {
    final browser = File(
      'lib/features/browser/presentation/browser_window.dart',
    ).readAsStringSync();
    final terminal = File(
      'lib/features/terminal/presentation/terminal_window.dart',
    ).readAsStringSync();
    final bridge = File(
      'native_bridge/cloudos_flutter_bridge_v20.cpp',
    ).readAsStringSync();

    expect(browser, contains('WebviewController'));
    expect(browser, contains('return Webview(_webview)'));
    expect(browser, isNot(contains('CloudOS Web Navigation')));
    expect(browser, isNot(contains('Future<void>.delayed')));

    expect(terminal, contains('TerminalView('));
    expect(terminal, contains('createTerminalSession('));
    expect(terminal, isNot(contains('Comando executado via ConPTY host')));
    expect(bridge, contains('terminal.createSession'));
    expect(bridge, contains('CloudOSConPTYManager::Instance()'));
  });
}
