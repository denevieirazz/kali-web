export interface CloudFileRef {
  provider: 'cloudos';
  path: string[];
}

const MAX_SEGMENTS = 64;
const LEGACY_HOME_DIRECTORIES = new Set(['Desktop', 'Documents', 'Downloads', 'Projects']);

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
  const segments = filePath.slice(2).split('/').filter(Boolean);
  if (!segments.length || segments.length > MAX_SEGMENTS || segments.some(segment => !validSegment(segment))) return null;

  // CloudOS Files currently labels the Drive root as `~/`, therefore canonical
  // entries already arrive as `~/Home/...` or `~/Shared/...`. Preserve those
  // roots exactly instead of accidentally generating Home/Home/...
  if (segments[0] === 'Home' || segments[0] === 'Shared') {
    return segments.length >= 2 ? { provider: 'cloudos', path: segments } : null;
  }

  // Compatibility with older callers that exposed Home children directly as
  // `~/Downloads/...`, `~/Documents/...`, etc.
  if (LEGACY_HOME_DIRECTORIES.has(segments[0])) {
    return { provider: 'cloudos', path: ['Home', ...segments] };
  }

  // Apps/, arbitrary Drive roots and unknown legacy paths never gain a handoff.
  return null;
}

export function isCloudFileRef(value: unknown): value is CloudFileRef {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const candidate = value as { provider?: unknown; path?: unknown };
  return candidate.provider === 'cloudos'
    && Array.isArray(candidate.path)
    && candidate.path.length >= 2
    && candidate.path.length <= MAX_SEGMENTS
    && candidate.path.every(segment => typeof segment === 'string' && validSegment(segment))
    && (candidate.path[0] === 'Home' || candidate.path[0] === 'Shared');
}
