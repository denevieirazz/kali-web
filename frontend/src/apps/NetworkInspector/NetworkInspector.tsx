import { useCallback, useEffect, useMemo, useState } from 'react';
import { apiClient } from '../../services/apiClient';
import { getUserStorageKey } from '../../services/userScope.js';
import './NetworkInspector.css';

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
};

type NetworkNeighbor = {
  interfaceAddress: string | null;
  address: string;
  mac: string;
  state: string;
};

type DefaultRoute = {
  destination: string;
  netmask: string;
  gateway: string;
  interfaceAddress: string;
  metric: number | null;
};

type NetworkDiagnostics = {
  collectedAt: string;
  dnsServers: string[];
  neighbors: NetworkNeighbor[];
  defaultRoutes: DefaultRoute[];
  capabilities: { neighbors: boolean; routes: boolean; dns: boolean };
};

type RouteHop = {
  hop: number;
  address: string | null;
  averageMs: number | null;
  samplesMs: number[];
  timedOut: boolean;
};

type HostDiagnostics = {
  schemaVersion: number;
  kind: string;
  target: string;
  startedAt: string;
  completedAt: string;
  durationMs: number;
  identity: {
    reverseDns: string[];
    mac: string | null;
    neighborState: string | null;
    interfaceAddress: string | null;
    isDefaultGateway: boolean;
  };
  reachability: {
    available: boolean;
    reachable: boolean;
    attempts: number;
    replies: number;
    lossPercent: number | null;
    samplesMs: number[];
    minMs: number | null;
    maxMs: number | null;
    averageMs: number | null;
    ttl: number | null;
    source: string;
  };
  route: {
    available: boolean;
    hops: RouteHop[];
    hopCount: number;
    source: string;
  };
  localNetwork: {
    defaultGateway: string | null;
    dnsServers: string[];
  };
  nextSteps: string[];
  policy: {
    privateIpv4Only: boolean;
    activeProbe: boolean;
    methods: string[];
    maxTracerouteHops: number;
    arbitraryArguments: boolean;
    credentialAttacks: boolean;
    activeWirelessAttacks: boolean;
  };
};

type HistoryItem = {
  target: string;
  completedAt: string;
  reachable: boolean;
  averageMs: number | null;
  mac: string | null;
  reverseDns: string[];
  hopCount: number;
};

const HISTORY_KEY = 'cloudos-network-inspector-history-v1';

function storageKey() {
  return getUserStorageKey(HISTORY_KEY);
}

function loadHistory(): HistoryItem[] {
  try {
    const parsed = JSON.parse(localStorage.getItem(storageKey()) || '[]');
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(item => item && typeof item.target === 'string' && typeof item.completedAt === 'string').slice(0, 10);
  } catch {
    localStorage.removeItem(storageKey());
    return [];
  }
}

function looksLikePrivateIpv4(value: string) {
  return /^(?:10\.|127\.|169\.254\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.)\d{1,3}\.\d{1,3}$/.test(value.trim());
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

function formatLatency(value: number | null) {
  return value === null ? '—' : `${value} ms`;
}

export default function NetworkInspector() {
  const [overview, setOverview] = useState<NetworkOverview | null>(null);
  const [network, setNetwork] = useState<NetworkDiagnostics | null>(null);
  const [target, setTarget] = useState('');
  const [result, setResult] = useState<HostDiagnostics | null>(null);
  const [history, setHistory] = useState<HistoryItem[]>(loadHistory);
  const [loadingNetwork, setLoadingNetwork] = useState(true);
  const [loadingHost, setLoadingHost] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  useEffect(() => {
    localStorage.setItem(storageKey(), JSON.stringify(history.slice(0, 10)));
  }, [history]);

  const refreshNetwork = useCallback(async () => {
    setLoadingNetwork(true);
    setError('');
    try {
      const [overviewData, diagnosticsData] = await Promise.all([
        apiClient<NetworkOverview>('/api/security/tools/network/overview', { timeoutMs: 12000 }),
        apiClient<NetworkDiagnostics>('/api/security/tools/network/diagnostics', { timeoutMs: 15000 }),
      ]);
      setOverview(overviewData);
      setNetwork(diagnosticsData);
      setTarget(current => current || diagnosticsData.defaultRoutes[0]?.gateway || diagnosticsData.neighbors[0]?.address || overviewData.interfaces.find(item => item.privateLocal && !item.internal)?.address || '');
      setNotice(`Mapa local atualizado: ${diagnosticsData.neighbors.length} vizinho(s), ${diagnosticsData.dnsServers.length} DNS.`);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Não foi possível mapear a rede local.');
    } finally {
      setLoadingNetwork(false);
    }
  }, []);

  useEffect(() => { void refreshNetwork(); }, [refreshNetwork]);

  const runDiagnostics = async (candidate = target) => {
    const normalized = candidate.trim();
    if (!looksLikePrivateIpv4(normalized)) {
      setError('Informe um IPv4 privado/local, por exemplo 192.168.1.1.');
      return;
    }
    setLoadingHost(true);
    setError('');
    setNotice('');
    try {
      const data = await apiClient<HostDiagnostics>('/api/security/tools/network/host/diagnostics', {
        method: 'POST', timeoutMs: 20000,
        body: JSON.stringify({ target: normalized }),
      });
      setTarget(normalized);
      setResult(data);
      setHistory(current => [{
        target: data.target,
        completedAt: data.completedAt,
        reachable: data.reachability.reachable,
        averageMs: data.reachability.averageMs,
        mac: data.identity.mac,
        reverseDns: data.identity.reverseDns,
        hopCount: data.route.hopCount,
      }, ...current.filter(item => item.target !== data.target)].slice(0, 10));
      setNotice(`Diagnóstico de ${data.target} concluído.`);
    } catch (cause) {
      setResult(null);
      setError(cause instanceof Error ? cause.message : 'Falha no diagnóstico do dispositivo.');
    } finally {
      setLoadingHost(false);
    }
  };

  const aiPayload = useMemo(() => result ? {
    schemaVersion: 1,
    kind: 'cloudos-network-host-context',
    purpose: 'authorized-defensive-network-troubleshooting',
    target: result.target,
    identity: result.identity,
    reachability: {
      reachable: result.reachability.reachable,
      replies: result.reachability.replies,
      lossPercent: result.reachability.lossPercent,
      averageMs: result.reachability.averageMs,
      ttl: result.reachability.ttl,
    },
    route: result.route.hops.map(hop => ({ hop: hop.hop, address: hop.address, averageMs: hop.averageMs, timedOut: hop.timedOut })),
    localNetwork: result.localNetwork,
    recommendedDefensiveNextSteps: result.nextSteps,
    constraints: {
      privateIpv4Only: true,
      doNotGenerateCredentialAttacks: true,
      doNotGenerateDeauthOrPacketInjection: true,
      doNotTreatReachabilityAsProofOfVulnerability: true,
    },
  } : null, [result]);

  const copyForAi = async () => {
    if (!aiPayload) return;
    try {
      await navigator.clipboard.writeText(JSON.stringify(aiPayload, null, 2));
      setNotice('Contexto do host copiado para a IA do CloudOS.');
    } catch {
      setError('Não foi possível acessar a área de transferência.');
    }
  };

  const exportEvidence = () => {
    if (!aiPayload || !result) return;
    downloadJson(`cloudos-host-${result.target.replace(/\./g, '_')}-${Date.now()}.json`, aiPayload);
    setNotice('Evidência JSON exportada.');
  };

  const gateway = network?.defaultRoutes[0]?.gateway || null;
  const localInterfaces = overview?.interfaces.filter(item => item.privateLocal && !item.internal) || [];

  return <div className="ni-root">
    <header className="ni-hero">
      <div><small>CloudOS · Network Inspector</small><h1>Diagnóstico de dispositivo</h1><p>Entenda um IP da sua rede sem precisar decorar ping, ARP, DNS ou traceroute.</p></div>
      <div className="ni-policy"><span>IPv4 privado</span><span>3 pings</span><span>máx. 8 hops</span><span>sem argv livre</span></div>
    </header>

    {(error || notice) && <div className={`ni-banner ${error ? 'is-error' : ''}`} role={error ? 'alert' : 'status'}><span>{error || notice}</span><button type="button" onClick={() => { setError(''); setNotice(''); }}>×</button></div>}

    <section className="ni-overview">
      <article><small>Computador</small><strong>{overview?.host || 'CloudOS'}</strong><span>{localInterfaces.map(item => `${item.name} · ${item.address}`).join(' | ') || 'identificando interface…'}</span></article>
      <article><small>Gateway</small><strong>{gateway || '—'}</strong><button type="button" disabled={!gateway} onClick={() => gateway && void runDiagnostics(gateway)}>Diagnosticar gateway</button></article>
      <article><small>DNS</small><strong>{network?.dnsServers.length || 0}</strong><span>{network?.dnsServers.join(', ') || 'não detectado'}</span></article>
      <article><small>Vizinhos vistos</small><strong>{network?.neighbors.length || 0}</strong><button type="button" onClick={() => void refreshNetwork()} disabled={loadingNetwork}>{loadingNetwork ? 'Mapeando…' : '↻ Atualizar'}</button></article>
    </section>

    <section className="ni-runner">
      <label><span>IPv4 privado/local</span><input value={target} onChange={event => setTarget(event.target.value)} placeholder="192.168.1.1" onKeyDown={event => { if (event.key === 'Enter') void runDiagnostics(); }} /></label>
      <button type="button" className="ni-primary" onClick={() => void runDiagnostics()} disabled={loadingHost}>{loadingHost ? 'Diagnosticando…' : '▶ Diagnosticar dispositivo'}</button>
      <p>O CloudOS faz somente conectividade, rota, DNS reverso e correlação com o cache ARP local.</p>
    </section>

    <div className="ni-layout">
      <section className="ni-neighbors">
        <header><div><small>Cache ARP</small><strong>Dispositivos vistos pelo Windows</strong></div><span>{network?.neighbors.length || 0}</span></header>
        <div className="ni-neighbor-list">
          {network?.neighbors.length ? network.neighbors.slice(0, 80).map(item => <button type="button" key={`${item.interfaceAddress}-${item.address}-${item.mac}`} onClick={() => { setTarget(item.address); void runDiagnostics(item.address); }}><div><strong>{item.address}</strong><span>{item.state}</span></div><code>{item.mac}</code></button>) : <p>Nenhum vizinho disponível no cache local.</p>}
        </div>
      </section>

      <main className="ni-result">
        {!result ? <div className="ni-empty"><span>⌁</span><strong>Escolha um IP ou um vizinho da rede.</strong><p>O perfil aparece aqui com identidade, latência e caminho.</p></div> : <>
          <div className="ni-result-head"><div><small>Perfil do host</small><h2>{result.target}</h2><span>{result.identity.reverseDns[0] || (result.identity.isDefaultGateway ? 'gateway local' : 'sem PTR conhecido')}</span></div><span className={`ni-reach ${result.reachability.reachable ? 'is-up' : 'is-down'}`}>{result.reachability.reachable ? 'respondendo' : 'sem resposta ICMP'}</span></div>

          <div className="ni-metrics">
            <article><small>MAC</small><strong>{result.identity.mac || '—'}</strong><span>{result.identity.neighborState || 'não está no ARP'}</span></article>
            <article><small>Latência média</small><strong>{formatLatency(result.reachability.averageMs)}</strong><span>{result.reachability.replies}/{result.reachability.attempts} respostas · perda {result.reachability.lossPercent ?? '—'}%</span></article>
            <article><small>TTL</small><strong>{result.reachability.ttl ?? '—'}</strong><span>apenas evidência de rede</span></article>
            <article><small>Caminho</small><strong>{result.route.hopCount}</strong><span>hop(s) respondendo</span></article>
          </div>

          {result.identity.reverseDns.length > 0 && <section className="ni-block"><header><strong>Nomes DNS reversos</strong></header><div className="ni-chips">{result.identity.reverseDns.map(name => <span key={name}>{name}</span>)}</div></section>}

          <section className="ni-block"><header><strong>Rota até o dispositivo</strong><span>máximo {result.policy.maxTracerouteHops} hops</span></header>{result.route.hops.length ? <div className="ni-route">{result.route.hops.map(hop => <div key={hop.hop}><b>{hop.hop}</b><span>{hop.address || 'sem resposta'}</span><small>{formatLatency(hop.averageMs)}</small></div>)}</div> : <p>Nenhum hop foi retornado nesta coleta.</p>}</section>

          <section className="ni-block"><header><strong>O que fazer agora</strong><span>orientação defensiva</span></header><ol className="ni-steps">{result.nextSteps.map((step, index) => <li key={`${index}-${step}`}>{step}</li>)}</ol></section>

          <section className="ni-actions"><button type="button" onClick={() => void copyForAi()}>Copiar para IA</button><button type="button" onClick={exportEvidence}>Exportar JSON</button><button type="button" onClick={() => void runDiagnostics(result.target)} disabled={loadingHost}>↻ Repetir diagnóstico</button></section>
        </>}
      </main>
    </div>

    <section className="ni-history"><header><div><small>Últimos dispositivos</small><strong>Histórico local</strong></div><button type="button" onClick={() => setHistory([])} disabled={!history.length}>Limpar</button></header><div>{history.length ? history.map(item => <button type="button" key={`${item.target}-${item.completedAt}`} onClick={() => { setTarget(item.target); void runDiagnostics(item.target); }}><strong>{item.target}</strong><span>{item.reverseDns[0] || item.mac || 'sem identidade adicional'}</span><small>{item.reachable ? `online · ${formatLatency(item.averageMs)}` : 'sem resposta ICMP'} · {item.hopCount} hop(s)</small></button>) : <p>Nenhum diagnóstico salvo ainda.</p>}</div></section>

    <footer className="ni-footer"><strong>Ferramentas por trás da experiência</strong><span>ARP / DNS reverso / ICMP / traceroute no host Windows. Nmap e ferramentas Linux continuam no Kali Tool Center para assessment autorizado.</span></footer>
  </div>;
}
