import 'package:cloudos_flutter_shell/features/terminal/domain/wsl_runtime_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WslRuntimePolicy', () {
    test('normalizes duplicate distro names without inventing a default', () {
      final policy = WslRuntimePolicy(
        wslAvailable: true,
        installedDistros: const <String>[
          ' Ubuntu ',
          'ubuntu',
          '',
          'kali-linux',
        ],
      );

      expect(policy.installedDistros, const <String>['Ubuntu', 'kali-linux']);
      expect(policy.defaultDistro, isEmpty);
      expect(policy.launchFallbackDistro, 'Ubuntu');
      expect(policy.preferredSecurityDistro, 'kali-linux');
      expect(policy.kaliInstalled, isTrue);
    });

    test('uses broker default distro when it is actually installed', () {
      final policy = WslRuntimePolicy(
        wslAvailable: true,
        installedDistros: const <String>['Ubuntu', 'Debian'],
        defaultDistro: 'debian',
      );

      expect(policy.defaultDistro, 'Debian');
      expect(policy.resolveRequestedDistro(null), 'Debian');
    });

    test('never substitutes an explicitly requested missing distro', () {
      final policy = WslRuntimePolicy(
        wslAvailable: true,
        installedDistros: const <String>['Ubuntu'],
        defaultDistro: 'Ubuntu',
      );

      expect(policy.containsDistro('kali-linux'), isFalse);
      expect(policy.resolveRequestedDistro('kali-linux'), isEmpty);
      expect(policy.resolveRequestedDistro(null), 'Ubuntu');
      expect(policy.kaliInstalled, isFalse);
    });

    test('tracks engine availability independently from registered distros', () {
      final policy = WslRuntimePolicy(
        wslAvailable: false,
        engineAvailable: true,
        installedDistros: const <String>[],
      );

      expect(policy.engineAvailable, isTrue);
      expect(policy.wslAvailable, isFalse);
      expect(policy.hasInstalledDistros, isFalse);
      expect(policy.canStartWslSession, isFalse);
      expect(policy.defaultDistro, isEmpty);
      expect(policy.resolveRequestedDistro(null), isEmpty);
    });

    test('rejects a stale broker default that is not in the inventory', () {
      final policy = WslRuntimePolicy(
        wslAvailable: true,
        installedDistros: const <String>['Ubuntu'],
        defaultDistro: 'Debian',
      );

      expect(policy.defaultDistro, isEmpty);
      expect(policy.launchFallbackDistro, 'Ubuntu');
    });
  });
}
