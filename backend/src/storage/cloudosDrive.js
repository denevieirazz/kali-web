import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { config } from '../config/index.js';

const RESERVED_SEGMENTS = new Set(['.cloudos-system']);
const STANDARD_DIRECTORIES = Object.freeze([
  ['Home'],
  ['Home', 'Desktop'],
  ['Home', 'Documents'],
  ['Home', 'Downloads'],
  ['Home', 'Projects'],
  ['Shared'],
  ['Apps'],
  ['Apps', 'windows'],
  ['Apps', 'linux'],
]);
const MAX_SEGMENTS = 64;
const MAX_NAME_BYTES = 255;
const INTERNAL_ROOT = '.cloudos-system';
const TRASH_ROOT = [INTERNAL_ROOT, 'trash'];

export class CloudOsDriveError extends Error {
  constructor(code, message, cause) {
    super(message, cause ? { cause } : undefined);
    this.name = 'CloudOsDriveError';
    this.code = code;
  }
}

function validateSegments(value, { allowEmpty = true } = {}) {
  if (!Array.isArray(value) || value.length > MAX_SEGMENTS || (!allowEmpty && value.length === 0)) {
    throw new CloudOsDriveError('CLOUDOS_DRIVE_PATH_INVALID', 'Caminho inválido no CloudOS Drive.');
  }
  return value.map(raw => {
    if (typeof raw !== 'string') throw new CloudOsDriveError('CLOUDOS_DRIVE_PATH_INVALID', 'Caminho inválido no CloudOS Drive.');
    const segment = raw.normalize('NFC');
    if (!segment || segment === '.' || segment === '..' || segment.includes('/') || segment.includes('\\') || segment.includes('\0')
      || Buffer.byteLength(segment, 'utf8') > MAX_NAME_BYTES || RESERVED_SEGMENTS.has(segment)) {
      throw new CloudOsDriveError('CLOUDOS_DRIVE_PATH_INVALID', 'Caminho inválido no CloudOS Drive.');
    }
    return segment;
  });
}

function kindForStat(stat) {
  if (stat.isSymbolicLink()) return 'symlink';
  if (stat.isDirectory()) return 'directory';
  if (stat.isFile()) return 'file';
  return 'other';
}

function isInside(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}

function mapFsError(error, fallbackCode = 'CLOUDOS_DRIVE_IO_FAILED') {
  if (error instanceof CloudOsDriveError) return error;
  if (error?.code === 'ENOENT') return new CloudOsDriveError('CLOUDOS_DRIVE_NOT_FOUND', 'Arquivo ou pasta não encontrado no CloudOS Drive.', error);
  if (error?.code === 'EEXIST' || error?.code === 'ENOTEMPTY') return new CloudOsDriveError('CLOUDOS_DRIVE_CONFLICT', 'O destino já existe ou não está vazio.', error);
  if (error?.code === 'EACCES' || error?.code === 'EPERM') return new CloudOsDriveError('CLOUDOS_DRIVE_ACCESS_DENIED', 'O sistema operacional recusou acesso ao CloudOS Drive.', error);
  return new CloudOsDriveError(fallbackCode, 'Falha ao acessar o CloudOS Drive.', error);
}

export function windowsPathToWslPath(candidate) {
  if (typeof candidate !== 'string') return null;
  const match = /^([a-zA-Z]):[\\/](.*)$/.exec(candidate);
  if (!match) return null;
  const drive = match[1].toLowerCase();
  const rest = match[2].split(/[\\/]+/).filter(Boolean).join('/');
  return `/mnt/${drive}${rest ? `/${rest}` : ''}`;
}

export class CloudOsDrive {
  constructor(rootDir = process.env.CLOUDOS_DRIVE_DIR || path.join(config.dataDir, 'drive')) {
    this.rootDir = path.resolve(rootDir);
    this.realRoot = null;
    this.readyPromise = null;
  }

  async ensureReady() {
    if (!this.readyPromise) this.readyPromise = this.#initialize();
    return this.readyPromise;
  }

  async #initialize() {
    await fs.mkdir(this.rootDir, { recursive: true, mode: 0o700 });
    const rootStat = await fs.lstat(this.rootDir);
    if (rootStat.isSymbolicLink() || !rootStat.isDirectory()) {
      throw new CloudOsDriveError('CLOUDOS_DRIVE_ROOT_INVALID', 'A raiz do CloudOS Drive não é um diretório físico confiável.');
    }
    this.realRoot = await fs.realpath(this.rootDir);
    for (const segments of [...STANDARD_DIRECTORIES, TRASH_ROOT]) {
      await fs.mkdir(path.join(this.realRoot, ...segments), { recursive: true, mode: 0o700 });
    }
    return this.realRoot;
  }

  async runtimePaths() {
    await this.ensureReady();
    return Object.freeze({
      hostRoot: this.realRoot,
      hostHome: path.join(this.realRoot, 'Home'),
      hostDownloads: path.join(this.realRoot, 'Home', 'Downloads'),
      hostProjects: path.join(this.realRoot, 'Home', 'Projects'),
      hostShared: path.join(this.realRoot, 'Shared'),
      windowsApps: path.join(this.realRoot, 'Apps', 'windows'),
      linuxApps: path.join(this.realRoot, 'Apps', 'linux'),
      wslRoot: process.platform === 'win32' ? windowsPathToWslPath(this.realRoot) : null,
    });
  }

  async status() {
    await this.ensureReady();
    let capacity = null;
    try {
      const stat = await fs.statfs(this.realRoot);
      const blockSize = Number(stat.bsize) || 0;
      capacity = {
        total: Number(stat.blocks) * blockSize,
        free: Number(stat.bavail) * blockSize,
      };
    } catch {
      capacity = null;
    }
    return {
      source: 'cloudos',
      mode: 'cloudos-drive-v1',
      available: true,
      mounted: true,
      rootLabel: 'CloudOS Drive',
      directories: STANDARD_DIRECTORIES.filter(parts => parts.length <= 2).map(parts => parts.join('/')),
      capacity,
    };
  }

  async #existingPath(segments, { allowEmpty = true } = {}) {
    await this.ensureReady();
    const safe = validateSegments(segments, { allowEmpty });
    const lexical = path.resolve(this.realRoot, ...safe);
    if (!isInside(this.realRoot, lexical)) throw new CloudOsDriveError('CLOUDOS_DRIVE_PATH_INVALID', 'Caminho fora do CloudOS Drive.');
    let stat;
    try { stat = await fs.lstat(lexical); }
    catch (error) { throw mapFsError(error); }
    if (stat.isSymbolicLink()) throw new CloudOsDriveError('CLOUDOS_DRIVE_SYMLINK_BLOCKED', 'Links simbólicos não são seguidos pelo CloudOS Drive.');
    const real = await fs.realpath(lexical);
    if (!isInside(this.realRoot, real)) throw new CloudOsDriveError('CLOUDOS_DRIVE_ESCAPE_BLOCKED', 'O caminho tentaria sair do CloudOS Drive.');
    return { safe, absolute: real, stat };
  }

  async #destinationPath(segments) {
    const safe = validateSegments(segments, { allowEmpty: false });
    const parentSegments = safe.slice(0, -1);
    const leaf = safe.at(-1);
    const parent = await this.#existingPath(parentSegments, { allowEmpty: true });
    if (!parent.stat.isDirectory()) throw new CloudOsDriveError('CLOUDOS_DRIVE_PARENT_INVALID', 'A pasta de destino não existe.');
    const absolute = path.join(parent.absolute, leaf);
    if (!isInside(this.realRoot, absolute)) throw new CloudOsDriveError('CLOUDOS_DRIVE_PATH_INVALID', 'Caminho fora do CloudOS Drive.');
    try {
      const stat = await fs.lstat(absolute);
      if (stat.isSymbolicLink()) throw new CloudOsDriveError('CLOUDOS_DRIVE_SYMLINK_BLOCKED', 'Links simbólicos não são seguidos pelo CloudOS Drive.');
      return { safe, absolute, exists: true, stat };
    } catch (error) {
      if (error instanceof CloudOsDriveError) throw error;
      if (error?.code === 'ENOENT') return { safe, absolute, exists: false, stat: null };
      throw mapFsError(error);
    }
  }

  async list(segments = []) {
    const target = await this.#existingPath(segments);
    if (!target.stat.isDirectory()) throw new CloudOsDriveError('CLOUDOS_DRIVE_NOT_DIRECTORY', 'O caminho não é uma pasta.');
    const names = await fs.readdir(target.absolute);
    const entries = [];
    for (const name of names) {
      if (target.safe.length === 0 && name === INTERNAL_ROOT) continue;
      const stat = await fs.lstat(path.join(target.absolute, name));
      const kind = kindForStat(stat);
      if (kind === 'other') continue;
      entries.push({
        name,
        kind,
        size: stat.isFile() ? stat.size : 0,
        modifiedAt: stat.mtime.toISOString(),
        symlink: stat.isSymbolicLink(),
      });
    }
    entries.sort((left, right) => left.name.localeCompare(right.name, undefined, { sensitivity: 'base' }));
    return entries;
  }

  async read(segments, offset = 0, limit = 256 * 1024) {
    const target = await this.#existingPath(segments, { allowEmpty: false });
    if (!target.stat.isFile()) throw new CloudOsDriveError('CLOUDOS_DRIVE_NOT_FILE', 'O caminho não é um arquivo regular.');
    const size = target.stat.size;
    const start = Math.min(Math.max(0, offset), size);
    const length = Math.min(Math.max(1, limit), Math.max(0, size - start));
    if (length === 0) return { data: '', bytes: 0, size, eof: true };
    const handle = await fs.open(target.absolute, 'r');
    try {
      const buffer = Buffer.allocUnsafe(length);
      const { bytesRead } = await handle.read(buffer, 0, length, start);
      return { data: buffer.subarray(0, bytesRead).toString('base64'), bytes: bytesRead, size, eof: start + bytesRead >= size };
    } finally {
      await handle.close();
    }
  }

  async write(segments, data, { offset = 0, truncate = false } = {}) {
    if (!Buffer.isBuffer(data)) throw new CloudOsDriveError('CLOUDOS_DRIVE_DATA_INVALID', 'Bloco de gravação inválido.');
    const target = await this.#destinationPath(segments);
    if (target.exists && !target.stat.isFile()) throw new CloudOsDriveError('CLOUDOS_DRIVE_NOT_FILE', 'O destino não é um arquivo regular.');
    const handle = await fs.open(target.absolute, truncate ? 'w+' : (target.exists ? 'r+' : 'w+'), 0o600);
    try {
      if (truncate && offset > 0) await handle.truncate(0);
      if (data.length) await handle.write(data, 0, data.length, offset);
      const stat = await handle.stat();
      return { written: data.length, size: stat.size };
    } finally {
      await handle.close();
    }
  }

  async mkdir(segments) {
    const target = await this.#destinationPath(segments);
    if (target.exists) throw new CloudOsDriveError('CLOUDOS_DRIVE_CONFLICT', 'A pasta já existe.');
    try { await fs.mkdir(target.absolute, { mode: 0o700 }); }
    catch (error) { throw mapFsError(error); }
    return { created: true };
  }

  async move(sourceSegments, destinationSegments) {
    const source = await this.#existingPath(sourceSegments, { allowEmpty: false });
    const destination = await this.#destinationPath(destinationSegments);
    if (destination.exists) throw new CloudOsDriveError('CLOUDOS_DRIVE_CONFLICT', 'O destino já existe.');
    try { await fs.rename(source.absolute, destination.absolute); }
    catch (error) { throw mapFsError(error); }
    return { moved: true };
  }

  async #assertTreeContainsNoSymlink(absolute) {
    const stat = await fs.lstat(absolute);
    if (stat.isSymbolicLink()) throw new CloudOsDriveError('CLOUDOS_DRIVE_SYMLINK_BLOCKED', 'Links simbólicos não podem ser copiados pelo CloudOS Drive.');
    if (!stat.isDirectory()) return;
    for (const name of await fs.readdir(absolute)) await this.#assertTreeContainsNoSymlink(path.join(absolute, name));
  }

  async copy(sourceSegments, destinationSegments) {
    const source = await this.#existingPath(sourceSegments, { allowEmpty: false });
    const destination = await this.#destinationPath(destinationSegments);
    if (destination.exists) throw new CloudOsDriveError('CLOUDOS_DRIVE_CONFLICT', 'O destino já existe.');
    await this.#assertTreeContainsNoSymlink(source.absolute);
    try {
      await fs.cp(source.absolute, destination.absolute, { recursive: source.stat.isDirectory(), errorOnExist: true, force: false, dereference: false });
    } catch (error) { throw mapFsError(error); }
    return { copied: true };
  }

  async trash(segments) {
    const source = await this.#existingPath(segments, { allowEmpty: false });
    const id = crypto.randomBytes(16).toString('hex');
    const trashDir = path.join(this.realRoot, ...TRASH_ROOT);
    const storedName = `${id}.item`;
    const storedPath = path.join(trashDir, storedName);
    const metadataPath = path.join(trashDir, `${id}.json`);
    const originalName = source.safe.at(-1);
    const originalPath = source.safe.slice(0, -1);
    const deletedAt = new Date().toISOString();
    try {
      await fs.rename(source.absolute, storedPath);
      await fs.writeFile(metadataPath, JSON.stringify({ id, storedName, originalName, originalPath, deletedAt }), { encoding: 'utf8', mode: 0o600, flag: 'wx' });
    } catch (error) {
      try { await fs.rename(storedPath, source.absolute); } catch {}
      throw mapFsError(error);
    }
    return { id, storedName, originalName, originalPath, deletedAt, kind: kindForStat(source.stat), size: source.stat.isFile() ? source.stat.size : 0 };
  }

  async listTrash() {
    await this.ensureReady();
    const trashDir = path.join(this.realRoot, ...TRASH_ROOT);
    const names = (await fs.readdir(trashDir)).filter(name => /^[a-f0-9]{32}\.json$/i.test(name));
    const entries = [];
    for (const name of names) {
      try {
        const metadata = JSON.parse(await fs.readFile(path.join(trashDir, name), 'utf8'));
        if (!metadata?.id || !/^[a-f0-9]{32}$/i.test(metadata.id)) continue;
        const storedPath = path.join(trashDir, `${metadata.id}.item`);
        const stat = await fs.lstat(storedPath);
        if (stat.isSymbolicLink()) continue;
        entries.push({ ...metadata, kind: kindForStat(stat), size: stat.isFile() ? stat.size : 0 });
      } catch {}
    }
    entries.sort((left, right) => String(right.deletedAt).localeCompare(String(left.deletedAt)));
    return entries;
  }

  async #trashMetadata(id) {
    if (typeof id !== 'string' || !/^[a-f0-9]{32}$/i.test(id)) throw new CloudOsDriveError('CLOUDOS_DRIVE_TRASH_ID_INVALID', 'Identificador de lixeira inválido.');
    await this.ensureReady();
    const trashDir = path.join(this.realRoot, ...TRASH_ROOT);
    try {
      const metadata = JSON.parse(await fs.readFile(path.join(trashDir, `${id}.json`), 'utf8'));
      if (metadata?.id !== id || !Array.isArray(metadata.originalPath) || typeof metadata.originalName !== 'string') throw new Error('metadata');
      validateSegments([...metadata.originalPath, metadata.originalName], { allowEmpty: false });
      return { metadata, trashDir };
    } catch (error) {
      throw mapFsError(error, 'CLOUDOS_DRIVE_TRASH_INVALID');
    }
  }

  async restoreTrash(id) {
    const { metadata, trashDir } = await this.#trashMetadata(id);
    const destination = await this.#destinationPath([...metadata.originalPath, metadata.originalName]);
    if (destination.exists) throw new CloudOsDriveError('CLOUDOS_DRIVE_CONFLICT', 'O local original já contém um item com esse nome.');
    const storedPath = path.join(trashDir, `${id}.item`);
    try {
      await fs.rename(storedPath, destination.absolute);
      await fs.rm(path.join(trashDir, `${id}.json`), { force: true });
    } catch (error) { throw mapFsError(error); }
    return { restored: true, name: metadata.originalName, path: metadata.originalPath };
  }

  async deleteTrash(id) {
    const { trashDir } = await this.#trashMetadata(id);
    try {
      await fs.rm(path.join(trashDir, `${id}.item`), { recursive: true, force: true });
      await fs.rm(path.join(trashDir, `${id}.json`), { force: true });
    } catch (error) { throw mapFsError(error); }
    return { deleted: true };
  }

  async emptyTrash() {
    const entries = await this.listTrash();
    for (const entry of entries) await this.deleteTrash(entry.id);
    return { deleted: entries.length };
  }
}

export const cloudOsDrive = new CloudOsDrive();
