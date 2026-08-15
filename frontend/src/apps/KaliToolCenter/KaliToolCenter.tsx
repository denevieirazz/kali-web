import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  SECURITY_WORKSPACE_STORAGE_KEY,
  addScopeAsset,
  normalizeSecurityWorkspace,
  removeScopeAsset,
  selectScopeAsset,
  type SecurityWorkspaceState,
} from '../../core/securityWorkspaceState.js';
import { apiClient } from '../../services/apiClient';
import { useProcessManager } from '../../stores/processManager';
import { useWindowManager } from '../../stores/windowManager';
import './KaliToolCenter.css';

type SecurityTool = {
  id: string;
  command: string;
  name: string;
  category: string;
  description: string;
  guiAliases: string[];
  installed: boolean;
};

type ToolInventory = {
  operational: boolean;
  distribution: string | null;
  errorCode: string | null;
  error: string | null;
  tools: SecurityTool[];
};

type WslInfo = {
  available: boolean;
  default: string | null;
  preferred: string | null;
  distributions: Array<{ name: string; version: number | null; state: string }>;
};

type NativeApp = {
  id: string;
  name: string;
  source: 'windows' | 'wsl';
  distribution: string | null;
  icon?: string;
  windowMode?: string;
};

type AppCatalogResponse = { apps: NativeApp[] };

const CATEGORY_META: Record<string, { label: string; icon: string }> = {
  recon: { label: 'Recon', icon: '◉' },
  osint: { label: 'OSINT', icon: '⌕' },
  web: { label: 'Web', icon: '🌐' },
  network: { label: 'Rede', icon: '⌁' },
  credentials: { label: 'Credenciais', icon: '🔑' },
  frameworks: { label: 'Frameworks', icon: '◈' },
  wireless: { label: 'Wireless', icon: '⌁' },
  forensics: { label: 'Forense', icon: '🔬' },
  reverse: { label: 'Reverse', icon: '⌘' },
};

function normalizeName(value: string) {
  return value.trim().toLocaleLowerCase('en-US').replace(/[^a-z0-9]+/g, '');
}

function findGuiApp(tool: SecurityTool, apps: NativeApp[], distribution: string) {
  const aliases = [tool.name, ...tool.guiAliases].map(normalizeName).filter(Boolean);
  return apps.find(app => {
    if (app.source !== 'wsl' || app.distribution !== distribution) return false;
    const appName = normalizeName(app.name);
    return aliases.some(alias => appName === alias || appName.includes(alias) || alias.includes(appName));
  }) ?? null;
}

function loadWorkspace(): SecurityWorkspaceState {
  try {
    return normalizeSecurityWorkspace(JSON.parse(localStorage.getItem(SECURITY_WORKSPACE_STORAGE_KEY) ?? 'null'));
  } catch {
    localStorage.removeItem(SECURITY_WORKSPACE_STORAGE_KEY);
    return normalizeSecurityWorkspace(null);
  }
}

export default function KaliToolCenter() {
  const [wslInfo, setWslInfo] = useState<WslInfo | null>(null);
  const [distribution, setDistribution] = useState('');
  const [inventory, setInventory] = useState<ToolInventory | null>(null);
  const [nativeApps, setNativeApps] = useState<NativeApp[]>([]);
  const [search, setSearch] = useState('');
  const [category, setCategory] = useState('all');
  const [installedOnly, setInstalledOnly] = useState(false);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [scopeInput, setScopeInput] = useState('');
  const [workspace, setWorkspace] = useState<SecurityWorkspaceState>(loadWorkspace);

  const createProcess = useProcessManager(state => state.createProcess);
  const openWindow = useWindowManager(state => state.openWindow);

  useEffect(() => {
    localStorage.setItem(SECURITY_WORKSPACE_STORAGE_KEY, JSON.stringify(workspace));
  }, [workspace]);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError('');

    void Promise.all([
      apiClient<WslInfo>('/api/wsl/distributions'),
      apiClient<AppCatalogResponse>('/api/apps'),
    ]).then(([wsl, catalog]) => {
      if (cancelled) return;
      setWslInfo(wsl);
      setNativeApps(catalog.apps ?? []);
      const preferred = wsl.preferred || wsl.default || wsl.distributions[0]?.name || '';
      setDistribution(preferred);
      if (!preferred) {
        setLoading(false);
        setError('Nenhuma distribuição WSL operacional foi encontrada. Instale o Kali Linux pela Central Windows + Linux.');
      }
    }).catch(cause => {
      if (cancelled) return;
      setLoading(false);
      setError(cause instanceof Error ? cause.message : 'Falha ao consultar o ambiente Windows + Linux.');
    });

    return () => { cancelled = true; };
  }, []);

  const refreshInventory = useCallback(async (showSpinner = true) => {
    if (!distribution) return;
    if (showSpinner) setRefreshing(true);
    setError('');
    try {
      const result = await apiClient<ToolInventory>(`/api/security/tools?distribution=${encodeURIComponent(distribution)}`);
      setInventory(result);
    } catch (cause) {
      setInventory(null);
      setError(cause instanceof Error ? cause.message : 'Falha ao consultar ferramentas da distribuição.');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [distribution]);

  useEffect(() => {
    if (distribution) void refreshInventory(false);
  }, [distribution, refreshInventory]);

  const categories = useMemo(() => {
    const values = new Set((inventory?.tools ?? []).map(tool => tool.category));
    return [...values].sort();
  }, [inventory?.tools]);

  const filteredTools = useMemo(() => {
    const query = search.trim().toLocaleLowerCase();
    return (inventory?.tools ?? []).filter(tool => {
      if (category !== 'all' && tool.category !== category) return false;
      if (installedOnly && !tool.installed) return false;
      if (!query) return true;
      return `${tool.name} ${tool.command} ${tool.description} ${tool.category}`.toLocaleLowerCase().includes(query);
    });
  }, [category, installedOnly, inventory?.tools, search]);

  const stats = useMemo(() => {
    const tools = inventory?.tools ?? [];
    const installed = tools.filter(tool => tool.installed).length;
    const gui = tools.filter(tool => findGuiApp(tool, nativeApps, distribution)).length;
    return { total: tools.length, installed, missing: Math.max(0, tools.length - installed), gui };
  }, [distribution, inventory?.tools, nativeApps]);

  const openTerminal = useCallback(() => {
    if (!distribution) return;
    const pid = createProcess('cloudos-terminal.obx', `Terminal · ${distribution}`, '⚡');
    openWindow({
      appId: 'cloudos-terminal',
      title: `CloudOS Terminal — ${distribution}`,
      icon: '⚡',
      width: 940,
      height: 610,
      processId: pid,
      params: { profile: 'wsl', distribution },
    });
  }, [createProcess, distribution, openWindow]);

  const launchGui = useCallback(async (app: NativeApp) => {
    setNotice('');
    setError('');
    try {
      await apiClient(`/api/apps/${encodeURIComponent(app.id)}/launch`, { method: 'POST' });
      setNotice(`${app.name} foi encaminhado ao Host/WSLg.`);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : `Não foi possível abrir ${app.name}.`);
    }
  }, []);

  const copyCommand = useCallback(async (command: string) => {
    try {
      await navigator.clipboard.writeText(command);
      setNotice(`Comando “${command}” copiado. O Tool Center não executa comandos automaticamente.`);
    } catch {
      setNotice(`Comando: ${command}`);
    }
  }, []);

  const addScope = () => {
    const result = addScopeAsset(workspace, scopeInput);
    setWorkspace(result.workspace);
    if (result.added) {
      setScopeInput('');
      setNotice('Alvo adicionado ao workspace de escopo local.');
      setError('');
    } else {
      setError(result.reason);
    }
  };

  return (
    <div className="ktc-root">
      <header className="ktc-hero">
        <div className="ktc-brand">
          <div className="ktc-logo" aria-hidden="true">🐉</div>
          <div>
            <p>Kali Linux · CloudOS</p>
            <h1>Tool Center</h1>
            <span>Inventário, escopo e acesso seguro às ferramentas da distribuição.</span>
          </div>
        </div>
        <div className="ktc-hero-actions">
          <select value={distribution} onChange={event => setDistribution(event.target.value)} aria-label="Distribuição WSL">
            {!wslInfo?.distributions.length && <option value="">Sem WSL</option>}
            {wslInfo?.distributions.map(distro => (
              <option key={distro.name} value={distro.name}>{distro.name} · WSL {distro.version ?? '?'}</option>
            ))}
          </select>
          <button type="button" onClick={openTerminal} disabled={!distribution}>⚡ Abrir Terminal</button>
          <button type="button" onClick={() => void refreshInventory()} disabled={!distribution || refreshing}>{refreshing ? 'Consultando…' : '↻ Atualizar'}</button>
        </div>
      </header>

      {(error || notice) && (
        <div className={`ktc-banner ${error ? 'ktc-banner--error' : 'ktc-banner--notice'}`} role={error ? 'alert' : 'status'}>
          <span>{error || notice}</span>
          <button type="button" onClick={() => { setError(''); setNotice(''); }}>×</button>
        </div>
      )}

      <section className="ktc-stats" aria-label="Resumo">
        <article><small>Catalogadas</small><strong>{stats.total}</strong><span>allowlist CloudOS</span></article>
        <article><small>Instaladas</small><strong>{stats.installed}</strong><span>na distro atual</span></article>
        <article><small>Ausentes</small><strong>{stats.missing}</strong><span>sem execução implícita</span></article>
        <article><small>GUI WSLg</small><strong>{stats.gui}</strong><span>detectadas no catálogo</span></article>
      </section>

      <div className="ktc-layout">
        <aside className="ktc-scope">
          <div className="ktc-section-title">
            <div><small>Projeto</small><strong>Escopo autorizado</strong></div>
            <span>{workspace.scopes.length}/50</span>
          </div>

          <label className="ktc-field">
            <span>Nome do projeto</span>
            <input value={workspace.projectName} onChange={event => setWorkspace(current => ({ ...current, projectName: event.target.value.slice(0, 120) }))} />
          </label>

          <div className="ktc-scope-add">
            <input
              value={scopeInput}
              onChange={event => setScopeInput(event.target.value)}
              onKeyDown={event => { if (event.key === 'Enter') addScope(); }}
              placeholder="domínio, IP, CIDR ou URL"
              aria-label="Adicionar alvo ao escopo"
            />
            <button type="button" onClick={addScope}>＋</button>
          </div>

          <div className="ktc-scope-list">
            {workspace.scopes.length === 0 ? (
              <p>Nenhum alvo registrado. O inventário continua disponível, mas mantenha a execução limitada ao escopo autorizado.</p>
            ) : workspace.scopes.map(scope => (
              <div className={`ktc-scope-item ${workspace.activeScope === scope ? 'is-active' : ''}`} key={scope}>
                <button type="button" className="ktc-scope-select" onClick={() => setWorkspace(current => selectScopeAsset(current, scope))} title={scope}>{scope}</button>
                <button type="button" className="ktc-scope-remove" onClick={() => setWorkspace(current => removeScopeAsset(current, scope))} aria-label={`Remover ${scope}`}>×</button>
              </div>
            ))}
          </div>

          <label className="ktc-field ktc-field--notes">
            <span>Notas locais</span>
            <textarea value={workspace.notes} onChange={event => setWorkspace(current => ({ ...current, notes: event.target.value.slice(0, 1000) }))} placeholder="Autorização, janela de teste, observações…" />
          </label>

          <div className="ktc-scope-warning">
            <strong>Execução controlada</strong>
            <p>Este painel não injeta comandos no terminal nem aceita executável/argv do frontend. Use o Terminal apenas em ativos autorizados.</p>
          </div>
        </aside>

        <main className="ktc-tools">
          <div className="ktc-filterbar">
            <input value={search} onChange={event => setSearch(event.target.value)} placeholder="Pesquisar Nmap, OSINT, web…" aria-label="Pesquisar ferramentas" />
            <select value={category} onChange={event => setCategory(event.target.value)} aria-label="Categoria">
              <option value="all">Todas as categorias</option>
              {categories.map(value => <option key={value} value={value}>{CATEGORY_META[value]?.label ?? value}</option>)}
            </select>
            <label className="ktc-toggle"><input type="checkbox" checked={installedOnly} onChange={event => setInstalledOnly(event.target.checked)} /><span>Só instaladas</span></label>
          </div>

          {loading ? (
            <div className="ktc-empty"><span className="ktc-spinner" /><strong>Mapeando ferramentas do Kali…</strong></div>
          ) : !distribution ? (
            <div className="ktc-empty"><span>🐧</span><strong>Instale uma distribuição Linux para usar o Tool Center.</strong></div>
          ) : filteredTools.length === 0 ? (
            <div className="ktc-empty"><span>⌕</span><strong>Nenhuma ferramenta corresponde aos filtros.</strong></div>
          ) : (
            <div className="ktc-grid">
              {filteredTools.map(tool => {
                const guiApp = findGuiApp(tool, nativeApps, distribution);
                const meta = CATEGORY_META[tool.category] ?? { label: tool.category, icon: '◌' };
                return (
                  <article className={`ktc-card ${tool.installed ? 'is-installed' : ''}`} key={tool.id}>
                    <header>
                      <div className="ktc-tool-icon">{meta.icon}</div>
                      <div className="ktc-tool-heading">
                        <small>{meta.label}</small>
                        <strong>{tool.name}</strong>
                      </div>
                      <span className={`ktc-status ${tool.installed ? 'ktc-status--ok' : 'ktc-status--missing'}`}>{tool.installed ? 'instalada' : 'ausente'}</span>
                    </header>
                    <p>{tool.description}</p>
                    <code>{tool.command}</code>
                    <footer>
                      <button type="button" onClick={() => void copyCommand(tool.command)}>Copiar nome</button>
                      {tool.installed && <button type="button" onClick={openTerminal}>Terminal</button>}
                      {guiApp && <button className="ktc-primary" type="button" onClick={() => void launchGui(guiApp)}>Abrir GUI</button>}
                    </footer>
                  </article>
                );
              })}
            </div>
          )}
        </main>
      </div>
    </div>
  );
}
