// Centralized HTTP/WebSocket client for the local CloudOS agent.

export interface RequestOptions extends RequestInit {
  timeoutMs?: number;
  skipAuth?: boolean;
  suppressUnauthorizedHandler?: boolean;
}

export interface CloudOSRuntimeConfig {
  apiBase?: string;
  webSocketBase?: string;
}

export interface ApiEventStreamOptions<T> {
  signal?: AbortSignal;
  skipAuth?: boolean;
  onEvent: (event: T) => void | Promise<void>;
}

declare global {
  interface Window {
    __CLOUDOS_RUNTIME__?: CloudOSRuntimeConfig;
  }
}

const TOKEN_KEY = 'cloudos_jwt_token';
const USER_KEY = 'cloudos_user_info';
const PRIVATE_USER_FIELD = /(?:password|recovery|secret|token|credential)/i;

let isHandlingUnauthorized = false;
let onUnauthorizedCallback: (() => void) | null = null;

export function setUnauthorizedHandler(handler: () => void) {
  onUnauthorizedCallback = handler;
}

export function getStoredToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}

export function setStoredToken(token: string) {
  localStorage.setItem(TOKEN_KEY, token);
}

function sanitizeStoredUser(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const clean: Record<string, unknown> = {};
  for (const [key, fieldValue] of Object.entries(value)) {
    if (!PRIVATE_USER_FIELD.test(key)) clean[key] = fieldValue;
  }
  return clean;
}

export function getStoredUser(): Record<string, unknown> | null {
  try {
    const raw = localStorage.getItem(USER_KEY);
    if (!raw) return null;
    const clean = sanitizeStoredUser(JSON.parse(raw));
    if (!clean) {
      localStorage.removeItem(USER_KEY);
      return null;
    }
    localStorage.setItem(USER_KEY, JSON.stringify(clean));
    return clean;
  } catch {
    localStorage.removeItem(USER_KEY);
    return null;
  }
}

export function setStoredUser(user: unknown) {
  const clean = sanitizeStoredUser(user);
  if (!clean) {
    localStorage.removeItem(USER_KEY);
    return;
  }
  localStorage.setItem(USER_KEY, JSON.stringify(clean));
}

export function clearStoredAuth() {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(USER_KEY);
}

function normalizedBase(value: unknown, protocols: string[]) {
  if (typeof value !== 'string' || !value.trim()) return null;
  try {
    const url = new URL(value.trim(), window.location.origin);
    if (!protocols.includes(url.protocol) || url.username || url.password) return null;
    return url.href.replace(/\/$/, '');
  } catch {
    return null;
  }
}

export function getApiBase() {
  return normalizedBase(window.__CLOUDOS_RUNTIME__?.apiBase, ['http:', 'https:']) || window.location.origin;
}

export function getWebSocketBase() {
  const injected = normalizedBase(window.__CLOUDOS_RUNTIME__?.webSocketBase, ['ws:', 'wss:']);
  if (injected) return injected;
  const api = new URL(getApiBase());
  api.protocol = api.protocol === 'https:' ? 'wss:' : 'ws:';
  return api.href.replace(/\/$/, '');
}

export function resolveApiUrl(endpoint: string) {
  if (/^https?:\/\//i.test(endpoint)) return endpoint;
  const path = endpoint.startsWith('/') ? endpoint : `/${endpoint}`;
  return `${getApiBase()}${path}`;
}

export function resolveWebSocketUrl(endpoint: string) {
  if (/^wss?:\/\//i.test(endpoint)) return endpoint;
  const path = endpoint.startsWith('/') ? endpoint : `/${endpoint}`;
  return `${getWebSocketBase()}${path}`;
}

function handleUnauthorizedStatus(status: number) {
  if (!isHandlingUnauthorized) {
    isHandlingUnauthorized = true;
    clearStoredAuth();
    onUnauthorizedCallback?.();
    window.setTimeout(() => { isHandlingUnauthorized = false; }, 2000);
  }
  throw new Error(`Sessão não autorizada ou expirada (${status}).`);
}

async function responseError(response: Response) {
  const errorText = await response.text();
  let errorMessage = `Erro ${response.status}: ${response.statusText}`;
  try {
    const parsed = JSON.parse(errorText) as { error?: unknown; message?: unknown };
    if (typeof parsed.error === 'string') errorMessage = parsed.error;
    else if (typeof parsed.message === 'string') errorMessage = parsed.message;
  } catch {
    // Preserve the HTTP status when the body is not JSON.
  }
  return new Error(errorMessage);
}

export async function streamApiEvents<T = unknown>(endpoint: string, options: ApiEventStreamOptions<T>): Promise<void> {
  const headers = new Headers({ Accept: 'text/event-stream' });
  if (!options.skipAuth) {
    const token = getStoredToken();
    if (token) headers.set('Authorization', `Bearer ${token}`);
  }

  const response = await fetch(resolveApiUrl(endpoint), {
    method: 'GET',
    headers,
    signal: options.signal,
  });

  if (response.status === 401 || response.status === 403) handleUnauthorizedStatus(response.status);
  if (!response.ok) throw await responseError(response);
  if (!response.body) throw new Error('O servidor não forneceu o stream de provisionamento.');

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  const consumeFrame = async (frame: string) => {
    const dataLines = frame
      .split(/\r?\n/)
      .filter(line => line.startsWith('data:'))
      .map(line => line.slice(5).trimStart());
    if (dataLines.length === 0) return;
    const payload = dataLines.join('\n');
    await options.onEvent(JSON.parse(payload) as T);
  };

  try {
    while (true) {
      const { value, done } = await reader.read();
      buffer += decoder.decode(value, { stream: !done });
      let boundary = buffer.search(/\r?\n\r?\n/);
      while (boundary >= 0) {
        const frame = buffer.slice(0, boundary);
        const separator = buffer.slice(boundary).match(/^\r?\n\r?\n/)?.[0] || '\n\n';
        buffer = buffer.slice(boundary + separator.length);
        await consumeFrame(frame);
        boundary = buffer.search(/\r?\n\r?\n/);
      }
      if (done) break;
    }
    if (buffer.trim()) await consumeFrame(buffer);
  } finally {
    reader.releaseLock();
  }
}

export async function apiClient<T = unknown>(endpoint: string, options: RequestOptions = {}): Promise<T> {
  const {
    timeoutMs = 10000,
    skipAuth = false,
    suppressUnauthorizedHandler = false,
    headers: customHeaders,
    signal: externalSignal,
    ...request
  } = options;

  const controller = new AbortController();
  let timedOut = false;
  const timeoutId = window.setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, Math.max(1, timeoutMs));

  const forwardExternalAbort = () => controller.abort(externalSignal?.reason);
  if (externalSignal?.aborted) {
    forwardExternalAbort();
  } else {
    externalSignal?.addEventListener('abort', forwardExternalAbort, { once: true });
  }

  const headers = new Headers(customHeaders);
  if (!headers.has('Accept')) headers.set('Accept', 'application/json');
  if (request.body !== undefined && request.body !== null && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }

  if (!skipAuth) {
    const token = getStoredToken();
    if (token) headers.set('Authorization', `Bearer ${token}`);
  }

  try {
    const response = await fetch(resolveApiUrl(endpoint), {
      ...request,
      headers,
      signal: controller.signal,
    });

    if ((response.status === 401 || response.status === 403) && !suppressUnauthorizedHandler) {
      handleUnauthorizedStatus(response.status);
    }

    if (!response.ok) throw await responseError(response);

    if (response.status === 204) return undefined as T;
    const contentType = response.headers.get('content-type') ?? '';
    if (contentType.includes('application/json')) return await response.json() as T;
    return await response.text() as T;
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') {
      if (timedOut) {
        throw new Error(`Requisição para ${endpoint} excedeu o tempo limite de ${timeoutMs}ms.`);
      }
      throw new Error(`Requisição para ${endpoint} foi cancelada.`);
    }
    throw error;
  } finally {
    window.clearTimeout(timeoutId);
    externalSignal?.removeEventListener('abort', forwardExternalAbort);
  }
}
