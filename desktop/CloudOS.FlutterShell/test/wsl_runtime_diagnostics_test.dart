import 'package:cloudos_flutter_shell/features/terminal/domain/wsl_runtime_diagnostics.dart';
import 'package:cloudos_flutter_shell/features/terminal/domain/wsl_runtime_policy.dart';
import 'package:cloudos_flutter_shell/models/cloud_wsl_health_probe.dart';
import 'package:flutter_test/flutter_test.dart';

CloudWslHealthProbeResult probe({
  required String distro,
  bool attempted = true,
  bool healthy = true,
  bool timedOut = false,
  bool markerSeen = true,
  int exitCode = 0,
  int durationMs = 125,
  String errorCode = '',
  String errorMessage = '',
}) {
  return CloudWslHealthProbeResult(
    distro: distro,
    attempted: attempted,
    healthy: healthy,
    timedOut: timedOut,
    markerSeen: markerSeen,
    exitCode: exitCode,
    durationMs: durationMs,
    output: markerSeen ? 'CLOUDOS_WSL_HEALTH_V22\n' : '',
    errorCode: errorCode,
    errorMessage: errorMessage,
  );
}

void main() {
  group('WslRuntimeDiagnostics passive evidence', () {
    test('reports engine unavailable without pretending distro state', () {
      final diagnostics = WslRuntimeDiagnostics.evaluate(
        WslRuntimePolicy(
          wslAvailable: false,
          engineAvailable: false,
          installedDistros: const <String>[],
        ),
      );

      expect(diagnostics.summary, 'WSL indisponível');
      expect(diagnostics.hasErrors, isTrue);
      expect(diagnostics.contains(WslDiagnosticCode.engineUnavailable), isTrue);
      expect(diagnostics.contains(WslDiagnosticCode.activeProbeRequired), isFalse);
    });

    test('reports engine-only install and Kali missing', () {
      final diagnostics = WslRuntimeDiagnostics.evaluate(
        WslRuntimePolicy(
          wslAvailable: false,
          engineAvailable: true,
          installedDistros: const <String>[],
        ),
      );

      expect(diagnostics.summary, 'WSL sem distribuição');
      expect(diagnostics.contains(WslDiagnosticCode.noRegisteredDistro), isTrue);
      expect(diagnostics.contains(WslDiagnosticCode.kaliMissing), isTrue);
    });

    test('keeps old bridge storage/version evidence explicitly unknown', () {
      final diagnostics = WslRuntimeDiagnostics.evaluate(
        WslRuntimePolicy(
          wslAvailable: true,
          engineAvailable: true,
          installedDistros: const <String>['Ubuntu'],
          defaultDistro: 'Ubuntu',
        ),
      );

      expect(
        diagnostics.contains(WslDiagnosticCode.distroStorageUnknown),
        isTrue,
      );
      expect(
        diagnostics.contains(WslDiagnosticCode.distroVersionUnknown),
        isTrue,
      );
      expect(diagnostics.contains(WslDiagnosticCode.kaliMissing), isTrue);
      expect(
        diagnostics.contains(WslDiagnosticCode.activeProbeRequired),
        isTrue,
      );
      expect(
        diagnostics.summary,
        'Linux registrado • health não comprovado',
      );
    });

    test('reports stale distro storage as error', () {
      final diagnostics = WslRuntimeDiagnostics.evaluate(
        WslRuntimePolicy(
          wslAvailable: true,
          engineAvailable: true,
          installedDistros: const <String>['Ubuntu'],
          distroVersions: const <String, int>{'Ubuntu': 2},
          distroStorageEvidence: const <String, bool>{'Ubuntu': false},
        ),
      );

      expect(diagnostics.hasErrors, isTrue);
      expect(
        diagnostics.contains(WslDiagnosticCode.distroStorageMissing),
        isTrue,
      );
      expect(diagnostics.issuesFor('ubuntu'), isNotEmpty);
    });

    test('warns when all known distros are WSL1', () {
      final diagnostics = WslRuntimeDiagnostics.evaluate(
        WslRuntimePolicy(
          wslAvailable: true,
          engineAvailable: true,
          installedDistros: const <String>['Ubuntu', 'Debian'],
          distroVersions: const <String, int>{'Ubuntu': 1, 'Debian': 1},
          distroStorageEvidence: const <String, bool>{
            'Ubuntu': true,
            'Debian': true,
          },
        ),
      );

      expect(diagnostics.contains(WslDiagnosticCode.wsl1Only), isTrue);
      expect(diagnostics.hasWarnings, isTrue);
    });

    test('does not call Kali ready when generation is unknown', () {
      final diagnostics = WslRuntimeDiagnostics.evaluate(
        WslRuntimePolicy(
          wslAvailable: true,
          engineAvailable: true,
          installedDistros: const <String>['kali-linux'],
          distroStorageEvidence: const <String, bool>{'kali-linux': true},
        ),
      );

      expect(
        diagnostics.contains(WslDiagnosticCode.kaliVersionUnknown),
        isTrue,
      );
      expect(diagnostics.policy.kaliPassiveReady, isFalse);
    });

    test('rejects Kali on WSL1 as security runtime', () {
      final diagnostics = WslRuntimeDiagnostics.evaluate(
        WslRuntimePolicy(
          wslAvailable: true,
          engineAvailable: true,
          installedDistros: const <String>['kali-linux'],
          distroVersions: const <String, int>{'kali-linux': 1},
          distroStorageEvidence: const <String, bool>{'kali-linux': true},
        ),
      );

      expect(diagnostics.contains(WslDiagnosticCode.kaliWsl1), isTrue);
      expect(diagnostics.hasErrors, isTrue);
    });

    test('security candidate still requires active probe', () {
      final diagnostics = WslRuntimeDiagnostics.evaluate(
        WslRuntimePolicy(
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
        ),
      );

      expect(diagnostics.policy.kaliPassiveReady, isTrue);
      expect(
        diagnostics.summary,
        'Kali/WSL2 candidata • probe ativo pendente',
      );
      expect(
        diagnostics.contains(WslDiagnosticCode.activeProbeRequired),
        isTrue,
      );
      expect(diagnostics.hasErrors, isFalse);
    });
  });

  group('WslRuntimeDiagnostics active probe', () {
    final genericPolicy = WslRuntimePolicy(
      wslAvailable: true,
      engineAvailable: true,
      installedDistros: const <String>['Ubuntu'],
      defaultDistro: 'Ubuntu',
      distroVersions: const <String, int>{'Ubuntu': 2},
      distroStorageEvidence: const <String, bool>{'Ubuntu': true},
    );

    final securityPolicy = WslRuntimePolicy(
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

    test('promotes a healthy generic probe to active Linux health', () {
      final diagnostics = WslRuntimeDiagnostics.evaluate(
        genericPolicy,
        activeProbe: probe(distro: 'Ubuntu', durationMs: 88),
      );

      expect(diagnostics.hasHealthyActiveProbe, isTrue);
      expect(diagnostics.contains(WslDiagnosticCode.activeProbeHealthy), isTrue);
      expect(diagnostics.contains(WslDiagnosticCode.activeProbeRequired), isFalse);
      expect(diagnostics.summary, 'Ubuntu • runtime Linux saudável');
      expect(diagnostics.hasErrors, isFalse);
    });

    test('healthy Ubuntu does not prove Kali security runtime', () {
      final diagnostics = WslRuntimeDiagnostics.evaluate(
        securityPolicy,
        activeProbe: probe(distro: 'Ubuntu'),
      );

      expect(diagnostics.hasHealthyActiveProbe, isTrue);
      expect(diagnostics.contains(WslDiagnosticCode.activeProbeHealthy), isTrue);
      expect(diagnostics.contains(WslDiagnosticCode.activeProbeRequired), isTrue);
      expect(diagnostics.summary, 'Ubuntu saudável • Kali ainda requer probe');
      expect(
        diagnostics.issues
            .where((issue) => issue.code == WslDiagnosticCode.activeProbeRequired)
            .single
            .distro,
        'kali-linux',
      );
    });

    test('healthy Kali probe proves the selected security runtime', () {
      final diagnostics = WslRuntimeDiagnostics.evaluate(
        securityPolicy,
        activeProbe: probe(distro: 'kali-linux', durationMs: 240),
      );

      expect(diagnostics.hasHealthyActiveProbe, isTrue);
      expect(diagnostics.contains(WslDiagnosticCode.activeProbeHealthy), isTrue);
      expect(diagnostics.contains(WslDiagnosticCode.activeProbeRequired), isFalse);
      expect(diagnostics.summary, 'kali-linux • backend de segurança saudável');
      expect(diagnostics.hasErrors, isFalse);
    });

    test('timeout is an active health error and is never promoted', () {
      final diagnostics = WslRuntimeDiagnostics.evaluate(
        genericPolicy,
        activeProbe: probe(
          distro: 'Ubuntu',
          healthy: false,
          timedOut: true,
          markerSeen: false,
          exitCode: -1,
          errorCode: 'wsl_probe_timeout',
          errorMessage: 'deadline exceeded',
        ),
      );

      expect(diagnostics.hasHealthyActiveProbe, isFalse);
      expect(diagnostics.contains(WslDiagnosticCode.activeProbeTimedOut), isTrue);
      expect(diagnostics.hasErrors, isTrue);
      expect(diagnostics.summary, 'Ubuntu • probe ativo em timeout');
    });

    test('non-timeout active failure remains an error', () {
      final diagnostics = WslRuntimeDiagnostics.evaluate(
        genericPolicy,
        activeProbe: probe(
          distro: 'Ubuntu',
          healthy: false,
          markerSeen: false,
          exitCode: 1,
          errorCode: 'wsl_probe_nonzero_exit',
          errorMessage: 'non-zero exit',
        ),
      );

      expect(diagnostics.contains(WslDiagnosticCode.activeProbeFailed), isTrue);
      expect(diagnostics.hasErrors, isTrue);
      expect(diagnostics.summary, 'Ubuntu • probe ativo falhou');
    });

    test('stale probe target is rejected against current inventory', () {
      final diagnostics = WslRuntimeDiagnostics.evaluate(
        genericPolicy,
        activeProbe: probe(distro: 'Debian'),
      );

      expect(
        diagnostics.contains(WslDiagnosticCode.activeProbeTargetInvalid),
        isTrue,
      );
      expect(diagnostics.contains(WslDiagnosticCode.activeProbeRequired), isTrue);
      expect(diagnostics.summary, isNot(contains('Debian • runtime Linux saudável')));
    });
  });
}
