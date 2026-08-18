import { useCallback, useEffect, useMemo, useState } from 'react';
import type { WorkflowProvider } from '../../core/workflowCore.js';
import { captureClipboardToActiveEvidence } from '../../services/workflowQuickEvidence';
import { getFileMark, listFileMarks, setFileMark, type WorkflowFileMark } from '../../services/workflowFileMarks';
import { launchWorkflowApp, openFilesAt, openWorkspace } from '../../services/workflowLaunch';
import {
  getActiveWorkspace,
  listIndexedFiles,
  listWorkspaceEvidence,
  listWorkspaceNotes,
  type IndexedFile,
  type WorkflowNote,
} from '../../services/workflowWorkspace';
import { forgetWorkflowWindow } from '../../services/workflowWindow';
import { useWindowManager } from '../../stores/windowManager';
import './WorkflowBatch4Shell.css';

type FilesSelection = {
  provider: WorkflowProvider;
  path: string[];
  name: string;
  kind: 'file' | 'directory' | 'symlink';
};

type WorkspaceContext = {
  notes: WorkflowNote[];
  evidence: Array<{ name: string; kind: string; size?: number; modified?: number }>;
  files: IndexedFile[];
};

function parseFilesSelection(target: EventTarget | null): FilesSelection | null {
  if (!(target instanceof Element)) return null;
  const item = target.closest<HTMLElement>('.cf-item');
  const root = item?.closest<HTMLElement>('.cf-root[data-files-source]');
  if (!item || !root) return null;
  const provider = root.dataset.filesSource;
  if (provider !== 'opfs' && provider !== 'windows' && provider !== 'wsl') return null;
  const name = item.querySelector<HTMLElement>('.cf-name')?.textContent?.trim() || '';
  if (!name) return null;
  const addressButtons = Array.from(root.querySelectorAll<HTMLButtonElement>('.cf-address button'));
  if (addressButtons.some(button => /lixeira/i.test(button.textContent || ''))) return null;
  const path = addressButtons.slice(1).map(button => (button.textContent || '').trim().replace(/^\/\s*/, '')).filter(Boolean);
  const rawKind = item.dataset.fileKind;
  const kind = rawKind === 'directory' || rawKind === 'symlink' ? rawKind : 'file';
  return { provider, path, name, kind };
}

function sameTarget(left: FilesSelection | null, right: FilesSelection | null) {
  return left?.provider === right?.provider && left?.name === right?.name && left?.kind === right?.kind && JSON.stringify(left?.path || []) === JSON.stringify(right?.path || []);
}

function requestWorkspaceTab(label: 'Visão geral' | 'Notes' | 'Evidence') {
  let attempts = 0;
  const trySelect = () => {
    const button = Array.from(document.querySelectorAll<HTMLButtonElement>('.workflow-workspace .ww-tabs button'))
      .find(item => item.textContent?.trim() === label && !item.disabled);
    if (button) {
      button.click();
      return;
    }
    attempts += 1;
    if (attempts < 12) window.requestAnimationFrame(trySelect);
  };
  window.requestAnimationFrame(trySelect);
}

function workspaceTabIsActive(label: string) {
  return Array.from(document.querySelectorAll<HTMLButtonElement>('.workflow-workspace .ww-tabs button.active'))
    .some(button => button.textContent?.trim() === label);
}

function displayedWorkspaceId() {
  const root = document.querySelector<HTMLElement>('.window.active .workflow-workspace[data-workspace-id]');
  return root?.dataset.workspaceId?.trim() || '';
}

function pathStartsWith(path: string[], prefix: string[]) {
  return path.length >= prefix.length && prefix.every((part, index) => path[index] === part);
}

function openMark(mark: WorkflowFileMark) {
  if (mark.kind === 'directory') return openFilesAt(mark.provider, [...mark.path, mark.name]);
  return openFilesAt(mark.provider, mark.path, mark.name);
}

function dispatchTerminalShortcut(key: string, shiftKey = false) {
  window.dispatchEvent(new KeyboardEvent('keydown', { key, ctrlKey: true, shiftKey, bubbles: true, cancelable: true }));
}

export default function WorkflowBatch4Shell() {
  const windows = useWindowManager(state => state.windows);
  const activeWindowId = useWindowManager(state => state.activeWindowId);
  const [revision, setRevision] = useState(0);
  const [message, setMessage] = useState('');
  const [filesSelection, setFilesSelection] = useState<FilesSelection | null>(null);
  const [workspaceContext, setWorkspaceContext] = useState<WorkspaceContext>({ notes: [], evidence: [], files: [] });

  const activeWindow = useMemo(() => windows.find(item => item.id === activeWindowId) || null, [activeWindowId, windows]);
  const activeWorkspace = useMemo(() => { void revision; return getActiveWorkspace(); }, [revision]);
  const currentMark = useMemo(() => filesSelection ? getFileMark(filesSelection) : null, [filesSelection, revision]);
  const favorites = useMemo(() => { void revision; return listFileMarks('favorites').slice(0, 5); }, [revision]);
  const pinned = useMemo(() => { void revision; return listFileMarks('pinned').slice(0, 5); }, [revision]);

  useEffect(() => {
    const changed = () => setRevision(value => value + 1);
    window.addEventListener('cloudos:workflow-changed', changed);
    return () => window.removeEventListener('cloudos:workflow-changed', changed);
  }, []);

  useEffect(() => {
    const onClick = (event: MouseEvent) => {
      const next = parseFilesSelection(event.target);
      if (next) setFilesSelection(current => sameTarget(current, next) ? current : next);
    };
    document.addEventListener('click', onClick, true);
    return () => document.removeEventListener('click', onClick, true);
  }, []);

  useEffect(() => {
    if (activeWindow?.appId !== 'workflow-workspace' || !activeWorkspace) {
      setWorkspaceContext({ notes: [], evidence: [], files: [] });
      return;
    }
    let cancelled = false;
    void Promise.all([
      listWorkspaceNotes(activeWorkspace),
      listWorkspaceEvidence(activeWorkspace),
    ]).then(([notes, evidence]) => {
      if (cancelled) return;
      const files = listIndexedFiles()
        .filter(file => file.provider === activeWorkspace.provider && pathStartsWith(file.path, activeWorkspace.root))
        .sort((left, right) => right.modified - left.modified)
        .slice(0, 5);
      setWorkspaceContext({ notes: notes.slice(0, 3), evidence: evidence.slice(0, 3), files });
    }).catch(() => {
      if (!cancelled) setWorkspaceContext({ notes: [], evidence: [], files: [] });
    });
    return () => { cancelled = true; };
  }, [activeWindow?.appId, activeWorkspace?.id, revision]);

  const toggleApp = useCallback((appId: string, opener: () => string | null | undefined) => {
    const manager = useWindowManager.getState();
    const existing = [...manager.windows].reverse().find(item => item.appId === appId && !item.isSystem);
    if (!existing) return opener();
    if (manager.activeWindowId === existing.id && !existing.isMinimized) {
      manager.minimizeWindow(existing.id);
      return existing.id;
    }
    manager.restoreWindow(existing.id);
    manager.focusWindow(existing.id);
    return existing.id;
  }, []);

  const toggleWorkspace = useCallback((notes = false) => {
    const manager = useWindowManager.getState();
    const existing = [...manager.windows].reverse().find(item => item.appId === 'workflow-workspace' && !item.isSystem);
    if (notes && existing && manager.activeWindowId === existing.id && !existing.isMinimized && workspaceTabIsActive('Notes')) {
      manager.minimizeWindow(existing.id);
      return;
    }
    if (!notes && existing && manager.activeWindowId === existing.id && !existing.isMinimized) {
      manager.minimizeWindow(existing.id);
      return;
    }
    if (existing) {
      manager.restoreWindow(existing.id);
      manager.focusWindow(existing.id);
    } else {
      openWorkspace(getActiveWorkspace()?.id);
    }
    requestWorkspaceTab(notes ? 'Notes' : 'Visão geral');
  }, []);

  const captureEvidence = useCallback(async (workspaceId?: string) => {
    setMessage('');
    try {
      const result = await captureClipboardToActiveEvidence(workspaceId);
      setMessage(`Evidence: ${result.name} salvo em “${result.workspace.name}”.`);
      setRevision(value => value + 1);
    } catch (cause) {
      setMessage(cause instanceof Error ? cause.message : 'Falha ao capturar evidência do clipboard.');
    }
  }, []);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (!event.isTrusted) return;
      const key = event.key.toLowerCase();
      const manager = useWindowManager.getState();
      const focused = manager.windows.find(item => item.id === manager.activeWindowId) || null;

      if (focused?.appId === 'cloudos-terminal' && event.ctrlKey && !event.altKey && !event.metaKey) {
        if (!event.shiftKey && key === 't') {
          event.preventDefault(); event.stopPropagation(); dispatchTerminalShortcut('t', true); return;
        }
        if (!event.shiftKey && key === 'w') {
          event.preventDefault(); event.stopPropagation(); dispatchTerminalShortcut('w', true); return;
        }
        if (event.key === 'Tab') {
          event.preventDefault(); event.stopPropagation(); dispatchTerminalShortcut(event.shiftKey ? 'PageUp' : 'PageDown'); return;
        }
      }

      if (event.ctrlKey && event.shiftKey && key === 'e') {
        event.preventDefault(); event.stopPropagation();
        if (focused?.appId === 'workflow-workspace') {
          const workspaceId = displayedWorkspaceId();
          if (!workspaceId) {
            setMessage('A janela Workspace ativa não possui um projeto selecionado para Evidence.');
            return;
          }
          void captureEvidence(workspaceId);
          return;
        }
        void captureEvidence();
        return;
      }
      if (event.ctrlKey && event.altKey && key === 'w') {
        if (focused && !focused.isSystem && focused.isClosable) {
          event.preventDefault(); event.stopPropagation(); forgetWorkflowWindow(focused.id); manager.closeWindow(focused.id);
        }
        return;
      }
      if (event.ctrlKey && event.altKey && key === '1') {
        event.preventDefault(); event.stopPropagation(); toggleWorkspace(false); return;
      }
      if (event.ctrlKey && event.altKey && key === '2') {
        event.preventDefault(); event.stopPropagation(); toggleWorkspace(true); return;
      }
      if (event.ctrlKey && event.altKey && key === '3') {
        event.preventDefault(); event.stopPropagation(); toggleApp('cloudos-terminal', () => launchWorkflowApp('cloudos-terminal')); return;
      }
    };
    window.addEventListener('keydown', onKeyDown, true);
    return () => window.removeEventListener('keydown', onKeyDown, true);
  }, [captureEvidence, toggleApp, toggleWorkspace]);

  const updateMark = useCallback((kind: 'favorite' | 'pinned') => {
    if (!filesSelection) return;
    const current = getFileMark(filesSelection);
    setFileMark(filesSelection, kind === 'favorite' ? { favorite: !current?.favorite } : { pinned: !current?.pinned });
    setRevision(value => value + 1);
  }, [filesSelection]);

  const showWorkspaceContext = activeWindow?.appId === 'workflow-workspace' && Boolean(activeWorkspace);
  const showFileShelf = activeWindow?.appId === 'cloudos-files';

  return <>
    {showWorkspaceContext && activeWorkspace && <aside className="wb4-context" aria-label="Contexto do projeto ativo">
      <header><div><small>Projeto atual</small><strong>{activeWorkspace.name}</strong><span>{activeWorkspace.client || activeWorkspace.description || 'Workspace local'}</span></div><button onClick={() => requestWorkspaceTab('Visão geral')}>Resumo</button></header>
      <div className="wb4-context-grid">
        <section><h4>Últimas notas</h4>{workspaceContext.notes.map(note => <button key={note.fileName} onClick={() => { openWorkspace(activeWorkspace.id, note.fileName); requestWorkspaceTab('Notes'); }}><strong>{note.title}</strong><small>{new Date(note.modified).toLocaleString()}</small></button>)}{!workspaceContext.notes.length && <p>Sem notas recentes.</p>}</section>
        <section><h4>Últimos arquivos</h4>{workspaceContext.files.map(file => <button key={`${file.provider}:${file.path.join('/')}:${file.name}`} onClick={() => openFilesAt(file.provider, file.path, file.name)}><strong>{file.name}</strong><small>{new Date(file.modified).toLocaleString()}</small></button>)}{!workspaceContext.files.length && <p>Sem arquivos indexados.</p>}</section>
        <section><h4>Últimas evidências</h4>{workspaceContext.evidence.map(entry => <button key={entry.name} onClick={() => requestWorkspaceTab('Evidence')}><strong>{entry.name}</strong><small>{entry.kind === 'file' ? `${entry.size || 0} bytes` : entry.kind}</small></button>)}{!workspaceContext.evidence.length && <p>Sem evidências.</p>}</section>
        <section><h4>Atividade recente</h4><p>Última atividade: {new Date(activeWorkspace.lastActivityAt).toLocaleString()}</p><p>Último acesso: {new Date(activeWorkspace.lastAccessAt).toLocaleString()}</p></section>
      </div>
      <footer><span>Ctrl+Alt+1 Workspace</span><span>Ctrl+Alt+2 Notes</span><span>Ctrl+Shift+E Evidence</span></footer>
    </aside>}

    {showFileShelf && <aside className="wb4-files" aria-label="Favoritos e fixados do Files">
      <header><div><small>Acesso rápido</small><strong>Favoritos · Fixados</strong></div>{filesSelection && <div><button className={currentMark?.favorite ? 'active' : ''} onClick={() => updateMark('favorite')}>★ Favorito</button><button className={currentMark?.pinned ? 'active' : ''} onClick={() => updateMark('pinned')}>📌 Fixar</button></div>}</header>
      {filesSelection && <p className="wb4-selected">{filesSelection.name} · {filesSelection.provider}:{filesSelection.path.length ? `/${filesSelection.path.join('/')}` : '/'}</p>}
      <div className="wb4-files-grid"><section><h4>Favoritos</h4>{favorites.map(mark => <button key={`fav:${mark.provider}:${mark.path.join('/')}:${mark.name}`} onClick={() => openMark(mark)}>{mark.name}</button>)}{!favorites.length && <p>Nenhum favorito.</p>}</section><section><h4>Fixados</h4>{pinned.map(mark => <button key={`pin:${mark.provider}:${mark.path.join('/')}:${mark.name}`} onClick={() => openMark(mark)}>{mark.name}</button>)}{!pinned.length && <p>Nenhum item fixado.</p>}</section></div>
    </aside>}

    {message && <div className="wb4-toast" role="status"><span>{message}</span><button onClick={() => setMessage('')}>×</button></div>}
  </>;
}