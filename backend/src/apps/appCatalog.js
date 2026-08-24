import crypto from 'node:crypto';
import { execFile } from 'node:child_process';
import path from 'node:path';
import { promisify } from 'node:util';
import { POWERSHELL_EXE, getWslSnapshot, safeChildEnvironment } from '../wsl/distroService.js';
import { scanLinuxDesktopApps, toPublicLinuxDesktopApp } from './linuxDesktopScanner.js';

const execFileAsync = promisify(execFile);
const BLOCKED_SHORTCUT_TARGETS = new Set([
  'cmd.exe', 'powershell.exe', 'pwsh.exe', 'wscript.exe', 'cscript.exe',
  'mshta.exe', 'rundll32.exe', 'regsvr32.exe', 'schtasks.exe', 'wmic.exe',
  'wsl.exe', 'wslg.exe', 'bash.exe', 'explorer.exe', 'runtimebroker.exe',
  'applicationframehost.exe', 'wt.exe', 'windowsterminal.exe'
]);
const catalogById = new Map();
let cachedCatalog = [];
let cacheTimestamp = 0;
let refreshInFlight = null;
const CACHE_TTL_MS = 60_000;

function currentWindowMode() {
  return process.env.CLOUDOS_NATIVE_HOST === '1' ? 'native-managed' : 'unavailable';
}

function opaqueId(...parts) {
  return `native-${crypto.createHash('sha256').update(parts.join('\0')).digest('hex').slice(0, 24)}`;
}

function publicApp(app) {
  if (app.source === 'linux') {
    return {
      ...toPublicLinuxDesktopApp(app),
      windowMode: 'xpra-contained',
      launchable: true
    };
  }
  const directWindowsLaunch = app.kind === 'windows-executable' || app.kind === 'windows-shortcut-direct';
  const launchable = app.source === 'windows'
    ? process.env.CLOUDOS_NATIVE_HOST === '1' && directWindowsLaunch
    : true;
  return {
    id: app.id,
    name: app.name,
    source: app.source,
    distribution: app.distribution || null,
    icon: app.icon,
    iconUrl: app.iconUrl || null,
    comment: app.comment || '',
    keywords: Array.isArray(app.keywords) ? app.keywords : ['Windows'],
    categories: Array.isArray(app.categories) ? app.categories : ['Windows'],
    category: app.category || 'windows',
    mimeTypes: Array.isArray(app.mimeTypes) ? app.mimeTypes : [],
    windowMode: launchable ? currentWindowMode() : 'unavailable',
    launchable
  };
}

function asArray(value) {
  if (Array.isArray(value)) return value;
  return value && typeof value === 'object' ? [value] : [];
}

function normalizedDisplayName(value) {
  return String(value || '').trim().toLocaleLowerCase('pt-BR');
}

export function parseWindowsAppDiscovery(payload, existingApps = []) {
  const directTargets = new Set(existingApps.map((app) => String(app.executable || '').toLowerCase()));
  const directNames = new Set(existingApps.map((app) => normalizedDisplayName(app.name)));
  const wslDistributionNames = new Set(asArray(payload?.WslDistributions).map((name) => normalizedDisplayName(name)).filter(Boolean));
  const shortcuts = [];

  for (const row of asArray(payload?.Shortcuts).slice(0, 1200)) {
    if (typeof row?.Name !== 'string' || typeof row?.ShortcutPath !== 'string' || typeof row?.TargetPath !== 'string') continue;
    const name = row.Name.trim().slice(0, 160);
    const shortcutPath = row.ShortcutPath.trim();
    const targetPath = row.TargetPath.trim();
    const argumentsText = typeof row.Arguments === 'string' ? row.Arguments.trim().slice(0, 16_384) : '';
    const workingDirectory = typeof row.WorkingDirectory === 'string' ? row.WorkingDirectory.trim().slice(0, 4096) : '';
    if (!name || name.includes('\0') || shortcutPath.includes('\0') || targetPath.includes('\0')) continue;
    if (/[\0\r\n]/.test(argumentsText) || /[\0\r\n]/.test(workingDirectory)) continue;
    if (!path.win32.isAbsolute(shortcutPath) || path.win32.extname(shortcutPath).toLowerCase() !== '.lnk') continue;
    if (!path.win32.isAbsolute(targetPath) || path.win32.extname(targetPath).toLowerCase() !== '.exe') continue;
    if (BLOCKED_SHORTCUT_TARGETS.has(path.win32.basename(targetPath).toLowerCase())) continue;

    const targetKey = targetPath.toLowerCase();
    const nameKey = normalizedDisplayName(name);
    if (directTargets.has(targetKey) || directNames.has(nameKey)) continue;
    directTargets.add(targetKey);
    directNames.add(nameKey);
    const directKind = argumentsText ? 'windows-shortcut' : 'windows-shortcut-direct';
    shortcuts.push({
      id: opaqueId(directKind, shortcutPath, targetPath, argumentsText),
      name,
      source: 'windows',
      distribution: null,
      icon: '\u25a6',
      kind: directKind,
      shortcutPath,
      targetPath,
      arguments: argumentsText,
      workingDirectory: path.win32.isAbsolute(workingDirectory) ? workingDirectory : path.win32.dirname(targetPath)
    });
  }

  const startApps = asArray(payload?.StartApps)
    .filter((row) => typeof row?.Name === 'string' && typeof row?.AppID === 'string')
    .slice(0, 600)
    // Windows publishes WSLg/RDP aliases into Get-StartApps. Importing those would
    // bypass the contained Linux scanner and create a real top-level HWND.
    .filter((row) => !/wsl|linux/i.test(row.AppID) && !wslDistributionNames.has(normalizedDisplayName(row.Name)))
    .filter((row) => !directNames.has(normalizedDisplayName(row.Name)))
    .map((row) => ({
      id: opaqueId('windows', row.AppID),
      name: row.Name.trim().slice(0, 160),
      source: 'windows',
      distribution: null,
      icon: '\u25a6',
      kind: 'windows-start-app',
      appUserModelId: row.AppID
    }));

  return [...existingApps, ...shortcuts, ...startApps];
}

async function getWindowsStartApps(wslDistributions = []) {
  if (process.platform !== 'win32') return [];
  const command = [
    '$ErrorActionPreference = "Stop"',
    '[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)',
    '$startApps = @(Get-StartApps | Select-Object Name, AppID)',
    '$shortcutRoots = @([Environment]::GetFolderPath("CommonStartMenu"), [Environment]::GetFolderPath("StartMenu")) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }',
    '$shortcuts = @()',
    '$shell = New-Object -ComObject WScript.Shell',
    'foreach ($root in $shortcutRoots) { Get-ChildItem -LiteralPath $root -Filter *.lnk -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 800 | ForEach-Object { try { $link = $shell.CreateShortcut($_.FullName); $target = [Environment]::ExpandEnvironmentVariables([string]$link.TargetPath); if ($target -and [IO.Path]::GetExtension($target) -ieq ".exe" -and (Test-Path -LiteralPath $target -PathType Leaf)) { $shortcuts += [PSCustomObject]@{ Name = $_.BaseName; ShortcutPath = $_.FullName; TargetPath = [IO.Path]::GetFullPath($target); Arguments = [string]$link.Arguments; WorkingDirectory = [Environment]::ExpandEnvironmentVariables([string]$link.WorkingDirectory) } } } catch {} } }',
    '[PSCustomObject]@{ StartApps = $startApps; Shortcuts = $shortcuts } | ConvertTo-Json -Depth 4 -Compress'
  ].join('; ');
  const encoded = Buffer.from(command, 'utf16le').toString('base64');
  try {
    const { stdout } = await execFileAsync(POWERSHELL_EXE, ['-NoLogo', '-NoProfile', '-EncodedCommand', encoded], {
      encoding: 'utf8',
      env: safeChildEnvironment(),
      timeout: 12_000,
      windowsHide: true,
      maxBuffer: 4 * 1024 * 1024
    });
    const parsed = JSON.parse(String(stdout || '{}').replace(/^\uFEFF/, ''));
    parsed.WslDistributions = wslDistributions;
    return parseWindowsAppDiscovery(parsed);
  } catch {
    return [];
  }
}

export async function refreshAppCatalog(force = false) {
  if (!force && cachedCatalog.length && Date.now() - cacheTimestamp < CACHE_TTL_MS) return [...cachedCatalog];
  if (refreshInFlight) return refreshInFlight;
  refreshInFlight = (async () => {
    const snapshot = await getWslSnapshot();
    const tasks = [getWindowsStartApps(snapshot.distributions?.map((distro) => distro.name) || [])];
    const distros = snapshot.operational ? snapshot.distributions.slice(0, 12) : [];
    tasks.push(...distros.map((distro) => scanLinuxDesktopApps(distro.name, { force })));
    const settled = await Promise.allSettled(tasks);
    const discovered = settled.flatMap((result) => result.status === 'fulfilled' && Array.isArray(result.value) ? result.value : []);
    const nextById = new Map();
    const nextCatalog = [];
    for (const app of discovered) {
      if (!app?.id || !app?.name || nextById.has(app.id)) continue;
      nextById.set(app.id, app);
      nextCatalog.push(publicApp(app));
    }
    nextCatalog.sort((left, right) => left.name.localeCompare(right.name, 'pt-BR'));
    catalogById.clear();
    for (const [id, app] of nextById) catalogById.set(id, app);
    cachedCatalog = nextCatalog;
    cacheTimestamp = Date.now();
    return [...cachedCatalog];
  })().finally(() => { refreshInFlight = null; });
  return refreshInFlight;
}

export async function launchCatalogApp(id) {
  if (!catalogById.has(id)) await refreshAppCatalog(false);
  const app = catalogById.get(id);
  if (!app) throw Object.assign(new Error('Aplicativo não encontrado no catálogo atual.'), { code: 'APP_NOT_FOUND' });
  if (app.source === 'linux' || app.source === 'wsl' || app.kind === 'linux-desktop' || app.kind === 'wsl-desktop') {
    throw Object.assign(new Error('Aplicativos Linux só podem ser iniciados pela superfície Xpra contida do CloudOS.'), {
      code: 'LINUX_CONTAINMENT_REQUIRED'
    });
  }
  if (process.env.CLOUDOS_NATIVE_HOST !== '1') {
    throw Object.assign(new Error('Aplicativos Windows exigem o Host nativo do CloudOS para permanecerem encaixados.'), {
      code: 'NATIVE_CONTAINMENT_REQUIRED'
    });
  }

  if (app.kind === 'windows-start-app') {
    throw Object.assign(new Error('Aplicativos UWP/brokerizados permanecem visíveis no menu, mas não podem ser contidos por PID direto.'), { code: 'APP_NOT_CONTAINABLE' });
  }
  const launchKind = app.kind === 'windows-shortcut-direct' ? 'windows-shortcut-direct' : app.kind;
  const executable = launchKind === 'windows-shortcut-direct' ? app.targetPath : app.executable;
  if (!['windows-shortcut-direct', 'windows-executable'].includes(launchKind) || !path.win32.isAbsolute(String(executable || ''))) {
    throw Object.assign(new Error('Tipo de aplicativo não suportado sob containment.'), { code: 'APP_KIND_UNSUPPORTED' });
  }
  return {
    id: app.id,
    name: app.name,
    source: app.source,
    distribution: null,
    windowMode: 'native-managed',
    launchKind,
    launchSpec: {
      executable,
      arguments: launchKind === 'windows-shortcut-direct'
        ? []
        : (Array.isArray(app.args) ? app.args.filter((value) => typeof value === 'string' && !/[\0\r\n]/.test(value)).slice(0, 128) : []),
      workingDirectory: app.workingDirectory || path.win32.dirname(executable)
    },
    containment: { required: true, correlation: 'direct-pid', startedHidden: true, createSuspended: true }
  };
}

export function resetAppCatalogForTests() {
  catalogById.clear();
  cachedCatalog = [];
  cacheTimestamp = 0;
  refreshInFlight = null;
}
