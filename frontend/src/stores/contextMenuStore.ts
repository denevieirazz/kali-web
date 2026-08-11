import { create } from 'zustand';
import type { ContextMenuItem } from '../types';

interface ContextMenuState {
  isOpen: boolean;
  x: number;
  y: number;
  items: ContextMenuItem[];
  
  openContextMenu: (x: number, y: number, items: ContextMenuItem[]) => void;
  closeContextMenu: () => void;
}

export const useContextMenuStore = create<ContextMenuState>((set) => ({
  isOpen: false,
  x: 0,
  y: 0,
  items: [],
  
  openContextMenu: (x, y, items) => set({ isOpen: true, x, y, items }),
  closeContextMenu: () => set({ isOpen: false }),
}));
