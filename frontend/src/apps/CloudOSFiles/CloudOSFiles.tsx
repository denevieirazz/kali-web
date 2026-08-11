import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import './CloudOSFiles.css';

export type FileEntry = {
  name: string;
  kind: 'file' | 'directory';
  size: number;
  modified: number;
  originalPath?: string[]; // for trash items
};

type SortField = 'name' | 'size' | 'modified';

interface ClipboardState {
  entry: FileEntry;
  action: 'copy' | 'cut';
  sourcePath: string[];
}

interface DialogState {
  type: 'create-file' | 'create-folder' | 'rename' | 'confirm-delete' | 'confirm-empty-trash' | null;
  entry?: FileEntry;
  initialValue?: string;
  title?: string;
  message?: string;
}

const ROOT_DIR = 'cloudos_files';
const TRASH_DIR = '.trash';

// OPFS directory traversal helper
async function getOpfsRoot(): Promise<FileSystemDirectoryHandle> {
  const root = await navigator.storage.getDirectory();
  return root.getDirectoryHandle(ROOT_DIR, { create: true });
}

async function getTrashRoot(): Promise<FileSystemDirectoryHandle> {
  const root = await navigator.storage.getDirectory();
  return root.getDirectoryHandle(TRASH_DIR, { create: true });
}

async function getDirAt(pathParts: string[]): Promise<FileSystemDirectoryHandle> {
  let dir = await getOpfsRoot();
  for (const part of pathParts) {
    dir = await dir.getDirectoryHandle(part, { create: false });
  }
  return dir;
}

// Helpers
function sanitizeName(name: string): string {
  return name.trim().replace(/[\\/:*?"<>|]/g, '-').slice(0, 120);
}

function formatBytes(bytes: number): string {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1048576).toFixed(1)} MB`;
}

// Safe recursive copy of directory in OPFS
async function copyDirRecursive(
  srcDir: FileSystemDirectoryHandle,
  destParentDir: FileSystemDirectoryHandle,
  newDirName: string
): Promise<void> {
  const newDir = await destParentDir.getDirectoryHandle(newDirName, { create: true });
  for await (const [name, handle] of (srcDir as any).entries()) {
    if (handle.kind === 'file') {
      const file = await (handle as FileSystemFileHandle).getFile();
      const destFileHandle = await newDir.getFileHandle(name, { create: true });
      const writable = await (destFileHandle as any).createWritable();
      await writable.write(file);
      await writable.close();
    } else if (handle.kind === 'directory') {
      await copyDirRecursive(handle as FileSystemDirectoryHandle, newDir, name);
    }
  }
}

// Check and resolve name collisions
async function getUniqueName(dir: FileSystemDirectoryHandle, baseName: string, isDir: boolean): Promise<string> {
  let name = baseName;
  let counter = 1;
  const extMatch = baseName.match(/^(.*?)(\.[^.]*)?$/);
  const nameNoExt = extMatch ? extMatch[1] : baseName;
  const ext = extMatch && extMatch[2] ? extMatch[2] : '';

  while (true) {
    try {
      if (isDir) {
        await dir.getDirectoryHandle(name);
      } else {
        await dir.getFileHandle(name);
      }
      // If it didn't throw, the name exists: increment
      name = isDir ? `${baseName} (${counter})` : `${nameNoExt} (${counter})${ext}`;
      counter++;
    } catch {
      // Name is available
      return name;
    }
  }
}

export default function CloudOSFiles({}: { windowId?: string }) {
  const [currentPath, setCurrentPath] = useState<string[]>([]);
  const [entries, setEntries] = useState<FileEntry[]>([]);
  const [selectedName, setSelectedName] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [sortField, setSortField] = useState<SortField>('name');
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState('');
  const [storageInfo, setStorageInfo] = useState<{ used: number; quota: number } | null>(null);

  // Views: 'files' | 'trash'
  const [viewMode, setViewMode] = useState<'files' | 'trash'>('files');

  // Clipboard for Copy / Cut / Paste
  const [clipboard, setClipboard] = useState<ClipboardState | null>(null);

  // Editor Modal
  const [editor, setEditor] = useState<{ name: string; content: string } | null>(null);

  // Modal Dialog state (replacing prompt/confirm/alert)
  const [dialog, setDialog] = useState<DialogState>({ type: null });
  const [dialogInputValue, setDialogInputValue] = useState('');

  const uploadInputRef = useRef<HTMLInputElement>(null);

  // Update storage usage estimate
  const updateStorageEstimate = useCallback(async () => {
    if (navigator.storage && navigator.storage.estimate) {
      try {
        const estimate = await navigator.storage.estimate();
        setStorageInfo({
          used: estimate.usage || 0,
          quota: estimate.quota || 0,
        });
      } catch {}
    }
  }, []);

  // Load entries in current folder or trash
  const loadDirectory = useCallback(async () => {
    setIsLoading(true);
    setErrorMessage('');
    try {
      const list: FileEntry[] = [];

      if (viewMode === 'trash') {
        const trashDir = await getTrashRoot();
        for await (const [name, handle] of (trashDir as any).entries()) {
          if (handle.kind === 'file') {
            const file = await (handle as FileSystemFileHandle).getFile();
            list.push({
              name,
              kind: 'file',
              size: file.size,
              modified: file.lastModified,
            });
          } else {
            list.push({
              name,
              kind: 'directory',
              size: 0,
              modified: 0,
            });
          }
        }
      } else {
        const dir = await getDirAt(currentPath);
        for await (const [name, handle] of (dir as any).entries()) {
          if (name === TRASH_DIR) continue;
          if (handle.kind === 'file') {
            const file = await (handle as FileSystemFileHandle).getFile();
            list.push({
              name,
              kind: 'file',
              size: file.size,
              modified: file.lastModified,
            });
          } else {
            list.push({
              name,
              kind: 'directory',
              size: 0,
              modified: 0,
            });
          }
        }
      }

      setEntries(list);
      setSelectedName(null);
      await updateStorageEstimate();
    } catch (err: any) {
      setErrorMessage('Não foi possível ler o diretório selecionado.');
    } finally {
      setIsLoading(false);
    }
  }, [currentPath, viewMode, updateStorageEstimate]);

  useEffect(() => {
    void loadDirectory();
  }, [loadDirectory]);

  // Filtered & Sorted Entries
  const visibleEntries = useMemo(() => {
    return entries
      .filter((e) => e.name.toLowerCase().includes(searchQuery.toLowerCase()))
      .sort((a, b) => {
        if (a.kind !== b.kind) return a.kind === 'directory' ? -1 : 1;
        if (sortField === 'size') return a.size - b.size;
        if (sortField === 'modified') return b.modified - a.modified;
        return a.name.localeCompare(b.name, 'pt-BR', { numeric: true });
      });
  }, [entries, searchQuery, sortField]);

  // Actions
  const handleOpenEntry = async (entry: FileEntry) => {
    if (viewMode === 'trash') return;
    if (entry.kind === 'directory') {
      setCurrentPath((prev) => [...prev, entry.name]);
      return;
    }
    // File
    try {
      const dir = await getDirAt(currentPath);
      const fileHandle = await dir.getFileHandle(entry.name);
      const file = await fileHandle.getFile();
      const isText =
        file.type.startsWith('text/') ||
        /\.(txt|md|json|js|ts|tsx|jsx|css|html|log|csv|svg|xml|yaml|yml)$/i.test(entry.name);

      if (isText) {
        const textContent = await file.text();
        setEditor({ name: entry.name, content: textContent });
      } else {
        handleDownload(entry.name);
      }
    } catch {
      setErrorMessage('Erro ao abrir o arquivo.');
    }
  };

  const handleSaveEditor = async () => {
    if (!editor) return;
    setIsLoading(true);
    try {
      const dir = await getDirAt(currentPath);
      const fileHandle = await dir.getFileHandle(editor.name, { create: true });
      const writable = await (fileHandle as any).createWritable();
      await writable.write(editor.content);
      await writable.close();
      setEditor(null);
      await loadDirectory();
    } catch {
      setErrorMessage('Falha ao salvar as alterações no arquivo.');
    } finally {
      setIsLoading(false);
    }
  };

  const handleDownload = async (fileName: string) => {
    try {
      const dir = viewMode === 'trash' ? await getTrashRoot() : await getDirAt(currentPath);
      const fileHandle = await dir.getFileHandle(fileName);
      const file = await fileHandle.getFile();
      const url = URL.createObjectURL(file);
      const link = document.createElement('a');
      link.href = url;
      link.download = fileName;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch {
      setErrorMessage('Falha no download do arquivo.');
    }
  };

  const handleUpload = async (files: FileList | null) => {
    if (!files || files.length === 0) return;
    setIsLoading(true);
    setErrorMessage('');
    try {
      const dir = await getDirAt(currentPath);
      for (const file of Array.from(files)) {
        const clean = sanitizeName(file.name);
        if (!clean) continue;
        const uniqueName = await getUniqueName(dir, clean, false);
        const fileHandle = await dir.getFileHandle(uniqueName, { create: true });
        const writable = await (fileHandle as any).createWritable();
        await writable.write(file);
        await writable.close();
      }
      await loadDirectory();
    } catch {
      setErrorMessage('Erro ao enviar arquivos para o armazenamento.');
    } finally {
      setIsLoading(false);
    }
  };

  // Dialog Submission (Create File/Folder, Rename, Delete, Empty Trash)
  const handleDialogConfirm = async () => {
    const { type, entry } = dialog;
    if (!type) return;

    setIsLoading(true);
    setErrorMessage('');

    try {
      if (type === 'create-file') {
        const clean = sanitizeName(dialogInputValue);
        if (!clean) return;
        const dir = await getDirAt(currentPath);
        const uniqueName = await getUniqueName(dir, clean, false);
        const fileHandle = await dir.getFileHandle(uniqueName, { create: true });
        const writable = await (fileHandle as any).createWritable();
        await writable.close();
      } else if (type === 'create-folder') {
        const clean = sanitizeName(dialogInputValue);
        if (!clean) return;
        const dir = await getDirAt(currentPath);
        const uniqueName = await getUniqueName(dir, clean, true);
        await dir.getDirectoryHandle(uniqueName, { create: true });
      } else if (type === 'rename' && entry) {
        const clean = sanitizeName(dialogInputValue);
        if (!clean || clean === entry.name) {
          setDialog({ type: null });
          setIsLoading(false);
          return;
        }
        const dir = await getDirAt(currentPath);
        if (entry.kind === 'file') {
          const oldHandle = await dir.getFileHandle(entry.name);
          const oldFile = await oldHandle.getFile();
          const uniqueName = await getUniqueName(dir, clean, false);
          const newHandle = await dir.getFileHandle(uniqueName, { create: true });
          const writable = await (newHandle as any).createWritable();
          await writable.write(oldFile);
          await writable.close();
          await dir.removeEntry(entry.name);
        } else {
          // Folder rename with recursive copy
          const srcDir = await dir.getDirectoryHandle(entry.name);
          const uniqueName = await getUniqueName(dir, clean, true);
          await copyDirRecursive(srcDir, dir, uniqueName);
          await dir.removeEntry(entry.name, { recursive: true });
        }
      } else if (type === 'confirm-delete' && entry) {
        if (viewMode === 'trash') {
          // Permanent delete
          const trashDir = await getTrashRoot();
          await trashDir.removeEntry(entry.name, { recursive: entry.kind === 'directory' });
        } else {
          // Move to trash
          const dir = await getDirAt(currentPath);
          const trashDir = await getTrashRoot();
          const uniqueTrashName = await getUniqueName(trashDir, entry.name, entry.kind === 'directory');

          if (entry.kind === 'file') {
            const srcHandle = await dir.getFileHandle(entry.name);
            const file = await srcHandle.getFile();
            const trashHandle = await trashDir.getFileHandle(uniqueTrashName, { create: true });
            const writable = await (trashHandle as any).createWritable();
            await writable.write(file);
            await writable.close();
            await dir.removeEntry(entry.name);
          } else {
            const srcDir = await dir.getDirectoryHandle(entry.name);
            await copyDirRecursive(srcDir, trashDir, uniqueTrashName);
            await dir.removeEntry(entry.name, { recursive: true });
          }
        }
      } else if (type === 'confirm-empty-trash') {
        const trashDir = await getTrashRoot();
        for await (const [name, handle] of (trashDir as any).entries()) {
          await trashDir.removeEntry(name, { recursive: handle.kind === 'directory' });
        }
      }

      setDialog({ type: null });
      setDialogInputValue('');
      await loadDirectory();
    } catch (err: any) {
      setErrorMessage(`Erro ao realizar a operação: ${err.message || 'Falha desconhecida'}`);
    } finally {
      setIsLoading(false);
    }
  };

  // Restore from Trash
  const handleRestoreFromTrash = async (entry: FileEntry) => {
    setIsLoading(true);
    setErrorMessage('');
    try {
      const trashDir = await getTrashRoot();
      const rootDir = await getOpfsRoot();
      const uniqueName = await getUniqueName(rootDir, entry.name, entry.kind === 'directory');

      if (entry.kind === 'file') {
        const srcHandle = await trashDir.getFileHandle(entry.name);
        const file = await srcHandle.getFile();
        const destHandle = await rootDir.getFileHandle(uniqueName, { create: true });
        const writable = await (destHandle as any).createWritable();
        await writable.write(file);
        await writable.close();
        await trashDir.removeEntry(entry.name);
      } else {
        const srcDir = await trashDir.getDirectoryHandle(entry.name);
        await copyDirRecursive(srcDir, rootDir, uniqueName);
        await trashDir.removeEntry(entry.name, { recursive: true });
      }

      await loadDirectory();
    } catch {
      setErrorMessage('Falha ao restaurar o item.');
    } finally {
      setIsLoading(false);
    }
  };

  // Clipboard operations
  const handleCut = (entry: FileEntry) => {
    setClipboard({ entry, action: 'cut', sourcePath: [...currentPath] });
  };

  const handleCopy = (entry: FileEntry) => {
    setClipboard({ entry, action: 'copy', sourcePath: [...currentPath] });
  };

  const handlePaste = async () => {
    if (!clipboard) return;
    setIsLoading(true);
    setErrorMessage('');
    try {
      const srcDir = await getDirAt(clipboard.sourcePath);
      const destDir = await getDirAt(currentPath);
      const { entry, action } = clipboard;

      const uniqueName = await getUniqueName(destDir, entry.name, entry.kind === 'directory');

      if (entry.kind === 'file') {
        const srcHandle = await srcDir.getFileHandle(entry.name);
        const file = await srcHandle.getFile();
        const destHandle = await destDir.getFileHandle(uniqueName, { create: true });
        const writable = await (destHandle as any).createWritable();
        await writable.write(file);
        await writable.close();

        if (action === 'cut') {
          await srcDir.removeEntry(entry.name);
          setClipboard(null);
        }
      } else {
        const srcSubDir = await srcDir.getDirectoryHandle(entry.name);
        await copyDirRecursive(srcSubDir, destDir, uniqueName);

        if (action === 'cut') {
          await srcDir.removeEntry(entry.name, { recursive: true });
          setClipboard(null);
        }
      }

      await loadDirectory();
    } catch {
      setErrorMessage('Falha ao colar o item no destino.');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="cf-root">
      {/* Main Toolbar */}
      <header className="cf-toolbar">
        <button
          className="cf-btn"
          onClick={() => setCurrentPath((p) => p.slice(0, -1))}
          disabled={!currentPath.length || viewMode === 'trash'}
          title="Voltar pasta anterior"
        >
          ←
        </button>
        <button className="cf-btn" onClick={() => void loadDirectory()} title="Atualizar">
          ↻
        </button>

        <div className="cf-toolbar-divider" />

        {viewMode === 'files' ? (
          <>
            <button
              className="cf-btn primary-btn"
              onClick={() => {
                setDialogInputValue('Novo Documento.txt');
                setDialog({
                  type: 'create-file',
                  title: 'Criar Novo Arquivo',
                  initialValue: 'Novo Documento.txt',
                });
              }}
            >
              ＋ Arquivo
            </button>
            <button
              className="cf-btn"
              onClick={() => {
                setDialogInputValue('Nova Pasta');
                setDialog({
                  type: 'create-folder',
                  title: 'Criar Nova Pasta',
                  initialValue: 'Nova Pasta',
                });
              }}
            >
              ＋ Pasta
            </button>
            <button className="cf-btn" onClick={() => uploadInputRef.current?.click()}>
              ↑ Enviar
            </button>
            <input
              ref={uploadInputRef}
              hidden
              multiple
              type="file"
              onChange={(e) => void handleUpload(e.target.files)}
            />

            {clipboard && (
              <button className="cf-btn paste-btn" onClick={() => void handlePaste()}>
                📋 Colar ({clipboard.entry.name})
              </button>
            )}

            <button
              className="cf-btn trash-toggle-btn"
              onClick={() => {
                setViewMode('trash');
                setCurrentPath([]);
              }}
              title="Abrir Lixeira"
            >
              🗑️ Lixeira
            </button>
          </>
        ) : (
          <>
            <button
              className="cf-btn primary-btn"
              onClick={() => {
                setViewMode('files');
                setCurrentPath([]);
              }}
            >
              📁 Meus Arquivos
            </button>
            <button
              className="cf-btn danger-btn"
              disabled={entries.length === 0}
              onClick={() =>
                setDialog({
                  type: 'confirm-empty-trash',
                  title: 'Esvaziar Lixeira',
                  message: 'Tem certeza que deseja apagar permanentemente todos os itens da lixeira?',
                })
              }
            >
              🗑️ Esvaziar Lixeira
            </button>
          </>
        )}

        {/* Address Breadcrumbs */}
        <nav className="cf-address" aria-label="Caminho de navegação">
          <button
            className={!currentPath.length && viewMode === 'files' ? 'active-breadcrumb' : ''}
            onClick={() => {
              setViewMode('files');
              setCurrentPath([]);
            }}
          >
            local:
          </button>
          {viewMode === 'trash' ? (
            <button className="active-breadcrumb">/ 🗑️ lixeira</button>
          ) : (
            currentPath.map((part, i) => (
              <button
                key={`${part}-${i}`}
                className={i === currentPath.length - 1 ? 'active-breadcrumb' : ''}
                onClick={() => setCurrentPath(currentPath.slice(0, i + 1))}
              >
                / {part}
              </button>
            ))
          )}
        </nav>

        {/* Search & Sort */}
        <input
          className="cf-search"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          placeholder="Pesquisar..."
          aria-label="Pesquisar arquivos"
        />

        <select
          className="cf-sort-select"
          value={sortField}
          onChange={(e) => setSortField(e.target.value as SortField)}
          aria-label="Ordenar por"
        >
          <option value="name">Nome (A-Z)</option>
          <option value="modified">Modificado</option>
          <option value="size">Tamanho</option>
        </select>
      </header>

      {/* Error Alert Box */}
      {errorMessage && (
        <div className="cf-error" role="alert">
          <span>⚠️ {errorMessage}</span>
          <button onClick={() => setErrorMessage('')}>×</button>
        </div>
      )}

      {/* Content Area */}
      <main className="cf-content">
        {isLoading ? (
          <div className="cf-empty">
            <div className="cf-spinner" />
            <span>Processando armazenamento...</span>
          </div>
        ) : visibleEntries.length ? (
          <div className="cf-grid" role="list">
            {visibleEntries.map((entry) => {
              const isSelected = selectedName === entry.name;
              return (
                <article
                  key={entry.name}
                  className={`cf-item ${isSelected ? 'selected' : ''}`}
                  onClick={() => setSelectedName(entry.name)}
                  onDoubleClick={() => void handleOpenEntry(entry)}
                  role="listitem"
                  tabIndex={0}
                >
                  <div className="cf-icon">{entry.kind === 'directory' ? '📁' : '📄'}</div>
                  <strong className="cf-name" title={entry.name}>
                    {entry.name}
                  </strong>
                  <small className="cf-size">
                    {entry.kind === 'directory' ? 'Pasta' : formatBytes(entry.size)}
                  </small>

                  {/* Actions inside selected card */}
                  <div className="cf-actions">
                    {viewMode === 'files' ? (
                      <>
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            void handleOpenEntry(entry);
                          }}
                        >
                          {entry.kind === 'directory' ? 'Abrir' : 'Editar'}
                        </button>
                        {entry.kind === 'file' && (
                          <button
                            type="button"
                            onClick={(e) => {
                              e.stopPropagation();
                              void handleDownload(entry.name);
                            }}
                          >
                            Baixar
                          </button>
                        )}
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            handleCopy(entry);
                          }}
                        >
                          Copiar
                        </button>
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            handleCut(entry);
                          }}
                        >
                          Recortar
                        </button>
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            setDialogInputValue(entry.name);
                            setDialog({
                              type: 'rename',
                              entry,
                              title: `Renomear ${entry.kind === 'directory' ? 'Pasta' : 'Arquivo'}`,
                              initialValue: entry.name,
                            });
                          }}
                        >
                          Renomear
                        </button>
                        <button
                          type="button"
                          className="danger"
                          onClick={(e) => {
                            e.stopPropagation();
                            setDialog({
                              type: 'confirm-delete',
                              entry,
                              title: 'Mover para a Lixeira',
                              message: `Deseja mover “${entry.name}” para a lixeira?`,
                            });
                          }}
                        >
                          Excluir
                        </button>
                      </>
                    ) : (
                      <>
                        <button
                          type="button"
                          className="primary"
                          onClick={(e) => {
                            e.stopPropagation();
                            void handleRestoreFromTrash(entry);
                          }}
                        >
                          Restaurar
                        </button>
                        <button
                          type="button"
                          className="danger"
                          onClick={(e) => {
                            e.stopPropagation();
                            setDialog({
                              type: 'confirm-delete',
                              entry,
                              title: 'Excluir Permanentemente',
                              message: `Deseja apagar definitivamente “${entry.name}”? Esta ação não pode ser desfeita.`,
                            });
                          }}
                        >
                          Apagar
                        </button>
                      </>
                    )}
                  </div>
                </article>
              );
            })}
          </div>
        ) : (
          <div className="cf-empty">
            <span>{viewMode === 'trash' ? '🗑️' : '☁️'}</span>
            <strong>{viewMode === 'trash' ? 'Lixeira Vazia' : 'Pasta Vazia'}</strong>
            <small>
              {viewMode === 'trash'
                ? 'Nenhum item excluído recentemente.'
                : 'Crie uma pasta ou envie arquivos para começar.'}
            </small>
          </div>
        )}
      </main>

      {/* Footer Status Bar */}
      <footer className="cf-status">
        <span>{visibleEntries.length} item(ns)</span>
        <span>
          {storageInfo
            ? `Armazenamento OPFS: ${formatBytes(storageInfo.used)} usados de ${formatBytes(storageInfo.quota)}`
            : 'Armazenamento OPFS local e persistente'}
        </span>
      </footer>

      {/* Text Editor Modal */}
      {editor && (
        <div className="cf-modal" role="dialog" aria-modal="true" aria-labelledby="editor-title">
          <section className="cf-modal-card">
            <header className="cf-modal-header">
              <strong id="editor-title">📝 {editor.name}</strong>
              <button className="cf-modal-close" onClick={() => setEditor(null)}>
                ✕
              </button>
            </header>
            <textarea
              className="cf-modal-textarea"
              value={editor.content}
              onChange={(e) => setEditor({ ...editor, content: e.target.value })}
              aria-label="Conteúdo do arquivo"
            />
            <footer className="cf-modal-footer">
              <button className="cf-btn" onClick={() => setEditor(null)}>
                Cancelar
              </button>
              <button className="cf-btn primary-btn" onClick={() => void handleSaveEditor()}>
                Salvar Alterações
              </button>
            </footer>
          </section>
        </div>
      )}

      {/* Accessible React Prompt/Confirm Dialogs */}
      {dialog.type && (
        <div className="cf-modal" role="dialog" aria-modal="true" aria-labelledby="dialog-title">
          <div className="cf-dialog-box">
            <h3 id="dialog-title" className="cf-dialog-title">
              {dialog.title}
            </h3>

            {dialog.message && <p className="cf-dialog-message">{dialog.message}</p>}

            {(dialog.type === 'create-file' ||
              dialog.type === 'create-folder' ||
              dialog.type === 'rename') && (
              <div className="cf-dialog-input-wrapper">
                <input
                  type="text"
                  autoFocus
                  className="cf-dialog-input"
                  value={dialogInputValue}
                  onChange={(e) => setDialogInputValue(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') void handleDialogConfirm();
                    if (e.key === 'Escape') setDialog({ type: null });
                  }}
                  placeholder="Digite o nome..."
                />
              </div>
            )}

            <div className="cf-dialog-actions">
              <button
                type="button"
                className="cf-btn"
                onClick={() => {
                  setDialog({ type: null });
                  setDialogInputValue('');
                }}
              >
                Cancelar
              </button>
              <button
                type="button"
                className={`cf-btn ${
                  dialog.type.includes('delete') || dialog.type.includes('empty')
                    ? 'danger-btn'
                    : 'primary-btn'
                }`}
                onClick={() => void handleDialogConfirm()}
              >
                Confirmar
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
