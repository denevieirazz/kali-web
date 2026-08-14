import { useSettingsStore } from '../stores/settingsStore';

const parseResolution = (value: string) => {
  if (value === 'auto') return null;
  const [width, height] = value.split('x').map(Number);
  return Number.isFinite(width) && Number.isFinite(height) ? { width, height } : null;
};

const hexToRgb = (hex: string) => {
  const normalized = hex.replace('#', '');
  if (!/^[0-9a-f]{6}$/i.test(normalized)) return { r: 168, g: 85, b: 247 };
  return {
    r: parseInt(normalized.slice(0, 2), 16),
    g: parseInt(normalized.slice(2, 4), 16),
    b: parseInt(normalized.slice(4, 6), 16),
  };
};

const channel = (value: number) => {
  const v = value / 255;
  return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
};

function applyAccent(accent: string): void {
  const root = document.documentElement;
  const { r, g, b } = hexToRgb(accent);
  const luminance = 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
  root.style.setProperty('--accent', accent);
  root.style.setProperty('--accent-hover', accent);
  root.style.setProperty('--accent-subtle', `rgba(${r}, ${g}, ${b}, .18)`);
  root.style.setProperty('--text-accent', luminance > 0.72 ? '#17121f' : accent);
  root.style.setProperty('--cloudos-accent-foreground', luminance > 0.55 ? '#17121f' : '#ffffff');
  root.style.setProperty('--cloudos-accent-rgb', `${r}, ${g}, ${b}`);
}

export function applyNativeShellSettings(): void {
  const state = useSettingsStore.getState();
  const root = document.documentElement;
  const shell = document.querySelector<HTMLElement>('.obsidianos-root');
  const desktop = document.querySelector<HTMLElement>('.desktop');
  const scale = Math.max(0.75, Math.min(1.5, state.scale));

  root.style.setProperty('--cloudos-ui-scale', String(scale));
  root.style.setProperty('--cloudos-wallpaper-fit', state.wallpaperFit);
  root.dataset.cloudosTransparency = String(state.transparency);
  root.dataset.cloudosReducedMotion = String(state.reducedMotion);
  applyAccent(state.accent);

  if (shell) {
    shell.style.zoom = String(scale);
    shell.style.transform = 'none';
    const resolution = parseResolution(state.resolution);
    shell.style.width = resolution ? `${resolution.width}px` : `${100 / scale}vw`;
    shell.style.height = resolution ? `${resolution.height}px` : `${100 / scale}vh`;
    shell.style.maxWidth = `${100 / scale}vw`;
    shell.style.maxHeight = `${100 / scale}vh`;
  }

  if (desktop) {
    if (state.wallpaper) {
      desktop.style.backgroundImage = `linear-gradient(rgba(4,2,12,.16),rgba(4,2,12,.28)),url("${state.wallpaper}")`;
      desktop.style.backgroundSize = state.wallpaperFit;
      desktop.style.backgroundPosition = 'center';
      desktop.style.backgroundRepeat = 'no-repeat';
    } else {
      desktop.style.removeProperty('background-image');
      desktop.style.removeProperty('background-size');
      desktop.style.removeProperty('background-position');
      desktop.style.removeProperty('background-repeat');
    }
  }
}

let scheduled = false;
const scheduleApply = () => {
  if (scheduled) return;
  scheduled = true;
  requestAnimationFrame(() => {
    scheduled = false;
    applyNativeShellSettings();
  });
};

applyNativeShellSettings();
useSettingsStore.subscribe(scheduleApply);
new MutationObserver(scheduleApply).observe(document.documentElement, { childList: true, subtree: true });
window.addEventListener('resize', scheduleApply);
