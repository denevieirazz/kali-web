import { create } from 'zustand';
import type { UserProfile } from '../types';
import {
  apiClient,
  clearStoredAuth,
  getStoredToken,
  getStoredUser,
  setStoredToken,
  setStoredUser,
  setUnauthorizedHandler
} from '../services/apiClient';
import {
  ACCOUNT_RECOVERY_ENDPOINT,
  canRestoreAuthenticatedSession,
  extractRecoveryCode,
  normalizePublicUser,
  recoveryRequestBody,
  sanitizePersistedProfile
} from '../services/accountContract.js';

export type SetupStatus = 'checking' | 'required' | 'complete' | 'unavailable';
type ActionResult = { success: boolean; message?: string; recoveryCode?: string };
type CreateAccountResult = ActionResult & { user?: UserProfile };
export type RecoveryResult = ActionResult & { recoveryCode?: string };
const RECOVERY_CONFIRMATION_PENDING_KEY = 'cloudos_recovery_confirmation_pending';

function markRecoveryConfirmationPending() {
  localStorage.setItem(RECOVERY_CONFIRMATION_PENDING_KEY, 'true');
}

function hasPendingRecoveryConfirmation() {
  return localStorage.getItem(RECOVERY_CONFIRMATION_PENDING_KEY) === 'true';
}

function clearRecoveryConfirmationPending() {
  localStorage.removeItem(RECOVERY_CONFIRMATION_PENDING_KEY);
}

interface UserState {
  currentUser: UserProfile | null;
  isAuthenticated: boolean;
  isCheckingSession: boolean;
  setupRequired: boolean;
  setupStatus: SetupStatus;
  setupStatusMessage: string | null;
  recoveryAvailable: boolean | null;
  recoveryStatusMessage: string | null;
  checkSetupStatus: () => Promise<SetupStatus>;
  checkRecoveryStatus: () => Promise<boolean | null>;
  login: (username: string, password: string) => Promise<ActionResult>;
  createAccount: (username: string, displayName: string, password: string, confirmPassword: string) => Promise<CreateAccountResult>;
  createAdmin: (username: string, displayName: string, password: string, confirmPassword: string) => Promise<RecoveryResult>;
  recoverAccount: (recoveryCode: string, newUsername: string, displayName: string, password: string, confirmPassword: string) => Promise<RecoveryResult>;
  rotateRecoveryCode: () => Promise<RecoveryResult>;
  confirmRecoveryCodeSaved: () => void;
  logout: () => Promise<void>;
  validateSession: () => Promise<boolean>;
  resetLocalInstallation: () => Promise<boolean>;
}

function storeSession(response: { token?: unknown; user?: unknown }, fallback?: { username?: string; displayName?: string }) {
  if (typeof response.token !== 'string' || !response.token) return null;
  const profile = normalizePublicUser(response.user, fallback);
  if (!profile.username) return null;
  setStoredToken(response.token);
  setStoredUser(profile);
  return profile;
}

const persistedProfile = sanitizePersistedProfile(getStoredUser());
if (persistedProfile) setStoredUser(persistedProfile);

export const useUserStore = create<UserState>((set, get) => {
  setUnauthorizedHandler(() => {
    set({ currentUser: null, isAuthenticated: false });
  });

  return {
    currentUser: persistedProfile,
    isAuthenticated: Boolean(getStoredToken()),
    isCheckingSession: false,
    setupRequired: false,
    setupStatus: 'checking',
    setupStatusMessage: null,
    recoveryAvailable: null,
    recoveryStatusMessage: null,

    checkSetupStatus: async () => {
      set({ setupStatus: 'checking', setupStatusMessage: null });
      try {
        const response = await apiClient<{ setupRequired: boolean }>('/api/setup/status', {
          skipAuth: true,
          suppressUnauthorizedHandler: true
        });
        const required = response.setupRequired === true;
        const status: SetupStatus = required ? 'required' : 'complete';
        set((state) => ({
          setupRequired: required,
          setupStatus: status,
          setupStatusMessage: null,
          recoveryAvailable: required ? false : state.recoveryAvailable,
          recoveryStatusMessage: required ? null : state.recoveryStatusMessage
        }));
        return status;
      } catch (error) {
        set({
          setupStatus: 'unavailable',
          setupStatusMessage: error instanceof Error ? error.message : 'O agente local não respondeu.'
        });
        return 'unavailable';
      }
    },

    checkRecoveryStatus: async () => {
      set({ recoveryAvailable: null, recoveryStatusMessage: null });
      try {
        const response = await apiClient<{ available: boolean }>('/api/auth/recovery/status', {
          skipAuth: true,
          suppressUnauthorizedHandler: true
        });
        if (typeof response.available !== 'boolean') throw new Error('Resposta inválida do estado de recuperação.');
        set({ recoveryAvailable: response.available, recoveryStatusMessage: null });
        return response.available;
      } catch (error) {
        set({
          recoveryAvailable: null,
          recoveryStatusMessage: error instanceof Error ? error.message : 'Não foi possível verificar a recuperação.'
        });
        return null;
      }
    },

    createAdmin: async (username, displayName, password, confirmPassword) => {
      try {
        const response = await apiClient<{ token: string; user: unknown; recoveryCode?: string }>('/api/setup/admin', {
          method: 'POST',
          body: JSON.stringify({ username, displayName, password, confirmPassword }),
          skipAuth: true,
          suppressUnauthorizedHandler: true
        });
        const profile = storeSession(response, { username, displayName });
        const recoveryCode = extractRecoveryCode(response);
        markRecoveryConfirmationPending();
        if (!profile || !recoveryCode) {
          clearStoredAuth();
          return { success: false, message: 'O servidor não forneceu uma conta e um código de recuperação válidos.' };
        }
        set({
          currentUser: profile,
          isAuthenticated: true,
          setupRequired: false,
          setupStatus: 'complete',
          setupStatusMessage: null,
          recoveryAvailable: true,
          recoveryStatusMessage: null
        });
        return { success: true, recoveryCode };
      } catch (error) {
        return { success: false, message: error instanceof Error ? error.message : 'Falha ao criar a conta administradora.' };
      }
    },

    login: async (username, password) => {
      try {
        const response = await apiClient<{ token: string; user: unknown; recoveryCode?: string }>('/api/auth/login', {
          method: 'POST',
          body: JSON.stringify({ username, password }),
          skipAuth: true,
          suppressUnauthorizedHandler: true
        });
        const profile = storeSession(response, { username, displayName: username });
        if (!profile) return { success: false, message: 'Resposta inválida do servidor.' };
        let recoveryCode = extractRecoveryCode(response) || undefined;
        if (!recoveryCode && hasPendingRecoveryConfirmation()) {
          const rotated = await apiClient<{ recoveryCode?: string }>('/api/auth/recovery/rotate', {
            method: 'POST',
            body: '{}'
          });
          recoveryCode = extractRecoveryCode(rotated) || undefined;
          if (!recoveryCode) throw new Error('O servidor não retornou o código que ainda precisa ser salvo.');
        }
        if (recoveryCode) markRecoveryConfirmationPending();
        set({
          currentUser: profile,
          isAuthenticated: true,
          setupRequired: false,
          setupStatus: 'complete',
          ...(recoveryCode ? { recoveryAvailable: true, recoveryStatusMessage: null } : {})
        });
        return { success: true, recoveryCode };
      } catch (error) {
        return { success: false, message: error instanceof Error ? error.message : 'Não foi possível entrar.' };
      }
    },

    createAccount: async (username, displayName, password, confirmPassword) => {
      try {
        const response = await apiClient<{ user: unknown }>('/api/auth/accounts', {
          method: 'POST',
          body: JSON.stringify({ username, displayName, password, confirmPassword })
        });
        const user = normalizePublicUser(response.user, { username, displayName });
        if (!user.username) return { success: false, message: 'O servidor não retornou a conta criada.' };
        return { success: true, user };
      } catch (error) {
        return { success: false, message: error instanceof Error ? error.message : 'Não foi possível criar a conta.' };
      }
    },

    recoverAccount: async (recoveryCode, newUsername, displayName, password, confirmPassword) => {
      try {
        const response = await apiClient<{ token: string; user: unknown; recoveryCode?: string }>(ACCOUNT_RECOVERY_ENDPOINT, {
          method: 'POST',
          body: JSON.stringify(recoveryRequestBody({ recoveryCode, username: newUsername, displayName, password, confirmPassword })),
          skipAuth: true,
          suppressUnauthorizedHandler: true
        });
        const profile = storeSession(response, { username: newUsername, displayName });
        const rotatedCode = extractRecoveryCode(response);
        markRecoveryConfirmationPending();
        if (!profile || !rotatedCode) {
          clearStoredAuth();
          return { success: false, message: 'A recuperação terminou sem uma nova credencial de recuperação válida.' };
        }
        set({
          currentUser: profile,
          isAuthenticated: true,
          setupRequired: false,
          setupStatus: 'complete',
          recoveryAvailable: true,
          recoveryStatusMessage: null
        });
        return { success: true, recoveryCode: rotatedCode };
      } catch (error) {
        return { success: false, message: error instanceof Error ? error.message : 'Não foi possível recuperar a conta.' };
      }
    },

    rotateRecoveryCode: async () => {
      try {
        const response = await apiClient<{ recoveryCode?: string }>('/api/auth/recovery/rotate', {
          method: 'POST',
          body: '{}'
        });
        const recoveryCode = extractRecoveryCode(response);
        markRecoveryConfirmationPending();
        if (!recoveryCode) return { success: false, message: 'O servidor não retornou o novo código.' };
        set({ recoveryAvailable: true, recoveryStatusMessage: null });
        return { success: true, recoveryCode };
      } catch (error) {
        return { success: false, message: error instanceof Error ? error.message : 'Não foi possível gerar um novo código.' };
      }
    },

    confirmRecoveryCodeSaved: () => {
      clearRecoveryConfirmationPending();
    },

    validateSession: async () => {
      const token = getStoredToken();
      if (!token) {
        set({ currentUser: null, isAuthenticated: false, isCheckingSession: false });
        await get().checkSetupStatus();
        return false;
      }
      set({ isCheckingSession: true });
      try {
        const response = await apiClient<{ authenticated: boolean; user: unknown }>('/api/auth/session');
        if (!canRestoreAuthenticatedSession(response.authenticated, hasPendingRecoveryConfirmation())) {
          throw new Error('A sessão exige a confirmação de um novo código de recuperação.');
        }
        if (response.authenticated) {
          const profile = normalizePublicUser(response.user);
          if (!profile.username) throw new Error('Sessão sem usuário válido.');
          setStoredUser(profile);
          set({ currentUser: profile, isAuthenticated: true, isCheckingSession: false, setupRequired: false, setupStatus: 'complete' });
          return true;
        }
      } catch {
        clearStoredAuth();
        set({ currentUser: null, isAuthenticated: false, isCheckingSession: false });
      }
      await get().checkSetupStatus();
      return false;
    },

    logout: async () => {
      try {
        await apiClient('/api/auth/logout', { method: 'POST' });
      } catch {
      } finally {
        clearStoredAuth();
        set({ currentUser: null, isAuthenticated: false });
        await get().checkSetupStatus();
      }
    },

    resetLocalInstallation: async () => {
      try {
        await apiClient('/api/setup/reset', { method: 'POST', body: JSON.stringify({ confirm: true }) });
        clearStoredAuth();
        clearRecoveryConfirmationPending();
        set({
          currentUser: null,
          isAuthenticated: false,
          setupRequired: true,
          setupStatus: 'required',
          recoveryAvailable: false,
          recoveryStatusMessage: null
        });
        return true;
      } catch {
        return false;
      }
    }
  };
});
