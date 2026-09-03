type Finding = { id: string; severity: string; title: string; evidence: string; recommendation: string };
type Cookie = { name: string; secure: boolean; httpOnly: boolean; sameSite: string | null; domain: string | null; path: string | null; valueExposed: false };
type Inspection = {
  requestedUrl: string; finalUrl: string; resolvedAddress: string; status: number; statusMessage: string; title: string | null;
  redirects: Array<{ from: string; to: string; status: number }>;
  headers: Record<string, string>; cookies: Cookie[];
  tls: null | { protocol: string | null; cipher: string | null; subjectCommonName: string | null; issuerCommonName: string | null; issuerOrganization: string | null; validFrom: string | null; validTo: string | null; fingerprint256: string | null; subjectAltNameCount: number };
  technologies: Array<{ source: string; value: string; heuristic: boolean }>;
  findings: Finding[]; nextSteps: string[]; completedAt: string; durationMs: number;
};

export function buildQuickWebEvidence(result: Inspection) {
  return {
    schemaVersion: 1,
    kind: 'cloudos-quick-web-check',
    purpose: 'authorized-defensive-web-assessment',
    generatedAt: new Date().toISOString(),
    target: { requestedUrl: result.requestedUrl, finalUrl: result.finalUrl, resolvedAddress: result.resolvedAddress, status: result.status, title: result.title },
    tls: result.tls,
    headers: result.headers,
    cookies: result.cookies,
    redirects: result.redirects,
    technologies: result.technologies,
    findings: result.findings,
    nextSteps: result.nextSteps,
    completedAt: result.completedAt,
    durationMs: result.durationMs,
    constraints: { publicHttpHttpsOnly: true, noCrawler: true, noFuzzing: true, noCredentialAttacks: true, noExploitAutomation: true, cookieValuesExcluded: true },
  };
}

export function buildQuickWebMarkdown(result: Inspection) {
  const rows = [
    '# CloudOS — Relatório web rápido', '',
    `- **URL solicitada:** ${result.requestedUrl}`,
    `- **URL final:** ${result.finalUrl}`,
    `- **IP resolvido:** ${result.resolvedAddress}`,
    `- **HTTP:** ${result.status} ${result.statusMessage || ''}`.trim(),
    `- **Título:** ${result.title || 'não observado'}`,
    `- **Coletado em:** ${result.completedAt}`,
    '',
    '## TLS', '',
  ];
  if (result.tls) rows.push(
    `- **Protocolo:** ${result.tls.protocol || 'não observado'}`,
    `- **Cifra:** ${result.tls.cipher || 'não observada'}`,
    `- **Certificado:** ${result.tls.subjectCommonName || 'não observado'}`,
    `- **Emissor:** ${result.tls.issuerOrganization || result.tls.issuerCommonName || 'não observado'}`,
    `- **Validade:** ${result.tls.validTo || 'não observada'}`,
    `- **Fingerprint SHA-256:** ${result.tls.fingerprint256 || 'não observada'}`
  );
  else rows.push('TLS não foi observado na URL final.');

  rows.push('', '## Pontos para revisão', '');
  if (result.findings.length) result.findings.forEach(item => rows.push(`- **[${item.severity}] ${item.title}**`, `  - Evidência: ${item.evidence}`, `  - Recomendação: ${item.recommendation}`));
  else rows.push('Nenhum ponto adicional foi gerado nesta coleta.');

  rows.push('', '## Cookies observados', '');
  if (result.cookies.length) result.cookies.forEach(item => rows.push(`- **${item.name}** — Secure: ${item.secure ? 'sim' : 'não'} · HttpOnly: ${item.httpOnly ? 'sim' : 'não'} · SameSite: ${item.sameSite || 'não observado'}`));
  else rows.push('Nenhum Set-Cookie foi observado.');

  rows.push('', '## Próximos passos', '');
  result.nextSteps.forEach((step, index) => rows.push(`${index + 1}. ${step}`));
  rows.push('', '> Coleta limitada a metadata HTTP/TLS. Ausência de finding não equivale a certificação de segurança.');
  return rows.join('\n');
}
