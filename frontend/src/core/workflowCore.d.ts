export type WorkspaceType = 'client' | 'project' | 'ticket' | 'lab' | 'custom';
export type WorkflowProvider = 'opfs' | 'windows' | 'wsl';
export type WorkspaceStatus = 'active' | 'archived';
export type WorkflowFileOpenMode = 'directory' | 'notes' | 'viewer' | 'info';

export interface WorkspaceRecord {
  id: string;
  type: WorkspaceType;
  name: string;
  description: string;
  client: string;
  tags: string[];
  status: WorkspaceStatus;
  provider: WorkflowProvider;
  root: string[];
  originPath: string[];
  createdAt: string;
  lastAccessAt: string;
  lastActivityAt: string;
}

export interface ClipboardMetadata {
  id: string;
  source: string;
  createdAt: string;
  bytes: number;
  preview: string;
  favorite: boolean;
  fileName: string;
}

export const WORKSPACE_TYPES: ReadonlyArray<{ id: WorkspaceType; label: string }>;
export const WORKSPACE_FOLDERS: ReadonlyArray<string>;
export const MAX_CLIPBOARD_ITEMS: number;
export const MAX_CLIPBOARD_ITEM_BYTES: number;
export const MAX_WORKSPACE_DESCRIPTION: number;
export const MAX_WORKSPACE_TAGS: number;
export const MAX_WORKSPACE_TAG_LENGTH: number;
export const MIN_VIEWER_ZOOM: number;
export const MAX_VIEWER_ZOOM: number;
export const VIEWER_ZOOM_STEP: number;

export function workspaceTypeLabel(type: WorkspaceType | string): string;
export function sanitizeWorkspaceName(value: unknown): string;
export function sanitizeWorkspaceTags(value: unknown): string[];
export function workspaceFolderName(name: string, id: string): string;
export function normalizeWorkspaceRecord(value: unknown): WorkspaceRecord | null;
export function createWorkspaceRecord(input: {
  id: string;
  type: WorkspaceType;
  name: string;
  description?: string;
  client?: string;
  tags?: string[];
  status?: WorkspaceStatus;
  provider: WorkflowProvider;
  root: string[];
  originPath?: string[];
  now?: string;
}): WorkspaceRecord | null;
export function buildWorkspaceManifest(workspace: WorkspaceRecord): {
  versao: 1;
  id: string;
  tipo: string;
  nome: string;
  descricao: string;
  cliente: string;
  tags: string[];
  status: WorkspaceStatus;
  data: string;
  ultimoAcesso: string;
  ultimaAtividade: string;
  origem: { provider: WorkflowProvider; caminhoInicial: string[] };
  estrutura: string[];
};
export function workspaceSearchText(workspace: WorkspaceRecord): string;
export function workflowFileOpenMode(name: unknown, kind?: 'file' | 'directory' | 'symlink', symlink?: boolean): WorkflowFileOpenMode;
export function normalizeViewerZoom(value: unknown): number;
export function stepViewerZoom(current: unknown, direction: unknown): number;
export function looksSensitiveText(value: unknown): boolean;
export function clipboardTextPolicy(value: unknown): { allowed: boolean; reason: 'empty' | 'too-large' | 'sensitive' | 'ok'; bytes: number };
export function normalizeClipboardMetadata(entries: unknown): ClipboardMetadata[];
export function terminalHereCapability(provider: WorkflowProvider): { supported: boolean; profile: 'powershell' | 'wsl'; reason: string };
export function buildWslCdCommand(path: string[]): string;
export function snapBounds(side: 'left' | 'right', viewportWidth: number, viewportHeight: number, reservedTop?: number, reservedBottom?: number): { x: number; y: number; width: number; height: number };
export function matchesWorkflowQuery(value: unknown, query: unknown): boolean;
