import { validatePastePath } from '../../core/fileOperationPolicy.js';

export type FileEntry = {
  name: string;
  kind: 'file' | 'directory';
  size: number;
  modified: number;
  originalPath?: string[];
  originalName?: string;
  deletedAt?: number;
};

export type ClipboardEntry = {
  entry: FileEntry;
  action: 'copy' | 'cut';
  sourcePath: string[];
};

export type StorageInfo = { used: number; quota: number };

type TrashMetadataEntry = {
  originalPath: string[];
  originalName: string;
  deletedAt: number;
  kind: FileEntry['kind'];
};

type TrashMetadata = { version: 1; entries: Record<string, TrashMetadataEntry> };

const ROOT_DIR = 'cloudos_files';
const TRASH_DIR = '.trash';
const TRASH_META = '.cloudos-trash-meta.json';

function cleanPath(path: string[]) {
  return path.map(part => sanitizeName(part)).filter(Boolean).slice(0, 64);
}

export function sanitizeName(name: string): string {
  return name.trim().replace(/[\\/:*?"<>|\u0000-\u001f]/g, '-').replace(/\.+$/g, '').slice(0, 120);
}

export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return '0 B';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1073741824) return `${(bytes / 1048576).toFixed(1)} MB`;
  return `${(bytes / 1073741824).toFixed(1)} GB`;
}

async function storageRoot() {
  return navigator.storage.getDirectory();
}

export async function getOpfsRoot(): Promise<FileSystemDirectoryHandle> {
  const root = await (await storageRoot()).getDirectoryHandle(ROOT_DIR, { create: true });
  const defaultFolders = ['Downloads', 'Documents', 'Desktop', 'Pictures', 'Videos', 'Projects', 'Workspace'];
  for (const folder of defaultFolders) {
    try { await root.getDirectoryHandle(folder, { create: true }); } catch {}
  }
  return root;
}

export async function getTrashRoot(): Promise<FileSystemDirectoryHandle> {
  return (await storageRoot()).getDirectoryHandle(TRASH_DIR, { create: true });
}

export async function getDirAt(pathParts: string[], create = false): Promise<FileSystemDirectoryHandle> {
  let dir = await getOpfsRoot();
  for (const part of cleanPath(pathParts)) dir = await dir.getDirectoryHandle(part, { create });
  return dir;
}

async function readTrashMetadata(): Promise<TrashMetadata> {
  try {
    const trash = await getTrashRoot();
    const handle = await trash.getFileHandle(TRASH_META);
    const file = await handle.getFile();
    const parsed = JSON.parse(await file.text()) as Partial<TrashMetadata>;
    const entries: Record<string, TrashMetadataEntry> = {};
    if (parsed.entries && typeof parsed.entries === 'object') {
      for (const [trashName, raw] of Object.entries(parsed.entries)) {
        if (!raw || typeof raw !== 'object') continue;
        const source = raw as Partial<TrashMetadataEntry>;
        const originalName = sanitizeName(String(source.originalName ?? ''));
        if (!originalName) continue;
        entries[trashName] = {
          originalPath: Array.isArray(source.originalPath) ? cleanPath(source.originalPath.map(String)) : [],
          originalName,
          deletedAt: Number.isFinite(source.deletedAt) ? Number(source.deletedAt) : 0,
          kind: source.kind === 'directory' ? 'directory' : 'file',
        };
      }
    }
    return { version: 1, entries };
  } catch {
    return { version: 1, entries: {} };
  }
}

async function writeTrashMetadata(metadata: TrashMetadata) {
  const trash = await getTrashRoot();
  const handle = await trash.getFileHandle(TRASH_META, { create: true });
  const writable = await (handle as any).createWritable();
  await writable.write(JSON.stringify(metadata));
  await writable.close();
}

async function copyDirectory(source: FileSystemDirectoryHandle, destinationParent: FileSystemDirectoryHandle, destinationName: string): Promise<void> {
  const destination = await destinationParent.getDirectoryHandle(destinationName, { create: true });
  for await (const [name, handle] of (source as any).entries()) {
    if (handle.kind === 'file') {
      const file = await (handle as FileSystemFileHandle).getFile();
      const target = await destination.getFileHandle(name, { create: true });
      const writable = await (target as any).createWritable();
      await writable.write(file);
      await writable.close();
    } else if (handle.kind === 'directory') {
      await copyDirectory(handle as FileSystemDirectoryHandle, destination, name);
    }
  }
}

export async function getUniqueName(dir: FileSystemDirectoryHandle, baseName: string, isDirectory: boolean) {
  const safeBase = sanitizeName(baseName);
  if (!safeBase) throw new Error('Nome inválido.');
  let candidate = safeBase;
  let counter = 1;
  const match = safeBase.match(/^(.*?)(\.[^.]*)?$/);
  const stem = match?.[1] || safeBase;
  const extension = !isDirectory && match?.[2] ? match[2] : '';

  while (true) {
    try {
      if (isDirectory) await dir.getDirectoryHandle(candidate);
      else await dir.getFileHandle(candidate);
      candidate = isDirectory ? `${safeBase} (${counter++})` : `${stem} (${counter++})${extension}`;
    } catch {
      return candidate;
    }
  }
}

export async function listDirectory(path: string[]): Promise<FileEntry[]> {
  const dir = await getDirAt(path);
  const list: FileEntry[] = [];
  for await (const [name, handle] of (dir as any).entries()) {
    if (handle.kind === 'file') {
      const file = await (handle as FileSystemFileHandle).getFile();
      list.push({ name, kind: 'file', size: file.size, modified: file.lastModified });
    } else if (handle.kind === 'directory') {
      list.push({ name, kind: 'directory', size: 0, modified: 0 });
    }
  }
  return list;
}

export async function listTrash(): Promise<FileEntry[]> {
  const trash = await getTrashRoot();
  const metadata = await readTrashMetadata();
  const list: FileEntry[] = [];
  for await (const [name, handle] of (trash as any).entries()) {
    if (name === TRASH_META) continue;
    const meta = metadata.entries[name];
    if (handle.kind === 'file') {
      const file = await (handle as FileSystemFileHandle).getFile();
      list.push({ name, kind: 'file', size: file.size, modified: file.lastModified, originalPath: meta?.originalPath, originalName: meta?.originalName, deletedAt: meta?.deletedAt });
    } else {
      list.push({ name, kind: 'directory', size: 0, modified: meta?.deletedAt ?? 0, originalPath: meta?.originalPath, originalName: meta?.originalName, deletedAt: meta?.deletedAt });
    }
  }
  return list;
}

export async function storageEstimate(): Promise<StorageInfo | null> {
  try {
    const estimate = await navigator.storage.estimate();
    return { used: estimate.usage ?? 0, quota: estimate.quota ?? 0 };
  } catch {
    return null;
  }
}

export async function readFile(path: string[], name: string, fromTrash = false) {
  const dir = fromTrash ? await getTrashRoot() : await getDirAt(path);
  return (await dir.getFileHandle(name)).getFile();
}

export async function writeTextFile(path: string[], name: string, content: string) {
  const dir = await getDirAt(path);
  const handle = await dir.getFileHandle(sanitizeName(name), { create: true });
  const writable = await (handle as any).createWritable();
  await writable.write(content);
  await writable.close();
}

export async function createEntry(path: string[], kind: FileEntry['kind'], requestedName: string) {
  const dir = await getDirAt(path);
  const name = await getUniqueName(dir, requestedName, kind === 'directory');
  if (kind === 'directory') await dir.getDirectoryHandle(name, { create: true });
  else {
    const handle = await dir.getFileHandle(name, { create: true });
    const writable = await (handle as any).createWritable();
    await writable.close();
  }
  return name;
}

export async function uploadFiles(path: string[], files: File[]) {
  const dir = await getDirAt(path);
  for (const file of files) {
    const safe = sanitizeName(file.name);
    if (!safe) continue;
    const name = await getUniqueName(dir, safe, false);
    const handle = await dir.getFileHandle(name, { create: true });
    const writable = await (handle as any).createWritable();
    await writable.write(file);
    await writable.close();
  }
}

export async function renameEntry(path: string[], entry: FileEntry, requestedName: string) {
  const dir = await getDirAt(path);
  const safe = sanitizeName(requestedName);
  if (!safe || safe === entry.name) return entry.name;
  const unique = await getUniqueName(dir, safe, entry.kind === 'directory');
  if (entry.kind === 'file') {
    const file = await (await dir.getFileHandle(entry.name)).getFile();
    const target = await dir.getFileHandle(unique, { create: true });
    const writable = await (target as any).createWritable();
    await writable.write(file);
    await writable.close();
    await dir.removeEntry(entry.name);
  } else {
    const source = await dir.getDirectoryHandle(entry.name);
    await copyDirectory(source, dir, unique);
    await dir.removeEntry(entry.name, { recursive: true });
  }
  return unique;
}

export async function moveToTrash(path: string[], entry: FileEntry) {
  const source = await getDirAt(path);
  const trash = await getTrashRoot();
  const trashName = await getUniqueName(trash, entry.name, entry.kind === 'directory');

  if (entry.kind === 'file') {
    const file = await (await source.getFileHandle(entry.name)).getFile();
    const target = await trash.getFileHandle(trashName, { create: true });
    const writable = await (target as any).createWritable();
    await writable.write(file);
    await writable.close();
    await source.removeEntry(entry.name);
  } else {
    const sourceDir = await source.getDirectoryHandle(entry.name);
    await copyDirectory(sourceDir, trash, trashName);
    await source.removeEntry(entry.name, { recursive: true });
  }

  const metadata = await readTrashMetadata();
  metadata.entries[trashName] = { originalPath: cleanPath(path), originalName: entry.name, deletedAt: Date.now(), kind: entry.kind };
  await writeTrashMetadata(metadata);
}

export async function restoreFromTrash(entry: FileEntry) {
  const trash = await getTrashRoot();
  const metadata = await readTrashMetadata();
  const meta = metadata.entries[entry.name];
  let destination: FileSystemDirectoryHandle;
  try {
    destination = await getDirAt(meta?.originalPath ?? entry.originalPath ?? [], false);
  } catch {
    destination = await getOpfsRoot();
  }

  const preferredName = meta?.originalName || entry.originalName || entry.name;
  const restoredName = await getUniqueName(destination, preferredName, entry.kind === 'directory');
  if (entry.kind === 'file') {
    const file = await (await trash.getFileHandle(entry.name)).getFile();
    const target = await destination.getFileHandle(restoredName, { create: true });
    const writable = await (target as any).createWritable();
    await writable.write(file);
    await writable.close();
    await trash.removeEntry(entry.name);
  } else {
    const source = await trash.getDirectoryHandle(entry.name);
    await copyDirectory(source, destination, restoredName);
    await trash.removeEntry(entry.name, { recursive: true });
  }
  delete metadata.entries[entry.name];
  await writeTrashMetadata(metadata);
  return restoredName;
}

export async function permanentlyDelete(entry: FileEntry) {
  const trash = await getTrashRoot();
  await trash.removeEntry(entry.name, { recursive: entry.kind === 'directory' });
  const metadata = await readTrashMetadata();
  delete metadata.entries[entry.name];
  await writeTrashMetadata(metadata);
}

export async function emptyTrash() {
  const trash = await getTrashRoot();
  for await (const [name, handle] of (trash as any).entries()) {
    if (name === TRASH_META) continue;
    await trash.removeEntry(name, { recursive: handle.kind === 'directory' });
  }
  await writeTrashMetadata({ version: 1, entries: {} });
}

export function validatePaste(sourcePath: string[], entry: FileEntry, destinationPath: string[]) {
  const result = validatePastePath({ sourcePath, entryName: entry.name, kind: entry.kind, destinationPath });
  if (!result.ok) throw new Error(result.reason);
  return result.sameDirectory ? 'same-directory' as const : 'ok' as const;
}

export async function pasteEntry(clipboard: ClipboardEntry, destinationPath: string[]) {
  const result = validatePastePath({
    sourcePath: clipboard.sourcePath,
    entryName: clipboard.entry.name,
    kind: clipboard.entry.kind,
    destinationPath,
    action: clipboard.action,
  });
  if (!result.ok) throw new Error(result.reason);
  if (clipboard.action === 'cut' && result.sameDirectory) return { moved: false, name: clipboard.entry.name };

  const source = await getDirAt(clipboard.sourcePath);
  const destination = await getDirAt(destinationPath);
  const entry = clipboard.entry;
  const name = await getUniqueName(destination, entry.name, entry.kind === 'directory');

  if (entry.kind === 'file') {
    const file = await (await source.getFileHandle(entry.name)).getFile();
    const target = await destination.getFileHandle(name, { create: true });
    const writable = await (target as any).createWritable();
    await writable.write(file);
    await writable.close();
    if (clipboard.action === 'cut') await source.removeEntry(entry.name);
  } else {
    const sourceDir = await source.getDirectoryHandle(entry.name);
    await copyDirectory(sourceDir, destination, name);
    if (clipboard.action === 'cut') await source.removeEntry(entry.name, { recursive: true });
  }
  return { moved: clipboard.action === 'cut', name };
}
