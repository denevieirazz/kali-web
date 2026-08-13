import crypto from 'node:crypto';
import { execFile } from 'node:child_process';
import path from 'node:path';
import { promisify } from 'node:util';
import { POWERSHELL_EXE, WSL_EXE, getWslSnapshot, launchDetached, safeChildEnvironment } from '../wsl/distroService.js';

const execFileAsync = promisify(execFile);
const WINDOWS_DIRECTORY = process.env.WINDIR || process.env.SystemRoot || 'C:\\Windows';
const EXPLORER_EXE = path.join(WINDOWS_DIRECTORY, 'explorer.exe');
const BLOCKED_SHORTCUT_TARGETS = new Set([
  'cmd.exe', 'powershell.exe', 'pwsh.exe', 'wscript.exe', 'cscript.exe',
  'mshta.exe', 'rundll32.exe', 'regsvr32.exe', 'schtasks.exe', 'wmic.exe'
]);
const catalogById = new Map();
let cachedCatalog = [];
let cacheTimestamp = 0;
const CACHE_TTL_MS = 60_000;

function currentWindowMode() {
  return process.env.CLOUDOS_NATIVE_HOST === '1' ? 'native-managed' : 'native-external';
}

function opaqueId(...parts) {
  return `native-${crypto.createHash('sha256').update(parts.join('\0')).digest('hex').slice(0, 24)}`;
}

function publicApp(app) {
  return {
    id: app.id,
    name: app.name,
    source: app.source,
    distribution: app.distribution || null,
    icon: app.icon,
    windowMode: currentWindowMode()
  };
}

function register(app) {
  if (!app?.id || !app?.name || catalogById.has(app.id)) return;
  catalogById.set(app.id, app);
  cachedCatalog.push(publicApp(app));
}

function asArray(value) {
  if (Array.isArray(value)) return value;
  return value && typeof value === 'object' ? [value] : [];
}

function normalizedDisplayName(value) {
  return String(value || '').trim().toLocaleLowerCase('pt-BR');
}

export function parseWindowsAppDiscovery(payload, curatedApps = []) {
  const directTargets = new Set(curatedApps.map((app) => String(app.executable || '').toLowerCase()));
  const directNames = new Set(curatedApps.map((app) => normalizedDisplayName(app.name)));
  const shortcuts = [];

  for (const row of asArray(payload?.Shortcuts).slice(0, 1200)) {
    if (typeof row?.Name !== 'string' || typeof row?.ShortcutPath !== 'string' || typeof row?.TargetPath !== 'string') continue;
    const name = row.Name.trim().slice(0, 160);
    const shortcutPath = row.ShortcutPath.trim();
    const targetPath = row.TargetPath.trim();
    if (!name || name.includes('\0') || shortcutPath.includes('\0') || targetPath.includes('\0')) continue;
    if (!path.win32.isAbsolute(shortcutPath) || path.win32.extname(shortcutPath).toLowerCase() !== '.lnk') continue;
    if (!path.win32.isAbsolute(targetPath) || path.win32.extname(targetPath).toLowerCase() !== '.exe') continue;
    if (BLOCKED_SHORTCUT_TARGETS.has(path.win32.basename(targetPath).toLowerCase())) continue;

    const targetKey = targetPath.toLowerCase();
    const nameKey = normalizedDisplayName(name);
    if (directTargets.has(targetKey) || directNames.has(nameKey)) continue;
    directTargets.add(targetKey);
    directNames.add(nameKey);
    shortcuts.push({
      id: opaqueId('windows-shortcut', shortcutPath, targetPath),
      name,
      source: 'windows',
      distribution: null,
      icon: '\u25a6',
      kind: 'windows-shortcut',
      shortcutPath,
      targetPath
    });
  }

  const startApps = asArray(payload?.StartApps)
    .filter((row) => typeof row?.Name === 'string' && typeof row?.AppID === 'string')
    .slice(0, 600)
    .filter((row) => !directNames.has(normalizedDisplayName(row.Name)))
    .map((row) => ({
      id: opaqueId('windows', row.AppID),
      name: row.Name.trim().slice(0, 160),
      source: /wsl|linux/i.test(row.AppID) ? 'wsl' : 'windows',
      distribution: null,
      icon: /wsl|linux/i.test(row.AppID) ? '\ud83d\udc27' : '\u25a6',
      kind: 'windows-start-app',
      appUserModelId: row.AppID
    }));

  return [...curatedApps, ...shortcuts, ...startApps];
}

async function getWindowsStartApps() {
  if (process.platform !== 'win32') return [];
  const fallbackApps = () => [
    ['Bloco de Notas do Windows', path.join(WINDOWS_DIRECTORY, 'System32', 'notepad.exe'), '▤'],
    ['Explorador de Arquivos do Windows', EXPLORER_EXE, '▱'],
    ['Gerenciador de Tarefas do Windows', path.join(WINDOWS_DIRECTORY, 'System32', 'Taskmgr.exe'), '▥'],
    ['Calculadora do Windows', path.join(WINDOWS_DIRECTORY, 'System32', 'calc.exe'), '＋']
  ].map(([name, executable, icon]) => ({
    id: opaqueId('windows-executable', executable),
    name,
    source: 'windows',
    distribution: null,
    icon,
    kind: 'windows-executable',
    executable,
    args: []
  }));
  const curatedApps = fallbackApps();
  const command = [
    '$ErrorActionPreference = "Stop"',
    '[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)',
    '$startApps = @(Get-StartApps | Select-Object Name, AppID)',
    '$shortcutRoots = @([Environment]::GetFolderPath("CommonStartMenu"), [Environment]::GetFolderPath("StartMenu")) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }',
    '$shortcuts = @()',
    '$shell = New-Object -ComObject WScript.Shell',
    'foreach ($root in $shortcutRoots) { Get-ChildItem -LiteralPath $root -Filter *.lnk -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 800 | ForEach-Object { try { $link = $shell.CreateShortcut($_.FullName); $target = [Environment]::ExpandEnvironmentVariables([string]$link.TargetPath); if ($target -and [IO.Path]::GetExtension($target) -ieq ".exe" -and (Test-Path -LiteralPath $target -PathType Leaf)) { $shortcuts += [PSCustomObject]@{ Name = $_.BaseName; ShortcutPath = $_.FullName; TargetPath = [IO.Path]::GetFullPath($target) } } } catch {} } }',
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
    return parseWindowsAppDiscovery(parsed, curatedApps);
  } catch {
    return curatedApps;
  }
}

const LINUX_DESKTOP_DISCOVERY = [
  'shopt -s nullglob',
  'for file in /usr/share/applications/*.desktop "$HOME"/.local/share/applications/*.desktop; do',
  '  [ -f "$file" ] || continue',
  '  id="${file##*/}"',
  '  id="${id%.desktop}"',
  '  name="$(grep -m1 \'^Name=\' "$file" | cut -d= -f2-)"',
  '  hidden="$(grep -m1 -E \'^(NoDisplay|Hidden)=\' "$file" | cut -d= -f2- | tr \'[:upper:]\' \'[:lower:]\')"',
  '  terminal="$(grep -m1 \'^Terminal=\' "$file" | cut -d= -f2- | tr \'[:upper:]\' \'[:lower:]\')"',
  '  if [ -n "$name" ] && [ "$hidden" != "true" ] && [ "$terminal" != "true" ]; then',
  '    printf \'%s\\037%s\\037%s\\n\' "$id" "$name" "$file"',
  '  fi',
  'done'
].join('\n');

async function getLinuxDesktopApps(distribution) {
  try {
    const { stdout } = await execFileAsync(WSL_EXE, [
      '--distribution', distribution, '--exec', '/bin/bash', '-lc', LINUX_DESKTOP_DISCOVERY
    ], {
      encoding: 'utf8',
      env: safeChildEnvironment(),
      timeout: 12_000,
      windowsHide: true,
      maxBuffer: 4 * 1024 * 1024
    });
    return String(stdout || '')
      .split(/\r?\n/)
      .map((line) => line.split('\x1f'))
      .filter(([desktopId, name, desktopPath]) =>
        /^[a-zA-Z0-9][a-zA-Z0-9._+-]{0,159}$/.test(desktopId || '') &&
        Boolean(name?.trim()) &&
        /^\/(?:usr\/share|home\/[^/]+\/\.local\/share)\/applications\/[^\0]+\.desktop$/.test(desktopPath || '')
      )
      .slice(0, 400)
      .map(([desktopId, name, desktopPath]) => ({
        id: opaqueId('wsl', distribution, desktopId),
        name: name.trim().slice(0, 160),
        source: 'wsl',
        distribution,
        icon: '🐧',
        kind: 'wsl-desktop',
        desktopId,
        desktopPath
      }));
  } catch {
    return [];
  }
}

async function launchWindowsShortcut(app) {
  const command = [
    '$ErrorActionPreference = "Stop"',
    '$shortcutPath = [IO.Path]::GetFullPath($env:CLOUDOS_APP_SHORTCUT)',
    '$expectedTarget = [IO.Path]::GetFullPath($env:CLOUDOS_APP_TARGET)',
    '$shell = New-Object -ComObject WScript.Shell',
    '$link = $shell.CreateShortcut($shortcutPath)',
    '$actualTarget = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$link.TargetPath))',
    'if (-not [StringComparer]::OrdinalIgnoreCase.Equals($actualTarget, $expectedTarget)) { throw "Shortcut target changed after catalog discovery." }',
    '$process = Start-Process -FilePath $shortcutPath -PassThru',
    'if ($null -eq $process -or $process.Id -le 0) { throw "The shortcut did not return a process." }',
    '[Console]::Out.Write([string]$process.Id)'
  ].join('; ');
  const encoded = Buffer.from(command, 'utf16le').toString('base64');
  try {
    const { stdout } = await execFileAsync(POWERSHELL_EXE, ['-NoLogo', '-NoProfile', '-EncodedCommand', encoded], {
      encoding: 'utf8',
      env: safeChildEnvironment({
        CLOUDOS_APP_SHORTCUT: app.shortcutPath,
        CLOUDOS_APP_TARGET: app.targetPath
      }),
      timeout: 15_000,
      windowsHide: true,
      maxBuffer: 128 * 1024
    });
    const pid = Number.parseInt(String(stdout || '').trim(), 10);
    if (!Number.isSafeInteger(pid) || pid <= 0) throw new Error('Invalid process identifier.');
    return pid;
  } catch (cause) {
    throw Object.assign(new Error('O atalho do aplicativo não pôde ser iniciado.'), {
      code: 'APP_SHORTCUT_LAUNCH_FAILED',
      cause
    });
  }
}

export async function refreshAppCatalog(force = false) {
  if (!force && cachedCatalog.length && Date.now() - cacheTimestamp < CACHE_TTL_MS) return [...cachedCatalog];
  catalogById.clear();
  cachedCatalog = [];

  const windowsAppsPromise = getWindowsStartApps();
  const snapshot = await getWslSnapshot();
  const linuxPromises = snapshot.operational
    ? snapshot.distributions.slice(0, 12).map((distro) => getLinuxDesktopApps(distro.name))
    : [];
  const [windowsApps, ...linuxResults] = await Promise.all([windowsAppsPromise, ...linuxPromises]);
  windowsApps.forEach(register);
  linuxResults.flat().forEach(register);
  cachedCatalog.sort((left, right) => left.name.localeCompare(right.name, 'pt-BR'));
  cacheTimestamp = Date.now();
  return [...cachedCatalog];
}

export async function launchCatalogApp(id) {
  if (!catalogById.has(id)) await refreshAppCatalog(false);
  const app = catalogById.get(id);
  if (!app) throw Object.assign(new Error('Aplicativo não encontrado no catálogo atual.'), { code: 'APP_NOT_FOUND' });

  let pid;
  if (app.kind === 'windows-start-app') {
    pid = await launchDetached(EXPLORER_EXE, [`shell:AppsFolder\\${app.appUserModelId}`]);
  } else if (app.kind === 'windows-shortcut') {
    pid = await launchWindowsShortcut(app);
  } else if (app.kind === 'windows-executable') {
    pid = await launchDetached(app.executable, app.args || []);
  } else if (app.kind === 'wsl-desktop') {
    const fixedLauncher = 'if command -v gtk-launch >/dev/null 2>&1; then exec gtk-launch "$1"; elif command -v gio >/dev/null 2>&1; then exec gio launch "$2"; else echo "gtk-launch ou gio não encontrado" >&2; exit 127; fi';
    pid = await launchDetached(WSL_EXE, [
      '--distribution', app.distribution, '--exec', '/bin/sh', '-lc',
      fixedLauncher, 'cloudos-launch', app.desktopId, app.desktopPath
    ]);
  } else {
    throw Object.assign(new Error('Tipo de aplicativo não suportado.'), { code: 'APP_KIND_UNSUPPORTED' });
  }
  return { id: app.id, name: app.name, source: app.source, distribution: app.distribution || null, pid, windowMode: currentWindowMode() };
}

export function resetAppCatalogForTests() {
  catalogById.clear();
  cachedCatalog = [];
  cacheTimestamp = 0;
}
