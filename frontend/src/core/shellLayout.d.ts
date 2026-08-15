export type TaskbarPosition = 'top' | 'right' | 'bottom' | 'left';
export type ShellRect = { x: number; y: number; width: number; height: number };
export type ShellViewport = { width: number; height: number };

export const TASKBAR_SIZE: number;
export function normalizeTaskbarPosition(value: unknown): TaskbarPosition;
export function calculateShellLayout(
  viewport: Partial<ShellViewport> | null | undefined,
  requestedPosition?: unknown,
  requestedTaskbarSize?: number,
): { position: TaskbarPosition; taskbar: ShellRect; desktop: ShellRect };
