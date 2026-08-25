import type { NativeSession, NativeViewportBounds } from './nativeHostBridge';

export interface ViewportSize {
  width: number;
  height: number;
}

export interface NativeSurfaceLayoutState {
  bounds: NativeViewportBounds;
  visible: boolean;
}

export function nativeViewportBounds(
  rect: Pick<DOMRectReadOnly, 'x' | 'y' | 'left' | 'top' | 'width' | 'height'>,
  viewport: ViewportSize
): NativeViewportBounds | null;

export function nativeSurfaceLayoutChanged(
  previous: NativeSurfaceLayoutState | null,
  bounds: NativeViewportBounds | null,
  visible: boolean
): boolean;

export function nativeSessionForLaunch(
  sessions: NativeSession[],
  launch: { pid: number; sessionId?: string | null }
): NativeSession | null;
