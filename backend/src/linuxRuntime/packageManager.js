import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { WSL_EXE, getWslSnapshot, safeChildEnvironment, validateInstalledAsync } from '../wsl/distroService.js';
import { scanDiscoveredLinuxApps, invalidateDiscoveryCache } from './desktopScanner.js';

const execFileAsync = promisify(execFile);

export const CURATED_LINUX_APPS = Object.freeze([
  {
    id: 'firefox',
    name: 'Firefox ESR',
    packageName: 'firefox-esr',
    command: 'firefox-esr --no-remote -profile /tmp/cloudos-ff-{sessionId}',
    category: 'internet',
    description: 'Navegador web moderno, rápido e seguro da Mozilla.',
    icon: '🦊',
    isPopular: true,
    desktopId: 'firefox-esr'
  },
  {
    id: 'chromium',
    name: 'Chromium',
    packageName: 'chromium',
    command: 'chromium --no-sandbox --disable-gpu',
    category: 'internet',
    description: 'Navegador de código aberto base do Google Chrome.',
    icon: '🌐',
    isPopular: true,
    desktopId: 'chromium'
  },
  {
    id: 'code',
    name: 'Visual Studio Code',
    packageName: 'code',
    command: 'code --no-sandbox',
    category: 'development',
    description: 'Editor de código-fonte poderoso e extensível da Microsoft.',
    icon: '💻',
    isPopular: true,
    desktopId: 'code'
  },
  {
    id: 'gimp',
    name: 'GIMP',
    packageName: 'gimp',
    command: 'gimp',
    category: 'graphics',
    description: 'Editor profissional de imagens e manipulação fotográfica.',
    icon: '🎨',
    isPopular: true,
    desktopId: 'gimp'
  },
  {
    id: 'vlc',
    name: 'VLC Media Player',
    packageName: 'vlc',
    command: 'vlc',
    category: 'multimedia',
    description: 'Reprodutor multimídia completo compatível com múltiplos formatos.',
    icon: '🎬',
    isPopular: true,
    desktopId: 'vlc'
  },
  {
    id: 'libreoffice',
    name: 'LibreOffice',
    packageName: 'libreoffice',
    command: 'libreoffice',
    category: 'office',
    description: 'Suíte de escritório completa com editor de texto, planilhas e slides.',
    icon: '📄',
    isPopular: true,
    desktopId: 'libreoffice-startcenter'
  },
  {
    id: 'filezilla',
    name: 'FileZilla',
    packageName: 'filezilla',
    command: 'filezilla',
    category: 'internet',
    description: 'Cliente FTP, FTPS e SFTP gráfico rápido e confiável.',
    icon: '📁',
    isPopular: true,
    desktopId: 'filezilla'
  },
  {
    id: 'wireshark',
    name: 'Wireshark',
    packageName: 'wireshark',
    command: 'wireshark',
    category: 'security',
    description: 'Analisador de protocolos de rede e inspeção de tráfego em tempo real.',
    icon: '🦈',
    isPopular: true,
    desktopId: 'wireshark'
  },
  {
    id: 'galculator',
    name: 'Calculadora Científica',
    packageName: 'galculator',
    command: 'galculator',
    category: 'utilities',
    description: 'Calculadora científica avançada baseada em GTK.',
    icon: '🧮',
    isPopular: false,
    desktopId: 'galculator'
  },
  {
    id: 'htop',
    name: 'Htop Monitor',
    packageName: 'htop',
    command: "xterm -fa 'Monospace' -fs 11 -bg black -fg white -e htop",
    category: 'utilities',
    description: 'Visualizador de processos interativo em tempo real para Linux.',
    icon: '📈',
    isPopular: false,
    desktopId: 'htop'
  },
  {
    id: 'xclock',
    name: 'XClock',
    packageName: 'x11-apps',
    command: 'xclock',
    category: 'utilities',
    description: 'Relógio analógico e digital tradicional do sistema gráfico X11.',
    icon: '⏱️',
    isPopular: false,
    desktopId: 'xclock'
  },
  {
    id: 'xeyes',
    name: 'XEyes',
    packageName: 'x11-apps',
    command: 'xeyes',
    category: 'utilities',
    description: 'Aplicativo clássico do X11 que acompanha a posição do cursor do mouse.',
    icon: '👀',
    isPopular: false,
    desktopId: 'xeyes'
  },
  {
    id: 'xterm',
    name: 'XTerm',
    packageName: 'xterm',
    command: "xterm -fa 'Monospace' -fs 11 -bg black -fg white",
    category: 'utilities',
    description: 'Emulador de terminal gráfico padrão para o X Window System.',
    icon: '🖥️',
    isPopular: false,
    desktopId: 'xterm'
  }
]);

const PACKAGE_STATUS_SCRIPT = [
  'for item in "$@"; do',
  '  cmd="${item%%:*}"',
  '  pkg="${item##*:}"',
  '  if command -v "$cmd" >/dev/null 2>&1; then',
  '    printf "%s\\0371\\n" "$cmd"',
  '  elif command -v dpkg >/dev/null 2>&1 && dpkg -s "$pkg" 2>/dev/null | grep -q "Status: install ok installed"; then',
  '    printf "%s\\0371\\n" "$cmd"',
  '  elif command -v rpm >/dev/null 2>&1 && rpm -q "$pkg" >/dev/null 2>&1; then',
  '    printf "%s\\0371\\n" "$cmd"',
  '  elif command -v pacman >/dev/null 2>&1 && pacman -Q "$pkg" >/dev/null 2>&1; then',
  '    printf "%s\\0371\\n" "$cmd"',
  '  elif command -v apk >/dev/null 2>&1 && apk info -e "$pkg" >/dev/null 2>&1; then',
  '    printf "%s\\0371\\n" "$cmd"',
  '  else',
  '    printf "%s\\0370\\n" "$cmd"',
  '  fi',
  'done'
].join('\n');

function commandBinary(command) {
  return String(command || '').trim().split(/\s+/)[0].split('/').pop() || '';
}

function normalizedCatalogKey(value) {
  return String(value || '').trim().toLowerCase();
}

function discoveryKeys(app) {
  return [app?.id, app?.desktopId, app?.packageName, commandBinary(app?.command)]
    .map(normalizedCatalogKey)
    .filter(Boolean);
}

function buildDiscoveryIndex(discovered) {
  const index = new Map();
  for (const app of discovered) {
    for (const key of discoveryKeys(app)) {
      if (!index.has(key)) index.set(key, app);
    }
  }
  return index;
}

function findDiscoveredForCurated(app, discoveryIndex) {
  for (const key of discoveryKeys(app)) {
    const discovered = discoveryIndex.get(key);
    if (discovered) return discovered;
  }
  return null;
}

export function parsePackageStatuses(output, catalog = CURATED_LINUX_APPS) {
  const statusByCommand = new Map();
  const statusByBinary = new Map();
  for (const rawLine of String(output || '').split(/\r?\n/)) {
    const [cmd, rawInstalled] = rawLine.split('\x1f');
    if (!cmd) continue;
    const isInstalled = rawInstalled === '1';
    statusByCommand.set(cmd, isInstalled);
    const bin = commandBinary(cmd);
    if (bin) statusByBinary.set(bin, isInstalled);
  }
  return catalog.map((app) => {
    const bin = commandBinary(app.command);
    const installed = statusByCommand.has(app.command)
      ? statusByCommand.get(app.command) === true
      : (statusByBinary.get(bin) === true);
    return {
      id: app.id,
      name: app.name,
      packageName: app.packageName,
      command: app.command,
      category: app.category,
      description: app.description,
      icon: app.icon,
      isPopular: Boolean(app.isPopular),
      desktopId: app.desktopId || app.command,
      installed
    };
  });
}

export function mergeLinuxPackageCatalog(discovered = [], statusMap = new Map()) {
  const safeDiscovered = Array.isArray(discovered) ? discovered : [];
  const discoveryIndex = buildDiscoveryIndex(safeDiscovered);

  const curatedWithStatus = CURATED_LINUX_APPS.map(app => {
    const bin = commandBinary(app.command);
    const disc = findDiscoveredForCurated(app, discoveryIndex);
    const isInstalled = statusMap.get(bin) === true || Boolean(disc);
    return {
      id: app.id,
      name: app.name,
      packageName: app.packageName,
      command: app.command,
      category: app.category,
      description: app.description,
      icon: disc?.iconUrl || app.icon,
      iconName: disc?.iconName || null,
      iconUrl: disc?.iconUrl || null,
      emojiFallback: app.icon,
      isPopular: Boolean(app.isPopular),
      desktopId: app.desktopId || app.id,
      mimeTypes: Array.isArray(disc?.mimeTypes) ? disc.mimeTypes : [],
      installed: isInstalled,
      isCurated: true,
      isUserApp: true,
      isTechnical: false
    };
  });

  const curatedKeys = new Set();
  for (const app of CURATED_LINUX_APPS) {
    for (const key of discoveryKeys(app)) curatedKeys.add(key);
  }

  const additionalDiscovered = safeDiscovered.filter(app => {
    return !discoveryKeys(app).some(key => curatedKeys.has(key));
  }).map(app => ({
    id: app.id,
    name: app.name,
    genericName: app.genericName,
    packageName: app.packageName || app.id,
    command: app.command,
    category: app.category,
    categories: app.categories,
    description: app.comment || app.genericName || `${app.name} para Linux`,
    icon: app.iconUrl || app.emojiFallback,
    iconName: app.iconName,
    iconUrl: app.iconUrl,
    emojiFallback: app.emojiFallback,
    isPopular: false,
    desktopId: app.desktopId || app.id,
    terminal: app.terminal,
    mimeTypes: Array.isArray(app.mimeTypes) ? app.mimeTypes : [],
    installed: true,
    isDiscovered: true,
    isUserApp: app.isUserApp !== false,
    isTechnical: app.isTechnical === true
  }));

  return [...curatedWithStatus, ...additionalDiscovered];
}

export async function listLinuxPackages(requestedDistribution, dependencies = {}) {
  const getSnapshot = dependencies.getWslSnapshot || getWslSnapshot;
  const scanApps = dependencies.scanDiscoveredLinuxApps || scanDiscoveredLinuxApps;
  const runExecFile = dependencies.execFileAsync || execFileAsync;
  const snapshot = await getSnapshot();
  const distribution = typeof requestedDistribution === 'string' && requestedDistribution.trim()
    ? requestedDistribution.trim()
    : snapshot.preferred || snapshot.default || 'kali-linux';

  if (!snapshot.operational) {
    return {
      operational: false,
      distribution: null,
      errorCode: snapshot.errorCode || 'WSL_NOT_OPERATIONAL',
      error: snapshot.error || 'WSL não está operacional.',
      packages: CURATED_LINUX_APPS.map(app => ({ ...app, installed: false }))
    };
  }

  const discovered = await scanApps(distribution);
  const queryItems = CURATED_LINUX_APPS.map(app => `${commandBinary(app.command)}:${app.packageName}`);
  const statusMap = new Map();

  try {
    const { stdout } = await runExecFile(WSL_EXE, [
      '--distribution', distribution,
      '--exec', '/bin/sh', '-c', PACKAGE_STATUS_SCRIPT,
      'cloudos-pkg-status',
      ...queryItems
    ], {
      encoding: 'utf8',
      env: safeChildEnvironment(),
      timeout: 8_000,
      windowsHide: true,
      maxBuffer: 256 * 1024
    });

    for (const rawLine of String(stdout || '').split(/\r?\n/)) {
      const [cmd, rawInstalled] = rawLine.split('\x1f');
      if (cmd) statusMap.set(commandBinary(cmd), rawInstalled === '1');
    }
  } catch {
    // Discovery remains useful even when the status probe is temporarily unavailable.
  }

  const allPackages = mergeLinuxPackageCatalog(discovered, statusMap);

  return {
    operational: true,
    distribution,
    errorCode: null,
    error: null,
    packages: allPackages,
    totalDiscovered: discovered.length
  };
}

export async function detectDistroPackageManager(distribution) {
  const detectScript = [
    'if command -v apt-get >/dev/null 2>&1; then echo "apt";',
    'elif command -v dnf >/dev/null 2>&1; then echo "dnf";',
    'elif command -v pacman >/dev/null 2>&1; then echo "pacman";',
    'elif command -v apk >/dev/null 2>&1; then echo "apk";',
    'elif command -v zypper >/dev/null 2>&1; then echo "zypper";',
    'else echo "apt"; fi'
  ].join(' ');

  try {
    const { stdout } = await execFileAsync(WSL_EXE, [
      '--distribution', distribution,
      '--exec', '/bin/sh', '-c', detectScript
    ], { windowsHide: true, timeout: 5000 });
    return stdout.trim() || 'apt';
  } catch {
    return 'apt';
  }
}

export function buildInstallCommand(pm, pkg) {
  switch (pm) {
    case 'dnf':
      return `sudo -n dnf install -y ${pkg}`;
    case 'pacman':
      return `sudo -n pacman -Sy --noconfirm ${pkg}`;
    case 'apk':
      return `sudo -n apk add ${pkg}`;
    case 'zypper':
      return `sudo -n zypper install -y ${pkg}`;
    case 'apt':
    default:
      return `DEBIAN_FRONTEND=noninteractive sudo -n apt-get update -qq && DEBIAN_FRONTEND=noninteractive sudo -n apt-get install -y --no-install-recommends ${pkg}`;
  }
}

export function buildUninstallCommand(pm, pkg) {
  switch (pm) {
    case 'dnf':
      return `sudo -n dnf remove -y ${pkg}`;
    case 'pacman':
      return `sudo -n pacman -R --noconfirm ${pkg}`;
    case 'apk':
      return `sudo -n apk del ${pkg}`;
    case 'zypper':
      return `sudo -n zypper remove -y ${pkg}`;
    case 'apt':
    default:
      return `DEBIAN_FRONTEND=noninteractive sudo -n apt-get remove -y ${pkg}`;
  }
}

export function buildSearchCommand(pm, query) {
  switch (pm) {
    case 'dnf':
      return `dnf search ${query} 2>/dev/null | head -n 30`;
    case 'pacman':
      return `pacman -Ss ${query} 2>/dev/null | head -n 30`;
    case 'apk':
      return `apk search -v ${query} 2>/dev/null | head -n 30`;
    case 'zypper':
      return `zypper search ${query} 2>/dev/null | head -n 30`;
    case 'apt':
    default:
      return `apt-cache search ${query} 2>/dev/null | head -n 30`;
  }
}

export async function installLinuxPackage(requestedDistribution, packageId) {
  const snapshot = await getWslSnapshot();
  const distribution = typeof requestedDistribution === 'string' && requestedDistribution.trim()
    ? requestedDistribution.trim()
    : snapshot.preferred || snapshot.default || 'kali-linux';

  if (!distribution || !await validateInstalledAsync(distribution)) {
    const error = new Error('Distribuição WSL não encontrada.');
    error.code = 'DISTRO_NOT_INSTALLED';
    throw error;
  }

  const curated = CURATED_LINUX_APPS.find(app => app.id === packageId || app.packageName === packageId);
  const rawPkg = curated ? curated.packageName : packageId;
  const sanitizedPkg = rawPkg.replace(/[^a-zA-Z0-9._+-]/g, '');

  if (!sanitizedPkg) {
    const error = new Error(`Nome de pacote inválido: ${packageId}`);
    error.code = 'INVALID_PACKAGE_NAME';
    throw error;
  }

  const pm = await detectDistroPackageManager(distribution);
  const installCmd = buildInstallCommand(pm, sanitizedPkg);

  try {
    const { stdout, stderr } = await execFileAsync(WSL_EXE, [
      '--distribution', distribution,
      '--exec', '/bin/sh', '-lc', installCmd
    ], {
      encoding: 'utf8',
      env: safeChildEnvironment(),
      timeout: 120_000,
      windowsHide: true,
      maxBuffer: 4 * 1024 * 1024
    });

    invalidateDiscoveryCache();

    return {
      success: true,
      packageId,
      packageName: sanitizedPkg,
      distribution,
      packageManager: pm,
      log: stdout + (stderr ? `\n${stderr}` : '')
    };
  } catch (err) {
    const error = new Error(`Falha na instalação de ${sanitizedPkg}: ${err.message}`);
    error.code = 'INSTALL_FAILED';
    error.details = err.stderr || err.stdout;
    throw error;
  }
}

export async function uninstallLinuxPackage(requestedDistribution, packageId) {
  const snapshot = await getWslSnapshot();
  const distribution = typeof requestedDistribution === 'string' && requestedDistribution.trim()
    ? requestedDistribution.trim()
    : snapshot.preferred || snapshot.default || 'kali-linux';

  if (!distribution || !await validateInstalledAsync(distribution)) {
    const error = new Error('Distribuição WSL não encontrada.');
    error.code = 'DISTRO_NOT_INSTALLED';
    throw error;
  }

  const curated = CURATED_LINUX_APPS.find(app => app.id === packageId || app.packageName === packageId);
  const rawPkg = curated ? curated.packageName : packageId;
  const sanitizedPkg = rawPkg.replace(/[^a-zA-Z0-9._+-]/g, '');

  const pm = await detectDistroPackageManager(distribution);
  const removeCmd = buildUninstallCommand(pm, sanitizedPkg);

  try {
    const { stdout, stderr } = await execFileAsync(WSL_EXE, [
      '--distribution', distribution,
      '--exec', '/bin/sh', '-lc', removeCmd
    ], {
      encoding: 'utf8',
      env: safeChildEnvironment(),
      timeout: 60_000,
      windowsHide: true,
      maxBuffer: 2 * 1024 * 1024
    });

    invalidateDiscoveryCache();

    return {
      success: true,
      packageId,
      packageName: sanitizedPkg,
      distribution,
      packageManager: pm,
      log: stdout + (stderr ? `\n${stderr}` : '')
    };
  } catch (err) {
    const error = new Error(`Falha na desinstalação de ${sanitizedPkg}: ${err.message}`);
    error.code = 'UNINSTALL_FAILED';
    error.details = err.stderr || err.stdout;
    throw error;
  }
}

export async function searchLinuxPackages(requestedDistribution, query) {
  const cleanQuery = String(query || '').trim().replace(/[^a-zA-Z0-9._+-]/g, '').slice(0, 50);
  if (!cleanQuery) return { results: [] };

  const snapshot = await getWslSnapshot();
  const distribution = typeof requestedDistribution === 'string' && requestedDistribution.trim()
    ? requestedDistribution.trim()
    : snapshot.preferred || snapshot.default || 'kali-linux';

  if (!distribution || !await validateInstalledAsync(distribution)) {
    return { results: [], error: 'Distribuição não instalada.' };
  }

  const pm = await detectDistroPackageManager(distribution);
  const searchCmd = buildSearchCommand(pm, cleanQuery);

  try {
    const { stdout } = await execFileAsync(WSL_EXE, [
      '--distribution', distribution,
      '--exec', '/bin/sh', '-lc', searchCmd
    ], {
      encoding: 'utf8',
      env: safeChildEnvironment(),
      timeout: 15_000,
      windowsHide: true,
      maxBuffer: 1024 * 1024
    });

    const results = [];
    for (const line of stdout.split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('Listing') || trimmed.startsWith('Sorted')) continue;
      const parts = trimmed.split(/\s+-\s+|\s{2,}/);
      const pkg = parts[0]?.trim();
      const desc = parts[1]?.trim() || '';
      if (pkg && pkg.length < 80) {
        results.push({ name: pkg, description: desc });
      }
    }
    return { results: results.slice(0, 25), packageManager: pm };
  } catch (err) {
    return { results: [], error: err.message };
  }
}
