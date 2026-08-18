import { appendFilePath, normalizeFilePath } from './fileSourcePolicy';

export type WindowsFileEntry = {
  name: string;
  kind: 'file' | 'directory';
  size: number;
  modified: number;
  source: 'windows';
  trashId?: string;
  originalPath?: string[];
  originalName?: string;
  deletedAt?: number;
};

export type CopyProgress = { copiedBytes: number; totalBytes: number; entriesDone: number; totalEntries: number; current: string };

type TrashMeta = {
  version: 1;
  entries: Record<string, { id: string; storedName: string; originalPath: string[]; originalName: string; kind: 'file' | 'directory'; deletedAt: number }>;
};

const TRASH_DIR = '.cloudos-trash';
const TRASH_META = '.cloudos-trash-meta.json';
let mountedRoot: FileSystemDirectoryHandle | null = null;
let mountedLabel = '';

function picker() {
  return (window as unknown as { showDirectoryPicker?: (options?: { mode?: 'read' | 'readwrite'; id?: string }) => Promise<FileSystemDirectoryHandle> }).showDirectoryPicker;
}

function entriesOf(dir: FileSystemDirectoryHandle): AsyncIterable<[string, FileSystemHandle]> {
  return (dir as unknown as { entries(): AsyncIterable<[string, FileSystemHandle]> }).entries();
}

function assertMounted() {
  if (!mountedRoot) throw new Error('Selecione uma pasta do Windows primeiro.');
  return mountedRoot;
}

function assertNotReserved(path: string[]) {
  if (path[0] === TRASH_DIR) throw new Error('Caminho reservado pelo CloudOS Files.');
}

async function dirAt(path: string[], create = false, internal = false) {
  const safe = normalizeFilePath(path);
  if (!internal) assertNotReserved(safe);
  let current = assertMounted();
  for (const segment of safe) current = await current.getDirectoryHandle(segment, { create });
  return current;
}

async function exists(dir: FileSystemDirectoryHandle, name: string) {
  try { await dir.getFileHandle(name); return true; } catch {}
  try { await dir.getDirectoryHandle(name); return true; } catch {}
  return false;
}

async function uniqueName(dir: FileSystemDirectoryHandle, requested: string, directory: boolean) {
  const safe = normalizeFilePath([requested])[0];
  if (!(await exists(dir, safe))) return safe;
  const match = safe.match(/^(.*?)(\.[^.]*)?$/);
  const stem = match?.[1] || safe;
  const ext = !directory && match?.[2] ? match[2] : '';
  for (let index = 1; index < 10000; index += 1) {
    const candidate = directory ? `${safe} (${index})` : `${stem} (${index})${ext}`;
    if (!(await exists(dir, candidate))) return candidate;
  }
  throw new Error('Não foi possível gerar um nome de destino livre.');
}

async function readTrashMeta(): Promise<TrashMeta> {
  const trash = await dirAt([TRASH_DIR], true, true);
  let handle: FileSystemFileHandle;
  try {
    handle = await trash.getFileHandle(TRASH_META);
  } catch (error) {
    if (error instanceof DOMException && error.name === 'NotFoundError') return { version: 1, entries: {} };
    throw error;
  }
  try {
    const file = await handle.getFile();
    const parsed = JSON.parse(await file.text());
    if (parsed?.version !== 1 || !parsed.entries || typeof parsed.entries !== 'object' || Array.isArray(parsed.entries)) {
      throw new Error('Metadados da lixeira Windows estão inválidos.');
    }
    return parsed as TrashMeta;
  } catch (error) {
    if (error instanceof Error && error.message === 'Metadados da lixeira Windows estão inválidos.') throw error;
    throw new Error('Metadados da lixeira Windows estão corrompidos; nenhuma operação destrutiva foi executada.', { cause: error });
  }
}

async function writeTrashMeta(meta: TrashMeta) {
  const trash = await dirAt([TRASH_DIR], true, true);
  const handle = await trash.getFileHandle(TRASH_META, { create: true });
  const writable = await handle.createWritable();
  try {
    await writable.write(JSON.stringify(meta));
    await writable.close();
  } catch (error) {
    try { await writable.abort(); } catch {}
    throw error;
  }
}

async function statEntry(dir: FileSystemDirectoryHandle, name: string, handle: FileSystemHandle): Promise<WindowsFileEntry> {
  if (handle.kind === 'directory') return { name, kind: 'directory', size: 0, modified: 0, source: 'windows' };
  const file = await (handle as FileSystemFileHandle).getFile();
  return { name, kind: 'file', size: file.size, modified: file.lastModified, source: 'windows' };
}

async function scan(handle: FileSystemHandle, signal: AbortSignal, counter: { bytes: number; entries: number }) {
  if (signal.aborted) throw new DOMException('Operação cancelada.', 'AbortError');
  counter.entries += 1;
  if (handle.kind === 'file') {
    const file = await (handle as FileSystemFileHandle).getFile();
    counter.bytes += file.size;
    return;
  }
  for await (const [, child] of entriesOf(handle as FileSystemDirectoryHandle)) await scan(child, signal, counter);
}

async function copyHandle(
  source: FileSystemHandle,
  destinationParent: FileSystemDirectoryHandle,
  destinationName: string,
  signal: AbortSignal,
  totals: { bytes: number; entries: number },
  progress: { bytes: number; entries: number },
  onProgress?: (value: CopyProgress) => void,
) {
  if (signal.aborted) throw new DOMException('Operação cancelada.', 'AbortError');
  if (source.kind === 'file') {
    const file = await (source as FileSystemFileHandle).getFile();
    const target = await destinationParent.getFileHandle(destinationName, { create: true });
    const writable = await target.createWritable();
    try {
      const reader = file.stream().getReader();
      let offset = 0;
      while (true) {
        if (signal.aborted) throw new DOMException('Operação cancelada.', 'AbortError');
        const { done, value } = await reader.read();
        if (done) break;
        await writable.write({ type: 'write', position: offset, data: value });
        offset += value.byteLength;
        progress.bytes += value.byteLength;
        onProgress?.({ copiedBytes: progress.bytes, totalBytes: totals.bytes, entriesDone: progress.entries, totalEntries: totals.entries, current: destinationName });
      }
      await writable.close();
      progress.entries += 1;
      onProgress?.({ copiedBytes: progress.bytes, totalBytes: totals.bytes, entriesDone: progress.entries, totalEntries: totals.entries, current: destinationName });
      return;
    } catch (error) {
      try { await writable.abort(); } catch {}
      try { await destinationParent.removeEntry(destinationName); } catch {}
      throw error;
    }
  }

  const targetDir = await destinationParent.getDirectoryHandle(destinationName, { create: true });
  try {
    for await (const [name, child] of entriesOf(source as FileSystemDirectoryHandle)) {
      await copyHandle(child, targetDir, name, signal, totals, progress, onProgress);
    }
    progress.entries += 1;
    onProgress?.({ copiedBytes: progress.bytes, totalBytes: totals.bytes, entriesDone: progress.entries, totalEntries: totals.entries, current: destinationName });
  } catch (error) {
    try { await destinationParent.removeEntry(destinationName, { recursive: true }); } catch {}
    throw error;
  }
}

async function getHandle(path: string[], name: string): Promise<FileSystemHandle> {
  const dir = await dirAt(path);
  try { return await dir.getFileHandle(name); } catch {}
  return await dir.getDirectoryHandle(name);
}

export const windowsDirectorySource = {
  supported: () => typeof picker() === 'function',
  mounted: () => Boolean(mountedRoot),
  label: () => mountedLabel || 'Pasta do Windows',

  async mount() {
    const show = picker();
    if (!show) throw new Error('Este WebView/navegador não oferece acesso explícito a pastas do Windows.');
    const handle = await show({ mode: 'readwrite', id: 'cloudos-files-windows' });
    const permissionApi = handle as unknown as { requestPermission?: (options: { mode: 'readwrite' }) => Promise<PermissionState> };
    if (permissionApi.requestPermission) {
      const permission = await permissionApi.requestPermission({ mode: 'readwrite' });
      if (permission !== 'granted') throw new Error('A pasta não recebeu permissão de leitura e gravação.');
    }
    mountedRoot = handle;
    mountedLabel = handle.name || 'Pasta do Windows';
    return { label: mountedLabel };
  },

  unmount() {
    mountedRoot = null;
    mountedLabel = '';
  },

  async list(path: string[]): Promise<WindowsFileEntry[]> {
    const dir = await dirAt(path);
    const output: WindowsFileEntry[] = [];
    for await (const [name, handle] of entriesOf(dir)) {
      if (path.length === 0 && name === TRASH_DIR) continue;
      output.push(await statEntry(dir, name, handle));
    }
    return output;
  },

  async readFile(path: string[], name: string) {
    const dir = await dirAt(path);
    return (await dir.getFileHandle(normalizeFilePath([name])[0])).getFile();
  },

  async writeText(path: string[], name: string, content: string) {
    const dir = await dirAt(path);
    const handle = await dir.getFileHandle(normalizeFilePath([name])[0], { create: true });
    const writable = await handle.createWritable();
    await writable.write(content);
    await writable.close();
  },

  async writeFile(path: string[], file: File) {
    const dir = await dirAt(path);
    const name = await uniqueName(dir, file.name, false);
    const handle = await dir.getFileHandle(name, { create: true });
    const writable = await handle.createWritable();
    try {
      await writable.write(file);
      await writable.close();
      return name;
    } catch (error) {
      try { await writable.abort(); } catch {}
      try { await dir.removeEntry(name); } catch {}
      throw error;
    }
  },

  async create(path: string[], kind: 'file' | 'directory', requestedName: string) {
    const dir = await dirAt(path);
    const name = await uniqueName(dir, requestedName, kind === 'directory');
    if (kind === 'directory') await dir.getDirectoryHandle(name, { create: true });
    else {
      const handle = await dir.getFileHandle(name, { create: true });
      const writable = await handle.createWritable();
      await writable.close();
    }
    return name;
  },

  async copy(path: string[], name: string, destinationPath: string[], requestedName: string, signal: AbortSignal, onProgress?: (value: CopyProgress) => void) {
    const source = await getHandle(path, normalizeFilePath([name])[0]);
    const destination = await dirAt(destinationPath);
    const destinationName = await uniqueName(destination, requestedName, source.kind === 'directory');
    const totals = { bytes: 0, entries: 0 };
    await scan(source, signal, totals);
    const progress = { bytes: 0, entries: 0 };
    await copyHandle(source, destination, destinationName, signal, totals, progress, onProgress);
    return { name: destinationName, copiedBytes: progress.bytes, totalBytes: totals.bytes };
  },

  async move(path: string[], name: string, destinationPath: string[], requestedName: string, signal: AbortSignal, onProgress?: (value: CopyProgress) => void) {
    const sourceDir = await dirAt(path);
    const source = await getHandle(path, name);
    const result = await this.copy(path, name, destinationPath, requestedName, signal, onProgress);
    if (signal.aborted) {
      const destination = await dirAt(destinationPath);
      try { await destination.removeEntry(result.name, { recursive: source.kind === 'directory' }); } catch {}
      throw new DOMException('Operação cancelada.', 'AbortError');
    }
    try {
      await sourceDir.removeEntry(name, { recursive: source.kind === 'directory' });
      return result;
    } catch (error) {
      const destination = await dirAt(destinationPath);
      try { await destination.removeEntry(result.name, { recursive: source.kind === 'directory' }); } catch {}
      throw error;
    }
  },

  async rename(path: string[], name: string, requestedName: string) {
    const controller = new AbortController();
    const result = await this.move(path, name, path, requestedName, controller.signal);
    return result.name;
  },

  async trash(path: string[], entry: WindowsFileEntry) {
    const trash = await dirAt([TRASH_DIR], true, true);
    const id = crypto.randomUUID().replaceAll('-', '');
    const storedName = `${id}-item`;
    const source = await getHandle(path, entry.name);
    const totals = { bytes: 0, entries: 0 };
    const controller = new AbortController();
    await scan(source, controller.signal, totals);
    await copyHandle(source, trash, storedName, controller.signal, totals, { bytes: 0, entries: 0 });

    const meta = await readTrashMeta();
    meta.entries[id] = { id, storedName, originalPath: appendFilePath(path, entry.name), originalName: entry.name, kind: entry.kind, deletedAt: Date.now() };
    try {
      await writeTrashMeta(meta);
    } catch (error) {
      try { await trash.removeEntry(storedName, { recursive: source.kind === 'directory' }); } catch {}
      throw error;
    }

    const sourceDir = await dirAt(path);
    try {
      await sourceDir.removeEntry(entry.name, { recursive: source.kind === 'directory' });
    } catch (error) {
      delete meta.entries[id];
      try { await writeTrashMeta(meta); } catch {}
      try { await trash.removeEntry(storedName, { recursive: source.kind === 'directory' }); } catch {}
      throw error;
    }
    return id;
  },

  async listTrash(): Promise<WindowsFileEntry[]> {
    const trash = await dirAt([TRASH_DIR], true, true);
    const meta = await readTrashMeta();
    const output: WindowsFileEntry[] = [];
    for (const item of Object.values(meta.entries)) {
      try {
        const handle = item.kind === 'directory' ? await trash.getDirectoryHandle(item.storedName) : await trash.getFileHandle(item.storedName);
        const entry = await statEntry(trash, item.storedName, handle);
        output.push({ ...entry, trashId: item.id, originalPath: item.originalPath, originalName: item.originalName, deletedAt: item.deletedAt });
      } catch {}
    }
    return output.sort((a, b) => (b.deletedAt || 0) - (a.deletedAt || 0));
  },

  async restore(entry: WindowsFileEntry) {
    if (!entry.trashId || !entry.originalName) throw new Error('Metadados da lixeira inválidos.');
    const meta = await readTrashMeta();
    const item = meta.entries[entry.trashId];
    if (!item) throw new Error('Item não encontrado na lixeira.');
    const trash = await dirAt([TRASH_DIR], true, true);
    const parentPath = item.originalPath.slice(0, -1);
    let destination: FileSystemDirectoryHandle;
    try { destination = await dirAt(parentPath); } catch { destination = assertMounted(); }
    const source = item.kind === 'directory' ? await trash.getDirectoryHandle(item.storedName) : await trash.getFileHandle(item.storedName);
    const name = await uniqueName(destination, item.originalName, item.kind === 'directory');
    const controller = new AbortController();
    const totals = { bytes: 0, entries: 0 };
    await scan(source, controller.signal, totals);
    await copyHandle(source, destination, name, controller.signal, totals, { bytes: 0, entries: 0 });
    await trash.removeEntry(item.storedName, { recursive: item.kind === 'directory' });
    delete meta.entries[item.id];
    await writeTrashMeta(meta);
    return name;
  },

  async deleteTrash(entry: WindowsFileEntry) {
    if (!entry.trashId) throw new Error('Metadados da lixeira inválidos.');
    const meta = await readTrashMeta();
    const item = meta.entries[entry.trashId];
    if (!item) return;
    const trash = await dirAt([TRASH_DIR], true, true);
    await trash.removeEntry(item.storedName, { recursive: item.kind === 'directory' });
    delete meta.entries[item.id];
    await writeTrashMeta(meta);
  },

  async emptyTrash() {
    const trash = await dirAt([TRASH_DIR], true, true);
    const meta = await readTrashMeta();
    for (const item of Object.values(meta.entries)) {
      try { await trash.removeEntry(item.storedName, { recursive: item.kind === 'directory' }); } catch {}
    }
    await writeTrashMeta({ version: 1, entries: {} });
  },
};