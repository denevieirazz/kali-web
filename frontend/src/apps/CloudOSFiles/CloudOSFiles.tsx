import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import FilePreviewPanel from './FilePreviewPanel';
import {
  createEntry,
  emptyTrash,
  formatBytes,
  listDirectory,
  listTrash,
  moveToTrash,
  pasteEntry,
  permanentlyDelete,
  readFile,
  renameEntry,
  restoreFromTrash,
  storageEstimate,
  uploadFiles,
  writeTextFile,
  type ClipboardEntry,
  type FileEntry,
  type StorageInfo,
} from './opfsFileService';
import './CloudOSFiles.css';

type ViewMode = 'files' | 'trash';
type SortField = 'name' | 'modified' | 'size';
type DialogType = 'create-file' | 'create-folder' | 'rename' | 'confirm-delete' | 'confirm-empty-trash' | null;
type DialogState = { type: DialogType; title?: string; message?: string; entry?: FileEntry };
type EditorState = { name: string; content: string } | null;

function isTypingTarget(target: EventTarget | null) {
  return target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || target instanceof HTMLSelectElement || (target instanceof HTMLElement && target.isContentEditable);
}

export default function CloudOSFiles() {
  const [entries, setEntries] = useState<FileEntry[]>([]);
  const [currentPath, setCurrentPath] = useState<string[]>([]);
  const [viewMode, setViewMode] = useState<ViewMode>('files');
  const [selectedName, setSelectedName] = useState<string | null>(null);
  const [previewFile, setPreviewFile] = useState<File | null>(null);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [sortField, setSortField] = useState<SortField>('name');
  const [clipboard, setClipboard] = useState<ClipboardEntry | null>(null);
  const [storageInfo, setStorageInfo] = useState<StorageInfo | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isDragging, setIsDragging] = useState(false);
  const [errorMessage, setErrorMessage] = useState('');
  const [editor, setEditor] = useState<EditorState>(null);
  const [dialog, setDialog] = useState<DialogState>({ type: null });
  const [dialogInputValue, setDialogInputValue] = useState('');
  const uploadInputRef = useRef<HTMLInputElement>(null);
  const directoryGeneration = useRef(0);
  const previewGeneration = useRef(0);

  const selectedEntry = useMemo(
    () => entries.find(entry => entry.name === selectedName) ?? null,
    [entries, selectedName],
  );

  const loadDirectory = useCallback(async () => {
    const generation = ++directoryGeneration.current;
    setIsLoading(true);
    setErrorMessage('');
    try {
      const [nextEntries, estimate] = await Promise.all([
        viewMode === 'trash' ? listTrash() : listDirectory(currentPath),
        storageEstimate(),
      ]);
      if (generation !== directoryGeneration.current) return;
      setEntries(nextEntries);
      setStorageInfo(estimate);
      setSelectedName(null);
      setPreviewFile(null);
      setPreviewLoading(false);
    } catch (error) {
      if (generation !== directoryGeneration.current) return;
      setEntries([]);
      setErrorMessage(error instanceof Error ? error.message : 'Falha ao acessar o armazenamento OPFS.');
    } finally {
      if (generation === directoryGeneration.current) setIsLoading(false);
    }
  }, [currentPath, viewMode]);

  useEffect(() => {
    void loadDirectory();
  }, [loadDirectory]);

  const visibleEntries = useMemo(() => {
    const query = searchQuery.trim().toLocaleLowerCase();
    return entries
      .filter(entry => !query || (entry.originalName || entry.name).toLocaleLowerCase().includes(query))
      .sort((left, right) => {
        if (left.kind !== right.kind) return left.kind === 'directory' ? -1 : 1;
        if (sortField === 'size') return right.size - left.size;
        if (sortField === 'modified') return right.modified - left.modified;
        return (left.originalName || left.name).localeCompare(right.originalName || right.name, undefined, { sensitivity: 'base' });
      });
  }, [entries, searchQuery, sortField]);

  const selectEntry = useCallback(async (entry: FileEntry) => {
    setSelectedName(entry.name);
    const generation = ++previewGeneration.current;
    setPreviewFile(null);
    if (entry.kind === 'directory') {
      setPreviewLoading(false);
      return;
    }
    setPreviewLoading(true);
    try {
      const file = await readFile(currentPath, entry.name, viewMode === 'trash');
      if (generation === previewGeneration.current) setPreviewFile(file);
    } catch {
      if (generation === previewGeneration.current) setErrorMessage('Não foi possível carregar o preview deste arquivo.');
    } finally {
      if (generation === previewGeneration.current) setPreviewLoading(false);
    }
  }, [currentPath, viewMode]);

  const openEntry = useCallback(async (entry: FileEntry) => {
    if (entry.kind === 'directory' && viewMode === 'files') {
      setCurrentPath(path => [...path, entry.name]);
      return;
    }
    await selectEntry(entry);
  }, [selectEntry, viewMode]);

  const downloadEntry = useCallback(async (entry: FileEntry) => {
    if (entry.kind !== 'file') return;
    try {
      const file = await readFile(currentPath, entry.name, viewMode === 'trash');
      const url = URL.createObjectURL(file);
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = entry.originalName || entry.name;
      anchor.rel = 'noopener';
      anchor.click();
      window.setTimeout(() => URL.revokeObjectURL(url), 0);
    } catch {
      setErrorMessage('Falha ao preparar o download do arquivo.');
    }
  }, [currentPath, viewMode]);

  const openEditor = useCallback(async (entry: FileEntry) => {
    if (entry.kind !== 'file' || viewMode === 'trash') return;
    try {
      const file = await readFile(currentPath, entry.name);
      if (file.size > 2 * 1024 * 1024) throw new Error('Arquivo grande demais para o editor rápido.');
      setEditor({ name: entry.name, content: await file.text() });
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Falha ao abrir o editor.');
    }
  }, [currentPath, viewMode]);

  const saveEditor = useCallback(async () => {
    if (!editor) return;
    setIsLoading(true);
    try {
      await writeTextFile(currentPath, editor.name, editor.content);
      setEditor(null);
      await loadDirectory();
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Falha ao salvar o arquivo.');
    } finally {
      setIsLoading(false);
    }
  }, [currentPath, editor, loadDirectory]);

  const confirmDialog = useCallback(async () => {
    if (!dialog.type) return;
    setIsLoading(true);
    setErrorMessage('');
    try {
      if (dialog.type === 'create-file') {
        await createEntry(currentPath, 'file', dialogInputValue);
      } else if (dialog.type === 'create-folder') {
        await createEntry(currentPath, 'directory', dialogInputValue);
      } else if (dialog.type === 'rename' && dialog.entry) {
        await renameEntry(currentPath, dialog.entry, dialogInputValue);
      } else if (dialog.type === 'confirm-delete' && dialog.entry) {
        if (viewMode === 'trash') await permanentlyDelete(dialog.entry);
        else await moveToTrash(currentPath, dialog.entry);
      } else if (dialog.type === 'confirm-empty-trash') {
        await emptyTrash();
      }
      setDialog({ type: null });
      setDialogInputValue('');
      await loadDirectory();
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Falha ao realizar a operação.');
    } finally {
      setIsLoading(false);
    }
  }, [currentPath, dialog, dialogInputValue, loadDirectory, viewMode]);

  const restoreEntry = useCallback(async (entry: FileEntry) => {
    setIsLoading(true);
    try {
      await restoreFromTrash(entry);
      await loadDirectory();
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Falha ao restaurar o item.');
    } finally {
      setIsLoading(false);
    }
  }, [loadDirectory]);

  const pasteClipboard = useCallback(async () => {
    if (!clipboard || viewMode !== 'files') return;
    setIsLoading(true);
    try {
      const result = await pasteEntry(clipboard, currentPath);
      if (clipboard.action === 'cut' && (result.moved || result.name === clipboard.entry.name)) setClipboard(null);
      await loadDirectory();
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Falha ao colar o item.');
    } finally {
      setIsLoading(false);
    }
  }, [clipboard, currentPath, loadDirectory, viewMode]);

  const handleUpload = useCallback(async (files: FileList | File[]) => {
    if (viewMode !== 'files' || files.length === 0) return;
    setIsLoading(true);
    try {
      await uploadFiles(currentPath, Array.from(files));
      await loadDirectory();
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Falha ao enviar arquivos.');
    } finally {
      setIsLoading(false);
      if (uploadInputRef.current) uploadInputRef.current.value = '';
    }
  }, [currentPath, loadDirectory, viewMode]);

  const requestRename = useCallback((entry: FileEntry) => {
    if (viewMode !== 'files') return;
    setDialogInputValue(entry.name);
    setDialog({ type: 'rename', title: 'Renomear item', entry });
  }, [viewMode]);

  const requestDelete = useCallback((entry: FileEntry) => {
    setDialog({
      type: 'confirm-delete',
      entry,
      title: viewMode === 'trash' ? 'Excluir permanentemente' : 'Mover para a Lixeira',
      message: viewMode === 'trash'
        ? `Apagar definitivamente “${entry.originalName || entry.name}”? Esta ação não pode ser desfeita.`
        : `Mover “${entry.name}” para a Lixeira?`,
    });
  }, [viewMode]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (isTypingTarget(event.target) || editor || dialog.type) return;
      if (event.key === 'Escape') {
        setSelectedName(null);
        setPreviewFile(null);
      } else if (event.key === 'Delete' && selectedEntry) {
        event.preventDefault();
        requestDelete(selectedEntry);
      } else if (event.key === 'F2' && selectedEntry && viewMode === 'files') {
        event.preventDefault();
        requestRename(selectedEntry);
      } else if (event.key === 'Enter' && selectedEntry) {
        event.preventDefault();
        void openEntry(selectedEntry);
      } else if (event.ctrlKey && event.key.toLowerCase() === 'c' && selectedEntry && viewMode === 'files') {
        event.preventDefault();
        setClipboard({ entry: selectedEntry, action: 'copy', sourcePath: [...currentPath] });
      } else if (event.ctrlKey && event.key.toLowerCase() === 'x' && selectedEntry && viewMode === 'files') {
        event.preventDefault();
        setClipboard({ entry: selectedEntry, action: 'cut', sourcePath: [...currentPath] });
      } else if (event.ctrlKey && event.key.toLowerCase() === 'v' && clipboard && viewMode === 'files') {
        event.preventDefault();
        void pasteClipboard();
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [clipboard, currentPath, dialog.type, editor, openEntry, pasteClipboard, requestDelete, requestRename, selectedEntry, viewMode]);

  return (
    <div className="cf-root">
      <header className="cf-toolbar">
        <button className="cf-btn" onClick={() => setCurrentPath(path => path.slice(0, -1))} disabled={!currentPath.length || viewMode === 'trash'} title="Pasta anterior">←</button>
        <button className="cf-btn" onClick={() => void loadDirectory()} title="Atualizar">↻</button>
        <div className="cf-toolbar-divider" />

        {viewMode === 'files' ? (
          <>
            <button className="cf-btn primary-btn" onClick={() => { setDialogInputValue('Novo Documento.txt'); setDialog({ type: 'create-file', title: 'Criar arquivo' }); }}>＋ Arquivo</button>
            <button className="cf-btn" onClick={() => { setDialogInputValue('Nova Pasta'); setDialog({ type: 'create-folder', title: 'Criar pasta' }); }}>＋ Pasta</button>
            <button className="cf-btn" onClick={() => uploadInputRef.current?.click()}>↑ Enviar</button>
            <input ref={uploadInputRef} hidden multiple type="file" onChange={event => event.target.files && void handleUpload(event.target.files)} />
            {clipboard && <button className="cf-btn paste-btn" onClick={() => void pasteClipboard()}>📋 Colar</button>}
            <button className="cf-btn" onClick={() => { setViewMode('trash'); setCurrentPath([]); }}>🗑️ Lixeira</button>
          </>
        ) : (
          <>
            <button className="cf-btn primary-btn" onClick={() => { setViewMode('files'); setCurrentPath([]); }}>📁 Meus Arquivos</button>
            <button className="cf-btn danger-btn" disabled={!entries.length} onClick={() => setDialog({ type: 'confirm-empty-trash', title: 'Esvaziar Lixeira', message: 'Apagar permanentemente todos os itens da Lixeira?' })}>🗑️ Esvaziar</button>
          </>
        )}

        <nav className="cf-address" aria-label="Caminho">
          <button className={!currentPath.length && viewMode === 'files' ? 'active-breadcrumb' : ''} onClick={() => { setViewMode('files'); setCurrentPath([]); }}>local:</button>
          {viewMode === 'trash' ? <button className="active-breadcrumb">/ 🗑️ lixeira</button> : currentPath.map((part, index) => (
            <button key={`${part}-${index}`} className={index === currentPath.length - 1 ? 'active-breadcrumb' : ''} onClick={() => setCurrentPath(currentPath.slice(0, index + 1))}>/ {part}</button>
          ))}
        </nav>

        <input className="cf-search" value={searchQuery} onChange={event => setSearchQuery(event.target.value)} placeholder="Pesquisar…" aria-label="Pesquisar arquivos" />
        <select className="cf-sort-select" value={sortField} onChange={event => setSortField(event.target.value as SortField)} aria-label="Ordenar por">
          <option value="name">Nome</option><option value="modified">Modificado</option><option value="size">Tamanho</option>
        </select>
      </header>

      {errorMessage && <div className="cf-error" role="alert"><span>⚠️ {errorMessage}</span><button onClick={() => setErrorMessage('')}>×</button></div>}

      <div className="cf-workspace">
        <main
          className={`cf-content ${isDragging ? 'is-dragging' : ''}`}
          onDragOver={event => { if (viewMode === 'files') { event.preventDefault(); setIsDragging(true); } }}
          onDragLeave={() => setIsDragging(false)}
          onDrop={event => { event.preventDefault(); setIsDragging(false); if (viewMode === 'files' && event.dataTransfer.files.length) void handleUpload(event.dataTransfer.files); }}
        >
          {isDragging && <div className="cf-drop-overlay">Solte os arquivos para enviar</div>}
          {isLoading ? (
            <div className="cf-empty"><div className="cf-spinner" /><span>Processando armazenamento…</span></div>
          ) : visibleEntries.length ? (
            <div className="cf-grid" role="list">
              {visibleEntries.map(entry => {
                const selected = selectedName === entry.name;
                return (
                  <article
                    key={entry.name}
                    className={`cf-item ${selected ? 'selected' : ''}`}
                    onClick={() => void selectEntry(entry)}
                    onDoubleClick={() => void openEntry(entry)}
                    onKeyDown={event => { if (event.key === 'Enter') void openEntry(entry); }}
                    role="listitem"
                    tabIndex={0}
                  >
                    <div className="cf-icon">{entry.kind === 'directory' ? '📁' : '📄'}</div>
                    <strong className="cf-name" title={entry.originalName || entry.name}>{entry.originalName || entry.name}</strong>
                    <small className="cf-size">{entry.kind === 'directory' ? 'Pasta' : formatBytes(entry.size)}</small>
                    <div className="cf-actions">
                      {viewMode === 'files' ? (
                        <>
                          <button onClick={event => { event.stopPropagation(); void openEntry(entry); }}>{entry.kind === 'directory' ? 'Abrir' : 'Preview'}</button>
                          {entry.kind === 'file' && <button onClick={event => { event.stopPropagation(); void downloadEntry(entry); }}>Baixar</button>}
                          <button onClick={event => { event.stopPropagation(); setClipboard({ entry, action: 'copy', sourcePath: [...currentPath] }); }}>Copiar</button>
                          <button onClick={event => { event.stopPropagation(); setClipboard({ entry, action: 'cut', sourcePath: [...currentPath] }); }}>Recortar</button>
                          <button onClick={event => { event.stopPropagation(); requestRename(entry); }}>Renomear</button>
                          <button className="danger" onClick={event => { event.stopPropagation(); requestDelete(entry); }}>Excluir</button>
                        </>
                      ) : (
                        <>
                          <button className="primary" onClick={event => { event.stopPropagation(); void restoreEntry(entry); }}>Restaurar</button>
                          {entry.kind === 'file' && <button onClick={event => { event.stopPropagation(); void selectEntry(entry); }}>Preview</button>}
                          <button className="danger" onClick={event => { event.stopPropagation(); requestDelete(entry); }}>Apagar</button>
                        </>
                      )}
                    </div>
                  </article>
                );
              })}
            </div>
          ) : (
            <div className="cf-empty"><span>{viewMode === 'trash' ? '🗑️' : '☁️'}</span><strong>{viewMode === 'trash' ? 'Lixeira vazia' : 'Pasta vazia'}</strong><small>{viewMode === 'trash' ? 'Nenhum item excluído.' : 'Crie, envie ou arraste arquivos para começar.'}</small></div>
          )}
        </main>

        <FilePreviewPanel
          entry={selectedEntry}
          file={previewFile}
          loading={previewLoading}
          onClose={() => { setSelectedName(null); setPreviewFile(null); }}
          onEdit={() => selectedEntry && void openEditor(selectedEntry)}
          onDownload={() => selectedEntry && void downloadEntry(selectedEntry)}
        />
      </div>

      <footer className="cf-status">
        <span>{visibleEntries.length} item(ns){clipboard ? ` · ${clipboard.action === 'cut' ? 'recortado' : 'copiado'}: ${clipboard.entry.name}` : ''}</span>
        <span>{storageInfo ? `OPFS ${formatBytes(storageInfo.used)} / ${formatBytes(storageInfo.quota)}` : 'Armazenamento OPFS local'}</span>
      </footer>

      {editor && (
        <div className="cf-modal" role="dialog" aria-modal="true" aria-labelledby="editor-title">
          <section className="cf-modal-card">
            <header className="cf-modal-header"><strong id="editor-title">📝 {editor.name}</strong><button className="cf-modal-close" onClick={() => setEditor(null)}>✕</button></header>
            <textarea className="cf-modal-textarea" value={editor.content} onChange={event => setEditor({ ...editor, content: event.target.value })} aria-label="Conteúdo do arquivo" />
            <footer className="cf-modal-footer"><button className="cf-btn" onClick={() => setEditor(null)}>Cancelar</button><button className="cf-btn primary-btn" onClick={() => void saveEditor()}>Salvar alterações</button></footer>
          </section>
        </div>
      )}

      {dialog.type && (
        <div className="cf-modal" role="dialog" aria-modal="true" aria-labelledby="dialog-title">
          <section className="cf-dialog-box">
            <h2 className="cf-dialog-title" id="dialog-title">{dialog.title}</h2>
            {dialog.message && <p className="cf-dialog-message">{dialog.message}</p>}
            {(dialog.type === 'create-file' || dialog.type === 'create-folder' || dialog.type === 'rename') && (
              <input className="cf-dialog-input" autoFocus value={dialogInputValue} onChange={event => setDialogInputValue(event.target.value)} onKeyDown={event => { if (event.key === 'Enter') void confirmDialog(); }} />
            )}
            <div className="cf-dialog-actions"><button className="cf-btn" onClick={() => { setDialog({ type: null }); setDialogInputValue(''); }}>Cancelar</button><button className={`cf-btn ${dialog.type?.includes('delete') || dialog.type === 'confirm-empty-trash' ? 'danger-btn' : 'primary-btn'}`} onClick={() => void confirmDialog()}>Confirmar</button></div>
          </section>
        </div>
      )}
    </div>
  );
}
