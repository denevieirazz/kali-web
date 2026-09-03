import { useCallback, useEffect, useMemo, useState } from 'react';
import { apiClient } from '../../services/apiClient';
import './WifiInspector.css';

type WifiRadio = {
  bssid: string;
  signal: string | null;
  channel: string | null;
  radioType: string | null;
};

type WifiNetwork = {
  ssid: string;
  authentication: string | null;
  cipher: string | null;
  radios: WifiRadio[];
};

type WifiConnected = {
  name: string | null;
  state: string | null;
  ssid: string | null;
  bssid: string | null;
  signal: string | null;
  channel: string | null;
  radioType: string | null;
  authentication: string | null;
  cipher: string | null;
  receiveRateMbps: string | null;
  transmitRateMbps: string | null;
};

type WifiHealth = {
  highestAttention: 'info' | 'low' | 'medium' | 'high';
  connectedSecurity: { attention: 'info' | 'low' | 'medium' | 'high'; label: string };
  signalPercent: number | null;
  currentChannel: string | null;
  currentChannelOccupancy: number;
  channelOccupancy: Record<string, number>;
  visibleNetworkCount: number;
  visibleRadioCount: number;
  openOrLegacyNetworks: number;
  recommendations: string[];
  note: string;
};

type WifiDiagnostics = {
  available: boolean;
  source: string;
  interfaces: string;
  visibleNetworks: string;
  note: string;
  summary?: { connected: WifiConnected; networks: WifiNetwork[] };
  health?: WifiHealth;
};

const ATTENTION_LABEL = {
  info: 'normal',
  low: 'baixo',
  medium: 'atenção',
  high: 'prioridade',
} as const;

function signalNumber(value: string | null) {
  const match = String(value || '').match(/(\d{1,3})\s*%/);
  return match ? Math.max(0, Math.min(100, Number(match[1]))) : -1;
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

export default function WifiInspector() {
  const [data, setData] = useState<WifiDiagnostics | null>(null);
  const [loading, setLoading] = useState(true);
  const [query, setQuery] = useState('');
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  const refresh = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const result = await apiClient<WifiDiagnostics>('/api/security/tools/network/wifi', { timeoutMs: 15000 });
      setData(result);
      setNotice(result.available ? `Wi‑Fi atualizado: ${result.health?.visibleNetworkCount ?? result.summary?.networks.length ?? 0} rede(s) visível(is).` : 'O host não expôs dados Wi‑Fi nesta sessão.');
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Não foi possível consultar o Wi‑Fi local.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);

  const networks = useMemo(() => {
    const normalizedQuery = query.trim().toLowerCase();
    return [...(data?.summary?.networks || [])]
      .filter(network => !normalizedQuery || `${network.ssid} ${network.authentication || ''} ${network.cipher || ''}`.toLowerCase().includes(normalizedQuery))
      .sort((a, b) => Math.max(...b.radios.map(radio => signalNumber(radio.signal)), -1) - Math.max(...a.radios.map(radio => signalNumber(radio.signal)), -1));
  }, [data?.summary?.networks, query]);

  const channels = useMemo(() => Object.entries(data?.health?.channelOccupancy || {}).sort((a, b) => Number(a[0]) - Number(b[0])), [data?.health?.channelOccupancy]);

  const aiPayload = useMemo(() => data?.summary && data.health ? {
    schemaVersion: 1,
    kind: 'cloudos-wifi-health-context',
    purpose: 'authorized-defensive-wifi-troubleshooting',
    connected: data.summary.connected,
    health: data.health,
    visibleNetworks: data.summary.networks.map(network => ({
      ssid: network.ssid,
      authentication: network.authentication,
      cipher: network.cipher,
      radios: network.radios.map(radio => ({ signal: radio.signal, channel: radio.channel, radioType: radio.radioType })),
    })),
    constraints: {
      readOnly: true,
      doNotGenerateCredentialAttacks: true,
      doNotGenerateDeauthOrPacketInjection: true,
      doNotAttemptCracking: true,
    },
  } : null, [data]);

  const copyForAi = async () => {
    if (!aiPayload) return;
    try {
      await navigator.clipboard.writeText(JSON.stringify(aiPayload, null, 2));
      setNotice('Contexto de saúde Wi‑Fi copiado para a IA do CloudOS.');
    } catch {
      setError('Não foi possível acessar a área de transferência.');
    }
  };

  const exportEvidence = () => {
    if (!aiPayload) return;
    downloadJson(`cloudos-wifi-health-${Date.now()}.json`, aiPayload);
    setNotice('Relatório Wi‑Fi JSON exportado.');
  };

  const connected = data?.summary?.connected;
  const health = data?.health;

  return <div className="wi-root">
    <header className="wi-hero">
      <div><small>CloudOS · Wi‑Fi Inspector</small><h1>Saúde da rede sem fio</h1><p>Veja sinal, proteção, canal e concorrência sem precisar usar ferramentas de ataque.</p></div>
      <div className="wi-actions"><button type="button" onClick={() => void refresh()} disabled={loading}>{loading ? 'Consultando…' : '↻ Atualizar'}</button><button type="button" onClick={() => void copyForAi()} disabled={!aiPayload}>Copiar para IA</button><button type="button" onClick={exportEvidence} disabled={!aiPayload}>Exportar JSON</button></div>
    </header>

    {(error || notice) && <div className={`wi-banner ${error ? 'is-error' : ''}`}><span>{error || notice}</span><button type="button" onClick={() => { setError(''); setNotice(''); }}>×</button></div>}

    <section className="wi-current">
      <article><small>Rede atual</small><strong>{connected?.ssid || 'sem conexão identificada'}</strong><span>{connected?.name || connected?.state || 'adaptador indisponível'}</span></article>
      <article><small>Sinal</small><strong>{connected?.signal || '—'}</strong><span>{health?.signalPercent !== null && health?.signalPercent !== undefined ? `${health.signalPercent}% interpretado` : 'sem leitura'}</span></article>
      <article><small>Segurança</small><strong>{health?.connectedSecurity.label || connected?.authentication || '—'}</strong><span>{connected?.cipher || 'cifra não informada'}</span></article>
      <article><small>Canal</small><strong>{health?.currentChannel || connected?.channel || '—'}</strong><span>{health ? `${health.currentChannelOccupancy} rádio(s) visível(is) neste canal` : 'sem ocupação calculada'}</span></article>
      <article><small>Link</small><strong>{connected?.radioType || '—'}</strong><span>↓ {connected?.receiveRateMbps || '—'} Mbps · ↑ {connected?.transmitRateMbps || '—'} Mbps</span></article>
      <article><small>Leitura geral</small><strong className={`wi-attention wi-attention--${health?.highestAttention || 'info'}`}>{ATTENTION_LABEL[health?.highestAttention || 'info']}</strong><span>{health?.openOrLegacyNetworks || 0} rede(s) aberta(s)/legada(s) visível(is)</span></article>
    </section>

    <div className="wi-layout">
      <main>
        <section className="wi-panel wi-recommendations">
          <header><div><small>Assistente</small><strong>O que merece atenção</strong></div><span className={`wi-attention wi-attention--${health?.highestAttention || 'info'}`}>{ATTENTION_LABEL[health?.highestAttention || 'info']}</span></header>
          {health?.recommendations.length ? <ol>{health.recommendations.map((item, index) => <li key={`${index}-${item}`}>{item}</li>)}</ol> : <p>Atualize o diagnóstico para gerar recomendações.</p>}
          {health?.note && <small className="wi-note">{health.note}</small>}
        </section>

        <section className="wi-panel wi-networks">
          <header><div><small>Ambiente</small><strong>Redes visíveis</strong></div><span>{networks.length}</span></header>
          <input value={query} onChange={event => setQuery(event.target.value)} placeholder="Filtrar SSID ou proteção…" aria-label="Filtrar redes Wi-Fi" />
          <div className="wi-network-list">{networks.length ? networks.map((network, index) => {
            const bestSignal = Math.max(...network.radios.map(radio => signalNumber(radio.signal)), -1);
            return <article key={`${network.ssid}-${index}`}><header><div><strong>{network.ssid}</strong><span>{network.authentication || 'proteção não informada'}{network.cipher ? ` · ${network.cipher}` : ''}</span></div><b>{bestSignal >= 0 ? `${bestSignal}%` : '—'}</b></header><div>{network.radios.map(radio => <span key={radio.bssid}>canal {radio.channel || '—'} · {radio.signal || '—'} · {radio.radioType || 'rádio'} · {radio.bssid}</span>)}</div></article>;
          }) : <p>Nenhuma rede corresponde ao filtro.</p>}</div>
        </section>
      </main>

      <aside>
        <section className="wi-panel wi-channels">
          <header><div><small>Espectro lógico</small><strong>Ocupação por canal</strong></div><span>{channels.length}</span></header>
          <div>{channels.length ? channels.map(([channel, count]) => <article key={channel} className={channel === health?.currentChannel ? 'is-current' : ''}><span>Canal {channel}</span><div><i style={{ width: `${Math.min(100, count * 18)}%` }} /></div><strong>{count}</strong></article>) : <p>Sem informação de canais.</p>}</div>
        </section>

        <section className="wi-panel wi-policy">
          <header><div><small>Boundary</small><strong>Modo somente leitura</strong></div></header>
          <p>Este app usa apenas diagnóstico exposto pelo Windows. Não habilita monitor mode, deauth, injeção, captura de handshake, cracking ou brute force.</p>
          <ul><li>Aircrack-ng continua no Tool Center para laboratório autorizado.</li><li>Wifite e Reaver ficam catalogados, mas sem botão de ataque automático.</li><li>A IA recebe contexto de saúde, não credenciais nem comandos ofensivos.</li></ul>
        </section>
      </aside>
    </div>

    <details className="wi-technical"><summary>Detalhes técnicos retornados pelo host</summary><div><section><strong>Interface / conexão</strong><pre>{data?.interfaces || 'Nenhuma informação.'}</pre></section><section><strong>Redes visíveis</strong><pre>{data?.visibleNetworks || 'Nenhuma informação.'}</pre></section></div></details>
  </div>;
}
