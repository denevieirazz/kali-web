import { useCallback, useEffect, useMemo, useState } from 'react';
import { apiClient } from '../../services/apiClient';
import './NetworkAssessmentPanel.css';

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

type WifiDiagnostics = {
  available: boolean;
  source: string;
  interfaces: string;
  visibleNetworks: string;
  note: string;
};

type ScanHost = {
  address: string;
  hostname: string;
  up: boolean;
  ports: Array<{ port: number; state: string; protocol: string; service: string; version: string }>;
};

type ScanResult = {
  preset: string;
  label: string;
  target: string;
  distribution: string;
  hosts: ScanHost[];
  rawSummary: string;
  warnings: string;
  completedAt: string;
};

type Props = {
  distribution: string;
  activeScope?: string | null;
  onNotice?: (message: string) => void;
  onError?: (message: string) => void;
};

function looksLikeLocalIpv4(value: string) {
  return /^(?:10\.|127\.|169\.254\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.)\d{1,3}\.\d{1,3}(?:\/\d{1,2})?$/.test(value.trim());
}

export default function NetworkAssessmentPanel({ distribution, activeScope, onNotice, onError }: Props) {
  const [overview, setOverview] = useState<NetworkOverview | null>(null);
  const [wifi, setWifi] = useState<WifiDiagnostics | null>(null);
  const [target, setTarget] = useState('');
  const [preset, setPreset] = useState<'discover' | 'services' | 'commonPorts'>('discover');
  const [result, setResult] = useState<ScanResult | null>(null);
  const [loadingOverview, setLoadingOverview] = useState(false);
  const [loadingWifi, setLoadingWifi] = useState(false);
  const [scanning, setScanning] = useState(false);

  const loadOverview = useCallback(async () => {
    setLoadingOverview(true);
    try {
      const data = await apiClient<NetworkOverview>('/api/security/tools/network/overview');
      setOverview(data);
      setTarget(current => {
        if (current) return current;
        if (activeScope && looksLikeLocalIpv4(activeScope)) return activeScope;
        return data.suggestedTargets[0] || '';
      });
    } catch (cause) {
      onError?.(cause instanceof Error ? cause.message : 'Não foi possível identificar a rede local.');
    } finally {
      setLoadingOverview(false);
    }
  }, [activeScope, onError]);

  useEffect(() => { void loadOverview(); }, [loadOverview]);

  useEffect(() => {
    if (activeScope && looksLikeLocalIpv4(activeScope)) setTarget(activeScope);
  }, [activeScope]);

  const loadWifi = async () => {
    setLoadingWifi(true);
    try {
      const data = await apiClient<WifiDiagnostics>('/api/security/tools/network/wifi', { timeoutMs: 15000 });
      setWifi(data);
      onNotice?.(data.available ? 'Diagnóstico Wi‑Fi atualizado.' : 'O host não expôs diagnóstico Wi‑Fi nesta sessão.');
    } catch (cause) {
      onError?.(cause instanceof Error ? cause.message : 'Falha ao consultar o Wi‑Fi local.');
    } finally {
      setLoadingWifi(false);
    }
  };

  const runAssessment = async () => {
    if (!distribution) {
      onError?.('Selecione uma distribuição WSL com Nmap instalado.');
      return;
    }
    if (!target.trim()) {
      onError?.('Escolha a rede sugerida ou informe um IPv4 privado/local.');
      return;
    }
    setScanning(true);
    setResult(null);
    try {
      const data = await apiClient<ScanResult>('/api/security/tools/network/scan', {
        method: 'POST',
        timeoutMs: 60000,
        body: JSON.stringify({ preset, target: target.trim(), distribution }),
      });
      setResult(data);
      onNotice?.(`${data.label} concluído: ${data.hosts.length} dispositivo(s) retornado(s).`);
    } catch (cause) {
      onError?.(cause instanceof Error ? cause.message : 'A avaliação de rede falhou.');
    } finally {
      setScanning(false);
    }
  };

  const upHosts = useMemo(() => result?.hosts.filter(host => host.up) ?? [], [result]);

  const copyAiContext = async () => {
    if (!result) return;
    const payload = {
      kind: 'cloudos-network-assessment',
      scope: result.target,
      preset: result.preset,
      completedAt: result.completedAt,
      hosts: result.hosts,
      guidance: 'Use somente para análise, priorização e próximos passos defensivos dentro do escopo autorizado.',
    };
    try {
      await navigator.clipboard.writeText(JSON.stringify(payload, null, 2));
      onNotice?.('Contexto estruturado copiado para a IA do CloudOS.');
    } catch {
      onNotice?.('Não foi possível acessar a área de transferência.');
    }
  };

  return (
    <section className="ktc-network" aria-label="Rede e Wi-Fi">
      <div className="ktc-network-head">
        <div>
          <small>Assistente guiado</small>
          <h2>Rede & Wi‑Fi</h2>
          <p>Descubra sua rede local, identifique dispositivos e traduza o resultado do Nmap para uma visão simples.</p>
        </div>
        <div className="ktc-network-policy">
          <span>✓ somente rede privada/local</span>
          <span>✓ presets fechados</span>
          <span>✓ até /24</span>
        </div>
      </div>

      <div className="ktc-network-actions">
        <button type="button" onClick={() => void loadOverview()} disabled={loadingOverview}>
          {loadingOverview ? 'Identificando…' : '① Ver minha rede'}
        </button>
        <button type="button" onClick={() => void loadWifi()} disabled={loadingWifi}>
          {loadingWifi ? 'Consultando…' : '② Diagnóstico Wi‑Fi'}
        </button>
      </div>

      {overview && (
        <div className="ktc-network-overview">
          <div className="ktc-network-summary">
            <strong>{overview.host}</strong>
            <span>{overview.interfaces.filter(item => item.privateLocal && !item.internal).length} interface(s) local(is)</span>
          </div>
          <div className="ktc-network-chips">
            {overview.suggestedTargets.map(item => (
              <button type="button" key={item} onClick={() => { setTarget(item); setPreset('discover'); }}>{item}</button>
            ))}
            {overview.suggestedTargets.length === 0 && <span>Nenhuma faixa privada foi detectada automaticamente.</span>}
          </div>
        </div>
      )}

      <div className="ktc-network-runner">
        <label>
          <span>O que você quer fazer?</span>
          <select value={preset} onChange={event => setPreset(event.target.value as typeof preset)}>
            <option value="discover">Descobrir dispositivos conectados</option>
            <option value="commonPorts">Checar portas comuns de um dispositivo</option>
            <option value="services">Identificar serviços de um dispositivo</option>
          </select>
        </label>
        <label>
          <span>Alvo privado/local</span>
          <input value={target} onChange={event => setTarget(event.target.value)} placeholder={preset === 'discover' ? '192.168.1.0/24' : '192.168.1.10'} />
        </label>
        <button className="ktc-network-primary" type="button" onClick={() => void runAssessment()} disabled={scanning || !distribution}>
          {scanning ? 'Analisando…' : '▶ Executar avaliação'}
        </button>
      </div>

      <div className="ktc-network-explain">
        <strong>Para quem está começando</strong>
        <p>{preset === 'discover'
          ? 'Primeiro encontre quais dispositivos respondem na sua própria rede. Não procura portas nem tenta autenticação.'
          : preset === 'commonPorts'
            ? 'Verifica um conjunto pequeno de portas TCP comuns em um único IP local e mostra quais estão abertas.'
            : 'Pergunta ao Nmap quais serviços parecem estar rodando nas portas mais comuns de um único IP local.'}</p>
      </div>

      {result && (
        <div className="ktc-network-results">
          <div className="ktc-network-results-head">
            <div><small>{result.label}</small><strong>{upHosts.length} dispositivo(s) ativo(s)</strong><span>{result.target}</span></div>
            <button type="button" onClick={() => void copyAiContext()}>Copiar contexto para IA</button>
          </div>
          {result.hosts.length === 0 ? (
            <p className="ktc-network-empty">Nenhum dispositivo foi retornado por esse preset.</p>
          ) : (
            <div className="ktc-network-hosts">
              {result.hosts.map(host => (
                <article key={host.address}>
                  <header><strong>{host.address}</strong><span>{host.hostname || (host.up ? 'online' : 'sem resposta')}</span></header>
                  {host.ports.length > 0 ? (
                    <div className="ktc-network-ports">
                      {host.ports.map(port => <span key={`${host.address}-${port.port}`}>{port.port}/{port.protocol} · {port.service || port.state}</span>)}
                    </div>
                  ) : <p>Dispositivo detectado; este preset não enumerou serviços.</p>}
                </article>
              ))}
            </div>
          )}
        </div>
      )}

      {wifi && (
        <details className="ktc-network-wifi" open>
          <summary>Wi‑Fi local · {wifi.available ? 'diagnóstico disponível' : 'indisponível'}</summary>
          <p>{wifi.note}</p>
          <div className="ktc-network-wifi-grid">
            <div><strong>Interface / conexão</strong><pre>{wifi.interfaces || 'Nenhuma informação retornada.'}</pre></div>
            <div><strong>Redes visíveis</strong><pre>{wifi.visibleNetworks || 'Nenhuma informação retornada.'}</pre></div>
          </div>
        </details>
      )}

      <div className="ktc-network-lab-note">
        <strong>Aircrack-ng / Wifite / Reaver</strong>
        <span>Continuam no catálogo para laboratório autorizado, mas deauth, injeção, cracking e brute force não viram botão automático neste assistente.</span>
      </div>
    </section>
  );
}
