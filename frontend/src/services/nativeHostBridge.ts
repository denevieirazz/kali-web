import { getStoredToken } from './apiClient';

type NativeRequestMethod =
  | 'bridge.handshake'
  | 'host.getState'
  | 'host.setFullscreen'
  | 'host.requestClose'
  | 'host.requestLegacyRecoveryToken'
  | 'native.launchApp'
  | 'native.sessions.list'
  | 'native.session.focus'
  | 'native.session.minimize'
  | 'native.session.maximize'
  | 'native.session.restore'
  | 'native.session.close';

export interface NativeSession {
  sessionId: string;
  title: string;
  processId: number;
  minimized: boolean;
  maximized: boolean;
  bounds: { x: number; y: number; width: number; height: number };
}

export interface NativeHostState {
  nativeHost: boolean;
  fullscreen: boolean;
  kiosk: boolean;
  managedWindows: boolean;
  embeddedNativeWindows: boolean;
  platform: string;
  version: string;
}

interface NativeResponse<T> {
  v: 1;
  id: string;
  type: 'response';
  ok: boolean;
  result?: T;
  error?: { code: string; message: string };
}

interface WebViewMessageTransport {
  postMessage(message: unknown): void;
  addEventListener(type: 'message', listener: (event: MessageEvent) => void): void;
  removeEventListener(type: 'message', listener: (event: MessageEvent) => void): void;
}

declare global {
  interface Window {
    chrome?: { webview?: WebViewMessageTransport };
    __cloudosNativeNonce?: string;
  }
}

class NativeHostBridge {
  private transport: WebViewMessageTransport | null = null;
  private pending = new Map<string, { resolve: (value: unknown) => void; reject: (reason: Error) => void; timer: number }>();
  private eventListeners = new Set<(sessions: NativeSession[]) => void>();
  private connectPromise: Promise<boolean> | null = null;
  private listening = false;
  private ready = false;

  readonly available = Boolean(window.chrome?.webview && window.__cloudosNativeNonce);

  async connect() {
    if (!this.available || this.ready) return this.ready;
    if (this.connectPromise) return this.connectPromise;
    this.ensureTransport();
    const connection = this.request('bridge.handshake', {})
      .then(() => {
        this.ready = true;
        return true;
      })
      .finally(() => {
        this.connectPromise = null;
      });
    this.connectPromise = connection;
    return connection;
  }

  async getHostState() {
    if (!this.available) throw new Error('O host nativo do CloudOS não está ativo.');
    await this.connect();
    return this.request<NativeHostState>('host.getState', {});
  }

  async requestLegacyRecoveryToken() {
    if (!this.available) throw new Error('O host nativo do CloudOS não está ativo.');
    await this.connect();
    return this.request<{ token: string; expiresIn: number }>('host.requestLegacyRecoveryToken', {});
  }

  async launchApp(appId: string) {
    const token = getStoredToken();
    if (!token) throw new Error('Entre no CloudOS para abrir aplicativos nativos.');
    return this.request<{
      name: string;
      source: string;
      distribution: string | null;
      pid: number;
      windowMode: string;
      managed: boolean;
      managementReason: string | null;
    }>('native.launchApp', { appId, token }, 40_000);
  }

  listSessions() {
    return this.request<{ sessions: NativeSession[] }>('native.sessions.list', {});
  }

  operate(method: 'focus' | 'minimize' | 'maximize' | 'restore' | 'close', sessionId: string) {
    return this.request(`native.session.${method}` as NativeRequestMethod, { sessionId });
  }

  onSessionsChanged(listener: (sessions: NativeSession[]) => void) {
    this.eventListeners.add(listener);
    return () => this.eventListeners.delete(listener);
  }

  private request<T = unknown>(method: NativeRequestMethod, params: Record<string, unknown>, timeoutMs = 10_000): Promise<T> {
    if (!this.available) return Promise.reject(new Error('O host nativo do CloudOS não está ativo.'));
    this.ensureTransport();
    const id = crypto.randomUUID();
    return new Promise<T>((resolve, reject) => {
      const timer = window.setTimeout(() => {
        this.pending.delete(id);
        reject(new Error('A operação nativa excedeu o tempo limite.'));
      }, timeoutMs);
      this.pending.set(id, { resolve: resolve as (value: unknown) => void, reject, timer });
      this.transport!.postMessage({
        v: 1,
        id,
        type: 'request',
        method,
        nonce: window.__cloudosNativeNonce,
        params
      });
    });
  }

  private ensureTransport() {
    this.transport ??= window.chrome!.webview!;
    if (!this.listening) {
      this.transport.addEventListener('message', this.onMessage);
      this.listening = true;
    }
  }

  private onMessage = (event: MessageEvent) => {
    const message = event.data as NativeResponse<unknown> | { v: 1; type: 'event'; event: string; data?: { sessions?: NativeSession[] } };
    if (!message || message.v !== 1) return;
    if (message.type === 'event' && message.event === 'native.sessionsChanged') {
      const sessions = message.data?.sessions || [];
      this.eventListeners.forEach(listener => listener(sessions));
      return;
    }
    if (message.type !== 'response') return;
    const pending = this.pending.get(message.id);
    if (!pending) return;
    window.clearTimeout(pending.timer);
    this.pending.delete(message.id);
    if (message.ok) pending.resolve(message.result);
    else pending.reject(new Error(message.error?.message || 'O host nativo recusou a operação.'));
  };
}

export const nativeHostBridge = new NativeHostBridge();
