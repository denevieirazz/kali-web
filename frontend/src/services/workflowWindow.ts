import { snapBounds } from '../core/workflowCore.js';
import { useWindowManager } from '../stores/windowManager';

const snapped = new Map<string, { x: number; y: number; width: number; height: number }>();

export function isWorkflowWindowSnapped(windowId: string) {
  return snapped.has(windowId);
}

export function snapWorkflowWindow(windowId: string, side: 'left' | 'right') {
  const manager = useWindowManager.getState();
  const win = manager.getWindow(windowId);
  if (!win || win.isSystem || !win.isResizable) return false;
  if (!snapped.has(windowId)) {
    snapped.set(windowId, { x: win.x, y: win.y, width: win.width, height: win.height });
  }
  if (win.isMaximized) manager.restoreWindow(windowId);
  const bounds = snapBounds(side, window.innerWidth, window.innerHeight, 0, 48);
  manager.moveWindow(windowId, bounds.x, bounds.y);
  manager.resizeWindow(windowId, bounds.width, bounds.height);
  manager.focusWindow(windowId);
  return true;
}

export function restoreWorkflowWindow(windowId: string) {
  const manager = useWindowManager.getState();
  const win = manager.getWindow(windowId);
  if (!win) return false;
  if (win.isMaximized) manager.restoreWindow(windowId);
  const previous = snapped.get(windowId);
  if (!previous) return Boolean(win.isMaximized);
  snapped.delete(windowId);
  manager.moveWindow(windowId, previous.x, previous.y);
  manager.resizeWindow(windowId, previous.width, previous.height);
  manager.focusWindow(windowId);
  return true;
}

export function maximizeWorkflowWindow(windowId: string) {
  const manager = useWindowManager.getState();
  const win = manager.getWindow(windowId);
  if (!win || !win.isMaximizable) return false;
  snapped.delete(windowId);
  manager.maximizeWindow(windowId);
  manager.focusWindow(windowId);
  return true;
}

export function forgetWorkflowWindow(windowId: string) {
  snapped.delete(windowId);
}

export function activeWorkflowWindowId() {
  const windows = useWindowManager.getState().windows.filter(item => !item.isSystem && !item.isMinimized);
  const active = windows.find(item => item.isActive);
  if (active) return active.id;
  return [...windows].sort((left, right) => right.zIndex - left.zIndex)[0]?.id || null;
}
