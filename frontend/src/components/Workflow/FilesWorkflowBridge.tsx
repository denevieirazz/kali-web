import { useCallback, useEffect, useMemo, useState } from 'react';
import { terminalHereCapability, workflowFileOpenMode, type WorkflowProvider } from '../../core/workflowCore.js';
import { addFileToActiveWorkspaceEvidence } from '../../services/workflowWorkspace';
import { openTerminalHere, openTextFileInNotes } from '../../services/workflowLaunch';
import './FilesWorkflowBridge.css';

type FilesContext = { provider: WorkflowProvider; path: string[]; inTrash: boolean };
type FilesSelection = FilesContext & {
  name: string;
  kind: 'file' | 'directory' | 'symlink';
  symlink: boolean;
};

function parseProvider(root: HTMLElement): WorkflowProvider | null {
  const value = root.dataset.filesSource;
  return value === 'opfs' || value === 'windows' || value === 'wsl' ? value : null;
}

function parsePath(root: HTMLElement) {
  const buttons = Array.from(root.querySelectorAll<HTMLButtonElement>('.cf-address button'));
  if (buttons.some(button => /lixeira/i.test(button.textContent || ''))) return [];
  return buttons.slice(1).map(button => (button.textContent || '').trim().replace(/^\/\s*/, '')).filter(Boolean);
}

function contextFromRoot(root: HTMLElement): FilesContext | null {
  const provider = parseProvider(root);
  if (!provider) return null;
  return {
    provider,
    path: parsePath(root),
    inTrash: /lixeira/i.test(root.querySelector('.cf-address')?.textContent || ''),
  };
}

function selectionFromTarget(target: EventTarget | null): FilesSelection | null {
  if (!(target instanceof Element)) return null;
  const item = target.closest<HTMLElement>('.cf-item');
  const root = item?.closest<HTMLElement>('.cf-root');
  if (!item || !root) return null;
  const context = contextFromRoot(root);
  if (!context) return null;
  const kindRaw = item.dataset.fileKind;
  const kind = kindRaw === 'directory' || kindRaw === 'symlink' ? kindRaw : 'file';
  const name = item.querySelector<HTMLElement>('.cf-name')?.textContent?.trim() || '';
  if (!name) return null;
  return {
    ...context,
    name,
    kind,
    symlink: kind === 'symlink' || item.classList.contains('cf-item--symlink'),
  };
}

function originLabel(provider: WorkflowProvider) {
  if (provider === 'windows') return 'Windows';
  if (provider === 'wsl') return 'Linux';
  return 'OPFS';
}

function trashText(provider: WorkflowProvider) {
  if (provider === 'windows') return 'Lixeira CloudOS dentro da pasta Windows autorizada. Não é a Lixeira do Windows; restauração usa metadata do próprio CloudOS.';
  if (provider === 'wsl') return 'Lixeira gerenciada pelo CloudOS no Linux Home. Restauração só aparece quando o provider retorna um identificador válido.';
  return 'Lixeira transacional do OPFS privado do CloudOS, com restauração suportada pelo provider.';
}

function visibleFilesRoot() {
  const roots = Array.from(document.querySelectorAll<HTMLElement>('.cf-root[data-files-source]'));
  return [...roots].reverse().find(root => root.getClientRects().length > 0) || roots.at(-1) || null;
}

export default function FilesWorkflowBridge() {
  const [context, setContext] = useState<FilesContext | null>(null);
  const [selection, setSelection] = useState<FilesSelection | null>(null);
  const [message, setMessage] = useState('');

  useEffect(() => {
    const syncContext = (preferred?: HTMLElement | null) => {
      const root = preferred || visibleFilesRoot();
      const next = root ? contextFromRoot(root) : null;
      setContext(current => current?.provider === next?.provider && current?.inTrash === next?.inTrash && JSON.stringify(current?.path || []) === JSON.stringify(next?.path || []) ? current : next);
      if (!next) setSelection(null);
    };
    syncContext();
    const observer = new MutationObserver(() => syncContext());
    observer.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['data-files-source'] });

    const onClick = (event: MouseEvent) => {
      const element = event.target instanceof Element ? event.target : null;
      const root = element?.closest<HTMLElement>('.cf-root');
      if (root) syncContext(root);
      const next = selectionFromTarget(event.target);
      if (next) {
        setSelection(next);
        setMessage('');
      } else if (element && !element.closest('.wf-files-bridge') && !root) {
        setSelection(null);
      }
    };
    const onDoubleClick = (event: MouseEvent) => {
      const next = selectionFromTarget(event.target);
      if (!next || next.inTrash || next.symlink || next.kind !== 'file') return;
      if (workflowFileOpenMode(next.name, next.kind, next.symlink) !== 'notes') return;
      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();
      try {
        openTextFileInNotes({ provider: next.provider, path: next.path, name: next.name });
        setSelection(next);
      } catch (cause) {
        setMessage(cause instanceof Error ? cause.message : 'Falha ao abrir no Notes.');
      }
    };
    document.addEventListener('click', onClick, true);
    document.addEventListener('dblclick', onDoubleClick, true);
    return () => {
      observer.disconnect();
      document.removeEventListener('click', onClick, true);
      document.removeEventListener('dblclick', onDoubleClick, true);
    };
  }, []);

  const activeContext = selection || context;
  const openMode = useMemo(() => selection ? workflowFileOpenMode(selection.name, selection.kind, selection.symlink) : 'info', [selection]);
  const terminal = useMemo(() => activeContext ? terminalHereCapability(activeContext.provider) : null, [activeContext]);

  const openTerminal = useCallback(() => {
    if (!activeContext) return;
    const path = selection?.kind === 'directory' && !selection.symlink ? [...selection.path, selection.name] : activeContext.path;
    try { openTerminalHere(activeContext.provider, path); }
    catch (cause) { setMessage(cause instanceof Error ? cause.message : 'Terminal indisponível nesta origem.'); }
  }, [activeContext, selection]);

  const openNotes = useCallback(() => {
    if (!selection || openMode !== 'notes' || selection.inTrash) return;
    try { openTextFileInNotes({ provider: selection.provider, path: selection.path, name: selection.name }); }
    catch (cause) { setMessage(cause instanceof Error ? cause.message : 'Falha ao abrir no Notes.'); }
  }, [openMode, selection]);

  const addEvidence = useCallback(async () => {
    if (!selection || selection.kind !== 'file' || selection.symlink || selection.inTrash) return;
    if (!window.confirm(`Adicionar “${selection.name}” à Evidence do Workspace ativo? O original será preservado.`)) return;
    setMessage('');
    try {
      const result = await addFileToActiveWorkspaceEvidence(selection.provider, selection.path, selection.name);
      setMessage(`Adicionado à Evidence de “${result.workspace.name}”.`);
    } catch (cause) { setMessage(cause instanceof Error ? cause.message : 'Falha ao adicionar à Evidence.'); }
  }, [selection]);

  if (!activeContext) return null;

  const contextName = selection?.name || (activeContext.inTrash ? 'Lixeira' : activeContext.path.at(-1) || 'Raiz');
  return <aside className="wf-files-bridge" aria-label="Contexto e ações rápidas do Files">
    <div className="wf-files-context">
      <span className="wf-files-origin">{originLabel(activeContext.provider)}</span>
      <div><strong>{contextName}</strong><small>{activeContext.path.length ? `/${activeContext.path.join('/')}` : '/'} · {activeContext.inTrash ? 'Lixeira' : selection ? openMode === 'notes' ? 'Notes' : openMode === 'viewer' ? 'Viewer' : selection.kind === 'directory' ? 'Pasta' : 'Informações' : 'Origem ativa'}</small></div>
      {selection ? <button onClick={() => setSelection(null)} aria-label="Limpar seleção contextual">×</button> : <span />}
    </div>
    {activeContext.inTrash ? <p className="wf-files-trash-note"><strong>{originLabel(activeContext.provider)}:</strong> {trashText(activeContext.provider)}</p> : <div className="wf-files-actions">
      <button disabled={!terminal?.supported} title={terminal?.reason} onClick={openTerminal}>Abrir no Terminal</button>
      <button disabled={!selection || openMode !== 'notes'} title={!selection || openMode !== 'notes' ? 'Selecione txt, md, json ou log para abrir no Notes.' : ''} onClick={openNotes}>Abrir em Notes</button>
      <button disabled={!selection || selection.kind !== 'file' || selection.symlink} onClick={() => void addEvidence()}>Adicionar à Evidence</button>
    </div>}
    {message && <p className="wf-files-message">{message}</p>}
  </aside>;
}
