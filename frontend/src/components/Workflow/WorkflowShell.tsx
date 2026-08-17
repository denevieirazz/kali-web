import { useEffect, useMemo, useRef, useState } from 'react';
import { useAppRegistry } from '../../core/appRegistry';
import { matchesWorkflowQuery } from '../../core/workflowCore.js';
import { nativeHostBridge } from '../../services/nativeHostBridge';
import {
  clearClipboardHistory,
  copyClipboardEntryToSystem,
  installGlobalClipboardCapture,
  listClipboardEntries,
  pasteClipboardEntry,
  toggleClipboardFavorite,
  type ClipboardMetadata,
} from '../../services/workflowClipboard';
import { launchWorkflowApp, openDefaultBrowser, openFilesAt, openSettings, openWorkspace } from '../../services/workflowLaunch';
import { listIndexedFiles, listNoteIndex, listWorkspaces } from '../../services/workflowWorkspace';
import { activeWorkflowWindowId, maximizeWorkflowWindow, restoreWorkflowWindow, snapWorkflowWindow } from '../../services/workflowWindow';
import FilesWorkflowBridge from './FilesWorkflowBridge';
import './WorkflowShell.css';

type LauncherResult = {
  key: string;
  type: 'app' | 'workspace' | 'note' | 'file' | 'setting';
  title: string;
  detail: string;
  searchText?: string;
  icon: string;
  run: () => void;
};

function typingTarget(target: EventTarget | null) {
  return target instanceof HTMLInputElement
    || target instanceof HTMLTextAreaElement
    || target instanceof HTMLSelectElement
    || (target instanceof HTMLElement && target.isContentEditable);
}

function browserIntent(query: string) {
  return /browser|navegador|web/i.test(query.trim());
}

export default function WorkflowShell() {
  const appMap = useAppRegistry(state => state.apps);
  const [launcherOpen, setLauncherOpen] = useState(false);
  const [clipboardOpen, setClipboardOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [selected, setSelected] = useState(0);
  const [revision, setRevision] = useState(0);
  const [clipboardEntries, setClipboardEntries] = useState<ClipboardMetadata[]>(listClipboardEntries);
  const [message, setMessage] = useState('');
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => installGlobalClipboardCapture(), []);

  useEffect(() => {
    const changed = () => setRevision(value => value + 1);
    const clipboardChanged = () => setClipboardEntries(listClipboardEntries());
    window.addEventListener('cloudos:workflow-changed', changed);
    window.addEventListener('cloudos:clipboard-changed', clipboardChanged);
    return () => {
      window.removeEventListener('cloudos:workflow-changed', changed);
      window.removeEventListener('cloudos:clipboard-changed', clipboardChanged);
    };
  }, []);

  const allResults = useMemo<LauncherResult[]>(() => {
    void revision;
    const appResults: LauncherResult[] = Object.values(appMap)
      .filter(app => nativeHostBridge.available || app.id !== 'browser')
      .map(app => ({
        key: `app:${app.id}`,
        type: app.id === 'settings' ? 'setting' : 'app',
        title: app.name,
        detail: app.id === 'settings' ? 'Configurações' : 'Aplicativo',
        searchText: app.id === 'browser' ? 'browser navegador web modo full' : '',
        icon: app.icon || '◻',
        run: () => app.id === 'settings' ? openSettings() : launchWorkflowApp(app.id),
      }));

    const workspaces = listWorkspaces();
    const activeWorkspaces = workspaces.filter(workspace => workspace.status !== 'archived');
    const workspaceResults: LauncherResult[] = activeWorkspaces.map(workspace => ({
      key: `workspace:${workspace.id}`,
      type: 'workspace',
      title: workspace.name,
      detail: `Workspace · ${workspace.client ? `${workspace.client} · ` : ''}${workspace.provider}`,
      searchText: `${workspace.description} ${workspace.client} ${workspace.tags.join(' ')} ${workspace.type}`,
      icon: '▣',
      run: () => openWorkspace(workspace.id),
    }));

    const noteResults: LauncherResult[] = listNoteIndex().map(note => {
      const workspace = workspaces.find(item => item.id === note.workspaceId);
      return {
        key: `note:${note.workspaceId}:${note.fileName}`,
        type: 'note',
        title: note.title,
        detail: `Nota${workspace ? ` · ${workspace.name}` : ''}`,
        searchText: note.searchText,
        icon: '✎',
        run: () => openWorkspace(note.workspaceId, note.fileName),
      };
    });

    const fileResults: LauncherResult[] = listIndexedFiles().map(file => ({
      key: `file:${file.provider}:${file.path.join('/')}:${file.name}`,
      type: 'file',
      title: file.name,
      detail: `${file.provider}:${file.path.length ? `/${file.path.join('/')}` : '/'}${file.kind === 'directory' ? ' · pasta' : ''}`,
      icon: file.kind === 'directory' ? '📁' : '📄',
      run: () => file.kind === 'directory'
        ? openFilesAt(file.provider, [...file.path, file.name])
        : openFilesAt(file.provider, file.path, file.name),
    }));

    return [...workspaceResults, ...noteResults, ...appResults, ...fileResults];
  }, [appMap, revision]);

  const results = useMemo(() => {
    const filtered = allResults.filter(result => matchesWorkflowQuery(`${result.title} ${result.detail} ${result.searchText || ''} ${result.type}`, query));
    const typeOrder: Record<LauncherResult['type'], number> = { workspace: 0, note: 1, app: 2, setting: 3, file: 4 };
    return filtered.sort((left, right) => typeOrder[left.type] - typeOrder[right.type] || left.title.localeCompare(right.title)).slice(0, 40);
  }, [allResults, query]);

  const showWebOnlyBrowser = !nativeHostBridge.available && browserIntent(query);

  useEffect(() => { setSelected(0); }, [query]);
  useEffect(() => {
    if (!launcherOpen) return;
    window.setTimeout(() => inputRef.current?.focus(), 0);
  }, [launcherOpen]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const key = event.key.toLowerCase();
      if (event.altKey && !event.ctrlKey && event.code === 'Space') {
        event.preventDefault();
        setLauncherOpen(value => !value);
        setClipboardOpen(false);
        return;
      }
      if (event.ctrlKey && event.shiftKey && key === 'p') {
        event.preventDefault();
        setLauncherOpen(value => !value);
        setClipboardOpen(false);
        return;
      }
      if (event.ctrlKey && event.altKey && key === 'v') {
        event.preventDefault();
        setClipboardOpen(value => !value);
        setLauncherOpen(false);
        return;
      }
      if (event.key === 'Escape') {
        setLauncherOpen(false);
        setClipboardOpen(false);
        return;
      }

      // Window shortcuts intentionally run before launcher navigation. This keeps
      // Alt+Shift+Left/Right working while the launcher input owns focus.
      const targetWindow = activeWorkflowWindowId();
      const snapLeft = event.altKey && event.shiftKey && event.key === 'ArrowLeft';
      const snapRight = event.altKey && event.shiftKey && event.key === 'ArrowRight';
      const maximize = event.altKey && event.shiftKey && event.key === 'ArrowUp';
      const restore = event.altKey && event.shiftKey && event.key === 'ArrowDown';
      const metaLeft = event.metaKey && event.key === 'ArrowLeft';
      const metaRight = event.metaKey && event.key === 'ArrowRight';
      if (targetWindow && (snapLeft || snapRight || maximize || restore || metaLeft || metaRight)) {
        event.preventDefault();
        if (snapLeft || metaLeft) snapWorkflowWindow(targetWindow, 'left');
        else if (snapRight || metaRight) snapWorkflowWindow(targetWindow, 'right');
        else if (maximize) maximizeWorkflowWindow(targetWindow);
        else restoreWorkflowWindow(targetWindow);
        if (launcherOpen) window.requestAnimationFrame(() => inputRef.current?.focus());
        return;
      }

      if (launcherOpen) {
        if (event.key === 'ArrowDown') { event.preventDefault(); setSelected(value => Math.min(results.length - 1, value + 1)); }
        else if (event.key === 'ArrowUp') { event.preventDefault(); setSelected(value => Math.max(0, value - 1)); }
        else if (event.key === 'Enter' && results[selected]) {
          event.preventDefault();
          try { results[selected].run(); }
          catch (cause) { setMessage(cause instanceof Error ? cause.message : 'Falha ao abrir item.'); }
          setLauncherOpen(false);
          setQuery('');
        }
        return;
      }

      if (typingTarget(event.target)) return;
    };
    window.addEventListener('keydown', onKeyDown, true);
    return () => window.removeEventListener('keydown', onKeyDown, true);
  }, [launcherOpen, results, selected]);

  const clipboardAction = async (entry: ClipboardMetadata, action: 'copy' | 'paste') => {
    setMessage('');
    try {
      if (action === 'copy') await copyClipboardEntryToSystem(entry);
      else {
        const result = await pasteClipboardEntry(entry);
        if (!result.inserted) setMessage('Conteúdo copiado para o clipboard do sistema; cole no destino desejado.');
      }
    } catch (cause) {
      setMessage(cause instanceof Error ? cause.message : 'Falha no clipboard.');
    }
  };

  return <>
    <FilesWorkflowBridge />
    {launcherOpen && <div className="wf-overlay" onMouseDown={event => { if (event.target === event.currentTarget) setLauncherOpen(false); }}>
      <section className="wf-launcher" role="dialog" aria-modal="true" aria-label="App Launcher">
        <header><span>⌕</span><input ref={inputRef} value={query} onChange={event => setQuery(event.target.value)} placeholder="Aplicações, arquivos, workspace, notas, configurações…" /></header>
        {showWebOnlyBrowser && <div className="wf-webonly-browser" role="status"><div><strong>Browser disponível apenas no modo Full</strong><small>Esta sessão é WebOnly. Abrir o navegador padrão não ativa o Browser do CloudOS, não muda o modo da sessão e não cria integração nova.</small></div><button onClick={() => { try { openDefaultBrowser(); setLauncherOpen(false); setQuery(''); } catch (cause) { setMessage(cause instanceof Error ? cause.message : 'Não foi possível abrir o navegador padrão.'); } }}>Abrir navegador padrão</button></div>}
        {message && <div className="wf-message">{message}</div>}
        <div className="wf-results">{results.map((result, index) => <button key={result.key} className={index === selected ? 'selected' : ''} onMouseEnter={() => setSelected(index)} onClick={() => { try { result.run(); setLauncherOpen(false); setQuery(''); } catch (cause) { setMessage(cause instanceof Error ? cause.message : 'Falha ao abrir item.'); } }}><span className="wf-icon">{result.icon}</span><div><strong>{result.title}</strong><small>{result.detail}</small></div><span className="wf-kind">{result.type}</span></button>)}{!results.length && !showWebOnlyBrowser && <p>Nenhum resultado.</p>}</div>
        <footer><span>Alt+Espaço</span><span>fallback: Ctrl+Shift+P</span><span>↑↓ navegar · Enter abrir</span><span>Alt+Shift+←/→ organiza sem perder foco</span></footer>
      </section>
    </div>}

    {clipboardOpen && <div className="wf-clipboard-panel" role="dialog" aria-label="Clipboard Global">
      <header><div><strong>Clipboard Global</strong><small>30 entradas · 5 MiB/item · conteúdo sensível rejeitado</small></div><button onClick={() => setClipboardOpen(false)}>×</button></header>
      {message && <div className="wf-message">{message}</div>}
      <div className="wf-clipboard-list">{clipboardEntries.map(entry => <div key={entry.id} className="wf-clipboard-row"><button className={entry.favorite ? 'star active' : 'star'} onClick={() => { toggleClipboardFavorite(entry.id); setClipboardEntries(listClipboardEntries()); }}>★</button><div><strong>{entry.source}</strong><p>{entry.preview}</p><small>{entry.bytes} bytes · {new Date(entry.createdAt).toLocaleString()}</small></div><button onClick={() => void clipboardAction(entry, 'copy')}>Copiar</button><button onClick={() => void clipboardAction(entry, 'paste')}>Colar</button></div>)}{!clipboardEntries.length && <p className="wf-empty">Nenhuma entrada segura registrada.</p>}</div>
      <footer><button onClick={() => void clearClipboardHistory()}>Limpar histórico</button><span>Ctrl+Alt+V</span></footer>
    </div>}
  </>;
}
