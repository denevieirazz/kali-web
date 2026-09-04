import '../../../models/cloud_wsl_health_probe.dart';
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
  activeProbeHealthy,
  activeProbeFailed,
  activeProbeTimedOut,
  activeProbeTargetInvalid,
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
    this.activeProbe,
  });

  factory WslRuntimeDiagnostics.evaluate(
    WslRuntimePolicy policy, {
    CloudWslHealthProbeResult? activeProbe,
  }) {
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
        activeProbe: activeProbe,
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
        activeProbe: activeProbe,
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

    if (knownWsl1Count > 0 &&
        knownWsl2Count == 0 &&
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

    final probeTarget = activeProbe?.distro.trim() ?? '';
    final probeTargetInstalled =
        probeTarget.isNotEmpty && policy.containsDistro(probeTarget);
    final probeTargetsKali = probeTargetInstalled && WslRuntimePolicy.isKali(probeTarget);
    final probeCoversSecurityRuntime =
        probeTargetsKali &&
        policy.preferredSecurityDistro.isNotEmpty &&
        probeTarget.toLowerCase() == policy.preferredSecurityDistro.toLowerCase();

    if (activeProbe != null && !probeTargetInstalled) {
      issues.add(
        WslDiagnosticIssue(
          code: WslDiagnosticCode.activeProbeTargetInvalid,
          severity: WslDiagnosticSeverity.warning,
          distro: probeTarget,
          message: 'O resultado do probe ativo não corresponde a uma distro atualmente registrada.',
        ),
      );
    } else if (activeProbe != null && activeProbe.healthy) {
      issues.add(
        WslDiagnosticIssue(
          code: WslDiagnosticCode.activeProbeHealthy,
          severity: WslDiagnosticSeverity.info,
          distro: probeTarget,
          message:
              'Probe ativo de $probeTarget comprovou boot, comando fixo, marcador e exit code 0 em ${activeProbe.durationMs} ms.',
        ),
      );
    } else if (activeProbe != null && activeProbe.timedOut) {
      issues.add(
        WslDiagnosticIssue(
          code: WslDiagnosticCode.activeProbeTimedOut,
          severity: WslDiagnosticSeverity.error,
          distro: probeTarget,
          message: 'O probe ativo de $probeTarget excedeu o tempo limite.',
        ),
      );
    } else if (activeProbe != null && activeProbe.attempted) {
      issues.add(
        WslDiagnosticIssue(
          code: WslDiagnosticCode.activeProbeFailed,
          severity: WslDiagnosticSeverity.error,
          distro: probeTarget,
          message: activeProbe.errorMessage.isNotEmpty
              ? 'O probe ativo de $probeTarget falhou: ${activeProbe.errorMessage}'
              : 'O probe ativo de $probeTarget falhou.',
        ),
      );
    }

    final needsGenericProbe = activeProbe == null ||
        !probeTargetInstalled ||
        !activeProbe.healthy;
    final needsSecurityProbe =
        policy.kaliPassiveReady &&
        !(activeProbe?.healthy == true && probeCoversSecurityRuntime);

    if ((policy.passiveReady || policy.canStartWslSession) &&
        (needsGenericProbe || needsSecurityProbe)) {
      issues.add(
        WslDiagnosticIssue(
          code: WslDiagnosticCode.activeProbeRequired,
          severity: WslDiagnosticSeverity.info,
          distro: needsSecurityProbe ? policy.preferredSecurityDistro : '',
          message: needsSecurityProbe
              ? 'Kali possui evidência passiva, mas ainda precisa de probe ativo próprio antes de ser tratada como backend saudável.'
              : 'A evidência passiva não substitui um probe ativo de boot/comando/saída.',
        ),
      );
    }

    String summary;
    if (activeProbe?.timedOut == true && probeTargetInstalled) {
      summary = '$probeTarget • probe ativo em timeout';
    } else if (activeProbe?.attempted == true &&
        activeProbe?.healthy != true &&
        probeTargetInstalled) {
      summary = '$probeTarget • probe ativo falhou';
    } else if (activeProbe?.healthy == true && probeTargetInstalled) {
      if (probeCoversSecurityRuntime && policy.kaliPassiveReady) {
        summary = '$probeTarget • backend de segurança saudável';
      } else if (needsSecurityProbe) {
        summary = '$probeTarget saudável • Kali ainda requer probe';
      } else {
        summary = '$probeTarget • runtime Linux saudável';
      }
    } else {
      summary = switch (policy.readiness) {
        WslRuntimeReadiness.unavailable => 'WSL indisponível',
        WslRuntimeReadiness.engineOnly => 'WSL sem distribuição',
        WslRuntimeReadiness.registeredUnknown => 'Linux registrado • health não comprovado',
        WslRuntimeReadiness.passiveReady => 'Linux passivamente disponível',
        WslRuntimeReadiness.wsl2Ready => 'WSL2 passivamente disponível',
        WslRuntimeReadiness.securityReady => 'Kali/WSL2 candidata • probe ativo pendente',
      };
    }

    return WslRuntimeDiagnostics._(
      policy: policy,
      issues: List<WslDiagnosticIssue>.unmodifiable(issues),
      summary: summary,
      activeProbe: activeProbe,
    );
  }

  final WslRuntimePolicy policy;
  final List<WslDiagnosticIssue> issues;
  final String summary;
  final CloudWslHealthProbeResult? activeProbe;

  bool get hasErrors =>
      issues.any((issue) => issue.severity == WslDiagnosticSeverity.error);
  bool get hasWarnings =>
      issues.any((issue) => issue.severity == WslDiagnosticSeverity.warning);
  bool get hasHealthyActiveProbe => activeProbe?.healthy == true;

  Iterable<WslDiagnosticIssue> issuesFor(String distro) {
    final wanted = distro.trim().toLowerCase();
    return issues.where(
      (issue) => issue.distro.isNotEmpty && issue.distro.toLowerCase() == wanted,
    );
  }

  bool contains(WslDiagnosticCode code) =>
      issues.any((issue) => issue.code == code);
}
