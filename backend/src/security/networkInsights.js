const ATTENTION_RULES = Object.freeze([
  { ports: [21], services: ['ftp'], severity: 'medium', title: 'FTP exposto', why: 'FTP costuma transmitir credenciais e dados sem proteção quando não há TLS.', recommendation: 'Confirme se o serviço é necessário e prefira SFTP/FTPS ou restrição por firewall.' },
  { ports: [23], services: ['telnet'], severity: 'high', title: 'Telnet exposto', why: 'Telnet não protege a sessão com criptografia.', recommendation: 'Desative Telnet quando possível e use SSH em redes administradas.' },
  { ports: [69], services: ['tftp'], severity: 'medium', title: 'TFTP exposto', why: 'TFTP é um protocolo simples e normalmente não possui autenticação forte.', recommendation: 'Restrinja o serviço à rede de gerenciamento e valide se ele ainda é necessário.' },
  { ports: [139, 445], services: ['netbios-ssn', 'microsoft-ds', 'smb'], severity: 'medium', title: 'Compartilhamento SMB acessível', why: 'SMB é uma superfície importante de administração e compartilhamento em redes Windows.', recommendation: 'Revise compartilhamentos, permissões, SMB legado e regras de firewall.' },
  { ports: [3389], services: ['ms-wbt-server', 'rdp'], severity: 'medium', title: 'Área de Trabalho Remota acessível', why: 'RDP expõe uma superfície de autenticação e administração remota.', recommendation: 'Restrinja origens, exija NLA/MFA quando disponível e revise política de bloqueio.' },
  { ports: [5900, 5901], services: ['vnc'], severity: 'medium', title: 'VNC acessível', why: 'VNC permite controle remoto e depende fortemente da configuração de autenticação e transporte.', recommendation: 'Restrinja a rede de origem e use túnel/criptografia quando suportado.' },
  { ports: [5985], services: ['wsman', 'winrm'], severity: 'medium', title: 'WinRM HTTP acessível', why: 'WinRM é uma interface administrativa remota e merece segmentação e autenticação forte.', recommendation: 'Restrinja a hosts administrativos e avalie WinRM sobre HTTPS.' },
  { ports: [6379], services: ['redis'], severity: 'high', title: 'Redis acessível na rede', why: 'Bancos de dados de memória não devem ficar amplamente acessíveis sem controles de rede e autenticação.', recommendation: 'Restrinja bind/firewall, habilite autenticação adequada e revise ACLs.' },
  { ports: [9200, 9300], services: ['elasticsearch'], severity: 'high', title: 'Elasticsearch acessível', why: 'A API de busca pode expor dados e funções administrativas quando mal segmentada.', recommendation: 'Restrinja acesso, habilite autenticação/TLS e revise permissões.' },
  { ports: [2375], services: ['docker'], severity: 'critical', title: 'Docker API sem TLS aparente', why: 'A porta 2375 é frequentemente usada pela API Docker sem TLS e pode representar controle administrativo do host.', recommendation: 'Não exponha a API Docker sem proteção; restrinja a interface e use TLS/autorização.' },
  { ports: [27017], services: ['mongodb'], severity: 'high', title: 'MongoDB acessível na rede', why: 'Uma interface de banco de dados exposta aumenta o impacto de configuração fraca ou credenciais comprometidas.', recommendation: 'Restrinja por rede, habilite autenticação e revise roles.' },
  { ports: [3306], services: ['mysql'], severity: 'medium', title: 'MySQL acessível na rede', why: 'Banco de dados diretamente acessível amplia a superfície de autenticação e exposição de dados.', recommendation: 'Permita apenas clientes necessários e revise contas, TLS e firewall.' },
  { ports: [5432], services: ['postgresql', 'postgres'], severity: 'medium', title: 'PostgreSQL acessível na rede', why: 'Banco de dados diretamente acessível deve ficar limitado aos clientes autorizados.', recommendation: 'Revise pg_hba.conf, TLS, roles e segmentação de rede.' },
]);

const DEVICE_ROLE_RULES = Object.freeze([
  { id: 'printer', label: 'Possível impressora / print server', ports: [515, 631, 9100], minMatches: 1 },
  { id: 'container-platform', label: 'Possível host de containers / plataforma DevOps', ports: [2375, 2376, 6443, 10250], minMatches: 1 },
  { id: 'database-server', label: 'Possível servidor de banco de dados', ports: [1433, 1521, 3306, 5432, 6379, 9200, 27017], minMatches: 1 },
  { id: 'file-server', label: 'Possível servidor de arquivos / NAS', ports: [139, 445, 2049], minMatches: 1 },
  { id: 'remote-admin', label: 'Possível estação ou servidor administrável remotamente', ports: [22, 3389, 5900, 5901, 5985, 5986], minMatches: 1 },
  { id: 'network-infrastructure', label: 'Possível equipamento de infraestrutura de rede', ports: [53, 67, 68, 161, 162], minMatches: 1 },
  { id: 'web-service', label: 'Possível servidor ou appliance com interface web', ports: [80, 443, 8000, 8080, 8081, 8443], minMatches: 1 },
]);

const SEVERITY_WEIGHT = Object.freeze({ info: 0, low: 1, medium: 2, high: 3, critical: 4 });

function normalizedService(value) {
  return String(value || '').trim().toLowerCase();
}

function severityRank(value) {
  return SEVERITY_WEIGHT[value] ?? 0;
}

function openPorts(host) {
  return (Array.isArray(host?.ports) ? host.ports : []).filter(port => String(port?.state || '').toLowerCase() === 'open');
}

export function inferHostRole(host) {
  const ports = new Set(openPorts(host).map(item => Number(item.port)).filter(Number.isInteger));
  const candidates = DEVICE_ROLE_RULES.map(rule => {
    const matchedPorts = rule.ports.filter(port => ports.has(port));
    return { ...rule, matchedPorts, score: matchedPorts.length };
  }).filter(candidate => candidate.score >= candidate.minMatches);

  candidates.sort((a, b) => b.score - a.score || DEVICE_ROLE_RULES.findIndex(rule => rule.id === a.id) - DEVICE_ROLE_RULES.findIndex(rule => rule.id === b.id));
  const best = candidates[0];
  if (!best) {
    return {
      id: ports.size ? 'generic-network-host' : 'unknown',
      label: ports.size ? 'Dispositivo de rede não classificado' : 'Dispositivo detectado',
      confidence: 'low',
      matchedPorts: [],
      basis: 'heuristic-from-observed-services',
    };
  }
  return {
    id: best.id,
    label: best.label,
    confidence: best.score >= 2 ? 'medium' : 'low',
    matchedPorts: best.matchedPorts,
    basis: 'heuristic-from-observed-services',
  };
}

export function buildDefensiveChecklist(host, findings = []) {
  const ports = openPorts(host);
  const portNumbers = new Set(ports.map(item => Number(item.port)));
  const checklist = [
    { id: 'owner-purpose', title: 'Confirmar proprietário e finalidade', detail: 'Valide quem administra o dispositivo e quais serviços realmente precisam ficar acessíveis.', priority: 'baseline' },
  ];

  if (ports.length) {
    checklist.push({ id: 'firewall-segmentation', title: 'Revisar firewall e segmentação', detail: `Há ${ports.length} porta(s) observada(s) como aberta(s). Confirme se cada uma deve ser alcançável a partir desta rede.`, priority: 'baseline' });
  }
  if ([80, 443, 8000, 8080, 8081, 8443].some(port => portNumbers.has(port))) {
    checklist.push({ id: 'web-hardening', title: 'Revisar interface web', detail: 'Confirme autenticação, TLS quando aplicável, atualizações e exposição da interface administrativa.', priority: 'review' });
  }
  if ([22, 3389, 5900, 5901, 5985, 5986].some(port => portNumbers.has(port))) {
    checklist.push({ id: 'remote-admin-hardening', title: 'Revisar administração remota', detail: 'Restrinja origens administrativas, use autenticação forte e mantenha logs de acesso.', priority: 'review' });
  }
  if ([139, 445, 2049].some(port => portNumbers.has(port))) {
    checklist.push({ id: 'share-permissions', title: 'Revisar compartilhamentos e permissões', detail: 'Confirme princípio do menor privilégio, protocolos legados e acesso apenas pelas redes necessárias.', priority: 'review' });
  }

  for (const finding of findings) {
    if (!finding?.recommendation) continue;
    const id = `finding-${String(finding.id || '').slice(0, 80)}`;
    if (checklist.some(item => item.id === id)) continue;
    checklist.push({ id, title: `Ação: ${finding.title}`, detail: finding.recommendation, priority: severityRank(finding.severity) >= 3 ? 'priority' : 'review' });
  }
  checklist.push({ id: 'patch-owner-confirmation', title: 'Confirmar patching e versão com o responsável', detail: 'A identificação de versão por rede é aproximada; valide inventário e atualização no próprio ativo antes de concluir risco.', priority: 'baseline' });
  return checklist.slice(0, 12);
}

export function classifyHostObservations(host) {
  const ports = Array.isArray(host?.ports) ? host.ports : [];
  const findings = [];
  const seen = new Set();

  for (const observed of ports) {
    if (String(observed?.state || '').toLowerCase() !== 'open') continue;
    const port = Number(observed?.port);
    const service = normalizedService(observed?.service);
    for (const rule of ATTENTION_RULES) {
      if (!rule.ports.includes(port) && !rule.services.some(candidate => service === candidate || service.includes(candidate))) continue;
      const key = `${rule.title}:${port}`;
      if (seen.has(key)) continue;
      seen.add(key);
      findings.push({
        id: `${port}-${rule.title.toLowerCase().replace(/[^a-z0-9]+/g, '-')}`,
        severity: rule.severity,
        title: rule.title,
        port,
        service: service || null,
        why: rule.why,
        recommendation: rule.recommendation,
        evidence: `Porta ${port}/${observed?.protocol || 'tcp'} observada como aberta${service ? ` (${service})` : ''}.`,
        certainty: 'observed-surface-only',
      });
    }
  }

  findings.sort((a, b) => severityRank(b.severity) - severityRank(a.severity) || a.port - b.port);
  const highestSeverity = findings.reduce((current, finding) => severityRank(finding.severity) > severityRank(current) ? finding.severity : current, 'info');
  const role = inferHostRole(host);
  return {
    address: host?.address || null,
    highestSeverity,
    role,
    exposure: {
      openTcpPorts: openPorts(host).filter(item => !item.protocol || item.protocol === 'tcp').length,
      observedServices: [...new Set(openPorts(host).map(item => normalizedService(item.service)).filter(Boolean))],
    },
    findings,
    checklist: buildDefensiveChecklist(host, findings),
    note: 'Indicadores e função provável baseados apenas na superfície observada. Não confirmam vulnerabilidade, sistema operacional, fabricante ou finalidade real.',
  };
}

export function enrichNetworkAssessment(result) {
  const hosts = Array.isArray(result?.hosts) ? result.hosts : [];
  const hostInsights = hosts.map(classifyHostObservations);
  const counts = { critical: 0, high: 0, medium: 0, low: 0, info: 0 };
  for (const insight of hostInsights) {
    for (const finding of insight.findings) counts[finding.severity] = (counts[finding.severity] || 0) + 1;
  }
  const highestSeverity = hostInsights.reduce((current, insight) => severityRank(insight.highestSeverity) > severityRank(current) ? insight.highestSeverity : current, 'info');
  return {
    ...result,
    insights: {
      highestSeverity,
      counts,
      hosts: hostInsights,
      interpretation: 'Priorize revisão defensiva dos serviços destacados; um serviço aberto ou uma função inferida não significa, por si só, que exista vulnerabilidade.',
    },
  };
}

export function parseArpTable(output) {
  const entries = [];
  const seen = new Set();
  let interfaceAddress = null;
  for (const rawLine of String(output || '').split(/\r?\n/)) {
    const line = rawLine.trim();
    const interfaceMatch = line.match(/(?:Interface|Interface:|interface)\s*:?\s*(\d{1,3}(?:\.\d{1,3}){3})/i);
    if (interfaceMatch) interfaceAddress = interfaceMatch[1];
    const match = line.match(/^(\d{1,3}(?:\.\d{1,3}){3})\s+([0-9a-f]{2}(?:[-:][0-9a-f]{2}){5})\s+(\S+)/i);
    if (!match) continue;
    const address = match[1];
    const mac = match[2].replace(/-/g, ':').toLowerCase();
    const key = `${interfaceAddress || ''}:${address}:${mac}`;
    if (seen.has(key)) continue;
    seen.add(key);
    entries.push({ interfaceAddress, address, mac, state: match[3].toLowerCase() });
  }
  return entries;
}

export function parseIpv4RoutePrint(output) {
  const candidates = [];
  for (const rawLine of String(output || '').split(/\r?\n/)) {
    const fields = rawLine.trim().split(/\s+/);
    if (fields.length < 5 || fields[0] !== '0.0.0.0' || fields[1] !== '0.0.0.0') continue;
    const metric = Number(fields[4]);
    candidates.push({ destination: fields[0], netmask: fields[1], gateway: fields[2], interfaceAddress: fields[3], metric: Number.isFinite(metric) ? metric : null });
  }
  candidates.sort((a, b) => (a.metric ?? Number.MAX_SAFE_INTEGER) - (b.metric ?? Number.MAX_SAFE_INTEGER));
  return candidates;
}

export function buildNetworkAiContext({ project, authorizedScope, overview, diagnostics, assessment, selectedHost }) {
  const selectedInsight = assessment?.insights?.hosts?.find(item => item.address === selectedHost?.address) || null;
  return {
    schemaVersion: 2,
    kind: 'cloudos-network-assessment',
    purpose: 'authorized-defensive-network-assessment',
    project: String(project || '').slice(0, 120),
    authorizedScope: Array.isArray(authorizedScope) ? authorizedScope.slice(0, 50) : [],
    localNetwork: overview ? {
      host: overview.host || null,
      interfaces: Array.isArray(overview.interfaces) ? overview.interfaces.map(item => ({ name: item.name, address: item.address, cidr: item.cidr })) : [],
      dnsServers: diagnostics?.dnsServers || [],
      defaultGateway: diagnostics?.defaultRoutes?.[0]?.gateway || null,
    } : null,
    assessment: assessment ? {
      preset: assessment.preset,
      target: assessment.target,
      completedAt: assessment.completedAt,
      durationMs: assessment.durationMs ?? null,
      hostCount: Array.isArray(assessment.hosts) ? assessment.hosts.length : 0,
      highestAttention: assessment.insights?.highestSeverity || 'info',
    } : null,
    selectedHost: selectedHost ? {
      address: selectedHost.address,
      hostname: selectedHost.hostname || null,
      ports: Array.isArray(selectedHost.ports) ? selectedHost.ports.map(port => ({ port: port.port, protocol: port.protocol, state: port.state, service: port.service, version: port.version })) : [],
      role: selectedInsight?.role || null,
      findings: selectedInsight?.findings || [],
      defensiveChecklist: selectedInsight?.checklist || [],
    } : null,
    constraints: {
      doNotInferVulnerabilityFromOpenPort: true,
      doNotGenerateCredentialAttacks: true,
      doNotGenerateDeauthOrPacketInjection: true,
      nextSteps: 'Prefer validation, hardening, segmentation, patch review, service-owner confirmation and evidence collection inside the authorized scope.',
    },
  };
}
