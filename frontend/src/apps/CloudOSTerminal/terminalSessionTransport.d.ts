export type TerminalTransportState = 'connecting' | 'connected' | 'closing' | 'closed' | 'failed' | 'legacy-fallback';
export interface TerminalTransportStatus {
  state: TerminalTransportState;
  label: string;
  mode?: string | null;
}
export interface TerminalTransportSnapshot extends TerminalTransportStatus {
  ready: boolean;
  cols: number;
  rows: number;
}
export interface TerminalTransport {
  readonly snapshot: TerminalTransportSnapshot;
  input(data: string): boolean;
  resize(cols: number, rows: number): boolean;
  signal(signal: 'interrupt' | 'terminate' | 'hangup'): boolean;
  close(): void;
  dispose(): void;
}
export const WSL_CORE_MODE: 'wsl-core-v2';
export const LEGACY_MODE: 'legacy-pty';
export const EMULATOR_MODE: 'emulator';
export const WSL_CORE_PROTOCOL: 2;
export const WSL_CORE_PROTECTION: 'aes-256-gcm-seq';
export function sanitizeTerminalError(value: unknown): string;
export function createTerminalTransport(options: {
  socket: WebSocket;
  profile: 'wsl' | 'powershell';
  distribution?: string;
  initialCols?: number;
  initialRows?: number;
  onOutput?: (data: string) => void;
  onStatus?: (status: TerminalTransportStatus) => void;
  onExit?: (detail: { exitCode: number | null; signal: string }) => void;
  onNotice?: (notice: { tone: 'warning' | 'error'; message: string }) => void;
}): TerminalTransport;
