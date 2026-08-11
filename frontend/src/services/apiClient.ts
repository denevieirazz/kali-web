// ============================================
// Centralized API Client — CloudOS-Unified
// ============================================

interface RequestOptions extends RequestInit {
  timeoutMs?: number;
  skipAuth?: boolean;
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
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

export function setStoredUser(user: any) {
  localStorage.setItem(USER_KEY, JSON.stringify(user));
}

export function clearStoredAuth() {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(USER_KEY);
}

export async function apiClient<T = any>(endpoint: string, options: RequestOptions = {}): Promise<T> {
  const { timeoutMs = 10000, skipAuth = false, headers: customHeaders, ...rest } = options;

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
    const response = await fetch(endpoint, {
      ...rest,
      headers,
      signal: controller.signal
    });

    clearTimeout(timeoutId);

    if (response.status === 401 || response.status === 403) {
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
