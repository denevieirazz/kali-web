import { useEffect, useMemo, useState } from 'react';
import { apiClient } from '../../services/apiClient';
import QuickCheckHistory from './QuickCheckHistory';
import { explainPort } from './portKnowledge';
import { buildQuickCheckEvidence, buildQuickCheckMarkdown } from './quickCheckEvidence';
import './QuickLocalChecks.css';

type WslInfo = {
  available: boolean;
  default: string | null;
  preferred: string | null;
  distributions: Array<{ name: string; version: number | null; state: string }>;
};

type NetworkOverview = {
  suggestedTargets: string[];
  interfaces: Array<{ name: string; address: string; privateLocal: boolean; suggestedDiscoveryTarget: string | null }>;
  presets: Array<{ id: string; label: string; description?: string; requiresSingleHost?: boolean; ports?: number[] | null }>;
};

type NetworkDiagnostics = { defaultRoutes: Array<{ gateway: string }> };
type HostDiagnostics = {
  target: string;
  identity: { reverseDns: string[]; mac: string | null; neighborState: string | null; interfaceAddress: string | null; isDefaultGateway: boolean };
  reachability: { reachable: boolean; attempts: number; replies: number; lossPercent: number | null; averageMs: number | null; minMs: number | null; maxMs: number | null; ttl: number | null };
  route: { hopCount: number; hops: Array<{ hop: number; address: string | null; averageMs: number | null; timedOut: boolean }> };
  localNetwork: { defaultGateway: string | null; dnsServers: string[] };
  nextSteps: string[];
};
type ScanPort = { port: number; state: string; protocol: string; service: string; version: string };
type ScanHost = { address: string; hostname: string; up: boolean; ports: ScanPort[] };
type ScanResult = {
  preset: string;
  label: string;
  target: string;
  distribution: string;
  hosts: ScanHost[];
  completedAt: string;
  durationMs?: number;
  insights?: { highestSeverity?: string; hosts?: Array<{ address: string | null; findings?: Array<{ id: string; severity: string; title: string; evidence: string; recommendation: string }> }> };
};
type CheckBlock = { id: string; icon: string; title: string; description: string; badge?: string };

const CHECKS: CheckBlock[] = [
  { id: 'commonPorts', icon: '🚪', title: 'Portas comuns', description: 'Confere rapidamente as portas TCP mais frequentes.', badge: 'rápido' },
  { id: 'webSurface', icon: '🌐', title: 'Web e painéis', description: 'Procura serviços HTTP/HTTPS e painéis em portas web comuns.' },
  { id: 'remoteAccess', icon: '🖥️', title: 'Acesso remoto', description: 'Checa SSH, RDP, VNC e WinRM sem tentar senha.' },
  { id: 'windowsServices', icon: '🪟', title: 'Windows / SMB', description: 'Checa RPC, NetBIOS, SMB e WinRM do dispositivo.' },
  { id: 'fileSharing', icon: '📂', title: 'Compartilhamento', description: 'Checa FTP, SSH/SFTP, SMB, NFS e IPP.' },
  { id: 'databases', icon: '🗄️', title: 'Bancos e caches', description: 'Checa SQL Server, Oracle, MySQL, PostgreSQL, Redis, Elastic e MongoDB.' },
  { id: 'infrastructure', icon: '🧭', title: 'Infraestrutura', description: 'Checa DNS, Kerberos, NTP, SNMP e LDAP/LDAPS.' },
  { id: 'printersIot', icon: '📷', title: 'Impressoras / IoT', description: 'Checa web, RTSP, IPP, MQTT e impressão JetDirect.' },
  { id: 'development', icon: '🧪', title: 'Desenvolvimento', description: 'Checa portas comuns de servidores e painéis de desenvolvimento.' },
  { id: 'mailServices', icon: '✉️', title: 'Serviços de e-mail', description: 'Checa SMTP, POP e IMAP sem autenticação ou enumeração de contas.' },
];

function safePrivateHost(value: string) {
  return /^(?:10\.|127\.|169\.254\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.)\d{1,3}\.\d{1,3}$/.test(value.trim());
}
function downloadText(filename: string, body: string, type: string) {
  const href = URL.createObjectURL(new Blob([body], { type }));
  const anchor = document.createElement('a'); anchor.href = href; anchor.download = filename; anchor.click();
  window.setTimeout(() => URL.revokeObjectURL(href), 0);
}
function safeFilenameTarget(value: string) { return value.replace(/[^a-z0-9.-]+/gi, '_').slice(0, 80) || 'target'; }

export default function QuickLocalChecks() {
  const [distribution, setDistribution] = useState('');
  const [overview, setOverview] = useState<NetworkOverview | null>(null);
  const [gateway, setGateway] = useState('');
  const [target, setTarget] = useState('');
  const [result, setResult] = useState<ScanResult | null>(null);
  const [hostDiagnostics, setHostDiagnostics] = useState<HostDiagnostics | null>(null);
  const [loading, setLoading] = useState('');
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');
  const [wsl, setWsl] = useState<WslInfo | null>(null);

  useEffect(() => {
    let cancelled = false;
    void Promise.all([
      apiClient<WslInfo>('/api/wsl/distributions'),
      apiClient<NetworkOverview>('/api/security/tools/network/overview'),
      apiClient<NetworkDiagnostics>('/api/security/tools/network/diagnostics', { timeoutMs: 15_000 }),
    ]).then(([wslInfo, networkOverview, diagnostics]) => {
      if (cancelled) return;
      setWsl(wslInfo); setOverview(networkOverview);
      setDistribution(wslInfo.preferred || wslInfo.default || wslInfo.distributions[0]?.name || '');
      const firstGateway = diagnostics.defaultRoutes?.[0]?.gateway || '';
      setGateway(firstGateway);
      const ownAddress = networkOverview.interfaces.find(item => item.privateLocal && !item.address.startsWith('127.'))?.address || '';
      setTarget(firstGateway || ownAddress);
    }).catch(cause => { if (!cancelled) setError(cause instanceof Error ? cause.message : 'Não foi possível preparar os checks locais.'); });
    return () => { cancelled = true; };
  }, []);

  const serverPresets = useMemo(() => new Map((overview?.presets || []).map(item => [item.id, item])), [overview]);

  const runCheck = async (preset: string, selectedTarget = target) => {
    const cleanTarget = selectedTarget.trim();
    if (!distribution) { setError('Prepare uma distribuição Linux/WSL com Nmap antes de usar estes checks.'); return; }
    if (preset !== 'discover' && !safePrivateHost(cleanTarget)) { setError('Informe um IPv4 privado/local de um único dispositivo, por exemplo 192.168.1.1.'); return; }
    if (preset === 'discover' && !cleanTarget.includes('/')) { setError('A descoberta automática precisa de uma faixa privada CIDR sugerida pelo CloudOS.'); return; }
    setLoading(preset); setError(''); setNotice(''); setHostDiagnostics(null);
    try {
      const scanPromise = apiClient<ScanResult>('/api/security/tools/network/scan', {
        method: 'POST', timeoutMs: 65_000,
        body: JSON.stringify({ preset, target: cleanTarget, distribution }),
      });
      const diagnosticsPromise = preset === 'discover'
        ? Promise.resolve<HostDiagnostics | null>(null)
        : apiClient<HostDiagnostics>('/api/security/tools/network/host/diagnostics', {
          method: 'POST', timeoutMs: 20_000, body: JSON.stringify({ target: cleanTarget }),
        }).catch(() => null);
      const [data, diagnosticData] = await Promise.all([scanPromise, diagnosticsPromise]);
      setResult(data); setHostDiagnostics(diagnosticData);
      setNotice(`${data.label} concluído. O CloudOS juntou superfície, identidade e conectividade abaixo.`);
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'O check não foi concluído.'); }
    finally { setLoading(''); }
  };

  const discover = async () => {
    const discoveryTarget = overview?.suggestedTargets?.[0] || '';
    if (!discoveryTarget) { setError('O CloudOS não conseguiu determinar automaticamente uma faixa privada /24 ou menor.'); return; }
    await runCheck('discover', discoveryTarget);
  };

  const evidence = useMemo(() => result ? buildQuickCheckEvidence(result, hostDiagnostics) : null, [hostDiagnostics, result]);
  const copyForAi = async () => {
    if (!evidence) return;
    try { await navigator.clipboard.writeText(JSON.stringify(evidence, null, 2)); setNotice('Resultado explicado, identidade e conectividade copiados para a IA.'); }
    catch { setError('Não foi possível copiar para a área de transferência.'); }
  };
  const exportJson = () => {
    if (!result || !evidence) return;
    downloadText(`cloudos-network-${safeFilenameTarget(result.target)}-${Date.now()}.json`, JSON.stringify(evidence, null, 2), 'application/json');
    setNotice('Evidência JSON salva.');
  };
  const exportMarkdown = () => {
    if (!result) return;
    downloadText(`cloudos-network-report-${safeFilenameTarget(result.target)}-${Date.now()}.md`, buildQuickCheckMarkdown(result, hostDiagnostics), 'text/markdown;charset=utf-8');
    setNotice('Relatório Markdown salvo.');
  };

  const findings = useMemo(() => result?.insights?.hosts?.flatMap(host => host.findings || []).slice(0, 8) || [], [result]);
  const openPorts = useMemo(() => result?.hosts.flatMap(host => host.ports.filter(port => port.state === 'open').map(port => ({ host: host.address, ...port, knowledge: explainPort(port.port, port.service) }))).slice(0, 20) || [], [result]);
  const fullProfileAvailable = overview === null || serverPresets.has('fullProfile');

  return <section className="qlc-root" aria-label="Checks locais de um clique">
    <header className="qlc-head"><div><small>Checks locais · um botão por função</small><h2>Escolha o que quer conferir neste dispositivo</h2><p>Os botões usam presets fixos do CloudOS. Não existe campo de argumento do Nmap nesta tela.</p></div><button type="button" className="qlc-discover" onClick={() => void discover()} disabled={Boolean(loading)}>{loading === 'discover' ? 'Descobrindo…' : '🔎 Descobrir dispositivos da minha rede'}</button></header>

    {(error || notice) && <div className={`qlc-banner ${error ? 'is-error' : ''}`} role={error ? 'alert' : 'status'}><span>{error || notice}</span><button type="button" onClick={() => { setError(''); setNotice(''); }}>×</button></div>}

    <div className="qlc-targetbar">
      <label><span>Dispositivo privado/local</span><input value={target} onChange={event => setTarget(event.target.value)} placeholder="192.168.1.1" /></label>
      {gateway && <button type="button" onClick={() => setTarget(gateway)}>Usar gateway · {gateway}</button>}
      <label><span>Linux/WSL</span><select value={distribution} onChange={event => setDistribution(event.target.value)}><option value="">Selecione</option>{wsl?.distributions.map(item => <option key={item.name} value={item.name}>{item.name}</option>)}</select></label>
    </div>

    <article className="qlc-full"><div className="qlc-full-icon">⚡</div><div><small>Mais automático</small><strong>Perfil completo local</strong><p>Uma única checagem bounded reúne as superfícies mais comuns e, em paralelo, coleta ping, PTR, MAC e rota do host.</p><span>Não tenta senha, não roda script NSE de exploração e aceita somente um IPv4 privado/local.</span></div><button type="button" disabled={Boolean(loading) || !fullProfileAvailable} onClick={() => void runCheck('fullProfile')}>{loading === 'fullProfile' ? 'Montando perfil…' : '▶ Fazer perfil completo'}</button></article>

    <div className="qlc-grid">{CHECKS.map(check => {
      const metadata = serverPresets.get(check.id); const unavailable = overview !== null && !metadata;
      return <article key={check.id} className="qlc-card"><div className="qlc-icon">{check.icon}</div><div><small>{check.badge || 'check guiado'}</small><strong>{metadata?.label || check.title}</strong><p>{metadata?.description || check.description}</p></div><button type="button" disabled={Boolean(loading) || unavailable} onClick={() => void runCheck(check.id)}>{loading === check.id ? 'Verificando…' : 'Verificar →'}</button></article>;
    })}</div>

    <QuickCheckHistory result={result} hostDiagnostics={hostDiagnostics} busy={Boolean(loading)} onUseTarget={setTarget} onRerun={(preset, savedTarget) => void runCheck(preset, savedTarget)} />

    {result && <section className="qlc-result">
      <header><div><small>Último resultado</small><strong>{result.label}</strong><span>{result.target}</span></div><div className="qlc-result-actions"><button type="button" onClick={() => void copyForAi()}>Copiar para IA</button><button type="button" onClick={exportJson}>Exportar JSON</button><button type="button" onClick={exportMarkdown}>Salvar relatório</button><em>{result.insights?.highestSeverity || 'info'}</em></div></header>

      {hostDiagnostics && <div className="qlc-identity">
        <article><small>Responde?</small><strong>{hostDiagnostics.reachability.reachable ? 'sim' : 'não via ICMP'}</strong><span>{hostDiagnostics.reachability.lossPercent ?? '—'}% perda</span></article>
        <article><small>Latência média</small><strong>{hostDiagnostics.reachability.averageMs ?? '—'} ms</strong><span>3 tentativas bounded</span></article>
        <article><small>MAC</small><strong>{hostDiagnostics.identity.mac || 'não observado'}</strong><span>{hostDiagnostics.identity.neighborState || 'ARP sem evidência'}</span></article>
        <article><small>Nome PTR</small><strong>{hostDiagnostics.identity.reverseDns[0] || 'não observado'}</strong><span>{hostDiagnostics.identity.reverseDns.length} nome(s)</span></article>
        <article><small>Rota</small><strong>{hostDiagnostics.route.hopCount} salto(s)</strong><span>{hostDiagnostics.identity.isDefaultGateway ? 'é o gateway padrão' : 'host da rede'}</span></article>
      </div>}

      <div className="qlc-hosts">{result.hosts.length ? result.hosts.map(host => <article key={host.address}><div><strong>{host.address}</strong><span>{host.hostname || 'sem hostname'}</span></div><small>{host.up ? 'respondeu' : 'sem resposta'} · {host.ports.filter(port => port.state === 'open').length} porta(s) aberta(s)</small><div className="qlc-ports">{host.ports.filter(port => port.state === 'open').slice(0, 12).map(port => <span key={`${host.address}-${port.port}`}>{port.port}/{port.service || 'tcp'}</span>)}</div>{safePrivateHost(host.address) && <button type="button" onClick={() => setTarget(host.address)}>Usar este IP nos checks</button>}</article>) : <p>Nenhum host/serviço foi retornado neste check.</p>}</div>

      {openPorts.length > 0 && <div className="qlc-explain"><strong>O que essas portas significam</strong><div>{openPorts.map(port => <article key={`${port.host}-${port.port}`}><b>{port.port}</b><div><strong>{port.knowledge.title}</strong><span>{port.knowledge.category} · {port.host}</span><p>{port.knowledge.explanation}</p><small>Revise: {port.knowledge.review}</small></div></article>)}</div></div>}
      {hostDiagnostics?.nextSteps.length ? <div className="qlc-next"><strong>Próximos passos deste host</strong><ol>{hostDiagnostics.nextSteps.map((step, index) => <li key={`${index}-${step}`}>{step}</li>)}</ol></div> : null}
      {findings.length > 0 && <div className="qlc-findings"><strong>O que merece revisão</strong>{findings.map(finding => <article key={finding.id}><span>{finding.severity}</span><div><b>{finding.title}</b><p>{finding.evidence}</p><small>{finding.recommendation}</small></div></article>)}</div>}
      <p className="qlc-note">Porta aberta ou serviço identificado é evidência de superfície, não confirmação automática de vulnerabilidade.</p>
    </section>}
  </section>;
}
