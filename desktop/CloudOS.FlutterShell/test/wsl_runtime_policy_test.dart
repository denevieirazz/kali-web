import 'package:cloudos_flutter_shell/features/terminal/domain/wsl_runtime_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WslRuntimePolicy', () {
    test('normalizes duplicate distro names and preserves canonical spelling', () {
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
      expect(policy.defaultDistro, 'Ubuntu');
      expect(policy.preferredSecurityDistro, 'kali-linux');
      expect(policy.kaliInstalled, isTrue);
    });

    test('uses broker default distro when it is installed', () {
      final policy = WslRuntimePolicy(
        wslAvailable: true,
        installedDistros: const <String>['Ubuntu', 'Debian'],
        defaultDistro: 'debian',
      );

      expect(policy.defaultDistro, 'Debian');
      expect(policy.resolveRequestedDistro(null), 'Debian');
    });

    test('does not accept a requested distro that is not installed', () {
      final policy = WslRuntimePolicy(
        wslAvailable: true,
        installedDistros: const <String>['Ubuntu'],
        defaultDistro: 'Ubuntu',
      );

      expect(policy.containsDistro('kali-linux'), isFalse);
      expect(policy.resolveRequestedDistro('kali-linux'), 'Ubuntu');
      expect(policy.kaliInstalled, isFalse);
    });

    test('reports no usable distro when WSL has none registered', () {
      final policy = WslRuntimePolicy(
        wslAvailable: true,
        installedDistros: const <String>[],
      );

      expect(policy.hasInstalledDistros, isFalse);
      expect(policy.defaultDistro, isEmpty);
      expect(policy.resolveRequestedDistro(null), isEmpty);
    });
  });
}
