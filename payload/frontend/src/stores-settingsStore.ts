import { create } from 'zustand';
import { createJSONStorage, persist } from 'zustand/middleware';

export type VirtualResolution = 'auto' | '1280x720' | '1366x768' | '1600x900' | '1920x1080';
export type WallpaperFit = 'cover' | 'contain' | 'none';
interface NativeSettingsState {
  scale: number; resolution: VirtualResolution; accent: string; wallpaper?: string;
  wallpaperFit: WallpaperFit; reducedMotion: boolean; transparency: boolean;
  setScale: (value: number) => void; setResolution: (value: VirtualResolution) => void;
  setAccent: (value: string) => void; setWallpaper: (value?: string) => void;
  setWallpaperFit: (value: WallpaperFit) => void; setReducedMotion: (value: boolean) => void;
  setTransparency: (value: boolean) => void; reset: () => void;
}
const defaults = { scale: 1, resolution: 'auto' as VirtualResolution, accent: '#a855f7', wallpaper: undefined as string | undefined, wallpaperFit: 'cover' as WallpaperFit, reducedMotion: false, transparency: true };
export const useSettingsStore = create<NativeSettingsState>()(persist((set) => ({
  ...defaults,
  setScale: (scale) => set({ scale: Math.max(.75, Math.min(1.5, scale)) }),
  setResolution: (resolution) => set({ resolution }), setAccent: (accent) => set({ accent }),
  setWallpaper: (wallpaper) => set({ wallpaper }), setWallpaperFit: (wallpaperFit) => set({ wallpaperFit }),
  setReducedMotion: (reducedMotion) => set({ reducedMotion }), setTransparency: (transparency) => set({ transparency }),
  reset: () => set(defaults),
}), { name: 'cloudos.native-settings.v1', version: 1, storage: createJSONStorage(() => localStorage) }));
