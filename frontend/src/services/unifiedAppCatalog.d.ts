import type { AppDefinition } from '../types';

export interface UnifiedCatalogPayload {
  apps?: unknown[];
}

export function mapUnifiedCatalogApps(payload: UnifiedCatalogPayload | unknown[]): AppDefinition[];

