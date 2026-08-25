import { getStoredToken } from './apiClient';

type NativeRequestMethod =
  | 'bridge.handshake'
  | 'host.getState'
  | 'host.setFullscreen'
  | 'host.requestClose'
  | 'host.requestLegacyRecoveryToken'
  | 'browser.open'
  | 'native.launchApp'
  | 'native.sessions.list'
  | 'native.session.attach'
  | 'native.session.layout'
  | 'native.session.focus'
  | 'native.session.minimize'
  | 'native.session.maximize'
  | 'native.session.restore'
  | 'native.session.close';

export class NativeHostError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.name = 'NativeHostError';
    this.code = code;
  }
}

export interface NativeBrowserOpenResult {
  opened: boolean;
  reused?: boolean;
  windowVisible?: boolean;
  code?: string;
  message?: string;
}

export interface NativeViewportBounds {
  x: number;
  y: number;
  width: number;
  height: number;
}

export type NativeContainmentMode = 'anchored-overlay' | 'hidden-quarantine' | 'terminated';

export interface NativeSession {
  sessionId: string;
  title: string;
  processId: number;
  minimized: boolean;
  maximized: boolean;
  bounds: NativeViewportBounds;
  contained?: boolean;
  containmentMode?: NativeContainmentMode;
  visible?: boolean;
}

export interface NativeHostState {
  nativeHost: boolean;
  fullscreen: boolean;
  kiosk: boolean;
  managedWindows: boolean;
  embeddedNativeWindows: boolean;
  nativeWindowContainment?: NativeContainmentMode;
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

  private async requireConnection(message = 'O host nativo do CloudOS não está ativo.') {
    if (!this.available) throw new NativeHostError('NATIVE_HOST_UNAVAILABLE', message);
    const connected = await this.connect();
    if (!connected) throw new NativeHostError('NATIVE_HOST_UNAVAILABLE', message);
  }

  async getHostState() {
    await this.requireConnection();
    return this.request<NativeHostState>('host.getState', {});
  }

  async requestLegacyRecoveryToken() {
    await this.requireConnection();
    return this.request<{ token: string; expiresIn: number }>('host.requestLegacyRecoveryToken', {});
  }

  async openBrowser(url?: string): Promise<NativeBrowserOpenResult> {
    await this.requireConnection('O Navegador CloudOS requer o Host nativo.');
    const result = await this.request<NativeBrowserOpenResult>('browser.open', url ? { url } : {}, 30_000);
    if (!result?.opened) {
      throw new NativeHostError(
        result?.code || 'BROWSER_OPEN_FAILED',
        result?.message || 'A janela nativa do Navegador não pôde ser aberta.'
      );
    }
    if (result.windowVisible !== true) {
      throw new NativeHostError(
        'BROWSER_WINDOW_NOT_VISIBLE',
        'O Host respondeu, mas a janela nativa do Navegador não ficou visível.'
      );
    }
    return result;
  }

  async launchApp(appId: string) {
    const token = getStoredToken();
    if (!token) throw new NativeHostError('AUTH_REQUIRED', 'Entre no CloudOS para abrir aplicativos nativos.');
    await this.requireConnection();
    return this.request<{
      name: string;
      source: string;
      distribution: string | null;
      pid: number;
      windowMode: string;
      managed: boolean;
      managementReason: string | null;
      sessionId?: string | null;
      contained?: boolean;
      containmentMode?: NativeContainmentMode;
    }>('native.launchApp', { appId, token }, 40_000);
  }

  async listSessions() {
    await this.requireConnection();
    return this.request<{ sessions: NativeSession[] }>('native.sessions.list', {});
  }

  async operate(method: 'focus' | 'minimize' | 'maximize' | 'restore' | 'close', sessionId: string) {
    await this.requireConnection();
    return this.request(`native.session.${method}` as NativeRequestMethod, { sessionId });
  }

  async attachSession(sessionId: string, bounds: NativeViewportBounds) {
    await this.requireConnection();
    return this.request<{ sessionId: string; accepted: boolean; contained?: boolean; containmentMode?: NativeContainmentMode }>('native.session.attach', { sessionId, bounds });
  }

  async layoutSession(sessionId: string, bounds: NativeViewportBounds, visible: boolean) {
    await this.requireConnection();
    return this.request<{ sessionId: string; accepted: boolean; contained?: boolean; containmentMode?: NativeContainmentMode; visible?: boolean }>('native.session.layout', { sessionId, bounds, visible });
  }

  onSessionsChanged(listener: (sessions: NativeSession[]) => void) {
    this.eventListeners.add(listener);
    return () => this.eventListeners.delete(listener);
  }

  private request<T = unknown>(method: NativeRequestMethod, params: Record<string, unknown>, timeoutMs = 10_000): Promise<T> {
    if (!this.available) return Promise.reject(new NativeHostError('NATIVE_HOST_UNAVAILABLE', 'O host nativo do CloudOS não está ativo.'));
    this.ensureTransport();
    const id = crypto.randomUUID();
    return new Promise<T>((resolve, reject) => {
      const timer = window.setTimeout(() => {
        this.pending.delete(id);
        reject(new NativeHostError('NATIVE_TIMEOUT', 'A operação nativa excedeu o tempo limite.'));
      }, timeoutMs);
      this.pending.set(id, { resolve: resolve as (value: unknown) => void, reject, timer });
      try {
        this.transport!.postMessage({ v: 1, id, type: 'request', method, nonce: window.__cloudosNativeNonce, params });
      } catch (postError) {
        window.clearTimeout(timer);
        this.pending.delete(id);
        reject(new NativeHostError(
          'NATIVE_TRANSPORT_FAILED',
          postError instanceof Error ? postError.message : 'A ponte nativa não aceitou a solicitação.'
        ));
      }
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
      for (const listener of this.eventListeners) {
        try {
          listener(sessions);
        } catch {
          // One renderer listener must not prevent other native windows from receiving state updates.
        }
      }
      return;
    }
    if (message.type !== 'response') return;
    const pending = this.pending.get(message.id);
    if (!pending) return;
    window.clearTimeout(pending.timer);
    this.pending.delete(message.id);
    if (message.ok) pending.resolve(message.result);
    else pending.reject(new NativeHostError(
      message.error?.code || 'NATIVE_REQUEST_DENIED',
      message.error?.message || 'O host nativo recusou a operação.'
    ));
  };
}

export const nativeHostBridge = new NativeHostBridge();
