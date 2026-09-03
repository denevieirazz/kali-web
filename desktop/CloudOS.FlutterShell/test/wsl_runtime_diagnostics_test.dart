import 'package:cloudos_flutter_shell/features/terminal/domain/wsl_runtime_diagnostics.dart';
import 'package:cloudos_flutter_shell/features/terminal/domain/wsl_runtime_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WslRuntimeDiagnostics', () {
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
}
