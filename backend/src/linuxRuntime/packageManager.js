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
    command: 'firefox-esr --no-remote -profile /tmp/cloudos-ff-poc',
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
  '  if command -v "$cmd" >/dev/null 2>&1 || dpkg -s "$pkg" 2>/dev/null | grep -q "Status: install ok installed"; then',
  '    printf "%s\\0371\\n" "$cmd"',
  '  else',
  '    printf "%s\\0370\\n" "$cmd"',
  '  fi',
  'done'
].join('\n');

export function parsePackageStatuses(output, catalog = CURATED_LINUX_APPS) {
  const statusByCommand = new Map();
  const statusByBinary = new Map();
  for (const rawLine of String(output || '').split(/\r?\n/)) {
    const [cmd, rawInstalled] = rawLine.split('\x1f');
    if (!cmd) continue;
    const isInstalled = rawInstalled === '1';
    statusByCommand.set(cmd, isInstalled);
    const bin = cmd.trim().split(/\s+/)[0];
    if (bin) statusByBinary.set(bin, isInstalled);
  }
  return catalog.map((app) => {
    const bin = app.command.trim().split(/\s+/)[0];
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

export async function listLinuxPackages(requestedDistribution) {
  const snapshot = await getWslSnapshot();
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

  // 1. Scan discovered .desktop apps
  const discovered = await scanDiscoveredLinuxApps(distribution);
  const discoveredByBaseId = new Map();
  for (const d of discovered) {
    discoveredByBaseId.set(d.id, d);
    // Also index by simple binary name
    const binName = d.command.split(' ')[0].split('/').pop();
    if (binName) discoveredByBaseId.set(binName, d);
  }

  // 2. Query installed statuses for curated items
  const queryItems = CURATED_LINUX_APPS.map(app => `${app.command.split(' ')[0]}:${app.packageName}`);

  let curatedWithStatus = [];
  try {
    const { stdout } = await execFileAsync(WSL_EXE, [
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

    const statusMap = new Map();
    for (const rawLine of String(stdout || '').split(/\r?\n/)) {
      const [cmd, rawInstalled] = rawLine.split('\x1f');
      if (cmd) statusMap.set(cmd, rawInstalled === '1');
    }

    curatedWithStatus = CURATED_LINUX_APPS.map(app => {
      const bin = app.command.split(' ')[0];
      const isInstalled = statusMap.get(bin) === true || Boolean(discoveredByBaseId.get(app.id));
      const disc = discoveredByBaseId.get(app.id);
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
        installed: isInstalled,
        isCurated: true
      };
    });
  } catch (err) {
    curatedWithStatus = CURATED_LINUX_APPS.map(app => ({ ...app, installed: false, isCurated: true }));
  }

  // 3. Merge discovered apps that are NOT curated
  const curatedIds = new Set(CURATED_LINUX_APPS.map(a => a.id));
  const additionalDiscovered = discovered.filter(d => {
    if (curatedIds.has(d.id)) return false;
    const bin = d.command.split(' ')[0].split('/').pop();
    if (curatedIds.has(bin)) return false;
    return true;
  }).map(d => ({
    id: d.id,
    name: d.name,
    genericName: d.genericName,
    packageName: d.id,
    command: d.command,
    category: d.category,
    categories: d.categories,
    description: d.comment || d.genericName || `${d.name} para Linux`,
    icon: d.iconUrl || d.emojiFallback,
    iconName: d.iconName,
    iconUrl: d.iconUrl,
    emojiFallback: d.emojiFallback,
    isPopular: false,
    desktopId: d.id,
    terminal: d.terminal,
    installed: true,
    isDiscovered: true
  }));

  const allPackages = [...curatedWithStatus, ...additionalDiscovered];

  return {
    operational: true,
    distribution,
    errorCode: null,
    error: null,
    packages: allPackages,
    totalDiscovered: discovered.length
  };
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

  // Find target in curated or use raw packageId sanitized
  const curated = CURATED_LINUX_APPS.find(app => app.id === packageId || app.packageName === packageId);
  const rawPkg = curated ? curated.packageName : packageId;
  const sanitizedPkg = rawPkg.replace(/[^a-zA-Z0-9._+-]/g, '');

  if (!sanitizedPkg) {
    const error = new Error(`Nome de pacote inválido: ${packageId}`);
    error.code = 'INVALID_PACKAGE_NAME';
    throw error;
  }

  const installCmd = `DEBIAN_FRONTEND=noninteractive sudo -n apt-get update -qq && DEBIAN_FRONTEND=noninteractive sudo -n apt-get install -y --no-install-recommends ${sanitizedPkg}`;

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

  const removeCmd = `DEBIAN_FRONTEND=noninteractive sudo -n apt-get remove -y ${sanitizedPkg}`;

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
    return { results: [] };
  }

  try {
    const { stdout } = await execFileAsync(WSL_EXE, [
      '--distribution', distribution,
      '--exec', 'apt-cache', 'search', '--names-only', cleanQuery
    ], {
      encoding: 'utf8',
      env: safeChildEnvironment(),
      timeout: 10_000,
      windowsHide: true,
      maxBuffer: 512 * 1024
    });

    const results = String(stdout || '')
      .split(/\r?\n/)
      .filter(Boolean)
      .slice(0, 30)
      .map(line => {
        const idx = line.indexOf(' - ');
        if (idx === -1) return { packageName: line.trim(), description: '' };
        return {
          packageName: line.slice(0, idx).trim(),
          description: line.slice(idx + 3).trim()
        };
      });

    return { results };
  } catch {
    return { results: [] };
  }
}
