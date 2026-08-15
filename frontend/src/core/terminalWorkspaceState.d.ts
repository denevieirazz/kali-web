export type TerminalProfile = 'powershell' | 'wsl';
export interface TerminalTabState {
  id: string;
  profile: TerminalProfile;
  distribution: string;
}
export interface TerminalWorkspaceState {
  tabs: TerminalTabState[];
  activeId: string;
  splitId: string | null;
}

export const MAX_TERMINAL_TABS: number;
export const TERMINAL_WORKSPACE_STORAGE_KEY: string;
export function createTerminalTab(profile?: TerminalProfile, distribution?: string, id?: string): TerminalTabState;
export function normalizeTerminalWorkspace(value: unknown, fallbackTab?: TerminalTabState): TerminalWorkspaceState;
export function addTerminalTab(workspace: TerminalWorkspaceState, tab: TerminalTabState): TerminalWorkspaceState;
export function updateTerminalTab(workspace: TerminalWorkspaceState, tabId: string, updates: Partial<Omit<TerminalTabState, 'id'>>): TerminalWorkspaceState;
export function closeTerminalTab(workspace: TerminalWorkspaceState, tabId: string, fallbackTab?: TerminalTabState): TerminalWorkspaceState;
export function activateTerminalTab(workspace: TerminalWorkspaceState, tabId: string): TerminalWorkspaceState;
export function toggleTerminalSplit(workspace: TerminalWorkspaceState): TerminalWorkspaceState;
export function cycleTerminalTab(workspace: TerminalWorkspaceState, direction?: number): TerminalWorkspaceState;
export function serializableTerminalWorkspace(workspace: TerminalWorkspaceState): TerminalWorkspaceState;
