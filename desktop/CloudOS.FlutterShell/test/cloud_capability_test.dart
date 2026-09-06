import 'package:flutter_test/flutter_test.dart';
import 'package:cloudos_flutter_shell/models/cloud_capability.dart';

void main() {
  group('CloudCapability', () {
    test('serializes and deserializes correctly', () {
      const cap = CloudCapability(
        id: 'bluetooth',
        supported: true,
        available: true,
        enabled: true,
        writable: false,
        reason: 'Read-only adapter',
        permission: 'allowed',
        features: ['status', 'devices'],
      );

      final map = cap.toMap();
      final restored = CloudCapability.fromMap(map);

      expect(restored.id, 'bluetooth');
      expect(restored.supported, isTrue);
      expect(restored.available, isTrue);
      expect(restored.enabled, isTrue);
      expect(restored.writable, isFalse);
      expect(restored.reason, 'Read-only adapter');
      expect(restored.features, contains('status'));
      expect(restored.isOperational, isTrue);
    });

    test('unavailable returns safe degraded values', () {
      final cap = CloudCapability.unavailable;
      expect(cap.supported, isFalse);
      expect(cap.available, isFalse);
      expect(cap.isOperational, isFalse);
    });
  });

  group('CapabilityRegistry', () {
    test('returns fallback capability for unknown id', () {
      final registry = CapabilityRegistry();
      final cap = registry.get('non_existent');
      expect(cap.supported, isFalse);
      expect(cap.available, isFalse);
      expect(cap.isWritable, isFalse);
    });

    test('defaultCloudOS exposes standard system capabilities', () {
      final registry = CapabilityRegistry.defaultCloudOS(
        bluetoothAvailable: true,
        bluetoothWritable: false,
      );

      expect(registry.display.isOperational, isTrue);
      expect(registry.audio.isOperational, isTrue);
      expect(registry.bluetooth.isOperational, isTrue);
      expect(registry.bluetooth.writable, isFalse);
      expect(registry.isWritable('bluetooth'), isFalse);
      expect(registry.managedWindows.supported, isTrue);
      expect(registry.filesystem.supported, isTrue);
    });
  });
}
