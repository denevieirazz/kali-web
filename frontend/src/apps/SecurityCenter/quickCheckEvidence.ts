import { explainPort } from './portKnowledge';

type PortLike = { port: number; state: string; protocol: string; service: string; version: string };
type HostLike = { address: string; hostname: string; up: boolean; ports: PortLike[] };
type FindingLike = { id: string; severity: string; title: string; evidence: string; recommendation: string };

type ScanLike = {
  preset: string;
  label: string;
  target: string;
  distribution: string;
  hosts: HostLike[];
  completedAt: string;
  durationMs?: number;
  insights?: {
    highestSeverity?: string;
    hosts?: Array<{ address: string | null; findings?: FindingLike[] }>;
  };
};

type DiagnosticsLike = null | {
  target: string;
  identity: { reverseDns: string[]; mac: string | null; neighborState: string | null; interfaceAddress: string | null; isDefaultGateway: boolean };
  reachability: { reachable: boolean; attempts: number; replies: number; lossPercent: number | null; averageMs: number | null; minMs: number | null; maxMs: number | null; ttl: number | null };
  route: { hopCount: number; hops: Array<{ hop: number; address: string | null; averageMs: number | null; timedOut: boolean }> };
  localNetwork: { defaultGateway: string | null; dnsServers: string[] };
  nextSteps: string[];
};

export function buildQuickCheckEvidence(result: ScanLike, hostDiagnostics: DiagnosticsLike) {
  return {
    schemaVersion: 3,
    kind: 'cloudos-guided-local-check',
    purpose: 'authorized-defensive-local-network-assessment',
    generatedAt: new Date().toISOString(),
    assessment: {
      preset: result.preset,
      label: result.label,
      target: result.target,
      distribution: result.distribution,
      completedAt: result.completedAt,
      durationMs: result.durationMs ?? null,
      highestAttention: result.insights?.highestSeverity || 'info',
    },
    hostDiagnostics,
    hosts: result.hosts.map(host => ({
      address: host.address,
      hostname: host.hostname || null,
      up: host.up,
      ports: host.ports.map(port => ({
        ...port,
        explanation: explainPort(port.port, port.service),
      })),
      findings: result.insights?.hosts?.find(item => item.address === host.address)?.findings || [],
    })),
    constraints: {
      privateLocalOnly: true,
      arbitraryArguments: false,
      credentialAttacks: false,
      exploitAutomation: false,
      doNotInferVulnerabilityFromOpenPort: true,
    },
  };
}

function line(value: unknown) {
  return value === null || value === undefined || value === '' ? 'não observado' : String(value);
}

export function buildQuickCheckMarkdown(result: ScanLike, hostDiagnostics: DiagnosticsLike) {
  const evidence = buildQuickCheckEvidence(result, hostDiagnostics);
  const rows: string[] = [
    '# CloudOS — Relatório rápido de rede',
    '',
    `- **Alvo:** ${result.target}`,
    `- **Check:** ${result.label}`,
    `- **Distribuição:** ${result.distribution}`,
    `- **Coletado em:** ${result.completedAt}`,
    `- **Maior atenção:** ${result.insights?.highestSeverity || 'info'}`,
    '',
  ];

  if (hostDiagnostics) {
    rows.push(
      '## Identidade e conectividade',
      '',
      `- **Respondeu a ICMP:** ${hostDiagnostics.reachability.reachable ? 'sim' : 'não observado'}`,
      `- **Perda:** ${line(hostDiagnostics.reachability.lossPercent)}%`,
      `- **Latência média:** ${line(hostDiagnostics.reachability.averageMs)} ms`,
      `- **MAC:** ${line(hostDiagnostics.identity.mac)}`,
      `- **PTR:** ${hostDiagnostics.identity.reverseDns.length ? hostDiagnostics.identity.reverseDns.join(', ') : 'não observado'}`,
      `- **Gateway padrão:** ${hostDiagnostics.identity.isDefaultGateway ? 'sim' : 'não'}`,
      `- **Saltos observados:** ${hostDiagnostics.route.hopCount}`,
      ''
    );
  }

  for (const host of evidence.hosts) {
    rows.push(`## Host ${host.address}`, '', `- **Hostname:** ${line(host.hostname)}`, `- **Estado observado:** ${host.up ? 'respondeu' : 'sem resposta'}`, '');
    const open = host.ports.filter(port => port.state === 'open');
    if (!open.length) {
      rows.push('Nenhuma porta aberta foi observada neste preset.', '');
    } else {
      rows.push('### Portas abertas', '');
      for (const port of open) {
        rows.push(
          `- **${port.port}/${port.protocol || 'tcp'} — ${port.explanation.title}**`,
          `  - Serviço observado: ${line(port.service)} ${port.version ? `(${port.version})` : ''}`,
          `  - Significado: ${port.explanation.explanation}`,
          `  - Revisar: ${port.explanation.review}`
        );
      }
      rows.push('');
    }

    if (host.findings.length) {
      rows.push('### Pontos para revisão', '');
      for (const finding of host.findings) {
        rows.push(`- **[${finding.severity}] ${finding.title}**`, `  - Evidência: ${finding.evidence}`, `  - Recomendação: ${finding.recommendation}`);
      }
      rows.push('');
    }
  }

  if (hostDiagnostics?.nextSteps.length) {
    rows.push('## Próximos passos', '');
    hostDiagnostics.nextSteps.forEach((step, index) => rows.push(`${index + 1}. ${step}`));
    rows.push('');
  }

  rows.push('> Este relatório descreve superfície observada. Porta aberta não equivale a vulnerabilidade confirmada.');
  return rows.join('\n');
}
