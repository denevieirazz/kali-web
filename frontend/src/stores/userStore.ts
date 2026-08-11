import { create } from 'zustand';
import type { UserProfile } from '../types';
import { apiClient, getStoredToken, setStoredToken, getStoredUser, setStoredUser, clearStoredAuth, setUnauthorizedHandler } from '../services/apiClient';

interface UserState {
  currentUser: UserProfile | null;
  isAuthenticated: boolean;
  isCheckingSession: boolean;
  setupRequired: boolean;
  
  // Actions
  checkSetupStatus: () => Promise<boolean>;
  login: (username: string, password: string) => Promise<{ success: boolean; message?: string }>;
  createAdmin: (username: string, password: string, confirmPassword: string) => Promise<{ success: boolean; message?: string }>;
  logout: () => Promise<void>;
  validateSession: () => Promise<boolean>;
  resetLocalInstallation: () => Promise<boolean>;
  createProfile: (profile: Omit<UserProfile, 'lastLogin'>) => void;
}

export const useUserStore = create<UserState>((set, get) => {
  setUnauthorizedHandler(() => {
    set({ currentUser: null, isAuthenticated: false });
  });

  return {
    currentUser: getStoredUser() as UserProfile | null,
    isAuthenticated: !!getStoredToken(),
    isCheckingSession: false,
    setupRequired: false,

    checkSetupStatus: async () => {
      try {
        const res = await apiClient<{ setupRequired: boolean }>('/api/setup/status', { skipAuth: true });
        const required = !!(res && res.setupRequired);
        set({ setupRequired: required });
        return required;
      } catch (err) {
        return false;
      }
    },

    createAdmin: async (username, password, confirmPassword) => {
      try {
        const res = await apiClient<{ token: string; user: any }>('/api/setup/admin', {
          method: 'POST',
          body: JSON.stringify({ username, password, confirmPassword }),
          skipAuth: true
        });

        if (res && res.token) {
          setStoredToken(res.token);
          const profile: UserProfile = {
            username: res.user.username,
            displayName: res.user.username,
            avatar: `https://api.dicebear.com/7.x/avataaars/svg?seed=${res.user.username}`,
            password: '',
            isAdmin: true,
            lastLogin: Date.now()
          };
          setStoredUser(profile);
          set({ currentUser: profile, isAuthenticated: true, setupRequired: false });
          return { success: true };
        }
        return { success: false, message: 'Resposta inválida do servidor.' };
      } catch (err: any) {
        return { success: false, message: err.message || 'Falha ao criar conta de administrador.' };
      }
    },

    login: async (username, password) => {
      try {
        const res = await apiClient<{ token: string; user: any }>('/api/auth/login', {
          method: 'POST',
          body: JSON.stringify({ username, password }),
          skipAuth: true
        });

        if (res && res.token) {
          setStoredToken(res.token);
          const profile: UserProfile = {
            username: res.user.username || username,
            displayName: res.user.username || username,
            avatar: `https://api.dicebear.com/7.x/avataaars/svg?seed=${res.user.username || username}`,
            password: '',
            isAdmin: res.user.role === 'admin',
            lastLogin: Date.now()
          };
          setStoredUser(profile);
          set({ currentUser: profile, isAuthenticated: true });
          return { success: true };
        }
        return { success: false, message: 'Credenciais inválidas.' };
      } catch (err: any) {
        return { success: false, message: 'Credenciais inválidas.' };
      }
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
        const res = await apiClient<{ authenticated: boolean; user: any }>('/api/auth/session');
        if (res && res.authenticated) {
          const profile: UserProfile = {
            username: res.user.username,
            displayName: res.user.username,
            avatar: `https://api.dicebear.com/7.x/avataaars/svg?seed=${res.user.username}`,
            password: '',
            isAdmin: res.user.role === 'admin',
            lastLogin: Date.now()
          };
          setStoredUser(profile);
          set({ currentUser: profile, isAuthenticated: true, isCheckingSession: false, setupRequired: false });
          return true;
        }
      } catch (err) {
        clearStoredAuth();
        set({ currentUser: null, isAuthenticated: false, isCheckingSession: false });
      }
      await get().checkSetupStatus();
      return false;
    },

    logout: async () => {
      try {
        await apiClient('/api/auth/logout', { method: 'POST' });
      } catch (e) {
      } finally {
        clearStoredAuth();
        set({ currentUser: null, isAuthenticated: false });
        await get().checkSetupStatus();
      }
    },

    resetLocalInstallation: async () => {
      try {
        await apiClient('/api/setup/reset', {
          method: 'POST',
          body: JSON.stringify({ confirm: true }),
          skipAuth: true
        });
        clearStoredAuth();
        set({ currentUser: null, isAuthenticated: false, setupRequired: true });
        return true;
      } catch (e) {
        return false;
      }
    },

    createProfile: (profileData) => {
      const profile: UserProfile = {
        ...profileData,
        lastLogin: Date.now()
      };
      set({ currentUser: profile });
    }
  };
});
