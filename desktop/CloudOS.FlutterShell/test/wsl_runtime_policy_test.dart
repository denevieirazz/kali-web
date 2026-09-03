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
      expect(policy.kaliWsl2Ready, isFalse);
    });

    test('uses broker default distro when it is actually installed', () {
      final policy = WslRuntimePolicy(
        wslAvailable: true,
        installedDistros: const <String>['Ubuntu', 'Debian'],
        defaultDistro: 'debian',
        distroVersions: const <String, int>{'Ubuntu': 2, 'Debian': 2},
      );

      expect(policy.defaultDistro, 'Debian');
      expect(policy.resolveRequestedDistro(null), 'Debian');
      expect(policy.versionFor('debian'), 2);
      expect(policy.hasWsl2Distros, isTrue);
    });

    test('never substitutes an explicitly requested missing distro', () {
      final policy = WslRuntimePolicy(
        wslAvailable: true,
        installedDistros: const <String>['Ubuntu'],
        defaultDistro: 'Ubuntu',
        distroVersions: const <String, int>{'Ubuntu': 2},
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

    test('does not promote Kali to security-ready until WSL2 is proven', () {
      final unknown = WslRuntimePolicy(
        wslAvailable: true,
        engineAvailable: true,
        installedDistros: const <String>['kali-linux'],
      );
      expect(unknown.kaliInstalled, isTrue);
      expect(unknown.kaliWsl2Ready, isFalse);
      expect(unknown.preferredSecurityWsl2Distro, isEmpty);
      expect(unknown.statusLabelFor('kali-linux'), 'kali-linux • Security • WSL ?');

      final wsl1 = WslRuntimePolicy(
        wslAvailable: true,
        engineAvailable: true,
        installedDistros: const <String>['kali-linux'],
        distroVersions: const <String, int>{'KALI-LINUX': 1},
      );
      expect(wsl1.kaliWsl2Ready, isFalse);
      expect(wsl1.statusLabelFor('kali-linux'), 'kali-linux • Security • WSL1');

      final wsl2 = WslRuntimePolicy(
        wslAvailable: true,
        engineAvailable: true,
        installedDistros: const <String>['kali-linux'],
        defaultDistro: 'kali-linux',
        distroVersions: const <String, int>{'kali-linux': 2},
      );
      expect(wsl2.kaliWsl2Ready, isTrue);
      expect(wsl2.preferredSecurityWsl2Distro, 'kali-linux');
      expect(
        wsl2.statusLabelFor('kali-linux'),
        'kali-linux • Security • Default • WSL2',
      );
    });

    test('ignores impossible distro version values instead of guessing', () {
      final policy = WslRuntimePolicy(
        wslAvailable: true,
        installedDistros: const <String>['Ubuntu'],
        distroVersions: const <String, int>{'Ubuntu': 99},
      );

      expect(policy.versionFor('Ubuntu'), 0);
      expect(policy.hasWsl2Distros, isFalse);
      expect(policy.statusLabelFor('Ubuntu'), 'Ubuntu • WSL ?');
    });
  });
}
