import {
  createEntry as opfsCreate,
  emptyTrash as opfsEmptyTrash,
  listDirectory as opfsList,
  listTrash as opfsListTrash,
  moveToTrash as opfsTrash,
  pasteEntry as opfsPaste,
  permanentlyDelete as opfsDeleteTrash,
  readFile as opfsRead,
  renameEntry as opfsRename,
  restoreFromTrash as opfsRestore,
  storageEstimate,
  uploadFiles as opfsUpload,
  writeTextFile as opfsWriteText,
  type FileEntry as OpfsFileEntry,
  type StorageInfo,
} from './opfsFileService';
import { type FileSourceKind, normalizeFilePath } from './fileSourcePolicy';
import { windowsDirectorySource, type CopyProgress, type WindowsFileEntry } from './windowsDirectorySource';
import { wslFileSource, type FileOperation, type WslFileEntry, type WslFilesStatus } from './wslFileSource';

export type CloudFileEntry = {
  name: string;
  kind: 'file' | 'directory' | 'symlink';
  size: number;
  modified: number;
  source: FileSourceKind;
  originalName?: string;
  originalPath?: string[];
  deletedAt?: number;
  trashId?: string;
  mode?: number;
  uid?: number;
  gid?: number;
  symlink?: boolean;
};

export type CloudClipboardEntry = {
  entry: CloudFileEntry;
  action: 'copy' | 'cut';
  source: FileSourceKind;
  sourcePath: string[];
};

export type SourceRuntime = {
  source: FileSourceKind;
  label: string;
  mounted: boolean;
  available: boolean;
  detail: string;
};

export type PasteResult = {
  name: string;
  moved: boolean;
  operation?: FileOperation;
};

function fromOpfs(entry: OpfsFileEntry): CloudFileEntry {
  return { ...entry, kind: entry.kind, source: 'opfs' };
}

function fromWindows(entry: WindowsFileEntry): CloudFileEntry {
  return { ...entry, source: 'windows' };
}

function fromWsl(entry: WslFileEntry): CloudFileEntry {
  return { ...entry, source: 'wsl' };
}

function toOpfs(entry: CloudFileEntry): OpfsFileEntry {
  if (entry.kind === 'symlink') throw new Error('Link simbólico não existe no OPFS.');
  return {
    name: entry.name,
    kind: entry.kind,
    size: entry.size,
    modified: entry.modified,
    originalName: entry.originalName,
    originalPath: entry.originalPath,
    deletedAt: entry.deletedAt,
  };
}

export const fileSourceFacade = {
  async runtime(source: FileSourceKind): Promise<SourceRuntime> {
    if (source === 'opfs') return { source, label: 'CloudOS local', mounted: true, available: true, detail: 'Origin Private File System' };
    if (source === 'windows') {
      const mounted = windowsDirectorySource.mounted();
      return {
        source,
        label: mounted ? windowsDirectorySource.label() : 'Windows',
        mounted,
        available: windowsDirectorySource.supported(),
        detail: mounted ? 'Pasta explicitamente selecionada' : 'Selecione uma pasta para conceder acesso',
      };
    }
    try {
      const status: WslFilesStatus = await wslFileSource.status();
      return {
        source,
        label: status.distribution || 'Linux Home',
        mounted: status.available,
        available: status.available,
        detail: status.available ? `${status.mode} · ${status.protection}` : (status.reason || 'Linux Files indisponível'),
      };
    } catch (error) {
      return { source, label: 'Linux Home', mounted: false, available: false, detail: error instanceof Error ? error.message : 'Linux Files indisponível' };
    }
  },

  mountWindows: () => windowsDirectorySource.mount(),
  unmountWindows: () => windowsDirectorySource.unmount(),

  async list(source: FileSourceKind, path: string[], trash = false): Promise<CloudFileEntry[]> {
    const safe = normalizeFilePath(path);
    if (source === 'opfs') return (trash ? await opfsListTrash() : await opfsList(safe)).map(fromOpfs);
    if (source === 'windows') return (trash ? await windowsDirectorySource.listTrash() : await windowsDirectorySource.list(safe)).map(fromWindows);
    return (trash ? await wslFileSource.listTrash() : await wslFileSource.list(safe)).map(fromWsl);
  },

  async storage(source: FileSourceKind): Promise<StorageInfo | null> {
    return source === 'opfs' ? storageEstimate() : null;
  },

  async readFile(source: FileSourceKind, path: string[], entry: CloudFileEntry, maximumBytes: number): Promise<File> {
    if (entry.kind !== 'file' || entry.symlink) throw new Error('Este item não pode ser aberto como arquivo.');
    if (entry.size > maximumBytes) throw new Error(`Arquivo excede o limite permitido de ${maximumBytes} bytes.`);
    if (source === 'opfs') return opfsRead(path, entry.name, false);
    if (source === 'windows') return windowsDirectorySource.readFile(path, entry.name);
    return wslFileSource.readFile(path, entry.name, maximumBytes);
  },

  async create(source: FileSourceKind, path: string[], kind: 'file' | 'directory', name: string) {
    if (source === 'opfs') return opfsCreate(path, kind, name);
    if (source === 'windows') return windowsDirectorySource.create(path, kind, name);
    if (kind === 'directory') return wslFileSource.mkdir(path, name);
    return wslFileSource.writeText(path, name, '');
  },

  async writeText(source: FileSourceKind, path: string[], name: string, content: string, mode?: number) {
    if (source === 'opfs') return opfsWriteText(path, name, content);
    if (source === 'windows') return windowsDirectorySource.writeText(path, name, content);
    return wslFileSource.writeText(path, name, content, mode || 0o600);
  },

  async rename(source: FileSourceKind, path: string[], entry: CloudFileEntry, newName: string) {
    if (entry.symlink || entry.kind === 'symlink') throw new Error('Link simbólico não pode ser renomeado pelo CloudOS Files.');
    if (source === 'opfs') return opfsRename(path, toOpfs(entry), newName);
    if (source === 'windows') return windowsDirectorySource.rename(path, entry.name, newName);
    return wslFileSource.move(path, entry.name, path, newName);
  },

  async trash(source: FileSourceKind, path: string[], entry: CloudFileEntry) {
    if (entry.symlink || entry.kind === 'symlink') throw new Error('Link simbólico não entra na lixeira transacional.');
    if (source === 'opfs') return opfsTrash(path, toOpfs(entry));
    if (source === 'windows') return windowsDirectorySource.trash(path, entry as WindowsFileEntry);
    return wslFileSource.trash(path, entry.name);
  },

  async restore(source: FileSourceKind, entry: CloudFileEntry) {
    if (source === 'opfs') return opfsRestore(toOpfs(entry));
    if (source === 'windows') return windowsDirectorySource.restore(entry as WindowsFileEntry);
    if (!entry.trashId) throw new Error('Identificador da lixeira Linux ausente.');
    return wslFileSource.restoreTrash(entry.trashId);
  },

  async deleteTrash(source: FileSourceKind, entry: CloudFileEntry) {
    if (source === 'opfs') return opfsDeleteTrash(toOpfs(entry));
    if (source === 'windows') return windowsDirectorySource.deleteTrash(entry as WindowsFileEntry);
    if (!entry.trashId) throw new Error('Identificador da lixeira Linux ausente.');
    return wslFileSource.deleteTrash(entry.trashId);
  },

  async emptyTrash(source: FileSourceKind) {
    if (source === 'opfs') return opfsEmptyTrash();
    if (source === 'windows') return windowsDirectorySource.emptyTrash();
    const entries = await wslFileSource.listTrash();
    for (const entry of entries) if (entry.trashId) await wslFileSource.deleteTrash(entry.trashId);
  },

  async upload(source: FileSourceKind, path: string[], files: File[]) {
    if (source !== 'opfs') throw new Error('Envio direto ainda é restrito ao CloudOS local; use copiar/colar dentro da origem real.');
    return opfsUpload(path, files);
  },

  async paste(
    source: FileSourceKind,
    clipboard: CloudClipboardEntry,
    destinationPath: string[],
    options: { signal: AbortSignal; onProgress?: (value: CopyProgress) => void },
  ): Promise<PasteResult> {
    if (clipboard.source !== source) throw new Error('Transferência entre origens será habilitada somente após o gate transacional entre providers.');
    if (clipboard.entry.symlink || clipboard.entry.kind === 'symlink') throw new Error('Link simbólico não pode ser copiado pelo CloudOS Files.');

    if (source === 'opfs') {
      const result = await opfsPaste({ entry: toOpfs(clipboard.entry), action: clipboard.action, sourcePath: clipboard.sourcePath }, destinationPath);
      return { name: result.name, moved: result.moved };
    }

    if (source === 'windows') {
      const provider = windowsDirectorySource;
      const result = clipboard.action === 'cut'
        ? await provider.move(clipboard.sourcePath, clipboard.entry.name, destinationPath, clipboard.entry.name, options.signal, options.onProgress)
        : await provider.copy(clipboard.sourcePath, clipboard.entry.name, destinationPath, clipboard.entry.name, options.signal, options.onProgress);
      return { name: result.name, moved: clipboard.action === 'cut' };
    }

    if (clipboard.action === 'cut') {
      await wslFileSource.move(clipboard.sourcePath, clipboard.entry.name, destinationPath, clipboard.entry.name);
      return { name: clipboard.entry.name, moved: true };
    }
    const operation = await wslFileSource.copy(clipboard.sourcePath, clipboard.entry.name, destinationPath, clipboard.entry.name);
    return { name: clipboard.entry.name, moved: false, operation };
  },

  getWslOperation: (id: string) => wslFileSource.getOperation(id),
  cancelWslOperation: (id: string) => wslFileSource.cancelOperation(id),
};
