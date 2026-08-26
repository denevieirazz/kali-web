import fs from 'node:fs/promises';
import path from 'node:path';
import { cloudOsDrive, CloudOsDriveError } from './cloudosDrive.js';

const MAX_SEGMENTS = 64;
const MAX_SEGMENT_BYTES = 255;
const ALLOWED_ROOTS = new Set(['Home', 'Shared']);

function isInside(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}

function handoffError(code, message, cause) {
  return new CloudOsDriveError(code, message, cause);
}

export function validateCloudFileRef(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw handoffError('CLOUDOS_FILE_REF_INVALID', 'Referência de arquivo inválida.');
  }
  const keys = Object.keys(value);
  if (keys.some(key => key !== 'provider' && key !== 'path') || value.provider !== 'cloudos') {
    throw handoffError('CLOUDOS_FILE_REF_INVALID', 'A referência não pertence ao CloudOS Drive.');
  }
  if (!Array.isArray(value.path) || value.path.length < 2 || value.path.length > MAX_SEGMENTS) {
    throw handoffError('CLOUDOS_FILE_REF_INVALID', 'Caminho lógico inválido no CloudOS Drive.');
  }

  const segments = value.path.map(raw => {
    if (typeof raw !== 'string') throw handoffError('CLOUDOS_FILE_REF_INVALID', 'Caminho lógico inválido no CloudOS Drive.');
    const segment = raw.normalize('NFC');
    if (!segment || segment === '.' || segment === '..' || segment === '.cloudos-system'
      || segment.includes('/') || segment.includes('\\') || segment.includes('\0')
      || Buffer.byteLength(segment, 'utf8') > MAX_SEGMENT_BYTES) {
      throw handoffError('CLOUDOS_FILE_REF_INVALID', 'Caminho lógico inválido no CloudOS Drive.');
    }
    return segment;
  });

  if (!ALLOWED_ROOTS.has(segments[0])) {
    throw handoffError('CLOUDOS_FILE_REF_SCOPE_DENIED', 'Somente arquivos do Home ou Shared podem ser entregues a aplicativos.');
  }
  return Object.freeze({ provider: 'cloudos', path: Object.freeze(segments) });
}

export async function resolveCloudFileRef(value) {
  const fileRef = validateCloudFileRef(value);
  const runtimePaths = await cloudOsDrive.runtimePaths();
  const root = runtimePaths.hostRoot;
  let candidate = root;

  for (const segment of fileRef.path) {
    candidate = path.join(candidate, segment);
    let stat;
    try {
      stat = await fs.lstat(candidate);
    } catch (error) {
      if (error?.code === 'ENOENT') throw handoffError('CLOUDOS_DRIVE_NOT_FOUND', 'Arquivo não encontrado no CloudOS Drive.', error);
      throw handoffError('CLOUDOS_DRIVE_IO_FAILED', 'Falha ao validar o arquivo no CloudOS Drive.', error);
    }
    if (stat.isSymbolicLink()) {
      throw handoffError('CLOUDOS_DRIVE_SYMLINK_BLOCKED', 'Links e junctions não podem atravessar o broker de arquivos.');
    }
  }

  const stat = await fs.lstat(candidate);
  if (!stat.isFile()) throw handoffError('CLOUDOS_DRIVE_NOT_FILE', 'Somente arquivos regulares podem ser entregues a aplicativos.');
  const real = await fs.realpath(candidate);
  if (!isInside(root, real)) {
    throw handoffError('CLOUDOS_DRIVE_ESCAPE_BLOCKED', 'A referência tentaria sair do CloudOS Drive.');
  }

  return Object.freeze({ fileRef, absolutePath: real });
}
