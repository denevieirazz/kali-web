import type { AppDefinition } from '../types';

export interface WindowsCatalogPayload {
  apps?: unknown[];
}

export function mapWindowsCatalogApps(payload: WindowsCatalogPayload | unknown[]): AppDefinition[];
