import { useCallback, useEffect, useMemo, useState } from 'react';
import { apiClient } from '../../services/apiClient';
import './NetworkShield.css';

type Attention = 'info' | 'medium' | 'high';
type FirewallProfile = { name: string; enabled: boolean; defaultInboundAction: string; defaultOutboundAction: string };
type NetworkProfile = { interfaceAlias: string; name: string; category: string; ipv4Connectivity: string; ipv6Connectivity: string };
type Listener = { localAddress: string; port: number; processId: number | null; exposure: 'loopback' | 'all-interfaces' | 'specific-interface' | 'unknown' };
type LocalPosture = {
  available: boolean;
  source: string;
  collectedAt: string;
  firewall: FirewallProfile[];
  networkProfiles: NetworkProfile[];
  listeners: Listener[];
  summary: {
    highestAttention: Attention;
    firewallProfiles: number;
    disabledFirewallProfiles: string[];
    listeners: number;
    wildcardListeners: number;
    loopbackListeners: number;
    specificListeners: number;
  };
  recommendations: string[];
  policy: { readOnly: boolean; localMachineOnly: boolean; arbitraryArguments: boolean; firewallMutation?: boolean; processNamesExposed?: boolean };
};

const ATTENTION = { info: 'normal', medium: 'atenção', high: 'prioridade' } as const;
const EXPOSURE_LABEL = {
  'loopback': 'somente este PC',
  'all-interfaces': 'todas as interfaces',
  'specific-interface': 'interface específica',
  'unknown': 'não identificado',
} as const;

function downloadJson(filename: string, payload: unknown) {
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 0);
}

export default function NetworkShield() {
  const [data, setData] = useState<LocalPosture | null>(null);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<'all' | Listener['exposure']>('all');
  const [portSearch, setPortSearch] = useState('');
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  const refresh = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const result = await apiClient<LocalPosture>('/api/security/tools/network/local-posture', { timeoutMs: 16000 });
      setData(result);
      setNotice(result.available ? `Postura local atualizada: ${result.summary.listeners} porta(s) TCP em escuta.` : 'O Windows não forneceu a postura local nesta sessão.');
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Não foi possível consultar a postura de rede local.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);

  const listeners = useMemo(() => {
    const query = portSearch.trim();
    return (data?.listeners || []).filter(listener => {
      if (filter !== 'all' && listener.exposure !== filter) return false;
      if (query && !`${listener.port} ${listener.localAddress} ${listener.processId ?? ''}`.includes(query)) return false;
      return true;
    });
  }, [data?.listeners, filter, portSearch]);

  const aiPayload = useMemo(() => data ? {
    schemaVersion: 1,
    kind: 'cloudos-local-network-posture',
    purpose: 'authorized-defensive-local-machine-review',
    collectedAt: data.collectedAt,
    firewall: data.firewall,
    networkProfiles: data.networkProfiles,
    listeners: data.listeners.map(listener => ({ localAddress: listener.localAddress, port: listener.port, exposure: listener.exposure })),
    summary: data.summary,
    recommendations: data.recommendations,
    constraints: {
      readOnly: true,
      localMachineOnly: true,
      doNotDisableFirewall: true,
      doNotGenerateCredentialAttacks: true,
      openListenerDoesNotEqualVulnerability: true,
    },
  } : null, [data]);

  const copyForAi = async () => {
    if (!aiPayload) return;
    try {
      await navigator.clipboard.writeText(JSON.stringify(aiPayload, null, 2));
      setNotice('Postura local copiada para a IA do CloudOS.');
    } catch {
      setError('Não foi possível acessar a área de transferência.');
    }
  };

  const exportEvidence = () => {
    if (!aiPayload) return;
    downloadJson(`cloudos-network-shield-${Date.now()}.json`, aiPayload);
    setNotice('Relatório de postura local exportado.');
  };

  return <div className="ns-root">
    <header className="ns-hero">
      <div><small>CloudOS · Network Shield</small><h1>Postura de rede deste PC</h1><p>Firewall, perfil da conexão e portas locais em escuta traduzidos para uma revisão simples.</p></div>
      <div className="ns-actions"><button type="button" onClick={() => void refresh()} disabled={loading}>{loading ? 'Consultando…' : '↻ Atualizar'}</button><button type="button" onClick={() => void copyForAi()} disabled={!aiPayload}>Copiar para IA</button><button type="button" onClick={exportEvidence} disabled={!aiPayload}>Exportar JSON</button></div>
    </header>

    {(error || notice) && <div className={`ns-banner ${error ? 'is-error' : ''}`}><span>{error || notice}</span><button type="button" onClick={() => { setError(''); setNotice(''); }}>×</button></div>}

    <section className="ns-stats">
      <article><small>Leitura geral</small><strong className={`ns-attention ns-attention--${data?.summary.highestAttention || 'info'}`}>{ATTENTION[data?.summary.highestAttention || 'info']}</strong><span>coleta somente leitura</span></article>
      <article><small>Firewall</small><strong>{data?.summary.firewallProfiles ?? 0}</strong><span>{data?.summary.disabledFirewallProfiles.length ? `${data.summary.disabledFirewallProfiles.length} perfil(is) desativado(s)` : 'nenhum perfil desativado detectado'}</span></article>
      <article><small>Portas em escuta</small><strong>{data?.summary.listeners ?? 0}</strong><span>TCP local</span></article>
      <article><small>Todas interfaces</small><strong>{data?.summary.wildcardListeners ?? 0}</strong><span>merecem confirmar necessidade</span></article>
      <article><small>Somente local</small><strong>{data?.summary.loopbackListeners ?? 0}</strong><span>loopback</span></article>
      <article><small>Interface específica</small><strong>{data?.summary.specificListeners ?? 0}</strong><span>endereço local dedicado</span></article>
    </section>

    <div className="ns-layout">
      <main>
        <section className="ns-panel ns-recommendations">
          <header><div><small>Assistente defensivo</small><strong>O que revisar</strong></div><span className={`ns-attention ns-attention--${data?.summary.highestAttention || 'info'}`}>{ATTENTION[data?.summary.highestAttention || 'info']}</span></header>
          {data?.recommendations.length ? <ol>{data.recommendations.map((item, index) => <li key={`${index}-${item}`}>{item}</li>)}</ol> : <p>Atualize a coleta para gerar recomendações.</p>}
          <p className="ns-disclaimer">Uma porta em escuta não é, por si só, uma vulnerabilidade. O objetivo aqui é identificar exposição que precisa ser explicada pela função real da máquina.</p>
        </section>

        <section className="ns-panel ns-listeners">
          <header><div><small>Superfície local</small><strong>Portas TCP em escuta</strong></div><span>{listeners.length}/{data?.listeners.length || 0}</span></header>
          <div className="ns-filters"><select value={filter} onChange={event => setFilter(event.target.value as typeof filter)}><option value="all">Todas</option><option value="all-interfaces">Todas as interfaces</option><option value="specific-interface">Interface específica</option><option value="loopback">Somente este PC</option></select><input value={portSearch} onChange={event => setPortSearch(event.target.value)} placeholder="Filtrar porta ou IP…" /></div>
          <div className="ns-listener-list">{listeners.length ? listeners.map((listener, index) => <article key={`${listener.localAddress}-${listener.port}-${index}`}><div><strong>{listener.port}/TCP</strong><span>{listener.localAddress}</span></div><span className={`ns-exposure ns-exposure--${listener.exposure}`}>{EXPOSURE_LABEL[listener.exposure]}</span><small>PID {listener.processId ?? '—'}</small></article>) : <p>Nenhuma porta corresponde ao filtro.</p>}</div>
        </section>
      </main>

      <aside>
        <section className="ns-panel ns-firewall">
          <header><div><small>Windows Firewall</small><strong>Perfis</strong></div><span>{data?.firewall.length || 0}</span></header>
          <div>{data?.firewall.length ? data.firewall.map(profile => <article key={profile.name}><div><strong>{profile.name}</strong><span>{profile.enabled ? 'ativado' : 'desativado'}</span></div><b className={profile.enabled ? 'is-on' : 'is-off'}>{profile.enabled ? 'ON' : 'OFF'}</b><small>Entrada: {profile.defaultInboundAction} · Saída: {profile.defaultOutboundAction}</small></article>) : <p>Perfis não disponíveis.</p>}</div>
        </section>

        <section className="ns-panel ns-profiles">
          <header><div><small>Conexões</small><strong>Perfil da rede</strong></div></header>
          <div>{data?.networkProfiles.length ? data.networkProfiles.map((profile, index) => <article key={`${profile.interfaceAlias}-${profile.name}-${index}`}><strong>{profile.interfaceAlias || 'Interface'}</strong><span>{profile.name || 'sem nome'} · {profile.category}</span><small>IPv4 {profile.ipv4Connectivity} · IPv6 {profile.ipv6Connectivity}</small></article>) : <p>Nenhum perfil retornado.</p>}</div>
        </section>

        <section className="ns-panel ns-boundary"><header><div><small>Boundary</small><strong>Sem alteração automática</strong></div></header><p>O Network Shield apenas lê estado do Firewall, perfil da rede e listeners TCP. Ele não desativa proteção, não abre porta, não encerra processo e não recebe comandos do frontend.</p></section>
      </aside>
    </div>
  </div>;
}
