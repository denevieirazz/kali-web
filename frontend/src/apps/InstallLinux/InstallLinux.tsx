import { useCallback, useEffect, useMemo, useState } from 'react';
import { useAppRegistry } from '../../core/appRegistry';
import { useProcessManager } from '../../stores/processManager';
import { useWindowManager } from '../../stores/windowManager';
import {
  systemHubClient,
  type DistroCatalogItem,
  type HostCapabilities,
  type NativeApp,
  type SystemOperation,
  type WslDistribution
} from '../../services/systemHubClient';
import SystemReadiness from './SystemReadiness';
import './InstallLinux.css';

type Section = 'readiness' | 'overview' | 'distros' | 'apps' | 'operations';

function capabilityTone(value: boolean) {
  return value ? 'ready' : 'attention';
}

function isOperationActive(operation: SystemOperation) {
  return ['queued', 'running', 'cancelling'].includes(operation.status);
}

export default function InstallLinux() {
  const [section, setSection] = useState<Section>('readiness');
  const [capabilities, setCapabilities] = useState<HostCapabilities | null>(null);
  const [distros, setDistros] = useState<WslDistribution[]>([]);
  const [catalog, setCatalog] = useState<DistroCatalogItem[]>([]);
  const [apps, setApps] = useState<NativeApp[]>([]);
  const [operations, setOperations] = useState<SystemOperation[]>([]);
  const [selectedDistro, setSelectedDistro] = useState('');
  const [webDownload, setWebDownload] = useState(false);
  const [query, setQuery] = useState('');
  const [loading, setLoading] = useState(true);
  const [busyAction, setBusyAction] = useState<string | null>(null);
  const [notice, setNotice] = useState<{ tone: 'info' | 'success' | 'error'; text: string } | null>(null);

  const createProcess = useProcessManager((state) => state.createProcess);
  const openWindow = useWindowManager((state) => state.openWindow);

  const refresh = useCallback(async (forceApps = false) => {
    setLoading(true);
    const results = await Promise.allSettled([
      systemHubClient.capabilities(),
      systemHubClient.distributions(),
      systemHubClient.catalog(),
      systemHubClient.operations(),
      systemHubClient.apps(forceApps)
    ]);

    if (results[0].status === 'fulfilled') setCapabilities(results[0].value);
    if (results[1].status === 'fulfilled') setDistros(results[1].value.distributions || []);
    if (results[2].status === 'fulfilled') {
      setCatalog(results[2].value.distributions || []);
    }
    if (results[3].status === 'fulfilled') setOperations(results[3].value.operations || []);
    if (results[4].status === 'fulfilled') setApps(results[4].value.apps || []);

    if (results[1].status === 'fulfilled' && results[2].status === 'fulfilled') {
      const installed = new Set(results[1].value.distributions.map((distro) => distro.name.toLowerCase()));
      const choices = results[2].value.distributions.filter((item) => !installed.has(item.id.toLowerCase()));
      setSelectedDistro((current) => choices.some((item) => item.id === current) ? current : choices[0]?.id || '');
    }

    const failed = results.filter((result) => result.status === 'rejected') as PromiseRejectedResult[];
    if (failed.length === results.length) {
      setNotice({ tone: 'error', text: 'O agente local do CloudOS não respondeu. Inicie o backend e tente novamente.' });
    } else if (failed.length) {
      setNotice({ tone: 'info', text: 'Parte do inventário não pôde ser lida. Os detalhes do host mostram a causa provável.' });
    }
    setLoading(false);
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  useEffect(() => {
    if (!operations.some(isOperationActive)) return;
    const timer = window.setInterval(async () => {
      try {
        const response = await systemHubClient.operations();
        setOperations(response.operations);
        if (!response.operations.some(isOperationActive)) refresh();
      } catch {}
    }, 1600);
    return () => window.clearInterval(timer);
  }, [operations, refresh]);

  const runAction = useCallback(async (key: string, action: () => Promise<unknown>, successMessage: string, refreshAfter = true) => {
    setBusyAction(key);
    setNotice(null);
    try {
      await action();
      setNotice({ tone: 'success', text: successMessage });
      if (refreshAfter) await refresh();
    } catch (error) {
      setNotice({ tone: 'error', text: error instanceof Error ? error.message : 'A operação não pôde ser concluída.' });
    } finally {
      setBusyAction(null);
    }
  }, [refresh]);

  const installSelected = () => {
    if (!selectedDistro) return;
    runAction(
      `install-${selectedDistro}`,
      () => systemHubClient.install(selectedDistro, webDownload),
      `A instalação de ${selectedDistro} foi enviada ao Windows. Acompanhe o progresso em Operações.`
    );
    setSection('operations');
  };

  const launchTerminal = useCallback((profile: 'wsl' | 'powershell', distribution?: string) => {
    const app = useAppRegistry.getState().apps['cloudos-terminal'];
    if (!app) {
      setNotice({ tone: 'error', text: 'O Terminal CloudOS ainda não foi registrado pelo kernel.' });
      return;
    }
    const title = profile === 'wsl' ? `Terminal — ${distribution || 'WSL'}` : 'Terminal — PowerShell';
    const pid = createProcess('cloudos-terminal', title, app.icon);
    openWindow({
      title,
      icon: app.icon,
      appId: 'cloudos-terminal',
      width: app.defaultWidth,
      height: app.defaultHeight,
      minWidth: app.minWidth,
      minHeight: app.minHeight,
      isResizable: app.isResizable,
      processId: pid,
      params: { profile, distribution }
    });
  }, [createProcess, openWindow]);

  const filteredApps = useMemo(() => {
    const normalized = query.trim().toLocaleLowerCase('pt-BR');
    if (!normalized) return apps;
    return apps.filter((app) => `${app.name} ${app.source} ${app.distribution || ''}`.toLocaleLowerCase('pt-BR').includes(normalized));
  }, [apps, query]);

  const launchNativeApp = useCallback(async (app: NativeApp) => {
    const key = `app-${app.id}`;
    setBusyAction(key);
    setNotice(null);
    try {
      const launched = await systemHubClient.launchApp(app.id);
      if (capabilities?.integration.managedNativeWindows && launched.managed === false) {
        setNotice({
          tone: 'info',
          text: `${app.name} foi aberto. ${launched.managementReason || 'O Windows entregou esta janela a um broker compartilhado, então ela permanece no fallback nativo.'}`
        });
      } else {
        setNotice({ tone: 'success', text: `${app.name} foi aberto${launched.managed ? ' e integrado à taskbar CloudOS' : ' em uma janela nativa'}.` });
      }
    } catch (error) {
      setNotice({ tone: 'error', text: error instanceof Error ? error.message : 'O aplicativo não pôde ser aberto.' });
    } finally {
      setBusyAction(null);
    }
  }, [capabilities?.integration.managedNativeWindows]);

  const installedNames = useMemo(() => new Set(distros.map((distro) => distro.name.toLowerCase())), [distros]);
  const availableCatalog = catalog.filter((item) => !installedNames.has(item.id.toLowerCase()));
  const activeCount = operations.filter(isOperationActive).length;

  return (
    <div className="system-hub">
      <aside className="system-hub-sidebar">
        <div className="system-hub-brand">
          <span className="system-hub-brandmark">C</span>
          <div><strong>CloudOS</strong><small>Windows + Linux Hub</small></div>
        </div>
        <nav aria-label="Seções da central do sistema">
          <HubNavButton active={section === 'readiness'} onClick={() => setSection('readiness')} icon="◎" label="Prontidão" />
          <HubNavButton active={section === 'overview'} onClick={() => setSection('overview')} icon="◫" label="Visão geral" />
          <HubNavButton active={section === 'distros'} onClick={() => setSection('distros')} icon="◇" label="Distribuições" count={distros.length} />
          <HubNavButton active={section === 'apps'} onClick={() => setSection('apps')} icon="▦" label="Aplicativos" count={apps.length} />
          <HubNavButton active={section === 'operations'} onClick={() => setSection('operations')} icon="↻" label="Operações" count={activeCount || undefined} />
        </nav>
        <div className="system-hub-mode">
          <span className={`status-dot ${capabilities?.integration.managedNativeWindows ? 'ready' : 'attention'}`} />
          <div>
            <strong>{capabilities?.integration.managedNativeWindows ? 'Host nativo ativo' : 'Modo web local'}</strong>
            <small>{capabilities?.integration.managedNativeWindows ? 'Janelas gerenciadas' : 'Apps em janelas nativas'}</small>
          </div>
        </div>
      </aside>

      <main className="system-hub-main">
        <header className="system-hub-header">
          <div>
            <span className="eyebrow">CONTROLE DO HOST</span>
            <h1>{section === 'readiness' ? 'Prontidão do sistema' : section === 'overview' ? 'Seu ambiente híbrido' : section === 'distros' ? 'Distribuições Linux' : section === 'apps' ? 'Aplicativos do computador' : 'Operações do sistema'}</h1>
            <p>{section === 'readiness' ? 'Evidências reais para evoluir o CloudOS sem alterar o shell do Windows antes da hora.' : section === 'overview' ? 'Windows, WSL e WSLg coordenados a partir do CloudOS.' : section === 'distros' ? 'Instale, inicie e configure sistemas WSL sem sair desta central.' : section === 'apps' ? 'Um catálogo seguro para programas Windows e aplicativos gráficos Linux.' : 'Instalações e conversões continuam mesmo quando esta janela é fechada.'}</p>
          </div>
          {section !== 'readiness' && <button className="secondary-button" onClick={() => refresh(true)} disabled={loading}>{loading ? 'Lendo host…' : 'Atualizar inventário'}</button>}
        </header>

        {notice && <div className={`hub-notice ${notice.tone}`}><span>{notice.tone === 'error' ? '!' : notice.tone === 'success' ? '✓' : 'i'}</span>{notice.text}<button onClick={() => setNotice(null)} aria-label="Fechar aviso">×</button></div>}

        {section === 'readiness' && <SystemReadiness />}

        {section === 'overview' && (
          <section className="hub-section">
            <div className="capability-grid">
              <CapabilityCard label="Windows host" value={capabilities?.host.windows ? `${capabilities.host.release} · ${capabilities.host.architecture}` : 'Não detectado'} tone={capabilityTone(Boolean(capabilities?.host.windows))} detail={capabilities?.host.hostname || 'Aguardando agente local'} />
              <CapabilityCard label="WSL" value={capabilities?.wsl.operational ? `Versão ${capabilities.wsl.wslVersion || 'instalada'}` : capabilities?.wsl.installed ? 'Requer atenção' : 'Não instalado'} tone={capabilityTone(Boolean(capabilities?.wsl.operational))} detail={capabilities?.wsl.error || `${distros.length} distribuição(ões) registrada(s)`} />
              <CapabilityCard label="WSLg" value={capabilities?.integration.linuxGuiApps ? `Versão ${capabilities.wsl.wslgVersion || 'ativa'}` : 'Indisponível'} tone={capabilityTone(Boolean(capabilities?.integration.linuxGuiApps))} detail="Aplicativos gráficos Linux no desktop Windows" />
              <CapabilityCard label="Integração de janelas" value={capabilities?.integration.managedNativeWindows ? 'Gerenciada pelo host' : 'Janela nativa'} tone={capabilities?.integration.managedNativeWindows ? 'ready' : 'neutral'} detail={capabilities?.integration.managedNativeWindows ? 'Foco, estado e fechamento integrados' : 'Abra pelo aplicativo desktop CloudOS'} />
            </div>

            <div className="hub-split">
              <article className="hub-panel hero-panel">
                <div><span className="panel-kicker">ACESSO RÁPIDO</span><h2>Windows e Linux lado a lado</h2><p>Abra um shell PowerShell ou entre diretamente na distribuição WSL escolhida.</p></div>
                <div className="hero-actions">
                  <button className="primary-button" onClick={() => launchTerminal('powershell')}>Abrir PowerShell</button>
                  <button className="secondary-button" disabled={!distros.length} onClick={() => launchTerminal('wsl', capabilities?.wsl.preferred || distros[0]?.name)}>Abrir Linux</button>
                </div>
              </article>
              <article className="hub-panel readiness-panel">
                <span className="panel-kicker">PRONTIDÃO</span>
                <h2>{capabilities?.integration.linuxGuiApps ? 'Ambiente gráfico pronto' : 'Configuração necessária'}</h2>
                <ul>
                  <li className={capabilities?.wsl.operational ? 'ok' : ''}>WSL operacional</li>
                  <li className={distros.some((distro) => distro.version === 2) ? 'ok' : ''}>Distribuição em WSL 2</li>
                  <li className={capabilities?.integration.linuxGuiApps ? 'ok' : ''}>WSLg detectado</li>
                </ul>
              </article>
            </div>

            {!capabilities?.integration.managedNativeWindows && (
              <article className="architecture-note"><span>Camada nativa</span><div><strong>O controle já é real; o encaixe visual vem com o host WebView2.</strong><p>Neste modo web, o CloudOS instala, descobre e inicia os programas, mas o Windows/WSLg desenha as janelas fora do DOM. Um navegador não pode incorporar HWNDs com segurança.</p></div></article>
            )}
          </section>
        )}

        {section === 'distros' && (
          <section className="hub-section distro-layout">
            <div className="distro-list">
              <div className="section-heading"><div><span className="panel-kicker">INSTALADAS</span><h2>{distros.length ? `${distros.length} sistema(s) disponível(is)` : 'Nenhuma distribuição detectada'}</h2></div></div>
              {distros.map((distro) => (
                <article className="distro-card" key={distro.name}>
                  <div className="distro-symbol">{distro.name.slice(0, 1).toUpperCase()}</div>
                  <div className="distro-info"><div><h3>{distro.name}</h3>{(distro.isDefault || capabilities?.wsl.default === distro.name) && <span className="default-badge">PADRÃO</span>}</div><p><span className={`status-dot ${/running|execução/i.test(distro.state) ? 'ready' : 'neutral'}`} /> {distro.state || 'Estado desconhecido'} · WSL {distro.version || '?'}</p></div>
                  <div className="distro-actions">
                    <button onClick={() => launchTerminal('wsl', distro.name)}>Terminal</button>
                    {/running|execução/i.test(distro.state) ? <button disabled={busyAction === `stop-${distro.name}`} onClick={() => runAction(`stop-${distro.name}`, () => systemHubClient.stopDistro(distro.name), `${distro.name} foi encerrada.`)}>Parar</button> : <button disabled={busyAction === `start-${distro.name}`} onClick={() => runAction(`start-${distro.name}`, () => systemHubClient.startDistro(distro.name), `${distro.name} foi iniciada.`)}>Iniciar</button>}
                    {capabilities?.wsl.default !== distro.name && <button onClick={() => runAction(`default-${distro.name}`, () => systemHubClient.setDefaultDistro(distro.name), `${distro.name} agora é a distribuição padrão.`)}>Tornar padrão</button>}
                    {distro.version !== 2 && <button onClick={() => { runAction(`convert-${distro.name}`, () => systemHubClient.setDistroVersion(distro.name, 2), `Conversão de ${distro.name} para WSL 2 iniciada.`); setSection('operations'); }}>Converter para WSL 2</button>}
                  </div>
                </article>
              ))}
            </div>

            <aside className="install-panel hub-panel">
              <span className="panel-kicker">NOVA DISTRIBUIÇÃO</span>
              <h2>Instalar Linux</h2>
              <p>O catálogo é lido diretamente do WSL. A instalação pode abrir uma confirmação administrativa do Windows.</p>
              <label>Distribuição<select value={selectedDistro} onChange={(event) => setSelectedDistro(event.target.value)} disabled={!availableCatalog.length}>{availableCatalog.length ? availableCatalog.map((item) => <option key={item.id} value={item.id}>{item.name}</option>) : <option value="">Nenhuma opção disponível</option>}</select></label>
              <label className="toggle-row"><input type="checkbox" checked={webDownload} onChange={(event) => setWebDownload(event.target.checked)} /><span><strong>Download direto</strong><small>Usa a fonte web quando a Microsoft Store estiver bloqueada.</small></span></label>
              <button className="primary-button wide" disabled={!selectedDistro || Boolean(busyAction)} onClick={installSelected}>{busyAction?.startsWith('install-') ? 'Preparando…' : 'Instalar distribuição'}</button>
              <button className="secondary-button wide" disabled={Boolean(busyAction)} onClick={() => { runAction('update-wsl', systemHubClient.updateWsl, 'Atualização do WSL iniciada.'); setSection('operations'); }}>Atualizar WSL e WSLg</button>
              <div className="install-footnote"><strong>Primeiro acesso</strong><span>Depois da instalação, abra o Terminal para criar o usuário Linux solicitado pela distribuição.</span></div>
            </aside>
          </section>
        )}

        {section === 'apps' && (
          <section className="hub-section">
            <div className="app-toolbar"><div className="hub-search"><span>⌕</span><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Pesquisar Windows, Linux ou distribuição…" /></div><div className="catalog-legend"><span><i className="windows" />Windows</span><span><i className="linux" />Linux/WSLg</span></div></div>
            {!capabilities?.integration.managedNativeWindows && <div className="inline-note">Os aplicativos abaixo são iniciados pelo agente local e aparecem como janelas nativas do Windows. O CloudOS nunca recebe comandos ou caminhos livres da página.</div>}
            <div className="native-app-grid">
              {filteredApps.map((app) => <button className="native-app-card" key={app.id} disabled={busyAction === `app-${app.id}`} onClick={() => launchNativeApp(app)}><span className={`native-app-icon ${app.source}`}>{app.icon || (app.source === 'wsl' ? 'L' : 'W')}</span><span className="native-app-copy"><strong>{app.name}</strong><small>{app.source === 'wsl' ? app.distribution || 'Linux / WSLg' : 'Windows'}</small></span><span className="launch-arrow">↗</span></button>)}
              {!filteredApps.length && <div className="empty-state"><strong>Nenhum aplicativo encontrado</strong><span>Atualize o inventário ou altere a pesquisa.</span></div>}
            </div>
          </section>
        )}

        {section === 'operations' && (
          <section className="hub-section operations-list">
            {operations.map((operation) => <article className={`operation-card ${operation.status}`} key={operation.id}><div className="operation-top"><div className="operation-icon">{operation.status === 'completed' ? '✓' : operation.status === 'failed' ? '!' : '↻'}</div><div className="operation-copy"><div><h3>{operation.target || operation.type}</h3><span className={`operation-status ${operation.status}`}>{operation.status}</span></div><p>{operation.message}</p></div><strong className="operation-percent">{operation.progress}%</strong></div><div className="operation-track"><span style={{ width: `${operation.progress}%` }} /></div>{operation.output.length > 0 && <details><summary>Detalhes técnicos</summary><pre>{operation.output.slice(-12).join('\n')}</pre></details>}{isOperationActive(operation) && <button className="operation-cancel" onClick={() => runAction(`cancel-${operation.id}`, () => systemHubClient.cancelOperation(operation.id), 'Cancelamento solicitado.')}>Cancelar</button>}</article>)}
            {!operations.length && <div className="empty-state large"><strong>Nenhuma operação registrada nesta sessão</strong><span>Instalações e conversões aparecerão aqui com progresso real.</span></div>}
          </section>
        )}
      </main>
    </div>
  );
}

function HubNavButton({ active, icon, label, count, onClick }: { active: boolean; icon: string; label: string; count?: number; onClick: () => void }) {
  return <button className={active ? 'active' : ''} onClick={onClick}><span>{icon}</span><strong>{label}</strong>{count !== undefined && <b>{count}</b>}</button>;
}

function CapabilityCard({ label, value, detail, tone }: { label: string; value: string; detail: string; tone: 'ready' | 'attention' | 'neutral' }) {
  return <article className={`capability-card ${tone}`}><div><span className={`status-dot ${tone}`} /><small>{label}</small></div><strong>{value}</strong><p>{detail}</p></article>;
}
