// ============================================
// Centralized API Client — CloudOS-Unified
// ============================================

interface RequestOptions extends RequestInit {
  timeoutMs?: number;
  skipAuth?: boolean;
  suppressUnauthorizedHandler?: boolean;
}

export interface CloudOSRuntimeConfig {
  apiBase?: string;
  webSocketBase?: string;
}

declare global {
  interface Window {
    __CLOUDOS_RUNTIME__?: CloudOSRuntimeConfig;
  }
}

const TOKEN_KEY = 'cloudos_jwt_token';
const USER_KEY = 'cloudos_user_info';

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

export function getStoredUser(): any | null {
  try {
    const raw = localStorage.getItem(USER_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object') return null;
    const clean = { ...parsed };
    for (const key of Object.keys(clean)) {
      if (/(?:password|recovery|secret|token|credential)/i.test(key)) delete clean[key];
    }
    localStorage.setItem(USER_KEY, JSON.stringify(clean));
    return clean;
  } catch {
    localStorage.removeItem(USER_KEY);
    return null;
  }
}

export function setStoredUser(user: any) {
  if (!user || typeof user !== 'object') {
    localStorage.removeItem(USER_KEY);
    return;
  }
  const clean = { ...user };
  for (const key of Object.keys(clean)) {
    if (/(?:password|recovery|secret|token|credential)/i.test(key)) delete clean[key];
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

export async function apiClient<T = any>(endpoint: string, options: RequestOptions = {}): Promise<T> {
  const { timeoutMs = 10000, skipAuth = false, suppressUnauthorizedHandler = false, headers: customHeaders, ...rest } = options;

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...(customHeaders as Record<string, string>)
  };

  if (!skipAuth) {
    const token = getStoredToken();
    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
    }
  }

  try {
    const response = await fetch(resolveApiUrl(endpoint), {
      ...rest,
      headers,
      signal: controller.signal
    });

    clearTimeout(timeoutId);

    if ((response.status === 401 || response.status === 403) && !suppressUnauthorizedHandler) {
      if (!isHandlingUnauthorized) {
        isHandlingUnauthorized = true;
        clearStoredAuth();
        if (onUnauthorizedCallback) {
          onUnauthorizedCallback();
        }
        setTimeout(() => { isHandlingUnauthorized = false; }, 2000);
      }
      throw new Error(`Sessão não autorizada ou expirada (${response.status}).`);
    }

    if (!response.ok) {
      const errorText = await response.text();
      let errorMsg = `Erro ${response.status}: ${response.statusText}`;
      try {
        const errJson = JSON.parse(errorText);
        if (errJson.error) errorMsg = errJson.error;
        else if (errJson.message) errorMsg = errJson.message;
      } catch {}
      throw new Error(errorMsg);
    }

    const contentType = response.headers.get('content-type');
    if (contentType && contentType.includes('application/json')) {
      return await response.json();
    }
    return (await response.text()) as unknown as T;

  } catch (error: any) {
    clearTimeout(timeoutId);
    if (error.name === 'AbortError') {
      throw new Error(`Requisição para ${endpoint} excedeu o tempo limite de ${timeoutMs}ms.`);
    }
    throw error;
  }
}
