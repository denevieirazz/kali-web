// ============================================
// System Store - Espelho do Kernel SystemState
// ============================================
// Este store reflete UserProfile, Theme, Hardware e UI states (notifications, modals).
// As configurações lógicas habitam o `kernel` e vêm via event emitter.
// ============================================

import { create } from 'zustand';
import kernel from '../core/kernel';
import type { SystemTheme, UserProfile, NotificationData } from '../types';

type BootPhase = 'off' | 'bios' | 'loading' | 'setup' | 'login' | 'desktop';

interface SystemState {
  bootPhase: BootPhase;
  isBooting: boolean;
  bootProgress: number;
  
  // Refletidos do Kernel
  currentUser: UserProfile;
  isLocked: boolean;
  theme: SystemTheme;
  volume: number;
  isMuted: boolean;
  brightness: number;
  isWifiConnected: boolean;
  isBluetooth: boolean;
  batteryLevel: number;
  
  // UI states locais
  notifications: NotificationData[];
  showNotificationCenter: boolean;
  isStartMenuOpen: boolean;
  isSearchOpen: boolean;
  
  // Funções
  setBootPhase: (phase: BootPhase) => void;
  setBootProgress: (progress: number) => void;
  login: (password: string) => boolean;
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
  const initialSnap = kernel.sysGetSnapshot();
  // Escutar atualizações do Kernel
  kernel.on('system:snapshot', (state: any) => {
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

  kernel.on('system:bootPhase', (phase: any) => {
    // Mapeamento de Kernel (Caixa Alta) para UI (Minúsculo)
    let uiPhase: any = phase;
    if (phase === 'WINLOGON') uiPhase = 'login';
    if (phase === 'OOBE') uiPhase = 'setup';
    if (phase === 'DESKTOP_READY') uiPhase = 'desktop';
    if (phase === 'OFF') uiPhase = 'off';
    
    set({ bootPhase: uiPhase.toLowerCase() });
  });

  return {
    bootPhase: 'off',
    isBooting: false,
    bootProgress: 0,
    
    // States do Kernel
    currentUser: initialSnap.user,
    isLocked: initialSnap.isLocked,
    theme: initialSnap.theme,
    volume: initialSnap.hardware.volume,
    isMuted: initialSnap.hardware.isMuted,
    brightness: initialSnap.hardware.brightness,
    isWifiConnected: initialSnap.hardware.isWifiConnected,
    isBluetooth: initialSnap.hardware.isBluetooth,
    batteryLevel: initialSnap.hardware.batteryLevel,

    // UI states locais
    notifications: [],
    showNotificationCenter: false,
    isStartMenuOpen: false,
    isSearchOpen: false,

    // Boot Control
    setBootPhase: (phase) => set({ bootPhase: phase }),
    setBootProgress: (progress) => set({ bootProgress: progress }),
    
    // Auth
    login: (password) => kernel.sysLogin(password),
    lock: () => kernel.sysLock(),
    unlock: () => kernel.sysUnlock(),
    
    // UI Controls
    toggleStartMenu: () => set(s => ({ isStartMenuOpen: !s.isStartMenuOpen, isSearchOpen: false })),
    closeStartMenu: () => set({ isStartMenuOpen: false }),
    toggleSearch: () => set(s => ({ isSearchOpen: !s.isSearchOpen, isStartMenuOpen: false })),
    
    // Theme
    setTheme: (updates) => kernel.sysSetTheme(updates),

    // Notifications
    addNotification: (notification) => {
      const id = Math.random().toString(36).substr(2, 9);
      set(s => ({
        notifications: [{ ...notification, id, timestamp: Date.now(), read: false }, ...s.notifications],
      }));
    },
    dismissNotification: (id) => set(s => ({
      notifications: s.notifications.filter(n => n.id !== id),
    })),
    clearNotifications: () => set({ notifications: [] }),
    toggleNotificationCenter: () => set(s => ({ showNotificationCenter: !s.showNotificationCenter })),

    // Hardware
    setVolume: (volume) => kernel.sysSetVolume(volume),
    toggleMute: () => kernel.sysToggleMute(),
    setBrightness: (brightness) => kernel.sysSetBrightness(brightness),
    toggleWifi: () => kernel.sysToggleWifi(),
    toggleBluetooth: () => kernel.sysToggleBluetooth(),
  };
});
