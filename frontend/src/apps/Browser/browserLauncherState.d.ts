import type { NativeBrowserOpenResult } from '../../services/nativeHostBridge';

export type BrowserLauncherStatus = 'opening' | 'success' | 'error';

export interface BrowserLauncherState {
  status: BrowserLauncherStatus;
  code: string | null;
  message: string;
  shouldClose: boolean;
}

export function browserLauncherOpening(): BrowserLauncherState;
export function browserLauncherSuccess(result: NativeBrowserOpenResult | null | undefined): BrowserLauncherState;
export function browserLauncherFailure(error: unknown): BrowserLauncherState;
