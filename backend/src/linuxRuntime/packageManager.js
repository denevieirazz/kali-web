import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { WSL_EXE, getWslSnapshot, safeChildEnvironment, validateInstalledAsync } from '../wsl/distroService.js';
import { invalidateLinuxDesktopAppCache, scanLinuxDesktopApps } from '../apps/linuxDesktopScanner.js';
import { getActiveDistro } from './distroManager.js';

const execFileAsync = promisify(execFile);

function commandBinary(command) {
  return String(command || '').trim().split(/\s+/)[0].split('/').pop() || '';
}

export function resolvePackageNameForDistro(packageName) {
  const normalized = String(packageName || '').trim();
  return /^[a-zA-Z0-9][a-zA-Z0-9._+-]{0,127}$/.test(normalized) ? normalized : '';
}

export function parsePackageStatuses(output, catalog = []) {
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

export function mergeLinuxPackageCatalog(discovered = []) {
  const safeDiscovered = Array.isArray(discovered) ? discovered : [];
  return safeDiscovered.map(app => ({
    id: app.id,
    name: app.name,
    genericName: app.genericName,
    packageName: app.packageName || app.desktopId || commandBinary(app.command || app.argv?.[0]) || app.id,
    category: app.category || app.categories?.[0] || 'Utility',
    categories: Array.isArray(app.categories) ? app.categories : [],
    description: app.comment || app.genericName || `${app.name} para Linux`,
    icon: app.iconUrl || app.icon || app.emojiFallback || '🐧',
    iconName: app.iconName || null,
    iconUrl: app.iconUrl || null,
    emojiFallback: app.emojiFallback || '🐧',
    isPopular: false,
    desktopId: app.desktopId || app.id,
    terminal: app.terminal,
    mimeTypes: Array.isArray(app.mimeTypes) ? app.mimeTypes : [],
    installed: true,
    isDiscovered: true,
    isUserApp: app.isUserApp !== false,
    isTechnical: app.isTechnical === true
  }));
}

export async function resolveActiveDistribution(requestedDistribution, getSnapshot = getWslSnapshot) {
  if (typeof requestedDistribution === 'string' && requestedDistribution.trim()) {
    return requestedDistribution.trim();
  }
  const active = getActiveDistro();
  if (active && await validateInstalledAsync(active)) {
    return active;
  }
  const snapshot = await getSnapshot();
  if (snapshot.preferred && await validateInstalledAsync(snapshot.preferred)) {
    return snapshot.preferred;
  }
  if (snapshot.default && await validateInstalledAsync(snapshot.default)) {
    return snapshot.default;
  }
  if (Array.isArray(snapshot.distributions) && snapshot.distributions.length > 0) {
    return snapshot.distributions[0].name;
  }
  return active || 'kali-linux';
}

export async function listLinuxPackages(requestedDistribution, dependencies = {}) {
  const getSnapshot = dependencies.getWslSnapshot || getWslSnapshot;
  const scanApps = dependencies.scanLinuxDesktopApps || dependencies.scanDiscoveredLinuxApps || scanLinuxDesktopApps;
  const snapshot = await getSnapshot();
  const distribution = await resolveActiveDistribution(requestedDistribution, getSnapshot);

  if (!snapshot.operational) {
    return {
      operational: false,
      distribution: null,
      errorCode: snapshot.errorCode || 'WSL_NOT_OPERATIONAL',
      error: snapshot.error || 'WSL não está operacional.',
      packages: []
    };
  }

  const discovered = await scanApps(distribution);
  const allPackages = mergeLinuxPackageCatalog(discovered);

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
      return `dnf install -y ${pkg}`;
    case 'pacman':
      return `pacman -Sy --noconfirm ${pkg}`;
    case 'apk':
      return `apk add ${pkg}`;
    case 'zypper':
      return `zypper install -y ${pkg}`;
    case 'apt':
    default:
      return `DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${pkg}`;
  }
}

export function buildUninstallCommand(pm, pkg) {
  switch (pm) {
    case 'dnf':
      return `dnf remove -y ${pkg}`;
    case 'pacman':
      return `pacman -R --noconfirm ${pkg}`;
    case 'apk':
      return `apk del ${pkg}`;
    case 'zypper':
      return `zypper remove -y ${pkg}`;
    case 'apt':
    default:
      return `DEBIAN_FRONTEND=noninteractive apt-get remove -y ${pkg}`;
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
  const distribution = await resolveActiveDistribution(requestedDistribution);
  let isInstalled = await validateInstalledAsync(distribution);

  if (!isInstalled && process.platform === 'win32' && process.env.NODE_ENV !== 'test') {
    try {
      await execFileAsync(WSL_EXE, ['--install', '-d', distribution, '--no-launch'], { windowsHide: true, timeout: 60000 });
      isInstalled = await validateInstalledAsync(distribution);
    } catch {}
  }

  if (!distribution || !isInstalled) {
    const error = new Error(`Distribuição WSL "${distribution}" não encontrada ou não instalada.`);
    error.code = 'DISTRO_NOT_INSTALLED';
    throw error;
  }

  const rawPkg = resolvePackageNameForDistro(packageId, distribution);
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
      '--user', 'root',
      '--exec', '/bin/sh', '-lc', installCmd
    ], {
      encoding: 'utf8',
      env: safeChildEnvironment(),
      timeout: 120_000,
      windowsHide: true,
      maxBuffer: 4 * 1024 * 1024
    });

    invalidateLinuxDesktopAppCache(distribution);

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
  const distribution = await resolveActiveDistribution(requestedDistribution);

  if (!distribution || !await validateInstalledAsync(distribution)) {
    const error = new Error(`Distribuição WSL "${distribution}" não encontrada ou não instalada.`);
    error.code = 'DISTRO_NOT_INSTALLED';
    throw error;
  }

  const rawPkg = resolvePackageNameForDistro(packageId, distribution);
  const sanitizedPkg = rawPkg.replace(/[^a-zA-Z0-9._+-]/g, '');

  const pm = await detectDistroPackageManager(distribution);
  const removeCmd = buildUninstallCommand(pm, sanitizedPkg);

  try {
    const { stdout, stderr } = await execFileAsync(WSL_EXE, [
      '--distribution', distribution,
      '--user', 'root',
      '--exec', '/bin/sh', '-lc', removeCmd
    ], {
      encoding: 'utf8',
      env: safeChildEnvironment(),
      timeout: 60_000,
      windowsHide: true,
      maxBuffer: 2 * 1024 * 1024
    });

    invalidateLinuxDesktopAppCache(distribution);

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

  const distribution = await resolveActiveDistribution(requestedDistribution);

  if (!distribution || !await validateInstalledAsync(distribution)) {
    return { results: [], error: `Distribuição "${distribution}" não instalada.` };
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
