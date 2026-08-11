// ============================================
// Window Manager Store — Espelho do Kernel
// ============================================
// Este store é um ESPELHO READ-ONLY do estado de janelas do kernel.
// Mutações NUNCA acontecem aqui — elas vão ao kernel (openWindow, closeWindow, etc.).
// O store subscreve aos eventos do kernel e reflete as mudanças para o React.
// ============================================

import { create } from 'zustand';
import kernel from '../core/kernel';
import type { WindowState } from '../types';

type OpenWindowConfig = {
  title: string;
  icon: string;
  appId: string;
  width?: number;
  height?: number;
  minWidth?: number;
  minHeight?: number;
  isResizable?: boolean;
  processId: number;
  params?: any;
  hasFrame?: boolean;
  isSystem?: boolean;
  zIndex?: number;
};

interface WindowManagerState {
  windows: WindowState[];
  activeWindowId: string | null;
  topZIndex: number;

  // Thin wrappers → delegam ao kernel
  openWindow: (config: OpenWindowConfig) => string;
  closeWindow: (id: string) => void;
  minimizeWindow: (id: string) => void;
  maximizeWindow: (id: string) => void;
  restoreWindow: (id: string) => void;
  focusWindow: (id: string) => void;
  moveWindow: (id: string, x: number, y: number) => void;
  resizeWindow: (id: string, width: number, height: number) => void;
  updateWindowTitle: (id: string, title: string) => void;
  toggleMaximize: (id: string) => void;

  // Seletores locais
  getWindow: (id: string) => WindowState | undefined;
  getActiveWindow: () => WindowState | undefined;
  getVisibleWindows: () => WindowState[];
}

export const useWindowManager = create<WindowManagerState>((set, get) => {

  // ── window:snapshot → estado global changed (open/close/focus/minimize/restore)
  kernel.on('window:snapshot', ({ windows, activeWindowId, topZIndex }: {
    windows: WindowState[];
    activeWindowId: string | null;
    topZIndex: number;
  }) => {
    set({ windows, activeWindowId, topZIndex });
  });

  // ── window:updated → apenas uma janela changed (move/resize/maximize/title)
  kernel.on('window:updated', (win: WindowState) => {
    set(state => ({
      windows: state.windows.map(w => w.id === win.id ? win : w),
    }));
  });

  // ── kernel reset → limpa tudo
  kernel.on('reset', () => {
    set({ windows: [], activeWindowId: null, topZIndex: 100 });
  });

  return {
    // Estado inicial = snapshot do kernel (sempre vazio no boot)
    windows: kernel.getWindows(),
    activeWindowId: kernel.activeWindowId,
    topZIndex: kernel.topZIndex,

    // Thin wrappers — toda a lógica vive no kernel
    openWindow:       (config)      => kernel.openWindow(config),
    closeWindow:      (id)          => kernel.closeWindow(id),
    minimizeWindow:   (id)          => kernel.minimizeWindow(id),
    maximizeWindow:   (id)          => kernel.maximizeWindow(id),
    restoreWindow:    (id)          => kernel.restoreWindow(id),
    focusWindow:      (id)          => kernel.focusWindow(id),
    moveWindow:       (id, x, y)   => kernel.moveWindow(id, x, y),
    resizeWindow:     (id, w, h)   => kernel.resizeWindow(id, w, h),
    updateWindowTitle:(id, title)  => kernel.updateWindowTitle(id, title),
    toggleMaximize:   (id)          => kernel.toggleMaximize(id),

    // Seletores (leem do estado local para reatividade React)
    getWindow:         (id) => get().windows.find(w => w.id === id),
    getActiveWindow:   ()   => get().windows.find(w => w.isActive),
    getVisibleWindows: ()   => get().windows.filter(w => !w.isMinimized),
  };
});
