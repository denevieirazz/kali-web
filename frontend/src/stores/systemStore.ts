import { create } from 'zustand';
import kernel from '../core/kernel';
import type { NotificationData, SystemTheme, UserProfile } from '../types';

export type BootPhase = 'off' | 'bios' | 'loading' | 'setup' | 'login' | 'desktop';

const MAX_NOTIFICATIONS = 100;

function normalizeBootPhase(phase: unknown): BootPhase {
  const value = String(phase ?? '').toLowerCase();
  if (value === 'winlogon') return 'login';
  if (value === 'oobe') return 'setup';
  if (value === 'desktop_ready') return 'desktop';
  if (value === 'off') return 'off';
  if (value === 'bios' || value === 'loading' || value === 'setup' || value === 'login' || value === 'desktop') {
    return value;
  }
  return 'loading';
}

function notificationId() {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  return `notification-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
}

interface SystemState {
  bootPhase: BootPhase;
  isBooting: boolean;
  bootProgress: number;

  currentUser: UserProfile;
  isLocked: boolean;
  theme: SystemTheme;
  volume: number;
  isMuted: boolean;
  brightness: number;
  isWifiConnected: boolean;
  isBluetooth: boolean;
  batteryLevel: number;

  notifications: NotificationData[];
  showNotificationCenter: boolean;
  isStartMenuOpen: boolean;
  isSearchOpen: boolean;

  setBootPhase: (phase: BootPhase) => void;
  setBootProgress: (progress: number) => void;
  lock: () => void;
  unlock: () => void;
  toggleStartMenu: () => void;
  closeStartMenu: () => void;
  toggleSearch: () => void;
  setTheme: (theme: Partial<SystemTheme>) => void;
  addNotification: (notification: Omit<NotificationData, 'id' | 'timestamp' | 'read'>) => void;
  dismissNotification: (id: string) => void;
  clearNotifications: () => void;
  toggleNotificationCenter: () => void;
  setVolume: (volume: number) => void;
  toggleMute: () => void;
  setBrightness: (brightness: number) => void;
  toggleWifi: () => void;
  toggleBluetooth: () => void;
}

export const useSystem = create<SystemState>((set) => {
  const initialSnapshot = kernel.sysGetSnapshot();

  kernel.on('system:snapshot', (state: ReturnType<typeof kernel.sysGetSnapshot>) => {
    set({
      currentUser: state.user,
      isLocked: state.isLocked,
      theme: state.theme,
      volume: state.hardware.volume,
      isMuted: state.hardware.isMuted,
      brightness: state.hardware.brightness,
      isWifiConnected: state.hardware.isWifiConnected,
      isBluetooth: state.hardware.isBluetooth,
      batteryLevel: state.hardware.batteryLevel,
    });
  });

  kernel.on('system:bootPhase', (phase: unknown) => {
    set({ bootPhase: normalizeBootPhase(phase) });
  });

  return {
    bootPhase: 'off',
    isBooting: false,
    bootProgress: 0,

    currentUser: initialSnapshot.user,
    isLocked: initialSnapshot.isLocked,
    theme: initialSnapshot.theme,
    volume: initialSnapshot.hardware.volume,
    isMuted: initialSnapshot.hardware.isMuted,
    brightness: initialSnapshot.hardware.brightness,
    isWifiConnected: initialSnapshot.hardware.isWifiConnected,
    isBluetooth: initialSnapshot.hardware.isBluetooth,
    batteryLevel: initialSnapshot.hardware.batteryLevel,

    notifications: [],
    showNotificationCenter: false,
    isStartMenuOpen: false,
    isSearchOpen: false,

    setBootPhase: (phase) => set({ bootPhase: phase }),
    setBootProgress: (progress) => set({
      bootProgress: Number.isFinite(progress) ? Math.max(0, Math.min(100, progress)) : 0,
    }),

    lock: () => kernel.sysLock(),
    unlock: () => kernel.sysUnlock(),

    toggleStartMenu: () => set(state => ({
      isStartMenuOpen: !state.isStartMenuOpen,
      isSearchOpen: false,
    })),
    closeStartMenu: () => set({ isStartMenuOpen: false }),
    toggleSearch: () => set(state => ({
      isSearchOpen: !state.isSearchOpen,
      isStartMenuOpen: false,
    })),

    setTheme: (updates) => kernel.sysSetTheme(updates),

    addNotification: (notification) => {
      const next: NotificationData = {
        ...notification,
        id: notificationId(),
        timestamp: Date.now(),
        read: false,
      };
      set(state => ({ notifications: [next, ...state.notifications].slice(0, MAX_NOTIFICATIONS) }));
    },
    dismissNotification: (id) => set(state => ({
      notifications: state.notifications.filter(notification => notification.id !== id),
    })),
    clearNotifications: () => set({ notifications: [] }),
    toggleNotificationCenter: () => set(state => ({
      showNotificationCenter: !state.showNotificationCenter,
    })),

    setVolume: (volume) => kernel.sysSetVolume(volume),
    toggleMute: () => kernel.sysToggleMute(),
    setBrightness: (brightness) => kernel.sysSetBrightness(brightness),
    toggleWifi: () => kernel.sysToggleWifi(),
    toggleBluetooth: () => kernel.sysToggleBluetooth(),
  };
});
