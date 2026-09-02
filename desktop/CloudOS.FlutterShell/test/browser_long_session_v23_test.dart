import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Browser V23 long-session lifecycle', () {
    late String source;

    setUpAll(() {
      source = File('lib/widgets/browser_window.dart').readAsStringSync();
    });

    test('WebView2 tabs have bounded count and explicit disposal state', () {
      expect(source, contains('static const int maxTabs = 24'));
      expect(source, contains('bool disposeRequested = false'));
      expect(source, contains('bool controllerDisposed = false'));
      expect(source, contains('Future<void>? _disposeFuture'));
      expect(source, contains('disposeControllerIfReady'));
    });

    test('close-during-initialize cannot resurrect an abandoned controller', () {
      final initialize = source.indexOf('await tab.controller.initialize();');
      final markInitialized = source.indexOf('tab.initialized = true;', initialize);
      final disposedCheck = source.indexOf('if (tab.disposeRequested)', markInitialized);
      final controllerDispose = source.indexOf(
        'await tab.disposeControllerIfReady();',
        disposedCheck,
      );

      expect(initialize, greaterThanOrEqualTo(0));
      expect(markInitialized, greaterThan(initialize));
      expect(disposedCheck, greaterThan(markInitialized));
      expect(controllerDispose, greaterThan(disposedCheck));
    });

    test('callbacks reject removed/disposed tabs before setState', () {
      expect(
        RegExp(r'!mounted \|\| tab\.disposeRequested \|\| !_tabs\.contains\(tab\)')
            .allMatches(source)
            .length,
        greaterThanOrEqualTo(5),
      );
    });

    test('inactive tabs and hidden browser are suspended', () {
      expect(source, contains('await tab.controller.resume()'));
      expect(source, contains('await tab.controller.suspend()'));
      expect(source, contains('widget.isVisible && index == _activeTabIndex'));
    });

    test('browser traffic remains WebView2-owned rather than custom HTTP', () {
      expect(source, contains('webview_flutter_windows'));
      expect(source, isNot(contains("import 'dart:io'")));
      expect(source, isNot(contains('HttpClient(')));
      expect(source, isNot(contains('Socket.connect')));
    });
  });
}
