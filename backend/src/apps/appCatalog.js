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
const WINDOWS_SCRIPT_EXTENSIONS = new Set(['.bat', '.cmd']);
const catalogById = new Map();
let cachedCatalog = [];
let cacheTimestamp = 0;
let refreshInFlight = null;
const CACHE_TTL_MS = 60_000;
const MAX_SHORTCUT_ARGUMENTS = 128;
const MAX_SHORTCUT_ARGUMENT_LENGTH = 8_192;

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
  const directWindowsLaunch = [
    'windows-executable',
    'windows-shortcut-direct',
    'windows-shortcut-argv',
    'windows-script-direct'
  ].includes(app.kind);
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

function shortcutIdentityKey(targetPath, parsedArguments, argumentsText = '') {
  const targetKey = String(targetPath || '').trim().toLowerCase();
  if (!targetKey) return null;
  const argumentKey = Array.isArray(parsedArguments)
    ? JSON.stringify(parsedArguments)
    : `raw:${String(argumentsText || '')}`;
  return `${targetKey}\0${argumentKey}`;
}

function windowsCommandProcessor() {
  const systemRoot = String(process.env.SystemRoot || process.env.WINDIR || '').trim();
  if (!path.win32.isAbsolute(systemRoot)) return null;
  return path.win32.join(systemRoot, 'System32', 'cmd.exe');
}

export function buildWindowsScriptArguments(scriptPath) {
  // `cmd /s /c "C:\\path with spaces\\script.cmd"` strips the command's
  // outer quotes before execution and truncates the path at the first space.
  // A fixed CALL token keeps the quoted script path as a distinct command
  // operand while preserving the bounded, non-user-controlled shell grammar.
  return ['/d', '/s', '/v:off', '/c', 'call', scriptPath];
}

// Parse only the documented Windows backslash/quote grammar used by conventional
// Win32 argv consumers. Malformed/unbalanced input fails closed instead of being
// approximated. The Host will quote each resulting argv entry again before
// CreateProcessW, preserving the parsed argument boundaries without invoking a shell.
export function parseWindowsShortcutArguments(value) {
  const input = typeof value === 'string' ? value.trim() : '';
  if (!input) return [];
  if (input.length > 16_384 || /[\0\r\n]/.test(input)) return null;

  const args = [];
  let index = 0;
  while (index < input.length) {
    while (index < input.length && /[ \t]/.test(input[index])) index += 1;
    if (index >= input.length) break;
    if (args.length >= MAX_SHORTCUT_ARGUMENTS) return null;

    let argument = '';
    let inQuotes = false;
    let started = false;
    while (index < input.length) {
      if (!inQuotes && /[ \t]/.test(input[index])) break;

      let backslashes = 0;
      while (index < input.length && input[index] === '\\') {
        backslashes += 1;
        index += 1;
      }

      if (index < input.length && input[index] === '"') {
        argument += '\\'.repeat(Math.floor(backslashes / 2));
        if (backslashes % 2 === 1) {
          argument += '"';
        } else {
          inQuotes = !inQuotes;
        }
        started = true;
        index += 1;
        continue;
      }

      argument += '\\'.repeat(backslashes);
      if (index >= input.length) break;
      argument += input[index];
      started = true;
      index += 1;
      if (argument.length > MAX_SHORTCUT_ARGUMENT_LENGTH) return null;
    }

    if (inQuotes || !started || argument.length > MAX_SHORTCUT_ARGUMENT_LENGTH) return null;
    args.push(argument);
    while (index < input.length && /[ \t]/.test(input[index])) index += 1;
  }

  return args;
}

export function parseWindowsAppDiscovery(payload, existingApps = []) {
  const directIdentities = new Set(existingApps.map((app) => {
    const targetPath = String(app?.targetPath || app?.executable || '').trim();
    if (!targetPath) return null;
    return shortcutIdentityKey(targetPath, Array.isArray(app.args) ? app.args : []);
  }).filter(Boolean));
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

    const targetExtension = path.win32.extname(targetPath).toLowerCase();
    const executableTarget = targetExtension === '.exe';
    const scriptTarget = WINDOWS_SCRIPT_EXTENSIONS.has(targetExtension);
    if (!path.win32.isAbsolute(targetPath) || (!executableTarget && !scriptTarget)) continue;
    if (scriptTarget && /[%\r\n\0]/.test(targetPath)) continue;
    if (executableTarget && BLOCKED_SHORTCUT_TARGETS.has(path.win32.basename(targetPath).toLowerCase())) continue;

    const parsedArguments = executableTarget
      ? (argumentsText ? parseWindowsShortcutArguments(argumentsText) : [])
      : (argumentsText ? null : []);
    const identityKey = shortcutIdentityKey(targetPath, parsedArguments, argumentsText);
    const nameKey = normalizedDisplayName(name);
    if (identityKey && directIdentities.has(identityKey)) continue;
    if (identityKey) directIdentities.add(identityKey);
    directNames.add(nameKey);

    const directKind = !argumentsText
      ? (scriptTarget ? 'windows-script-direct' : 'windows-shortcut-direct')
      : (executableTarget && parsedArguments ? 'windows-shortcut-argv' : 'windows-shortcut');
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
      args: directKind === 'windows-shortcut-argv' ? parsedArguments : [],
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
    'foreach ($root in $shortcutRoots) { Get-ChildItem -LiteralPath $root -Filter *.lnk -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 800 | ForEach-Object { try { $link = $shell.CreateShortcut($_.FullName); $target = [Environment]::ExpandEnvironmentVariables([string]$link.TargetPath); $ext = [IO.Path]::GetExtension($target).ToLowerInvariant(); if ($target -and @(".exe", ".bat", ".cmd") -contains $ext -and (Test-Path -LiteralPath $target -PathType Leaf)) { $shortcuts += [PSCustomObject]@{ Name = $_.BaseName; ShortcutPath = $_.FullName; TargetPath = [IO.Path]::GetFullPath($target); Arguments = [string]$link.Arguments; WorkingDirectory = [Environment]::ExpandEnvironmentVariables([string]$link.WorkingDirectory) } } } catch {} } }',
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

  const launchKind = app.kind;
  const scriptLaunch = launchKind === 'windows-script-direct';
  const shortcutLaunch = launchKind === 'windows-shortcut-direct' || launchKind === 'windows-shortcut-argv';
  const executable = scriptLaunch
    ? windowsCommandProcessor()
    : (shortcutLaunch ? app.targetPath : app.executable);
  if (!['windows-shortcut-direct', 'windows-shortcut-argv', 'windows-executable', 'windows-script-direct'].includes(launchKind)
      || !path.win32.isAbsolute(String(executable || ''))) {
    throw Object.assign(new Error('Tipo de aplicativo não suportado sob containment.'), { code: 'APP_KIND_UNSUPPORTED' });
  }

  const scriptPath = scriptLaunch ? String(app.targetPath || '') : null;
  if (scriptLaunch && (!path.win32.isAbsolute(scriptPath) || !WINDOWS_SCRIPT_EXTENSIONS.has(path.win32.extname(scriptPath).toLowerCase()) || /[%\0\r\n]/.test(scriptPath))) {
    throw Object.assign(new Error('Script Windows inválido para execução contida.'), { code: 'APP_SCRIPT_INVALID' });
  }

  const launchArguments = scriptLaunch
    ? buildWindowsScriptArguments(scriptPath)
    : (launchKind === 'windows-shortcut-direct'
        ? []
        : (Array.isArray(app.args) ? app.args.filter((value) => typeof value === 'string' && !/[\0\r\n]/.test(value)).slice(0, 128) : []));
  const workingDirectory = scriptLaunch
    ? (app.workingDirectory || path.win32.dirname(scriptPath))
    : (app.workingDirectory || path.win32.dirname(executable));

  return {
    id: app.id,
    name: app.name,
    source: app.source,
    distribution: null,
    windowMode: 'native-managed',
    launchKind,
    launchSpec: {
      executable,
      arguments: launchArguments,
      workingDirectory
    },
    containment: { required: true, correlation: 'direct-pid-job-tree', startedHidden: true, createSuspended: true }
  };
}

export function resetAppCatalogForTests() {
  catalogById.clear();
  cachedCatalog = [];
  cacheTimestamp = 0;
  refreshInFlight = null;
}
