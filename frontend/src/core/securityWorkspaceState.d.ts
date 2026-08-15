export interface SecurityWorkspaceState {
  projectName: string;
  notes: string;
  scopes: string[];
  activeScope: string | null;
}

export const SECURITY_WORKSPACE_STORAGE_KEY: string;
export const MAX_SCOPE_ASSETS: number;
export function normalizeScopeAsset(value: unknown): string | null;
export function normalizeSecurityWorkspace(value: unknown): SecurityWorkspaceState;
export function addScopeAsset(workspace: SecurityWorkspaceState, value: unknown): { workspace: SecurityWorkspaceState; added: boolean; reason: string };
export function removeScopeAsset(workspace: SecurityWorkspaceState, value: string): SecurityWorkspaceState;
export function selectScopeAsset(workspace: SecurityWorkspaceState, value: string): SecurityWorkspaceState;
