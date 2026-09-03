import 'wsl_runtime_policy.dart';

enum WslDiagnosticSeverity { info, warning, error }

enum WslDiagnosticCode {
  engineUnavailable,
  noRegisteredDistro,
  distroStorageMissing,
  distroStorageUnknown,
  distroVersionUnknown,
  wsl1Only,
  kaliMissing,
  kaliVersionUnknown,
  kaliWsl1,
  kaliStorageMissing,
  kaliStorageUnknown,
  activeProbeRequired,
}

class WslDiagnosticIssue {
  const WslDiagnosticIssue({
    required this.code,
    required this.severity,
    required this.message,
    this.distro = '',
  });

  final WslDiagnosticCode code;
  final WslDiagnosticSeverity severity;
  final String message;
  final String distro;
}

class WslRuntimeDiagnostics {
  const WslRuntimeDiagnostics._({
    required this.policy,
    required this.issues,
    required this.summary,
  });

  factory WslRuntimeDiagnostics.evaluate(WslRuntimePolicy policy) {
    final issues = <WslDiagnosticIssue>[];

    if (!policy.engineAvailable) {
      issues.add(
        const WslDiagnosticIssue(
          code: WslDiagnosticCode.engineUnavailable,
          severity: WslDiagnosticSeverity.error,
          message: 'O mecanismo WSL não foi detectado no Windows.',
        ),
      );
      return WslRuntimeDiagnostics._(
        policy: policy,
        issues: List<WslDiagnosticIssue>.unmodifiable(issues),
        summary: 'WSL indisponível',
      );
    }

    if (!policy.hasInstalledDistros) {
      issues.add(
        const WslDiagnosticIssue(
          code: WslDiagnosticCode.noRegisteredDistro,
          severity: WslDiagnosticSeverity.error,
          message: 'WSL existe, mas nenhuma distribuição Linux está registrada.',
        ),
      );
      issues.add(
        const WslDiagnosticIssue(
          code: WslDiagnosticCode.kaliMissing,
          severity: WslDiagnosticSeverity.warning,
          message: 'Kali Linux não está instalada.',
        ),
      );
      return WslRuntimeDiagnostics._(
        policy: policy,
        issues: List<WslDiagnosticIssue>.unmodifiable(issues),
        summary: 'WSL sem distribuição',
      );
    }

    var knownWsl1Count = 0;
    var knownWsl2Count = 0;
    for (final distro in policy.installedDistros) {
      final version = policy.versionFor(distro);
      final storage = policy.storageFor(distro);

      if (version == 1) {
        knownWsl1Count++;
      } else if (version == 2) {
        knownWsl2Count++;
      } else {
        issues.add(
          WslDiagnosticIssue(
            code: WslDiagnosticCode.distroVersionUnknown,
            severity: WslDiagnosticSeverity.info,
            distro: distro,
            message: 'A geração WSL de $distro não foi comprovada.',
          ),
        );
      }

      if (storage == false) {
        issues.add(
          WslDiagnosticIssue(
            code: WslDiagnosticCode.distroStorageMissing,
            severity: WslDiagnosticSeverity.error,
            distro: distro,
            message: 'O armazenamento registrado de $distro não foi encontrado.',
          ),
        );
      } else if (storage == null) {
        issues.add(
          WslDiagnosticIssue(
            code: WslDiagnosticCode.distroStorageUnknown,
            severity: WslDiagnosticSeverity.info,
            distro: distro,
            message: 'O bridge ainda não publicou evidência de armazenamento para $distro.',
          ),
        );
      }
    }

    if (knownWsl1Count > 0 && knownWsl2Count == 0 &&
        policy.installedDistros.every((distro) => policy.versionFor(distro) != 0)) {
      issues.add(
        const WslDiagnosticIssue(
          code: WslDiagnosticCode.wsl1Only,
          severity: WslDiagnosticSeverity.warning,
          message: 'Todas as distribuições com versão conhecida estão em WSL1.',
        ),
      );
    }

    if (!policy.kaliInstalled) {
      issues.add(
        const WslDiagnosticIssue(
          code: WslDiagnosticCode.kaliMissing,
          severity: WslDiagnosticSeverity.warning,
          message: 'Kali Linux não está instalada; o runtime de segurança permanece indisponível.',
        ),
      );
    } else {
      final kali = policy.preferredSecurityDistro;
      final kaliVersion = policy.versionFor(kali);
      final kaliStorage = policy.storageFor(kali);
      if (kaliVersion == 0) {
        issues.add(
          WslDiagnosticIssue(
            code: WslDiagnosticCode.kaliVersionUnknown,
            severity: WslDiagnosticSeverity.warning,
            distro: kali,
            message: 'Kali foi detectada, mas sua geração WSL não foi comprovada.',
          ),
        );
      } else if (kaliVersion == 1) {
        issues.add(
          WslDiagnosticIssue(
            code: WslDiagnosticCode.kaliWsl1,
            severity: WslDiagnosticSeverity.error,
            distro: kali,
            message: 'Kali está em WSL1; o backend de segurança exige WSL2.',
          ),
        );
      }

      if (kaliStorage == false) {
        issues.add(
          WslDiagnosticIssue(
            code: WslDiagnosticCode.kaliStorageMissing,
            severity: WslDiagnosticSeverity.error,
            distro: kali,
            message: 'Kali está registrada, mas seu armazenamento não foi encontrado.',
          ),
        );
      } else if (kaliStorage == null) {
        issues.add(
          WslDiagnosticIssue(
            code: WslDiagnosticCode.kaliStorageUnknown,
            severity: WslDiagnosticSeverity.info,
            distro: kali,
            message: 'O armazenamento da Kali ainda não foi comprovado pelo bridge.',
          ),
        );
      }
    }

    // Passive readiness is deliberately not the same thing as an active Linux
    // health check. A real probe must still prove boot + command + stdout.
    if (policy.passiveReady || policy.canStartWslSession) {
      issues.add(
        const WslDiagnosticIssue(
          code: WslDiagnosticCode.activeProbeRequired,
          severity: WslDiagnosticSeverity.info,
          message: 'A evidência passiva não substitui um probe ativo de boot/comando/saída.',
        ),
      );
    }

    final summary = switch (policy.readiness) {
      WslRuntimeReadiness.unavailable => 'WSL indisponível',
      WslRuntimeReadiness.engineOnly => 'WSL sem distribuição',
      WslRuntimeReadiness.registeredUnknown => 'Linux registrado • health não comprovado',
      WslRuntimeReadiness.passiveReady => 'Linux passivamente disponível',
      WslRuntimeReadiness.wsl2Ready => 'WSL2 passivamente disponível',
      WslRuntimeReadiness.securityReady => 'Kali/WSL2 candidata • probe ativo pendente',
    };

    return WslRuntimeDiagnostics._(
      policy: policy,
      issues: List<WslDiagnosticIssue>.unmodifiable(issues),
      summary: summary,
    );
  }

  final WslRuntimePolicy policy;
  final List<WslDiagnosticIssue> issues;
  final String summary;

  bool get hasErrors =>
      issues.any((issue) => issue.severity == WslDiagnosticSeverity.error);
  bool get hasWarnings =>
      issues.any((issue) => issue.severity == WslDiagnosticSeverity.warning);

  Iterable<WslDiagnosticIssue> issuesFor(String distro) {
    final wanted = distro.trim().toLowerCase();
    return issues.where(
      (issue) => issue.distro.isNotEmpty && issue.distro.toLowerCase() == wanted,
    );
  }

  bool contains(WslDiagnosticCode code) =>
      issues.any((issue) => issue.code == code);
}
