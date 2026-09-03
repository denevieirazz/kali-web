import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  NETWORK_ASSESSMENT_HISTORY_KEY,
  appendNetworkAssessmentHistory,
  normalizeNetworkAssessmentHistory,
  type NetworkAssessmentHistoryRecord,
} from '../../core/networkAssessmentHistory.js';
import { apiClient } from '../../services/apiClient';
import { getUserStorageKey } from '../../services/userScope.js';
import './NetworkAssessmentPanel.css';

type Severity = 'info' | 'low' | 'medium' | 'high' | 'critical';

type NetworkInterface = {
  name: string;
  address: string;
  netmask: string;
  cidr: string | null;
  internal: boolean;
  privateLocal: boolean;
  suggestedDiscoveryTarget: string | null;
};

type NetworkOverview = {
  host: string;
  platform: string;
  interfaces: NetworkInterface[];
  suggestedTargets: string[];
  presets: Array<{ id: 'discover' | 'services' | 'commonPorts'; label: string }>;
  policy: {
    scope: string;
    maxDiscoveryRange: string;
    arbitraryArguments: boolean;
    activeWirelessAttacks: boolean;
  };
};

type NetworkNeighbor = { interfaceAddress: string | null; address: string; mac: string; state: string };
type DefaultRoute = { destination: string; netmask: string; gateway: string; interfaceAddress: string; metric: number | null };
type NetworkDiagnostics = {
  collectedAt: string;
  dnsServers: string[];
  neighbors: NetworkNeighbor[];
  defaultRoutes: DefaultRoute[];
  capabilities: { neighbors: boolean; routes: boolean; dns: boolean };
  sources: { neighbors: string; routes: string; dns: string };
  policy: { readOnly: boolean; activeProbe: boolean; arbitraryArguments: boolean };
};

type WifiDiagnostics = {
  available: boolean;
  source: string;
  interfaces: string;
  visibleNetworks: string;
  note: string;
};

type ScanPort = { port: number; state: string; protocol: string; service: string; version: string };
type ScanHost = { address: string; hostname: string; up: boolean; ports: ScanPort[] };
type HostFinding = {
  id: string;
  severity: Severity;
  title: string;
  port: number;
  service: string | null;
  why: string;
  recommendation: string;
  evidence: string;
  certainty: string;
};
type HostInsight = { address: string | null; highestSeverity: Severity; findings: HostFinding[]; note: string };
type ScanResult = {
  preset: string;
  label: string;
  target: string;
  distribution: string;
  hosts: ScanHost[];
  rawSummary: string;
  warnings: string;
  startedAt?: string;
  completedAt: string;
  durationMs?: number;
  policy?: Record<string, boolean | string>;
  insights?: {
    highestSeverity: Severity;
    counts: Record<Severity, number>;
    hosts: HostInsight[];
    interpretation: string;
  };
};

type Props = {
  distribution: string;
  activeScope?: string | null;
  onNotice?: (message: string) => void;
  onError?: (message: string) => void;
};

type ViewTab = 'guided' | 'map' | 'history' | 'wifi';

const SEVERITY_LABEL: Record<Severity, string> = {
  info: 'informativo', low: 'baixo', medium: 'médio', high: 'alto', critical: 'crítico',
};

function looksLikeLocalIpv4(value: string) {
  return /^(?:10\.|127\.|169\.254\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.)\d{1,3}\.\d{1,3}(?:\/\d{1,2})?$/.test(value.trim());
}

function historyStorageKey() {
  return getUserStorageKey(NETWORK_ASSESSMENT_HISTORY_KEY);
}

function loadHistory(): NetworkAssessmentHistoryRecord[] {
  try {
    return normalizeNetworkAssessmentHistory(JSON.parse(localStorage.getItem(historyStorageKey()) || '[]'));
  } catch {
    localStorage.removeItem(historyStorageKey());
    return [];
  }
}

function formatDuration(value: number | null | undefined) {
  if (!Number.isFinite(value)) return '—';
  if ((value || 0) < 1000) return `${Math.round(value || 0)} ms`;
  return `${((value || 0) / 1000).toFixed(1)} s`;
}

function downloadJson(filename: string, payload: unknown) {
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 0);
}

export default function NetworkAssessmentPanel({ distribution, activeScope, onNotice, onError }: Props) {
  const [overview, setOverview] = useState<NetworkOverview | null>(null);
  const [diagnostics, setDiagnostics] = useState<NetworkDiagnostics | null>(null);
  const [wifi, setWifi] = useState<WifiDiagnostics | null>(null);
  const [target, setTarget] = useState('');
  const [preset, setPreset] = useState<'discover' | 'services' | 'commonPorts'>('discover');
  const [result, setResult] = useState<ScanResult | null>(null);
  const [selectedHostAddress, setSelectedHostAddress] = useState<string | null>(null);
  const [history, setHistory] = useState<NetworkAssessmentHistoryRecord[]>(loadHistory);
  const [tab, setTab] = useState<ViewTab>('guided');
  const [loadingOverview, setLoadingOverview] = useState(false);
  const [loadingDiagnostics, setLoadingDiagnostics] = useState(false);
  const [loadingWifi, setLoadingWifi] = useState(false);
  const [scanning, setScanning] = useState(false);
  const [quickAuditStep, setQuickAuditStep] = useState<0 | 1 | 2 | 3>(0);

  useEffect(() => {
    localStorage.setItem(historyStorageKey(), JSON.stringify(history));
  }, [history]);

  const loadOverview = useCallback(async (quiet = false) => {
    setLoadingOverview(true);
    try {
      const data = await apiClient<NetworkOverview>('/api/security/tools/network/overview');
      setOverview(data);
      setTarget(current => {
        if (current) return current;
        if (activeScope && looksLikeLocalIpv4(activeScope)) return activeScope;
        return data.suggestedTargets[0] || '';
      });
      if (!quiet) onNotice?.('Mapa básico da rede local atualizado.');
      return data;
    } catch (cause) {
      onError?.(cause instanceof Error ? cause.message : 'Não foi possível identificar a rede local.');
      return null;
    } finally {
      setLoadingOverview(false);
    }
  }, [activeScope, onError, onNotice]);

  const loadDiagnostics = useCallback(async (quiet = false) => {
    setLoadingDiagnostics(true);
    try {
      const data = await apiClient<NetworkDiagnostics>('/api/security/tools/network/diagnostics', { timeoutMs: 15000 });
      setDiagnostics(data);
      if (!quiet) onNotice?.(`Mapa local atualizado: ${data.neighbors.length} vizinho(s), ${data.dnsServers.length} DNS.`);
      return data;
    } catch (cause) {
      onError?.(cause instanceof Error ? cause.message : 'Falha ao consultar DNS, gateway e vizinhos locais.');
      return null;
    } finally {
      setLoadingDiagnostics(false);
    }
  }, [onError, onNotice]);

  useEffect(() => {
    void loadOverview(true);
    void loadDiagnostics(true);
  }, [loadDiagnostics, loadOverview]);

  useEffect(() => {
    if (activeScope && looksLikeLocalIpv4(activeScope)) setTarget(activeScope);
  }, [activeScope]);

  const loadWifi = async () => {
    setLoadingWifi(true);
    try {
      const data = await apiClient<WifiDiagnostics>('/api/security/tools/network/wifi', { timeoutMs: 15000 });
      setWifi(data);
      setTab('wifi');
      onNotice?.(data.available ? 'Diagnóstico Wi‑Fi atualizado.' : 'O host não expôs diagnóstico Wi‑Fi nesta sessão.');
    } catch (cause) {
      onError?.(cause instanceof Error ? cause.message : 'Falha ao consultar o Wi‑Fi local.');
    } finally {
      setLoadingWifi(false);
    }
  };

  const persistAssessment = (data: ScanResult) => {
    setHistory(current => appendNetworkAssessmentHistory(current, data));
  };

  const executeAssessment = async (selectedPreset: typeof preset, selectedTarget: string) => {
    if (!distribution) throw new Error('Selecione uma distribuição WSL com Nmap instalado.');
    if (!selectedTarget.trim()) throw new Error('Escolha a rede sugerida ou informe um IPv4 privado/local.');
    const data = await apiClient<ScanResult>('/api/security/tools/network/scan', {
      method: 'POST',
      timeoutMs: 65000,
      body: JSON.stringify({ preset: selectedPreset, target: selectedTarget.trim(), distribution }),
    });
    setResult(data);
    persistAssessment(data);
    const firstUp = data.hosts.find(host => host.up)?.address || data.hosts[0]?.address || null;
    setSelectedHostAddress(firstUp);
    return data;
  };

  const runAssessment = async () => {
    setScanning(true);
    try {
      const data = await executeAssessment(preset, target);
      onNotice?.(`${data.label} concluído: ${data.hosts.length} dispositivo(s) retornado(s).`);
    } catch (cause) {
      onError?.(cause instanceof Error ? cause.message : 'A avaliação de rede falhou.');
    } finally {
      setScanning(false);
    }
  };

  const runQuickAudit = async () => {
    setScanning(true);
    setQuickAuditStep(1);
    try {
      const currentOverview = overview || await loadOverview(true);
      await loadDiagnostics(true);
      setQuickAuditStep(2);
      const discoveryTarget = currentOverview?.suggestedTargets[0] || (looksLikeLocalIpv4(target) && target.includes('/') ? target : '');
      if (!discoveryTarget) throw new Error('Não foi possível determinar automaticamente uma faixa local /24 ou menor.');
      setTarget(discoveryTarget);
      setPreset('discover');
      const data = await executeAssessment('discover', discoveryTarget);
      setQuickAuditStep(3);
      onNotice?.(`Auditoria rápida concluiu a descoberta: ${data.hosts.filter(host => host.up).length} dispositivo(s). Selecione um host para aprofundar.`);
    } catch (cause) {
      setQuickAuditStep(0);
      onError?.(cause instanceof Error ? cause.message : 'A auditoria rápida não foi concluída.');
    } finally {
      setScanning(false);
    }
  };

  const profileHost = async (address: string) => {
    if (!looksLikeLocalIpv4(address) || address.includes('/')) return;
    setSelectedHostAddress(address);
    setTarget(address);
    setPreset('services');
    setScanning(true);
    try {
      const data = await executeAssessment('services', address);
      setSelectedHostAddress(address);
      onNotice?.(`Perfil defensivo de ${address} atualizado.`);
    } catch (cause) {
      onError?.(cause instanceof Error ? cause.message : 'Não foi possível aprofundar este dispositivo.');
    } finally {
      setScanning(false);
    }
  };

  const upHosts = useMemo(() => result?.hosts.filter(host => host.up) ?? [], [result]);
  const selectedHost = useMemo(() => result?.hosts.find(host => host.address === selectedHostAddress) || null, [result, selectedHostAddress]);
  const selectedInsight = useMemo(() => result?.insights?.hosts.find(item => item.address === selectedHostAddress) || null, [result, selectedHostAddress]);
  const selectedNeighbor = useMemo(() => diagnostics?.neighbors.find(item => item.address === selectedHostAddress) || null, [diagnostics, selectedHostAddress]);

  const buildAiPayload = () => ({
    schemaVersion: 2,
    kind: 'cloudos-network-assessment',
    purpose: 'authorized-defensive-network-assessment',
    authorizedScope: activeScope ? [activeScope] : [],
    localNetwork: overview ? {
      host: overview.host,
      interfaces: overview.interfaces.filter(item => item.privateLocal).map(item => ({ name: item.name, address: item.address, cidr: item.cidr })),
      dnsServers: diagnostics?.dnsServers || [],
      defaultGateway: diagnostics?.defaultRoutes[0]?.gateway || null,
    } : null,
    assessment: result ? {
      preset: result.preset, target: result.target, completedAt: result.completedAt,
      durationMs: result.durationMs ?? null, highestAttention: result.insights?.highestSeverity || 'info',
    } : null,
    selectedHost: selectedHost ? {
      address: selectedHost.address,
      hostname: selectedHost.hostname || null,
      mac: selectedNeighbor?.mac || null,
      ports: selectedHost.ports,
      findings: selectedInsight?.findings || [],
    } : null,
    constraints: {
      doNotInferVulnerabilityFromOpenPort: true,
      doNotGenerateCredentialAttacks: true,
      doNotGenerateDeauthOrPacketInjection: true,
      preferredNextSteps: ['confirmar proprietário do serviço', 'revisar configuração', 'validar patching', 'revisar firewall/segmentação', 'coletar evidência adicional autorizada'],
    },
  });

  const copyAiContext = async () => {
    if (!result) return;
    try {
      await navigator.clipboard.writeText(JSON.stringify(buildAiPayload(), null, 2));
      onNotice?.('Contexto estruturado e defensivo copiado para a IA do CloudOS.');
    } catch {
      onNotice?.('Não foi possível acessar a área de transferência.');
    }
  };

  const exportEvidence = () => {
    if (!result) return;
    const safeTarget = result.target.replace(/[^a-z0-9.-]+/gi, '_');
    downloadJson(`cloudos-network-${safeTarget}-${Date.now()}.json`, buildAiPayload());
    onNotice?.('Evidência JSON exportada localmente.');
  };

  return (
    <section className="ktc-network" aria-label="Rede e Wi-Fi">
      <div className="ktc-network-head">
        <div>
          <small>Assessment guiado · V2</small>
          <h2>Rede & Wi‑Fi</h2>
          <p>Mapeie a rede local, entenda cada dispositivo, organize evidências e entregue contexto limpo para a IA.</p>
        </div>
        <div className="ktc-network-policy">
          <span>✓ rede privada/local</span><span>✓ presets fechados</span><span>✓ até /24</span><span>✓ evidência estruturada</span>
        </div>
      </div>

      <nav className="ktc-network-tabs" aria-label="Áreas de rede">
        <button className={tab === 'guided' ? 'is-active' : ''} type="button" onClick={() => setTab('guided')}>Assistente</button>
        <button className={tab === 'map' ? 'is-active' : ''} type="button" onClick={() => setTab('map')}>Mapa local</button>
        <button className={tab === 'history' ? 'is-active' : ''} type="button" onClick={() => setTab('history')}>Evidências <span>{history.length}</span></button>
        <button className={tab === 'wifi' ? 'is-active' : ''} type="button" onClick={() => setTab('wifi')}>Wi‑Fi</button>
      </nav>

      {tab === 'guided' && <>
        <div className="ktc-network-quick">
          <div><strong>Auditoria rápida</strong><span>Detecta a faixa local → atualiza DNS/gateway/ARP → descobre dispositivos → você escolhe qual aprofundar.</span></div>
          <button type="button" className="ktc-network-primary" onClick={() => void runQuickAudit()} disabled={scanning || !distribution}>{scanning ? 'Executando…' : '▶ Iniciar auditoria rápida'}</button>
        </div>
        {quickAuditStep > 0 && <div className="ktc-network-steps">
          <span className={quickAuditStep >= 1 ? 'done' : ''}>1 Rede</span><span className={quickAuditStep >= 2 ? 'done' : ''}>2 Diagnóstico</span><span className={quickAuditStep >= 3 ? 'done' : ''}>3 Dispositivos</span><span>4 Selecione um host</span>
        </div>}

        <div className="ktc-network-actions">
          <button type="button" onClick={() => void loadOverview()} disabled={loadingOverview}>{loadingOverview ? 'Identificando…' : '↻ Rede'}</button>
          <button type="button" onClick={() => void loadDiagnostics()} disabled={loadingDiagnostics}>{loadingDiagnostics ? 'Mapeando…' : '⌁ DNS / Gateway / ARP'}</button>
          <button type="button" onClick={() => void loadWifi()} disabled={loadingWifi}>{loadingWifi ? 'Consultando…' : '◉ Diagnóstico Wi‑Fi'}</button>
        </div>

        {overview && <div className="ktc-network-overview">
          <div className="ktc-network-summary"><strong>{overview.host}</strong><span>{overview.interfaces.filter(item => item.privateLocal && !item.internal).length} interface(s) local(is)</span></div>
          <div className="ktc-network-chips">{overview.suggestedTargets.map(item => <button type="button" key={item} onClick={() => { setTarget(item); setPreset('discover'); }}>{item}</button>)}</div>
        </div>}

        <div className="ktc-network-runner">
          <label><span>O que você quer fazer?</span><select value={preset} onChange={event => setPreset(event.target.value as typeof preset)}><option value="discover">Descobrir dispositivos conectados</option><option value="commonPorts">Checar portas comuns de um dispositivo</option><option value="services">Criar perfil de serviços do dispositivo</option></select></label>
          <label><span>Alvo privado/local</span><input value={target} onChange={event => setTarget(event.target.value)} placeholder={preset === 'discover' ? '192.168.1.0/24' : '192.168.1.10'} /></label>
          <button className="ktc-network-primary" type="button" onClick={() => void runAssessment()} disabled={scanning || !distribution}>{scanning ? 'Analisando…' : '▶ Executar avaliação'}</button>
        </div>

        <div className="ktc-network-explain"><strong>O que este modo faz</strong><p>{preset === 'discover' ? 'Encontra quais dispositivos respondem na sua própria rede; não tenta autenticação.' : preset === 'commonPorts' ? 'Verifica um conjunto pequeno de portas TCP comuns em um único IP local.' : 'Identifica de forma leve os serviços aparentes nas portas mais comuns e transforma a superfície observada em recomendações defensivas.'}</p></div>

        {result && <div className="ktc-network-results">
          <div className="ktc-network-results-head">
            <div><small>{result.label} · {formatDuration(result.durationMs)}</small><strong>{upHosts.length} dispositivo(s) ativo(s)</strong><span>{result.target}</span></div>
            <div className="ktc-network-result-actions"><span className={`ktc-risk ktc-risk--${result.insights?.highestSeverity || 'info'}`}>atenção {SEVERITY_LABEL[result.insights?.highestSeverity || 'info']}</span><button type="button" onClick={() => void copyAiContext()}>Copiar para IA</button><button type="button" onClick={exportEvidence}>Exportar JSON</button></div>
          </div>
          {result.hosts.length === 0 ? <p className="ktc-network-empty">Nenhum dispositivo foi retornado por esse preset.</p> : <div className="ktc-network-hosts">
            {result.hosts.map(host => {
              const insight = result.insights?.hosts.find(item => item.address === host.address);
              const neighbor = diagnostics?.neighbors.find(item => item.address === host.address);
              return <article className={selectedHostAddress === host.address ? 'is-selected' : ''} key={host.address}>
                <button type="button" className="ktc-host-select" onClick={() => setSelectedHostAddress(host.address)}>
                  <header><strong>{host.address}</strong><span className={`ktc-risk ktc-risk--${insight?.highestSeverity || 'info'}`}>{SEVERITY_LABEL[insight?.highestSeverity || 'info']}</span></header>
                  <p>{host.hostname || 'Dispositivo local'}{neighbor?.mac ? ` · ${neighbor.mac}` : ''}</p>
                  {host.ports.length > 0 ? <div className="ktc-network-ports">{host.ports.map(port => <span key={`${host.address}-${port.port}`}>{port.port}/{port.protocol} · {port.service || port.state}</span>)}</div> : <p>Detectado; este preset não enumerou serviços.</p>}
                </button>
                {!host.address.includes('/') && <button type="button" className="ktc-host-profile" onClick={() => void profileHost(host.address)} disabled={scanning}>Aprofundar neste host →</button>}
              </article>;
            })}
          </div>}
        </div>}

        {selectedHost && <div className="ktc-host-detail">
          <div className="ktc-host-detail-head"><div><small>Perfil selecionado</small><h3>{selectedHost.address}</h3><span>{selectedHost.hostname || 'sem hostname'}{selectedNeighbor?.mac ? ` · MAC ${selectedNeighbor.mac}` : ''}</span></div><span className={`ktc-risk ktc-risk--${selectedInsight?.highestSeverity || 'info'}`}>atenção {SEVERITY_LABEL[selectedInsight?.highestSeverity || 'info']}</span></div>
          <div className="ktc-host-detail-grid">
            <div><strong>Serviços observados</strong>{selectedHost.ports.length ? selectedHost.ports.map(port => <p key={port.port}><b>{port.port}/{port.protocol}</b> {port.service || 'serviço não identificado'} {port.version ? `· ${port.version}` : ''}</p>) : <p>Nenhuma porta enumerada neste resultado.</p>}</div>
            <div><strong>O que merece revisão</strong>{selectedInsight?.findings.length ? selectedInsight.findings.map(finding => <div className="ktc-finding" key={finding.id}><span className={`ktc-risk ktc-risk--${finding.severity}`}>{SEVERITY_LABEL[finding.severity]}</span><b>{finding.title}</b><p>{finding.why}</p><small>{finding.recommendation}</small></div>) : <p>Nenhum indicador adicional foi gerado para as portas observadas. Isso não equivale a certificação de segurança.</p>}</div>
          </div>
        </div>}
      </>}

      {tab === 'map' && <div className="ktc-network-map-view">
        <div className="ktc-network-map-cards"><article><small>Gateway preferido</small><strong>{diagnostics?.defaultRoutes[0]?.gateway || 'não detectado'}</strong><span>{diagnostics?.defaultRoutes[0]?.interfaceAddress || '—'}</span></article><article><small>Servidores DNS</small><strong>{diagnostics?.dnsServers.length || 0}</strong><span>{diagnostics?.dnsServers.join(', ') || 'não detectados'}</span></article><article><small>Vizinhos ARP</small><strong>{diagnostics?.neighbors.length || 0}</strong><span>cache local, sem probe ativo</span></article></div>
        <div className="ktc-neighbor-table"><header><strong>Dispositivos vistos pelo host</strong><button type="button" onClick={() => void loadDiagnostics()} disabled={loadingDiagnostics}>↻ Atualizar</button></header>{diagnostics?.neighbors.length ? diagnostics.neighbors.map(item => <button type="button" key={`${item.interfaceAddress}-${item.address}-${item.mac}`} onClick={() => { setTab('guided'); setTarget(item.address); setPreset('services'); setSelectedHostAddress(item.address); }}><span>{item.address}</span><code>{item.mac}</code><small>{item.state}</small></button>) : <p>Nenhuma entrada ARP disponível nesta sessão.</p>}</div>
      </div>}

      {tab === 'history' && <div className="ktc-network-history">
        <div className="ktc-history-head"><div><strong>Evidências locais</strong><span>Até 20 avaliações por usuário; sem argv, comandos ou tokens.</span></div><button type="button" onClick={() => setHistory([])} disabled={!history.length}>Limpar histórico</button></div>
        {history.length === 0 ? <p className="ktc-network-empty">Execute uma avaliação para criar a primeira evidência.</p> : history.map(item => <article key={item.id}><div><small>{new Date(item.completedAt).toLocaleString()}</small><strong>{item.label || item.preset}</strong><span>{item.target} · {item.hosts.length} host(s) · {formatDuration(item.durationMs)}</span></div><span className={`ktc-risk ktc-risk--${item.highestSeverity}`}>{SEVERITY_LABEL[item.highestSeverity]}</span></article>)}
      </div>}

      {tab === 'wifi' && <div className="ktc-network-wifi-view">
        <div className="ktc-network-actions"><button type="button" onClick={() => void loadWifi()} disabled={loadingWifi}>{loadingWifi ? 'Consultando…' : '↻ Atualizar diagnóstico Wi‑Fi'}</button></div>
        {wifi ? <details className="ktc-network-wifi" open><summary>Wi‑Fi local · {wifi.available ? 'diagnóstico disponível' : 'indisponível'}</summary><p>{wifi.note}</p><div className="ktc-network-wifi-grid"><div><strong>Interface / conexão</strong><pre>{wifi.interfaces || 'Nenhuma informação retornada.'}</pre></div><div><strong>Redes visíveis</strong><pre>{wifi.visibleNetworks || 'Nenhuma informação retornada.'}</pre></div></div></details> : <p className="ktc-network-empty">Abra o diagnóstico para consultar a interface e as redes visíveis do host Windows.</p>}
        <div className="ktc-network-lab-note"><strong>Aircrack-ng / Wifite / Reaver</strong><span>Continuam no catálogo para laboratório autorizado. O assistente não automatiza deauth, injeção, cracking, captura de credenciais ou brute force.</span></div>
      </div>}
    </section>
  );
}
