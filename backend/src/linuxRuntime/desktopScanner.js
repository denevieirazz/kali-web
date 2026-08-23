import fs from 'node:fs';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { WSL_EXE, getWslSnapshot, safeChildEnvironment, validateInstalledAsync } from '../wsl/distroService.js';
import { resolveLinuxIconPath } from './iconResolver.js';

const execFileAsync = promisify(execFile);

const SCAN_CACHE_TTL_MS = 15_000;
let cachedDistro = null;
let lastScanTime = 0;
let cachedDiscoveredApps = [];

const SEARCH_SUBDIRS = [
  'usr/share/applications',
  'usr/local/share/applications',
  'root/.local/share/applications',
  'var/lib/snapd/desktop/applications',
  'var/lib/flatpak/exports/share/applications'
];

const TECHNICAL_NOISE_IDS = new Set([
  'debian-xterm',
  'debian-uxterm',
  'xterm',
  'uxterm',
  'xpra-gui',
  'display-im7.q16',
  'display-im6.q16',
  'display-im7',
  'display-im6',
  'lstopo',
  'hxtopo',
  'zenmap-root',
  'texdoctk',
  'org.gnome.yelp',
  'yad-icon-browser',
  'avahi-discover',
  'bssh',
  'bvnc',
  'qv4l2',
  'qvidcap',
  'software-properties-gtk',
  'software-properties-drivers',
  'gcr-viewer',
  'gcr-prompter',
  'info',
  'im-config',
  'org.freedesktop.ibus.setup'
]);

function cleanExec(raw) {
  if (!raw) return '';
  // Strip field codes: %f, %F, %u, %U, %d, %D, %n, %N, %i, %c, %k, %v, %m
  return String(raw).replace(/%[fFuUdDnNickvm]/g, '').trim();
}

function mapCategory(cats, name = '', id = '') {
  const catSet = new Set(cats.map(c => c.toLowerCase()));
  const idLower = id.toLowerCase();
  
  if (catSet.has('development') || catSet.has('programming') || catSet.has('ide') || catSet.has('debugger') || catSet.has('building') ||
      ['geany', 'code', 'cutter', 're.rizin.cutter', 'edb', 'dbeaver', 'sqlitebrowser', 'imhex', 'hexwalk', 'groovyconsole', 'io.github.horsicq.detect-it-easy'].includes(idLower)) {
    return 'development';
  }
  if (catSet.has('network') || catSet.has('webbrowser') || catSet.has('email') || catSet.has('chat') || catSet.has('filetransfer') ||
      ['firefox-esr', 'firefox', 'chromium', 'wireshark', 'org.wireshark.wireshark', 'caido', 'zenmap', 'ettercap', 'fwbuilder', 'minicom', 'routerkeygen', 'xfreerdp', 'hydra-gtk', 'xsser', 'driftnet'].includes(idLower)) {
    return 'internet';
  }
  if (catSet.has('office') || catSet.has('wordprocessor') || catSet.has('spreadsheet') || catSet.has('presentation') || catSet.has('publishing') || catSet.has('texteditor') ||
      ['obsidian', 'cherrytree', 'zim', 'org.zim_wiki.zim', 'joplin', 'mousepad', 'org.xfce.mousepad', 'libreoffice', 'mcedit', 'gvim'].includes(idLower)) {
    return 'office';
  }
  if (catSet.has('audiovideo') || catSet.has('audio') || catSet.has('video') || catSet.has('player') || catSet.has('recorder') || catSet.has('music') ||
      ['vlc', 'gqrx', 'dk.gqrx.gqrx'].includes(idLower)) {
    return 'multimedia';
  }
  if (catSet.has('graphics') || catSet.has('2dgraphics') || catSet.has('rastergraphics') || catSet.has('vectorgraphics') || catSet.has('photography') || catSet.has('viewer') ||
      ['gimp', 'inkscape', 'stegosuite', 'org.stegosuite', 'display-im7.q16', 'display-im6.q16'].includes(idLower)) {
    return 'graphics';
  }
  if (catSet.has('security') || catSet.has('networksecurity') || catSet.has('forensics') || catSet.has('kali') || catSet.has('penetrationtesting') || catSet.has('audit') ||
      ['gtkhash', 'org.gtkhash.gtkhash', 'ophcrack', 'guymager', 'rfdump', 'chirp', 'cutecom', 'lynis', 'tiger', 'kali-autopilot'].includes(idLower)) {
    return 'security';
  }
  if (catSet.has('system') || catSet.has('settings') || catSet.has('hardware') || catSet.has('packagemanager') || catSet.has('filesystem') ||
      ['gparted', 'galculator', 'system-config-printer', 'org.gnome.terminal', 'mc', 'lstopo'].includes(idLower)) {
    return 'system';
  }
  return 'utilities';
}

function getEmojiFallback(category, name) {
  const nameLower = String(name || '').toLowerCase();
  if (nameLower.includes('terminal') || nameLower.includes('uxterm') || nameLower.includes('xterm')) return '🖥️';
  if (nameLower.includes('calc')) return '🧮';
  if (nameLower.includes('edit') || nameLower.includes('pad') || nameLower.includes('vim') || nameLower.includes('note') || nameLower.includes('geany')) return '📝';
  if (nameLower.includes('browser') || nameLower.includes('web') || nameLower.includes('fox') || nameLower.includes('chrome')) return '🌐';
  if (nameLower.includes('view') || nameLower.includes('image') || nameLower.includes('photo') || nameLower.includes('paint') || nameLower.includes('gimp')) return '🎨';
  if (nameLower.includes('play') || nameLower.includes('media') || nameLower.includes('music') || nameLower.includes('audio') || nameLower.includes('vlc')) return '🎬';
  if (nameLower.includes('parted') || nameLower.includes('disk') || nameLower.includes('file')) return '📁';
  if (nameLower.includes('shark') || nameLower.includes('sniff') || nameLower.includes('scan') || nameLower.includes('nmap') || nameLower.includes('hash')) return '🛡️';

  const fallbacks = {
    development: '💻',
    internet: '🌐',
    office: '📄',
    multimedia: '🎬',
    graphics: '🎨',
    security: '🛡️',
    system: '⚙️',
    utilities: '🔧'
  };
  return fallbacks[category] || '📦';
}

function parseDesktopFileContent(content, filename) {
  let inEntry = false;
  const props = {};
  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    if (line.startsWith('[')) {
      inEntry = (line === '[Desktop Entry]');
      continue;
    }
    if (inEntry && line.includes('=')) {
      const idx = line.indexOf('=');
      const k = line.slice(0, idx).trim();
      const v = line.slice(idx + 1).trim();
      if (!props[k]) props[k] = v;
    }
  }

  if (props.Type && props.Type !== 'Application') return null;
  if (['true', '1'].includes(String(props.NoDisplay || '').toLowerCase())) return null;
  if (['true', '1'].includes(String(props.Hidden || '').toLowerCase())) return null;

  const rawExec = props.Exec || '';
  if (!rawExec) return null;

  const baseId = path.basename(filename, '.desktop').toLowerCase();
  const name = props['Name[pt_BR]'] || props['Name[pt]'] || props.Name || baseId;
  const genericName = props['GenericName[pt_BR]'] || props['GenericName[pt]'] || props.GenericName || '';
  const comment = props['Comment[pt_BR]'] || props['Comment[pt]'] || props.Comment || genericName || '';
  const icon = props.Icon || '';
  const terminal = ['true', '1'].includes(String(props.Terminal || '').toLowerCase());
  const catsRaw = props.Categories || '';
  const categories = catsRaw.split(';').map(c => c.trim()).filter(Boolean);
  const category = mapCategory(categories, name, baseId);
  const emojiFallback = getEmojiFallback(category, name);
  const command = cleanExec(rawExec);

  const isTechnical = TECHNICAL_NOISE_IDS.has(baseId) ||
                      ['su-to-root', 'exec-in-shell'].some(prefix => rawExec.includes(prefix)) ||
                      (terminal && !['vim', 'mc', 'mcedit'].includes(baseId));

  const isUserApp = !isTechnical;
  const mimeTypesRaw = props.MimeType || '';
  const mimeTypes = mimeTypesRaw.split(';').map(m => m.trim().toLowerCase()).filter(Boolean);

  return {
    id: baseId,
    name,
    genericName,
    comment,
    command,
    rawExec,
    icon: icon || emojiFallback,
    iconName: icon,
    emojiFallback,
    categories,
    category,
    mimeTypes,
    terminal,
    desktopFile: filename,
    installed: true,
    isDiscovered: true,
    isUserApp,
    isTechnical
  };
}

export async function scanDiscoveredLinuxApps(requestedDistro, { force = false } = {}) {
  const snapshot = await getWslSnapshot();
  const distro = typeof requestedDistro === 'string' && requestedDistro.trim()
    ? requestedDistro.trim()
    : snapshot.preferred || snapshot.default || 'kali-linux';

  if (!force && cachedDistro === distro && Date.now() - lastScanTime < SCAN_CACHE_TTL_MS && cachedDiscoveredApps.length > 0) {
    return cachedDiscoveredApps;
  }

  const baseWsl = `\\\\wsl.localhost\\${distro}`;
  const isDirectAccessible = fs.existsSync(baseWsl);

  const apps = [];
  const seenIds = new Set();

  if (isDirectAccessible) {
    for (const sub of SEARCH_SUBDIRS) {
      const winDir = path.join(baseWsl, sub.replace(/\//g, '\\'));
      if (!fs.existsSync(winDir)) continue;
      try {
        const files = fs.readdirSync(winDir);
        for (const file of files) {
          if (!file.endsWith('.desktop')) continue;
          const fullPath = path.join(winDir, file);
          try {
            const content = fs.readFileSync(fullPath, 'utf8');
            const linuxPath = `/${sub}/${file}`;
            const parsed = parseDesktopFileContent(content, linuxPath);
            if (parsed && !seenIds.has(parsed.id)) {
              seenIds.add(parsed.id);
              // Check if icon exists and formulate iconUrl
              const iconResolved = resolveLinuxIconPath(distro, parsed.iconName);
              if (iconResolved) {
                parsed.iconUrl = `/__cloudos/linux-runtime/icons/${encodeURIComponent(parsed.id)}?distro=${encodeURIComponent(distro)}`;
              } else {
                parsed.iconUrl = null;
              }
              apps.push(parsed);
            }
          } catch {}
        }
      } catch {}
    }
  } else {
    // Fallback: Run scanner script inside WSL
    try {
      const scannerPyPath = path.join(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([a-zA-Z]:)/, '$1')), 'desktopScanner.py');
      const { stdout } = await execFileAsync(WSL_EXE, [
        '-d', distro,
        '--exec', 'python3', '-c',
        fs.readFileSync(scannerPyPath, 'utf8')
      ], {
        encoding: 'utf8',
        env: safeChildEnvironment(),
        timeout: 10_000,
        windowsHide: true,
        maxBuffer: 4 * 1024 * 1024
      });

      const parsedList = JSON.parse(stdout || '[]');
      for (const item of parsedList) {
        if (!seenIds.has(item.id)) {
          seenIds.add(item.id);
          apps.push(item);
        }
      }
    } catch (err) {
      console.warn('⚠️ [DesktopScanner] Erro no fallback WSL:', err.message);
    }
  }

  // Sort alphabetically
  apps.sort((a, b) => a.name.localeCompare(b.name, 'pt-BR'));

  cachedDistro = distro;
  lastScanTime = Date.now();
  cachedDiscoveredApps = apps;
  return apps;
}

export function invalidateDiscoveryCache() {
  lastScanTime = 0;
  cachedDiscoveredApps = [];
}
