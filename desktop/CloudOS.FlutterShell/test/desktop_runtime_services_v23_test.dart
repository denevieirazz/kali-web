import 'dart:io';

import 'package:cloudos_flutter_shell/services/desktop_clock_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DesktopClockService', () {
    test('refresh is deterministic without starting a hidden timer', () {
      var current = DateTime(2026, 9, 2, 12, 0, 0);
      final service = DesktopClockService(now: () => current);
      var notifications = 0;
      service.addListener(() => notifications++);

      expect(service.isRunning, isFalse);
      expect(service.now, current);

      current = current.add(const Duration(seconds: 1));
      service.refreshForTesting();
      expect(service.now, current);
      expect(notifications, 1);
      expect(service.isRunning, isFalse);
      service.dispose();
    });

    test('start and stop own the periodic timer explicitly', () async {
      var current = DateTime(2026, 9, 2, 12, 0, 0);
      final service = DesktopClockService(
        now: () => current,
        tickInterval: const Duration(milliseconds: 5),
      );
      service.start();
      expect(service.isRunning, isTrue);
      current = current.add(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(service.now, current);
      service.stop();
      expect(service.isRunning, isFalse);
      service.dispose();
    });
  });

  test('desktop runtime widgets contain no process-environment test switches', () {
    final widgets = File('lib/widgets/desktop_widgets.dart').readAsStringSync();
    final metrics = File(
      'lib/services/system_metrics_service.dart',
    ).readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(widgets, isNot(contains("import 'dart:io'")));
    expect(widgets, isNot(contains('Platform.environment')));
    expect(metrics, isNot(contains("import 'dart:io'")));
    expect(metrics, isNot(contains('FLUTTER_TEST')));
    expect(mainSource, contains('DesktopClockService.instance.start()'));
  });
}
