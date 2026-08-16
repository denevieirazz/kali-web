export const TERMINAL_MIN_HOST_WIDTH: number;
export const TERMINAL_MIN_HOST_HEIGHT: number;
export function hasUsableTerminalGeometry(host: { isConnected?: boolean; clientWidth?: number; clientHeight?: number; getBoundingClientRect?: () => { width: number; height: number } } | null | undefined): boolean;
export function sanitizeTerminalLifecycleError(error: unknown): string;
export class TerminalFrameScheduler {
  constructor(options: { requestFrame?: (cb: FrameRequestCallback) => number; cancelFrame?: (id: number) => void; task: () => void });
  schedule(): void;
  dispose(): void;
}
export function waitForTerminalGeometry(host: HTMLElement, options?: { requestFrame?: (cb: FrameRequestCallback) => number; maxFrames?: number; cancelled?: () => boolean }): Promise<boolean>;
