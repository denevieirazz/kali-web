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
      expect(policy.kaliPassiveReady, isFalse);
      expect(policy.readiness, WslRuntimeReadiness.registeredUnknown);
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

      final plan = policy.planSession(requestedDistro: 'kali-linux');
      expect(plan.allowed, isFalse);
      expect(plan.reason, 'WSL_DISTRO_NOT_INSTALLED');
      expect(plan.distro, 'kali-linux');
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
      expect(policy.readiness, WslRuntimeReadiness.engineOnly);
      expect(
        policy.planSession().reason,
        'WSL_NO_REGISTERED_DISTRO',
      );
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
      expect(
        unknown.statusLabelFor('kali-linux'),
        'kali-linux • Security • WSL ?',
      );

      final wsl1 = WslRuntimePolicy(
        wslAvailable: true,
        engineAvailable: true,
        installedDistros: const <String>['kali-linux'],
        distroVersions: const <String, int>{'KALI-LINUX': 1},
      );
      expect(wsl1.kaliWsl2Ready, isFalse);
      expect(
        wsl1.statusLabelFor('kali-linux'),
        'kali-linux • Security • WSL1',
      );

      final wsl2 = WslRuntimePolicy(
        wslAvailable: true,
        engineAvailable: true,
        installedDistros: const <String>['kali-linux'],
        defaultDistro: 'kali-linux',
        distroVersions: const <String, int>{'kali-linux': 2},
      );
      expect(wsl2.kaliWsl2Ready, isTrue);
      expect(wsl2.kaliPassiveReady, isFalse);
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

    test('treats explicit missing storage as a hard launch blocker', () {
      final policy = WslRuntimePolicy(
        wslAvailable: true,
        engineAvailable: true,
        installedDistros: const <String>['Ubuntu'],
        defaultDistro: 'Ubuntu',
        distroVersions: const <String, int>{'Ubuntu': 2},
        distroStorageEvidence: const <String, bool>{'Ubuntu': false},
      );

      expect(policy.storageFor('ubuntu'), isFalse);
      expect(policy.canStartWslSession, isFalse);
      expect(policy.launchFallbackDistro, isEmpty);
      expect(policy.passiveReadinessKnown, isTrue);
      expect(policy.passiveReady, isFalse);
      expect(policy.readiness, WslRuntimeReadiness.registeredUnknown);

      final plan = policy.planSession(requestedDistro: 'Ubuntu');
      expect(plan.allowed, isFalse);
      expect(plan.reason, 'WSL_DISTRO_STORAGE_MISSING');
      expect(plan.storageEvidence, isFalse);
    });

    test('preserves legacy launch compatibility when storage evidence is absent', () {
      final policy = WslRuntimePolicy(
        wslAvailable: true,
        engineAvailable: true,
        installedDistros: const <String>['Ubuntu'],
        defaultDistro: 'Ubuntu',
      );

      expect(policy.storageFor('Ubuntu'), isNull);
      expect(policy.canStartWslSession, isTrue);
      final plan = policy.planSession();
      expect(plan.allowed, isTrue);
      expect(plan.distro, 'Ubuntu');
      expect(plan.storageEvidence, isNull);
      expect(plan.reason, 'LEGACY_STORAGE_EVIDENCE_UNKNOWN');
    });

    test('marks generic passive WSL2 runtime ready only with storage evidence', () {
      final policy = WslRuntimePolicy(
        wslAvailable: true,
        engineAvailable: true,
        installedDistros: const <String>['Ubuntu'],
        distroVersions: const <String, int>{'Ubuntu': 2},
        distroStorageEvidence: const <String, bool>{'Ubuntu': true},
      );

      expect(policy.passiveReady, isTrue);
      expect(policy.launchCandidateCount, 1);
      expect(policy.readiness, WslRuntimeReadiness.wsl2Ready);
      expect(
        policy.statusLabelFor('Ubuntu'),
        'Ubuntu • WSL2 • Storage ✓',
      );
    });

    test('requires proven WSL2 for strict WSL2 sessions', () {
      final unknown = WslRuntimePolicy(
        wslAvailable: true,
        engineAvailable: true,
        installedDistros: const <String>['Ubuntu'],
        distroStorageEvidence: const <String, bool>{'Ubuntu': true},
      );
      final unknownPlan = unknown.planSession(
        requirement: WslSessionRequirement.wsl2,
      );
      expect(unknownPlan.allowed, isFalse);
      expect(unknownPlan.reason, 'WSL_VERSION_UNKNOWN');

      final wsl1 = WslRuntimePolicy(
        wslAvailable: true,
        engineAvailable: true,
        installedDistros: const <String>['Ubuntu'],
        distroVersions: const <String, int>{'Ubuntu': 1},
        distroStorageEvidence: const <String, bool>{'Ubuntu': true},
      );
      expect(
        wsl1.planSession(requirement: WslSessionRequirement.wsl2).reason,
        'WSL2_REQUIRED',
      );

      final wsl2 = WslRuntimePolicy(
        wslAvailable: true,
        engineAvailable: true,
        installedDistros: const <String>['Ubuntu'],
        distroVersions: const <String, int>{'Ubuntu': 2},
        distroStorageEvidence: const <String, bool>{'Ubuntu': true},
      );
      expect(
        wsl2.planSession(requirement: WslSessionRequirement.wsl2).allowed,
        isTrue,
      );
    });

    test('security session requires Kali plus WSL2 plus storage', () {
      final noKali = WslRuntimePolicy(
        wslAvailable: true,
        engineAvailable: true,
        installedDistros: const <String>['Ubuntu'],
        distroVersions: const <String, int>{'Ubuntu': 2},
        distroStorageEvidence: const <String, bool>{'Ubuntu': true},
      );
      expect(
        noKali.planSession(requirement: WslSessionRequirement.security).reason,
        'KALI_NOT_INSTALLED',
      );

      final kaliUnknownStorage = WslRuntimePolicy(
        wslAvailable: true,
        engineAvailable: true,
        installedDistros: const <String>['kali-linux'],
        distroVersions: const <String, int>{'kali-linux': 2},
      );
      expect(
        kaliUnknownStorage
            .planSession(requirement: WslSessionRequirement.security)
            .reason,
        'KALI_STORAGE_NOT_PROVEN',
      );

      final kaliReady = WslRuntimePolicy(
        wslAvailable: true,
        engineAvailable: true,
        installedDistros: const <String>['Ubuntu', 'kali-linux'],
        defaultDistro: 'Ubuntu',
        distroVersions: const <String, int>{'Ubuntu': 2, 'kali-linux': 2},
        distroStorageEvidence: const <String, bool>{
          'Ubuntu': true,
          'kali-linux': true,
        },
        preferredSecurityDistro: 'kali-linux',
      );

      final plan = kaliReady.planSession(
        requirement: WslSessionRequirement.security,
      );
      expect(plan.allowed, isTrue);
      expect(plan.distro, 'kali-linux');
      expect(plan.version, 2);
      expect(plan.storageEvidence, isTrue);
      expect(kaliReady.kaliPassiveReady, isTrue);
      expect(kaliReady.readiness, WslRuntimeReadiness.securityReady);
    });

    test('rejects malicious or stale broker security candidate names', () {
      final policy = WslRuntimePolicy(
        wslAvailable: true,
        engineAvailable: true,
        installedDistros: const <String>['Ubuntu', 'kali-linux'],
        distroVersions: const <String, int>{'kali-linux': 2},
        distroStorageEvidence: const <String, bool>{'kali-linux': true},
        preferredSecurityDistro: 'Ubuntu',
      );

      expect(policy.brokerPreferredSecurityDistro, isEmpty);
      expect(policy.preferredSecurityDistro, 'kali-linux');
    });

    test('falls back around a default distro with explicitly missing storage', () {
      final policy = WslRuntimePolicy(
        wslAvailable: true,
        engineAvailable: true,
        installedDistros: const <String>['Ubuntu', 'Debian'],
        defaultDistro: 'Ubuntu',
        distroStorageEvidence: const <String, bool>{
          'Ubuntu': false,
          'Debian': true,
        },
      );

      expect(policy.defaultDistro, 'Ubuntu');
      expect(policy.launchFallbackDistro, 'Debian');
      expect(policy.resolveRequestedDistro(null), 'Debian');
      expect(policy.resolveRequestedDistro('Ubuntu'), isEmpty);
      expect(policy.resolveRequestedDistro('Debian'), 'Debian');
    });
  });
}
