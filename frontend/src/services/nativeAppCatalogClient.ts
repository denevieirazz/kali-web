import { apiClient } from './apiClient';

export type NativeRuntimeCompatibilityStatus =
  | 'UNQUALIFIED'
  | 'CAPTURE_SUPPORTED'
  | 'CAPTURE_BLOCKED'
  | 'BROKER_UNSAFE'
  | 'SINGLETON_UNSAFE'
  | 'RENDER_FAILED'
  | 'INPUT_UNSUPPORTED';

export interface NativeRuntimeCompatibility {
  status: NativeRuntimeCompatibilityStatus | string;
  reason?: string | null;
  qualifiedAt?: string | null;
}

export interface NativeCatalogApp {
  id: string;
  name: string;
  source: string;
  launchable: boolean;
  windowMode?: string | null;
  discoverySource?: string | null;
  runtimeClass?: string | null;
  compatibility?: NativeRuntimeCompatibility | null;
  [key: string]: unknown;
}

export interface NativeCatalogSnapshot {
  apps: NativeCatalogApp[];
  revision: string;
  generatedAt: string;
}

export interface NativeCatalogRefreshResult extends NativeCatalogSnapshot {
  changed: boolean;
  previousRevision: string | null;
  addedAppIds: string[];
  removedAppIds: string[];
}

function validateSnapshot(value: NativeCatalogSnapshot): NativeCatalogSnapshot {
  if (!value || !Array.isArray(value.apps)) throw new Error('Catálogo nativo retornou apps inválidos.');
  if (typeof value.revision !== 'string' || !/^[a-f0-9]{64}$/i.test(value.revision)) {
    throw new Error('Catálogo nativo retornou revision inválida.');
  }
  if (typeof value.generatedAt !== 'string' || Number.isNaN(Date.parse(value.generatedAt))) {
    throw new Error('Catálogo nativo retornou generatedAt inválido.');
  }
  const ids = new Set<string>();
  for (const app of value.apps) {
    if (!app || typeof app.id !== 'string' || !app.id || typeof app.name !== 'string' || !app.name) {
      throw new Error('Catálogo nativo contém app sem identidade pública válida.');
    }
    if (ids.has(app.id)) throw new Error(`Catálogo nativo contém ID duplicado: ${app.id}`);
    ids.add(app.id);
  }
  return value;
}

export async function getNativeAppCatalog(forceRefresh = false): Promise<NativeCatalogSnapshot> {
  const endpoint = forceRefresh ? '/api/apps?refresh=true' : '/api/apps';
  const snapshot = await apiClient<NativeCatalogSnapshot>(endpoint, { timeoutMs: forceRefresh ? 20_000 : 10_000 });
  return validateSnapshot(snapshot);
}

export async function refreshNativeAppCatalog(
  previous: NativeCatalogSnapshot | null = null,
): Promise<NativeCatalogRefreshResult> {
  const next = await getNativeAppCatalog(true);
  const previousIds = new Set(previous?.apps.map(app => app.id) ?? []);
  const nextIds = new Set(next.apps.map(app => app.id));
  return {
    ...next,
    changed: previous?.revision !== next.revision,
    previousRevision: previous?.revision ?? null,
    addedAppIds: next.apps.filter(app => !previousIds.has(app.id)).map(app => app.id),
    removedAppIds: previous?.apps.filter(app => !nextIds.has(app.id)).map(app => app.id) ?? [],
  };
}

export function captureQualifiedApps(snapshot: NativeCatalogSnapshot): NativeCatalogApp[] {
  return snapshot.apps.filter(app => app.compatibility?.status === 'CAPTURE_SUPPORTED');
}

export function unqualifiedCaptureCandidates(snapshot: NativeCatalogSnapshot): NativeCatalogApp[] {
  return snapshot.apps.filter(app => app.compatibility?.status === 'UNQUALIFIED');
}
