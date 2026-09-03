import { useState } from 'react';
import { apiClient } from '../../services/apiClient';
import { launchWorkflowApp } from '../../services/workflowLaunch';
import './QuickEnvironmentChecks.css';

type Mode = 'network' | 'wifi' | 'firewall' | 'listeners';
type NetworkDiagnostics = {
  dnsServers: string[];
  neighbors: Array<{ interfaceAddress: string | null; address: string; mac: string; state: string }>;
  defaultRoutes: Array<{ gateway: string; interfaceAddress: string; metric: number | null }>;
  collectedAt: string;
};
type WifiDiagnostics = {
  available: boolean;
  summary?: {
    connected: { ssid: string | null; bssid: string | null; signal: string | null; channel: string | null; authentication: string | null; cipher: string | null; receiveRateMbps: string | null; transmitRateMbps: string | null };
    networks: Array<{ ssid: string; authentication: string | null; cipher: string | null; radios: Array<{ bssid: string; signal: string | null; channel: string | null }> }>;
  };
  health?: { highestAttention: string; connectedSecurity: { label: string }; signalPercent: number | null; currentChannel: string | null; currentChannelOccupancy: number; visibleNetworkCount: number; openOrLegacyNetworks: number; recommendations: string[] };
};
type LocalPosture = {
  available: boolean;
  firewall: Array<{ name: string; enabled: boolean; defaultInboundAction: string; defaultOutboundAction: string }>;
  networkProfiles: Array<{ interfaceAlias: string; name: string; category: string; ipv4Connectivity: string; ipv6Connectivity: string }>;
  listeners: Array<{ localAddress: string; port: number; processId: number | null; exposure: string }>;
  summary: { highestAttention: string; firewallProfiles: number; disabledFirewallProfiles: string[]; listeners: number; wildcardListeners: number; loopbackListeners: number; specificListeners: number };
  recommendations: string[];
};

type Block = { id: Mode; icon: string; title: string; description: string; appId: string };
const BLOCKS: Block[] = [
  { id: 'network', icon: '🗺️', title: 'Mapa local', description: 'Gateway, DNS e vizinhos ARP observados neste PC.', appId: 'network-inspector' },
  { id: 'wifi', icon: '📶', title: 'Wi‑Fi agora', description: 'SSID, sinal, canal, segurança e redes visíveis.', appId: 'wifi-inspector' },
  { id: 'firewall', icon: '🛡️', title: 'Firewall do PC', description: 'Perfis do Firewall do Windows e perfil atual da rede.', appId: 'network-shield' },
  { id: 'listeners', icon: '👂', title: 'Portas deste PC', description: 'Listeners TCP locais e quais estão em todas as interfaces.', appId: 'network-shield' },
];

export default function QuickEnvironmentChecks() {
  const [mode, setMode] = useState<Mode>('network');
  const [network, setNetwork] = useState<NetworkDiagnostics | null>(null);
  const [wifi, setWifi] = useState<WifiDiagnostics | null>(null);
  const [posture, setPosture] = useState<LocalPosture | null>(null);
  const [loading, setLoading] = useState<Mode | ''>('');
  const [error, setError] = useState('');

  const run = async (selected: Mode) => {
    setMode(selected); setError('');
    if (selected === 'network' && network) return;
    if (selected === 'wifi' && wifi) return;
    if ((selected === 'firewall' || selected === 'listeners') && posture) return;
    setLoading(selected);
    try {
      if (selected === 'network') setNetwork(await apiClient<NetworkDiagnostics>('/api/security/tools/network/diagnostics', { timeoutMs: 15_000 }));
      else if (selected === 'wifi') setWifi(await apiClient<WifiDiagnostics>('/api/security/tools/network/wifi', { timeoutMs: 15_000 }));
      else setPosture(await apiClient<LocalPosture>('/api/security/tools/network/local-posture', { timeoutMs: 15_000 }));
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Não foi possível concluir a coleta local.'); }
    finally { setLoading(''); }
  };

  const copyCurrent = async () => {
    const payload = mode === 'network' ? network : mode === 'wifi' ? wifi : posture;
    if (!payload) return;
    try { await navigator.clipboard.writeText(JSON.stringify({ kind: `cloudos-quick-${mode}`, payload, constraints: { readOnly: true, localMachineOnly: mode !== 'network' || true } }, null, 2)); }
    catch { setError('Não foi possível copiar a evidência.'); }
  };

  return <section className="qec-root" aria-label="Checks do ambiente local">
    <header className="qec-head"><div><small>Este PC · somente leitura</small><h2>Quatro botões para entender o ambiente</h2><p>Essas coletas não dependem do Kali e não mudam Firewall, Wi‑Fi ou configuração de rede.</p></div></header>
    {error && <div className="qec-error">{error}<button type="button" onClick={() => setError('')}>×</button></div>}
    <div className="qec-grid">{BLOCKS.map(block => <article key={block.id} className={mode === block.id ? 'is-active' : ''}><div>{block.icon}</div><strong>{block.title}</strong><p>{block.description}</p><div className="qec-actions"><button type="button" disabled={Boolean(loading)} onClick={() => void run(block.id)}>{loading === block.id ? 'Lendo…' : 'Ver agora →'}</button><button type="button" onClick={() => launchWorkflowApp(block.appId)}>App completo</button></div></article>)}</div>

    {mode === 'network' && network && <section className="qec-result"><header><strong>Mapa local</strong><button type="button" onClick={() => void copyCurrent()}>Copiar</button></header><div className="qec-metrics"><article><small>Gateway</small><strong>{network.defaultRoutes[0]?.gateway || '—'}</strong></article><article><small>DNS</small><strong>{network.dnsServers.length}</strong></article><article><small>Vizinhos ARP</small><strong>{network.neighbors.length}</strong></article></div><div className="qec-list">{network.neighbors.slice(0, 12).map(item => <div key={`${item.address}-${item.mac}`}><b>{item.address}</b><span>{item.mac}</span><small>{item.state}</small></div>)}</div></section>}

    {mode === 'wifi' && wifi && <section className="qec-result"><header><strong>Wi‑Fi atual</strong><button type="button" onClick={() => void copyCurrent()}>Copiar</button></header><div className="qec-metrics"><article><small>SSID</small><strong>{wifi.summary?.connected.ssid || '—'}</strong></article><article><small>Sinal</small><strong>{wifi.summary?.connected.signal || '—'}</strong></article><article><small>Canal</small><strong>{wifi.summary?.connected.channel || '—'}</strong></article><article><small>Segurança</small><strong>{wifi.health?.connectedSecurity.label || '—'}</strong></article><article><small>Redes visíveis</small><strong>{wifi.health?.visibleNetworkCount ?? 0}</strong></article></div>{wifi.health?.recommendations.length ? <div className="qec-recommend">{wifi.health.recommendations.map((item, index) => <p key={`${index}-${item}`}>{item}</p>)}</div> : null}</section>}

    {mode === 'firewall' && posture && <section className="qec-result"><header><strong>Firewall e perfil de rede</strong><button type="button" onClick={() => void copyCurrent()}>Copiar</button></header><div className="qec-metrics"><article><small>Perfis</small><strong>{posture.summary.firewallProfiles}</strong></article><article><small>Desativados</small><strong>{posture.summary.disabledFirewallProfiles.length}</strong></article><article><small>Atenção</small><strong>{posture.summary.highestAttention}</strong></article></div><div className="qec-list">{posture.firewall.map(item => <div key={item.name}><b>{item.name}</b><span>{item.enabled ? 'ativado' : 'desativado'}</span><small>Entrada {item.defaultInboundAction} · saída {item.defaultOutboundAction}</small></div>)}</div>{posture.recommendations.map((item, index) => <p className="qec-tip" key={`${index}-${item}`}>{item}</p>)}</section>}

    {mode === 'listeners' && posture && <section className="qec-result"><header><strong>Portas TCP deste PC</strong><button type="button" onClick={() => void copyCurrent()}>Copiar</button></header><div className="qec-metrics"><article><small>Total</small><strong>{posture.summary.listeners}</strong></article><article><small>Todas interfaces</small><strong>{posture.summary.wildcardListeners}</strong></article><article><small>Somente local</small><strong>{posture.summary.loopbackListeners}</strong></article></div><div className="qec-list">{posture.listeners.slice(0, 40).map(item => <div key={`${item.localAddress}-${item.port}-${item.processId}`}><b>{item.localAddress}:{item.port}</b><span>{item.exposure}</span><small>PID {item.processId ?? '—'}</small></div>)}</div></section>}
  </section>;
}
