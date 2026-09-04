import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloudos_flutter_shell/shell/window_manager/cloud_window.dart';

void main() {
  group('CloudWindow Snap and State Tests', () {
    test('initializes with default snap properties set to false', () {
      final window = CloudWindow(
        id: 'win-1',
        title: 'Editor',
        icon: Icons.edit,
        type: CloudWindowType.notes,
        position: const Offset(100, 100),
        size: const Size(600, 400),
      );

      expect(window.isSnappedLeft, isFalse);
      expect(window.isSnappedRight, isFalse);
      expect(window.isMaximized, isFalse);
      expect(window.isMinimized, isFalse);
    });

    test('copyWith updates isSnappedLeft and isSnappedRight', () {
      final window = CloudWindow(
        id: 'win-1',
        title: 'Calculadora',
        icon: Icons.calculate,
        type: CloudWindowType.calculator,
        position: const Offset(50, 50),
        size: const Size(400, 500),
      );

      final snappedLeft = window.copyWith(isSnappedLeft: true, isSnappedRight: false);
      expect(snappedLeft.isSnappedLeft, isTrue);
      expect(snappedLeft.isSnappedRight, isFalse);

      final snappedRight = window.copyWith(isSnappedLeft: false, isSnappedRight: true);
      expect(snappedRight.isSnappedLeft, isFalse);
      expect(snappedRight.isSnappedRight, isTrue);
    });

    test('supports new CloudWindowType entries (notes, calculator, taskManager)', () {
      expect(CloudWindowType.values, contains(CloudWindowType.notes));
      expect(CloudWindowType.values, contains(CloudWindowType.calculator));
      expect(CloudWindowType.values, contains(CloudWindowType.taskManager));
    });
  });
}
