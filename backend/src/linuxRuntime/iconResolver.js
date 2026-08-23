import fs from 'node:fs';
import path from 'node:path';

const ICON_SUBDIRS = [
  'usr/share/icons/hicolor/scalable/apps',
  'usr/share/icons/hicolor/512x512/apps',
  'usr/share/icons/hicolor/256x256/apps',
  'usr/share/icons/hicolor/128x128/apps',
  'usr/share/icons/hicolor/64x64/apps',
  'usr/share/icons/hicolor/48x48/apps',
  'usr/share/icons/hicolor/32x32/apps',
  'usr/share/icons/hicolor/16x16/apps',
  'usr/share/pixmaps',
  'usr/share/icons/locolor/32x32/apps',
  'usr/share/icons/locolor/16x16/apps',
  'usr/share/icons/Adwaita/scalable/apps',
  'usr/share/icons/Adwaita/48x48/apps',
  'usr/share/icons/Papirus/scalable/apps',
  'usr/share/icons/Papirus/48x48/apps',
  'usr/share/icons/breeze/apps/48',
];

const resolvedIconCache = new Map();

export function resolveLinuxIconPath(distro, iconNameOrPath) {
  if (!distro || !iconNameOrPath) return null;
  const cacheKey = `${distro}:${iconNameOrPath}`;
  if (resolvedIconCache.has(cacheKey)) {
    return resolvedIconCache.get(cacheKey);
  }

  const baseWsl = `\\\\wsl.localhost\\${distro}`;
  const raw = String(iconNameOrPath).trim();

  // 1. If absolute Linux path
  if (raw.startsWith('/')) {
    const directWinPath = path.join(baseWsl, raw.replace(/^\//, '').replace(/\//g, '\\'));
    if (fs.existsSync(directWinPath)) {
      resolvedIconCache.set(cacheKey, directWinPath);
      return directWinPath;
    }
  }

  const namesToTry = [raw];
  if (raw.toLowerCase() !== raw) {
    namesToTry.push(raw.toLowerCase());
  }

  // 2. Try standard subdirs
  for (const name of namesToTry) {
    // If name already contains extension
    if (/\.(svg|png|xpm|ico|jpg)$/i.test(name)) {
      for (const sub of ICON_SUBDIRS) {
        const full = path.join(baseWsl, sub.replace(/\//g, '\\'), name);
        if (fs.existsSync(full)) {
          resolvedIconCache.set(cacheKey, full);
          return full;
        }
      }
    }

    // Try each extension in priority order
    for (const ext of ['.svg', '.png', '.xpm', '.ico']) {
      for (const sub of ICON_SUBDIRS) {
        const full = path.join(baseWsl, sub.replace(/\//g, '\\'), `${name}${ext}`);
        if (fs.existsSync(full)) {
          resolvedIconCache.set(cacheKey, full);
          return full;
        }
      }
    }
  }

  resolvedIconCache.set(cacheKey, null);
  return null;
}

export function getMimeTypeForIcon(filePath) {
  if (!filePath) return 'image/png';
  const ext = path.extname(filePath).toLowerCase();
  if (ext === '.svg') return 'image/svg+xml';
  if (ext === '.png') return 'image/png';
  if (ext === '.xpm') return 'image/x-xpixmap';
  if (ext === '.ico') return 'image/x-icon';
  if (ext === '.jpg' || ext === '.jpeg') return 'image/jpeg';
  return 'application/octet-stream';
}

export function clearIconCache() {
  resolvedIconCache.clear();
}
