// ============================================
// OPFS Driver — Origin Private File System
// Low-level disk I/O for ObsidianOS
// ============================================
// This module is the ONLY place that touches OPFS directly.
// It is loaded by ntfs.sys during DRIVER_LOAD phase.
// The kernel cache is kept in sync via write-through.
// ============================================

import type { FileSystemNode } from '../types';

const DISK_ROOT = 'obsidianos-disk';
const META_SUFFIX = '.__meta__';

// ── Path translation ──────────────────────────────────────────────────────────
// OS path:   C:\Users\User\Documents\notes.txt
// OPFS path: obsidianos-disk/C_/Users/User/Documents/notes.txt
function osPathToOpfs(osPath: string): string[] {
  // Normalize drive letter: "C:" → "C_"
  const normalized = osPath.replace(/^([A-Z]):/, '$1_').replace(/\\/g, '/');
  return normalized.split('/').filter(Boolean);
}

// OPFS entries() iterator is not in standard TS lib yet
type OPFSEntries = AsyncIterable<[string, FileSystemHandle]>;
function entries(dir: FileSystemDirectoryHandle): OPFSEntries {
  return (dir as unknown as { entries(): OPFSEntries }).entries();
}
let _diskRoot: FileSystemDirectoryHandle | null = null;

async function getDiskRoot(): Promise<FileSystemDirectoryHandle> {
  if (_diskRoot) return _diskRoot;
  const opfsRoot = await navigator.storage.getDirectory();
  _diskRoot = await opfsRoot.getDirectoryHandle(DISK_ROOT, { create: true });
  return _diskRoot;
}

// ── Directory traversal ───────────────────────────────────────────────────────
async function getDirectoryHandle(
  parts: string[],
  create = false
): Promise<FileSystemDirectoryHandle | null> {
  try {
    let current = await getDiskRoot();
    for (const part of parts) {
      current = await current.getDirectoryHandle(part, { create });
    }
    return current;
  } catch {
    return null;
  }
}

async function getFileHandle(
  parts: string[],
  create = false
): Promise<FileSystemFileHandle | null> {
  if (parts.length === 0) return null;
  const dirParts = parts.slice(0, -1);
  const fileName = parts[parts.length - 1];
  try {
    const dir = dirParts.length > 0
      ? await getDirectoryHandle(dirParts, create)
      : await getDiskRoot();
    if (!dir) return null;
    return await dir.getFileHandle(fileName, { create });
  } catch {
    return null;
  }
}

// ── Public API ────────────────────────────────────────────────────────────────

export interface OPFSDriver {
  isAvailable: () => boolean;
  formatDisk: (nodes: Record<string, FileSystemNode>) => Promise<void>;
  diskExists: () => Promise<boolean>;
  readMeta: (osPath: string) => Promise<FileSystemNode | null>;
  writeMeta: (node: FileSystemNode) => Promise<void>;
  readContent: (osPath: string) => Promise<string | null>;
  writeContent: (osPath: string, content: string) => Promise<void>;
  createDirectory: (osPath: string) => Promise<void>;
  deleteNode: (osPath: string) => Promise<void>;
  listDirectory: (osPath: string) => Promise<string[]>;
  renameNode: (osPath: string, newName: string) => Promise<void>;
  hydrateCache: () => Promise<Record<string, FileSystemNode>>;
}

export const opfsDriver: OPFSDriver = {
  isAvailable(): boolean {
    return typeof navigator !== 'undefined' && 'storage' in navigator && 'getDirectory' in navigator.storage;
  },

  async diskExists(): Promise<boolean> {
    try {
      const opfsRoot = await navigator.storage.getDirectory();
      await opfsRoot.getDirectoryHandle(DISK_ROOT, { create: false });
      return true;
    } catch {
      return false;
    }
  },

  // Called on first boot — writes all defaultNodes to OPFS
  async formatDisk(nodes: Record<string, FileSystemNode>): Promise<void> {
    // Reset disk root
    try {
      const opfsRoot = await navigator.storage.getDirectory();
      await opfsRoot.removeEntry(DISK_ROOT, { recursive: true });
    } catch { /* doesn't exist yet */ }
    _diskRoot = null;

    const sorted = Object.values(nodes).sort((a, b) => {
      const da = (a.path.match(/\\/g) || []).length;
      const db = (b.path.match(/\\/g) || []).length;
      return da - db;
    });

    for (const node of sorted) {
      if (node.type === 'directory') {
        await opfsDriver.createDirectory(node.path);
      } else {
        await opfsDriver.createDirectory(node.parentPath);
        await opfsDriver.writeContent(node.path, node.content || '');
      }
      await opfsDriver.writeMeta(node);
    }
  },

  async readMeta(osPath: string): Promise<FileSystemNode | null> {
    const parts = osPathToOpfs(osPath);
    const metaParts = [...parts.slice(0, -1), parts[parts.length - 1] + META_SUFFIX];
    const handle = await getFileHandle(metaParts);
    if (!handle) return null;
    try {
      const file = await handle.getFile();
      const text = await file.text();
      return JSON.parse(text) as FileSystemNode;
    } catch {
      return null;
    }
  },

  async writeMeta(node: FileSystemNode): Promise<void> {
    const parts = osPathToOpfs(node.path);
    const metaParts = [...parts.slice(0, -1), parts[parts.length - 1] + META_SUFFIX];
    const handle = await getFileHandle(metaParts, true);
    if (!handle) return;
    const writable = await handle.createWritable();
    await writable.write(JSON.stringify(node));
    await writable.close();
  },

  async readContent(osPath: string): Promise<string | null> {
    const parts = osPathToOpfs(osPath);
    const handle = await getFileHandle(parts);
    if (!handle) return null;
    try {
      const file = await handle.getFile();
      return await file.text();
    } catch {
      return null;
    }
  },

  async writeContent(osPath: string, content: string): Promise<void> {
    const parts = osPathToOpfs(osPath);
    // Ensure parent directory exists
    if (parts.length > 1) {
      await getDirectoryHandle(parts.slice(0, -1), true);
    }
    const handle = await getFileHandle(parts, true);
    if (!handle) return;
    const writable = await handle.createWritable();
    await writable.write(content);
    await writable.close();
  },

  async createDirectory(osPath: string): Promise<void> {
    const parts = osPathToOpfs(osPath);
    await getDirectoryHandle(parts, true);
  },

  async deleteNode(osPath: string): Promise<void> {
    const parts = osPathToOpfs(osPath);
    if (parts.length === 0) return;
    const parentParts = parts.slice(0, -1);
    const name = parts[parts.length - 1];
    const parent = parentParts.length > 0
      ? await getDirectoryHandle(parentParts)
      : await getDiskRoot();
    if (!parent) return;
    try { await parent.removeEntry(name, { recursive: true }); } catch { /* already gone */ }
    try { await parent.removeEntry(name + META_SUFFIX); } catch { /* no meta */ }
  },

  async listDirectory(osPath: string): Promise<string[]> {
    const parts = osPathToOpfs(osPath);
    const dir = parts.length > 0
      ? await getDirectoryHandle(parts)
      : await getDiskRoot();
    if (!dir) return [];
    const names: string[] = [];
    for await (const [name] of entries(dir)) {
      if (!name.endsWith(META_SUFFIX)) names.push(name);
    }
    return names;
  },

  async renameNode(osPath: string, newName: string): Promise<void> {
    // OPFS doesn't support rename natively — copy + delete
    const node = await opfsDriver.readMeta(osPath);
    if (!node) return;
    const parentPath = node.parentPath;
    const newPath = `${parentPath}\\${newName}`;

    if (node.type === 'file') {
      const content = await opfsDriver.readContent(osPath) || '';
      const newNode: FileSystemNode = { ...node, name: newName, path: newPath, id: newPath, modifiedAt: Date.now() };
      await opfsDriver.writeContent(newPath, content);
      await opfsDriver.writeMeta(newNode);
      await opfsDriver.deleteNode(osPath);
    } else {
      // For directories, recursively copy children then delete
      const children = await opfsDriver.listDirectory(osPath);
      await opfsDriver.createDirectory(newPath);
      const newDirNode: FileSystemNode = { ...node, name: newName, path: newPath, id: newPath, modifiedAt: Date.now() };
      await opfsDriver.writeMeta(newDirNode);
      for (const child of children) {
        await opfsDriver.renameNode(`${osPath}\\${child}`, child);
      }
      await opfsDriver.deleteNode(osPath);
    }
  },

  // Reads all metadata from OPFS and rebuilds the in-memory cache
  async hydrateCache(): Promise<Record<string, FileSystemNode>> {
    const cache: Record<string, FileSystemNode> = {};

    async function walk(dirHandle: FileSystemDirectoryHandle, osPath: string) {
      for await (const [name, handle] of entries(dirHandle)) {
        if (name.endsWith(META_SUFFIX)) continue;

        // Translate OPFS name back to OS path segment
        const childOsPath = osPath ? `${osPath}\\${name}` : name.replace('_', ':');

        if (handle.kind === 'directory') {
          const meta = await opfsDriver.readMeta(childOsPath);
          if (meta) cache[childOsPath] = meta;
          await walk(handle as FileSystemDirectoryHandle, childOsPath);
        } else {
          const meta = await opfsDriver.readMeta(childOsPath);
          if (meta) {
            // Content stays on disk — only load into cache on demand
            cache[childOsPath] = meta;
          }
        }
      }
    }

    const root = await getDiskRoot();
    for await (const [driveName, driveHandle] of entries(root)) {
      if (driveName.endsWith(META_SUFFIX)) continue;
      const driveOsPath = driveName.replace('_', ':');
      if (driveHandle.kind === 'directory') {
        const meta = await opfsDriver.readMeta(driveOsPath);
        if (meta) cache[driveOsPath] = meta;
        await walk(driveHandle as FileSystemDirectoryHandle, driveOsPath);
      }
    }

    return cache;
  },
};

export default opfsDriver;
