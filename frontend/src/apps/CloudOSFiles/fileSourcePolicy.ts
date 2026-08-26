export type FileSourceKind = 'cloudos' | 'opfs' | 'windows' | 'wsl';
export type FileActor = 'user-ui' | 'agent';

export const USER_FILE_ACTOR: FileActor = 'user-ui';
export const MAX_FILE_PATH_SEGMENTS = 64;
export const MAX_FILE_NAME_BYTES = 255;

export function normalizeFilePath(path: unknown): string[] {
  if (!Array.isArray(path) || path.length > MAX_FILE_PATH_SEGMENTS) throw new Error('Caminho inválido.');
  return path.map(segment => {
    if (typeof segment !== 'string') throw new Error('Caminho inválido.');
    const value = segment.normalize('NFC');
    if (!value || value === '.' || value === '..' || value.includes('/') || value.includes('\\') || value.includes('\0')) throw new Error('Caminho inválido.');
    if (new TextEncoder().encode(value).byteLength > MAX_FILE_NAME_BYTES) throw new Error('Nome excede o limite permitido.');
    return value;
  });
}

export function appendFilePath(path: unknown, name: unknown): string[] {
  return normalizeFilePath([...(Array.isArray(path) ? path : []), name]);
}

export function assertExplicitUserActor(actor: FileActor) {
  if (actor !== USER_FILE_ACTOR) throw new Error('Acesso a arquivos reais exige ação explícita do usuário.');
}

export function sourceLabel(source: FileSourceKind) {
  if (source === 'cloudos') return 'CloudOS Drive';
  if (source === 'windows') return 'Windows Drives (/mnt/c)';
  if (source === 'wsl') return 'Linux RootFS (/)';
  return 'CloudOS legado (OPFS)';
}

export function sourceIsReal(source: FileSourceKind) {
  return source === 'cloudos' || source === 'windows' || source === 'wsl';
}
