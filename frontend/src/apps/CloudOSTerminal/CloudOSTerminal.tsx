import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  MAX_TERMINAL_TABS,
  TERMINAL_WORKSPACE_STORAGE_KEY,
  activateTerminalTab,
  addTerminalTab,
  closeTerminalTab,
  createTerminalTab,
  cycleTerminalTab,
  normalizeTerminalWorkspace,
  serializableTerminalWorkspace,
  toggleTerminalSplit,
  updateTerminalTab,
  type TerminalProfile,
  type TerminalWorkspaceState,
} from '../../core/terminalWorkspaceState.js';
import { apiClient } from '../../services/apiClient';
import { useWindowManager } from '../../stores/windowManager';
import { TerminalSession, type TerminalPaneStatus } from './TerminalSession';
import 'xterm/css/xterm.css';
import './CloudOSTerminal.css';

interface WslInfo {
  available: boolean;
  default: string | null;
  preferred: string | null;
  distributions: Array<{ name: string; version: number | null; state: string }>;
}

const DEFAULT_STATUS: TerminalPaneStatus = { state: 'connecting', label: 'Preparando sessão…' };

function preferredDistribution(info: WslInfo | null) {
  return info?.preferred || info?.default || info?.distributions[0]?.name || '';
}

export default function CloudOSTerminal({ windowId }: { windowId?: string }) {
  const [launchParams] = useState(() => {
    const win = windowId ? useWindowManager.getState().getWindow(windowId) : undefined;
    const rawProfile = win?.params?.profile;
    const profile: TerminalProfile | null = rawProfile === 'powershell' || rawProfile === 'wsl' ? rawProfile : null;
    return {
      profile,
      distribution: typeof win?.params?.distribution === 'string' ? win.params.distribution : '',
      explicit: Boolean(profile || win?.params?.distribution),
    };
  });

  const [wslInfo, setWslInfo] = useState<WslInfo | null>(null);
  const [workspace, setWorkspace] = useState<TerminalWorkspaceState | null>(null);
  const [paneStatuses, setPaneStatuses] = useState<Record<string, TerminalPaneStatus>>({});
  const [profileMessage, setProfileMessage] = useState('Carregando perfis do Host…');

  useEffect(() => {
    let cancelled = false;

    void apiClient<WslInfo>('/api/wsl/distributions')
      .then(info => {
        if (cancelled) return;
        setWslInfo(info);
        const requestedExists = info.distributions.some(distro => distro.name === launchParams.distribution);
        const distribution = requestedExists ? launchParams.distribution : preferredDistribution(info);
        const profile: TerminalProfile = launchParams.profile ?? (info.available && distribution ? 'wsl' : 'powershell');
        const fallbackTab = createTerminalTab(profile, distribution);

        let restored: unknown = null;
        if (!launchParams.explicit) {
          try {
            restored = JSON.parse(localStorage.getItem(TERMINAL_WORKSPACE_STORAGE_KEY) ?? 'null');
          } catch {
            localStorage.removeItem(TERMINAL_WORKSPACE_STORAGE_KEY);
          }
        }
        setWorkspace(normalizeTerminalWorkspace(restored, fallbackTab));
        setProfileMessage(info.available ? `${info.distributions.length} distribuição(ões) WSL disponível(is)` : 'WSL indisponível · usando PowerShell');
      })
      .catch(error => {
        if (cancelled) return;
        const fallbackTab = createTerminalTab('powershell');
        setWslInfo({ available: false, default: null, preferred: null, distributions: [] });
        setWorkspace(normalizeTerminalWorkspace(null, fallbackTab));
        setProfileMessage(error instanceof Error ? error.message : 'WSL indisponível · PowerShell pronto');
      });

    return () => { cancelled = true; };
  }, [launchParams.distribution, launchParams.explicit, launchParams.profile]);

  useEffect(() => {
    if (!workspace) return;
    localStorage.setItem(TERMINAL_WORKSPACE_STORAGE_KEY, JSON.stringify(serializableTerminalWorkspace(workspace)));
  }, [workspace]);

  const handlePaneStatus = useCallback((tabId: string, status: TerminalPaneStatus) => {
    setPaneStatuses(current => {
      const previous = current[tabId];
      if (previous?.state === status.state && previous.label === status.label) return current;
      return { ...current, [tabId]: status };
    });
  }, []);

  const activeTab = useMemo(
    () => workspace?.tabs.find(tab => tab.id === workspace.activeId) ?? null,
    [workspace],
  );

  const mutateWorkspace = useCallback((mutator: (current: TerminalWorkspaceState) => TerminalWorkspaceState) => {
    setWorkspace(current => current ? mutator(current) : current);
  }, []);

  const openTab = useCallback((profile: TerminalProfile) => {
    const distribution = profile === 'wsl' ? preferredDistribution(wslInfo) : '';
    mutateWorkspace(current => addTerminalTab(current, createTerminalTab(profile, distribution)));
  }, [mutateWorkspace, wslInfo]);

  const closeTab = useCallback((tabId: string) => {
    const fallbackProfile: TerminalProfile = wslInfo?.available && preferredDistribution(wslInfo) ? 'wsl' : 'powershell';
    const fallback = createTerminalTab(fallbackProfile, preferredDistribution(wslInfo));
    mutateWorkspace(current => closeTerminalTab(current, tabId, fallback));
    setPaneStatuses(current => {
      const next = { ...current };
      delete next[tabId];
      return next;
    });
  }, [mutateWorkspace, wslInfo]);

  useEffect(() => {
    if (!workspace) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.ctrlKey && event.shiftKey && event.key.toLowerCase() === 't') {
        event.preventDefault();
        openTab(activeTab?.profile ?? 'powershell');
      } else if (event.ctrlKey && event.shiftKey && event.key.toLowerCase() === 'w') {
        event.preventDefault();
        closeTab(workspace.activeId);
      } else if (event.ctrlKey && event.key === 'PageDown') {
        event.preventDefault();
        mutateWorkspace(current => cycleTerminalTab(current, 1));
      } else if (event.ctrlKey && event.key === 'PageUp') {
        event.preventDefault();
        mutateWorkspace(current => cycleTerminalTab(current, -1));
      } else if (event.altKey && event.shiftKey && event.key.toLowerCase() === 'd') {
        event.preventDefault();
        mutateWorkspace(toggleTerminalSplit);
      }
    };

    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [activeTab?.profile, closeTab, mutateWorkspace, openTab, workspace]);

  if (!workspace || !activeTab) {
    return (
      <div className="terminal-workspace terminal-workspace--loading">
        <span className="terminal-workspace__spinner" aria-hidden="true" />
        <span>{profileMessage}</span>
      </div>
    );
  }

  const activeStatus = paneStatuses[activeTab.id] ?? DEFAULT_STATUS;
  const atLimit = workspace.tabs.length >= MAX_TERMINAL_TABS;

  return (
    <div className="terminal-workspace">
      <header className="terminal-workspace__chrome">
        <div className="terminal-workspace__tabs" role="tablist" aria-label="Sessões do Terminal">
          {workspace.tabs.map(tab => {
            const status = paneStatuses[tab.id] ?? DEFAULT_STATUS;
            const active = tab.id === workspace.activeId;
            return (
              <div className={`terminal-tab ${active ? 'is-active' : ''}`} key={tab.id} role="presentation">
                <button
                  type="button"
                  role="tab"
                  aria-selected={active}
                  onClick={() => mutateWorkspace(current => activateTerminalTab(current, tab.id))}
                  title={status.label}
                >
                  <span className={`terminal-tab__status terminal-tab__status--${status.state}`} />
                  <span className="terminal-tab__title">{tab.profile === 'wsl' ? (tab.distribution || 'WSL') : 'PowerShell'}</span>
                </button>
                <button type="button" className="terminal-tab__close" onClick={() => closeTab(tab.id)} aria-label="Fechar aba">×</button>
              </div>
            );
          })}
        </div>

        <div className="terminal-workspace__toolbar">
          <button type="button" onClick={() => openTab('powershell')} disabled={atLimit} title="Nova aba PowerShell">+ PowerShell</button>
          <button type="button" onClick={() => openTab('wsl')} disabled={atLimit || !wslInfo?.available} title="Nova aba WSL">+ WSL</button>

          {wslInfo?.available && wslInfo.distributions.length > 0 && (
            <select
              aria-label="Distribuição da aba ativa"
              value={activeTab.profile === 'wsl' ? activeTab.distribution : ''}
              onChange={event => mutateWorkspace(current => updateTerminalTab(current, current.activeId, { profile: 'wsl', distribution: event.target.value }))}
            >
              <option value="" disabled>Distribuição…</option>
              {wslInfo.distributions.map(distro => (
                <option key={distro.name} value={distro.name}>{distro.name} · WSL {distro.version ?? '?'}</option>
              ))}
            </select>
          )}

          <button
            type="button"
            className={workspace.splitId ? 'is-active' : ''}
            onClick={() => mutateWorkspace(toggleTerminalSplit)}
            disabled={workspace.tabs.length < 2}
            title="Dividir workspace (Alt+Shift+D)"
          >◫ Split</button>

          <span className="terminal-workspace__summary">
            <span className={`terminal-tab__status terminal-tab__status--${activeStatus.state}`} />
            {activeStatus.label} · {workspace.tabs.length}/{MAX_TERMINAL_TABS}
          </span>
        </div>
      </header>

      <main className={`terminal-workspace__panes ${workspace.splitId ? 'terminal-workspace__panes--split' : ''}`}>
        {workspace.tabs.map(tab => {
          const visible = tab.id === workspace.activeId || tab.id === workspace.splitId;
          return (
            <div className={`terminal-workspace__pane-shell ${visible ? 'is-visible' : ''}`} key={tab.id}>
              <TerminalSession tab={tab} visible={visible} onStatusChange={handlePaneStatus} />
            </div>
          );
        })}
      </main>

      <footer className="terminal-workspace__statusbar">
        <span>{profileMessage}</span>
        <span>Ctrl+PgUp/PgDn alterna · Ctrl+Shift+T cria · Ctrl+Shift+W fecha · Alt+Shift+D divide</span>
      </footer>
    </div>
  );
}
