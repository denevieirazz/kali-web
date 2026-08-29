export interface NativeShellApp {
  id: string;
  name: string;
  description: string;
  category: number;
}

export interface NativeShellWindow {
  hwnd: string;
  pid: number;
  title: string;
  floating: boolean;
  active: boolean;
}

export interface NativeShellStats {
  cpuAvailable: boolean;
  cpuPercent: number;
  ramAvailable: boolean;
  ramPercent: number;
  ramUsedMb: number;
  ramTotalMb: number;
  diskAvailable: boolean;
  diskFreeGb: number;
  diskTotalGb: number;
  uptime: string;
}

export interface NativeShellState {
  type: 'cloudos.state';
  native: true;
  workspace: number;
  tiling: boolean;
  managedWindowCount: number;
  stats: NativeShellStats;
  apps: NativeShellApp[];
  windows: NativeShellWindow[];
}

export interface NativeShellEvent {
  type: 'cloudos.event';
  event: string;
}

export type NativeShellMessage = NativeShellState | NativeShellEvent;

type WebViewMessageHandler = (event: { data: unknown }) => void;

interface CloudOSWebViewBridge {
  postMessage(message: string): void;
  addEventListener(type: 'message', handler: WebViewMessageHandler): void;
  removeEventListener(type: 'message', handler: WebViewMessageHandler): void;
}

function webView(): CloudOSWebViewBridge | undefined {
  const candidate = (window as unknown as {
    chrome?: { webview?: CloudOSWebViewBridge };
  }).chrome?.webview;
  return candidate;
}

export function isNativeShellWebView(): boolean {
  return Boolean(webView());
}

export function sendNativeCommand(command: string): boolean {
  const bridge = webView();
  if (!bridge || !command || command.length > 512) return false;
  bridge.postMessage(command);
  return true;
}

export function requestNativeState(): void {
  sendNativeCommand('state.request');
}

export function subscribeNativeShell(
  listener: (message: NativeShellMessage) => void,
): () => void {
  const bridge = webView();
  if (!bridge) return () => undefined;

  const handler: WebViewMessageHandler = (event) => {
    const data = event.data;
    if (!data || typeof data !== 'object') return;
    const type = (data as { type?: unknown }).type;
    if (type !== 'cloudos.state' && type !== 'cloudos.event') return;
    listener(data as NativeShellMessage);
  };

  bridge.addEventListener('message', handler);
  return () => bridge.removeEventListener('message', handler);
}
