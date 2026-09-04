import 'package:cloudos_flutter_shell/shell/window_manager/window_resize_guard.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('window resize guard', () {
    const viewport = Size(1366, 768);

    test('allows normal right and bottom resize bounds', () {
      expect(
        canResizeTowardViewportEdge(
          viewportSize: viewport,
          windowPosition: const Offset(200, 100),
          right: true,
          bottom: true,
        ),
        isTrue,
      );
    });

    test('blocks right resize when remaining width is below shell minimum', () {
      expect(
        canResizeTowardViewportEdge(
          viewportSize: viewport,
          windowPosition: const Offset(1000, 100),
          right: true,
          bottom: false,
        ),
        isFalse,
      );
    });

    test('blocks bottom resize when taskbar-safe height is below minimum', () {
      expect(
        canResizeTowardViewportEdge(
          viewportSize: viewport,
          windowPosition: const Offset(200, 500),
          right: false,
          bottom: true,
        ),
        isFalse,
      );
    });

    test('left and top-only resize remain available near viewport edges', () {
      expect(
        canResizeTowardViewportEdge(
          viewportSize: viewport,
          windowPosition: const Offset(1100, 600),
          right: false,
          bottom: false,
        ),
        isTrue,
      );
    });
  });
}
