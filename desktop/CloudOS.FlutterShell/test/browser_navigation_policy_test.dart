import 'package:cloudos_flutter_shell/features/browser/domain/browser_navigation_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

void main() {
  group('browser navigation policy', () {
    test('canonicalizes an empty query parameter before navigation', () {
      expect(
        normalizeBrowserTarget('https://www.win-rar.com/download.html?&L=9'),
        'https://www.win-rar.com/download.html?L=9',
      );
    });

    test('keeps URL and search normalization behavior', () {
      expect(normalizeBrowserTarget('example.com'), 'https://example.com');
      expect(
        normalizeBrowserTarget('teste cloudos'),
        'https://www.google.com/search?q=teste%20cloudos',
      );
    });

    test('ignores only superseded or intentionally canceled navigation', () {
      expect(
        isTransientNavigationError(WebErrorStatus.connectionAborted),
        isTrue,
      );
      expect(
        isTransientNavigationError(WebErrorStatus.operationCanceled),
        isTrue,
      );
      expect(
        isTransientNavigationError(WebErrorStatus.hostNameNotResolved),
        isFalse,
      );
      expect(
        isTransientNavigationError(WebErrorStatus.certificateIsInvalid),
        isFalse,
      );
    });
  });
}
