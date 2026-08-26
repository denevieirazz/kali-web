export interface CloudFileRef {
  provider: 'cloudos';
  path: string[];
}

const MAX_SEGMENTS = 64;

function validSegment(segment: string) {
  return Boolean(segment)
    && segment !== '.'
    && segment !== '..'
    && segment !== '.cloudos-system'
    && !segment.includes('/')
    && !segment.includes('\\')
    && !segment.includes('\0');
}

export function cloudFileRefFromLegacyPath(filePath: string): CloudFileRef | null {
  if (typeof filePath !== 'string' || !filePath.startsWith('~/')) return null;
  const relative = filePath.slice(2);
  const segments = relative.split('/').filter(Boolean);
  if (!segments.length || segments.length + 1 > MAX_SEGMENTS || segments.some(segment => !validSegment(segment))) return null;
  return { provider: 'cloudos', path: ['Home', ...segments] };
}

export function isCloudFileRef(value: unknown): value is CloudFileRef {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const candidate = value as { provider?: unknown; path?: unknown };
  return candidate.provider === 'cloudos'
    && Array.isArray(candidate.path)
    && candidate.path.length >= 2
    && candidate.path.length <= MAX_SEGMENTS
    && candidate.path.every(segment => typeof segment === 'string' && validSegment(segment));
}
