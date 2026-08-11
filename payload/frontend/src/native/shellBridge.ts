import { useWindowManager } from '../stores/windowManager';

type CloudWindow = {
  id: string; appId?: string; title?: string; icon?: string;
  isSystem?: boolean; isMinimized?: boolean; isMaximized?: boolean; isActive?: boolean;
};

declare global {
  interface Window {
    cloudOS?: {
      windows: () => CloudWindow[];
      focus: (id: string) => void;
      minimize: (id: string) => void;
      maximize: (id: string) => void;
      restore: (id: string) => void;
      close: (id: string) => void;
      closeAll: () => void;
      refreshDesktop: () => void;
      subscribe: (listener: () => void) => () => void;
    };
  }
}

const state = () => useWindowManager.getState();
const visibleWindows = () => state().windows.filter(window => !window.isSystem);

window.cloudOS = {
  windows: visibleWindows,
  focus: id => state().focusWindow(id),
  minimize: id => state().minimizeWindow(id),
  maximize: id => state().maximizeWindow(id),
  restore: id => state().restoreWindow(id),
  close: id => state().closeWindow(id),
  closeAll: () => visibleWindows().forEach(window => state().closeWindow(window.id)),
  refreshDesktop: () => {
    window.dispatchEvent(new CustomEvent('cloudos:desktop-refresh', { detail: { at: Date.now() } }));
  },
  subscribe: listener => useWindowManager.subscribe(listener),
};
