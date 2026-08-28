import { execFile } from 'node:child_process';
import path from 'node:path';
import { promisify } from 'node:util';
import { POWERSHELL_EXE, safeChildEnvironment } from '../wsl/distroService.js';

const execFileAsync = promisify(execFile);
const DIRECT_WINDOWS_LAUNCH_KINDS = new Set([
  'windows-executable',
  'windows-shortcut-direct',
  'windows-shortcut-argv'
]);
const ISOLATED_CHROMIUM_EXECUTABLES = new Set([
  'brave.exe', 'chrome.exe', 'chromium.exe', 'msedge.exe', 'vivaldi.exe', 'opera.exe'
]);
const PER_LAUNCH_TOKEN_PATTERN = /^[a-f0-9]{32}$/i;

function normalizedWindowsPath(value) {
  const candidate = String(value || '').trim();
  if (!path.win32.isAbsolute(candidate) || /[\0\r\n]/.test(candidate)) return null;
  return path.win32.normalize(candidate).toLowerCase();
}

function profilePathHasPerLaunchToken(profilePath, executableName) {
  const normalized = normalizedWindowsPath(profilePath);
  if (!normalized) return false;
  const token = path.win32.basename(normalized);
  const executableDirectory = path.win32.basename(path.win32.dirname(normalized));
  return PER_LAUNCH_TOKEN_PATTERN.test(token)
    && executableDirectory === executableName.toLowerCase();
}

function windowsSwitchKey(argument) {
  const value = String(argument || '').trim().toLowerCase();
  const match = value.match(/^(?:--|-|\/)([^=]+)(?:=.*)?$/);
  return match?.[1] || null;
}

function chromiumProfilePath(argumentsList) {
  for (let index = 0; index < argumentsList.length; index += 1) {
    const argument = String(argumentsList[index] || '');
    const match = argument.match(/^--user-data-dir=(.+)$/i);
    if (match) return match[1];
    if (windowsSwitchKey(argument) === 'user-data-dir' && index + 1 < argumentsList.length) {
      return String(argumentsList[index + 1] || '');
    }
  }
  return null;
}

function firefoxProfilePath(argumentsList) {
  for (let index = 0; index < argumentsList.length - 1; index += 1) {
    if (windowsSwitchKey(argumentsList[index]) !== 'profile') continue;
    return String(argumentsList[index + 1] || '');
  }
  return null;
}

export function hasExplicitPerLaunchInstanceIsolation(launch) {
  const executable = String(launch?.launchSpec?.executable || '');
  const executableName = path.win32.basename(executable).toLowerCase();
  const argumentsList = Array.isArray(launch?.launchSpec?.arguments)
    ? launch.launchSpec.arguments.filter((value) => typeof value === 'string')
    : [];

  if (ISOLATED_CHROMIUM_EXECUTABLES.has(executableName)) {
    const profilePath = chromiumProfilePath(argumentsList);
    return profilePathHasPerLaunchToken(profilePath, executableName)
      && argumentsList.some((argument) => String(argument).toLowerCase() === '--new-window');
  }

  if (executableName === 'firefox.exe') {
    const profilePath = firefoxProfilePath(argumentsList);
    const switches = new Set(argumentsList.map(windowsSwitchKey).filter(Boolean));
    return profilePathHasPerLaunchToken(profilePath, executableName)
      && switches.has('no-remote')
      && switches.has('new-instance');
  }

  return false;
}

export function shouldGuardExternalInstanceHandoff(launch) {
  if (!DIRECT_WINDOWS_LAUNCH_KINDS.has(String(launch?.launchKind || ''))) return false;
  if (!normalizedWindowsPath(launch?.launchSpec?.executable)) return false;
  return !hasExplicitPerLaunchInstanceIsolation(launch);
}

export function evaluateExternalInstanceProbe(executable, rows) {
  const target = normalizedWindowsPath(executable);
  if (!target) return { conflicts: [], unrelated: [], unverifiable: [] };

  const conflicts = [];
  const unrelated = [];
  const unverifiable = [];
  for (const row of Array.isArray(rows) ? rows : []) {
    const pid = Number(row?.pid);
    if (!Number.isInteger(pid) || pid <= 0) continue;
    const candidate = normalizedWindowsPath(row?.path);
    if (!candidate) {
      const item = { pid, reason: 'path-unverifiable' };
      unverifiable.push(item);
      conflicts.push(item);
      continue;
    }
    if (candidate === target) conflicts.push({ pid, reason: 'same-executable' });
    else unrelated.push({ pid, path: candidate });
  }
  return { conflicts, unrelated, unverifiable };
}

async function probeProcessesByExecutableName(executable) {
  const target = normalizedWindowsPath(executable);
  if (!target) throw new Error('invalid executable path');

  const command = [
    '$ErrorActionPreference = "Stop"',
    '[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)',
    '$target = [IO.Path]::GetFullPath([string]$env:CLOUDOS_EXTERNAL_INSTANCE_TARGET)',
    '$name = [IO.Path]::GetFileNameWithoutExtension($target)',
    '$records = @()',
    'foreach ($candidate in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {',
    '  try {',
    '    $candidatePath = $null',
    '    try { $candidatePath = [string]$candidate.Path } catch {}',
    '    if (-not [string]::IsNullOrWhiteSpace($candidatePath)) {',
    '      try { $candidatePath = [IO.Path]::GetFullPath($candidatePath) } catch { $candidatePath = $null }',
    '    }',
    '    $records += [PSCustomObject]@{ pid = [int]$candidate.Id; path = $candidatePath }',
    '  } finally { try { $candidate.Dispose() } catch {} }',
    '}',
    '@($records) | ConvertTo-Json -Compress'
  ].join('; ');
  const encoded = Buffer.from(command, 'utf16le').toString('base64');
  const { stdout } = await execFileAsync(
    POWERSHELL_EXE,
    ['-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', encoded],
    {
      encoding: 'utf8',
      env: {
        ...safeChildEnvironment(),
        CLOUDOS_EXTERNAL_INSTANCE_TARGET: executable
      },
      timeout: 4_000,
      windowsHide: true,
      maxBuffer: 256 * 1024
    }
  );
  const raw = String(stdout || '[]').replace(/^\uFEFF/, '').trim() || '[]';
  const parsed = JSON.parse(raw);
  return Array.isArray(parsed) ? parsed : [parsed];
}

export async function assertNoExternalInstanceHandoffRisk(launch) {
  if (!shouldGuardExternalInstanceHandoff(launch)) {
    return { checked: false, reason: hasExplicitPerLaunchInstanceIsolation(launch) ? 'per-launch-isolated' : 'not-direct-executable' };
  }
  if (process.platform !== 'win32') return { checked: false, reason: 'non-windows-host' };

  let rows;
  try {
    rows = await probeProcessesByExecutableName(launch.launchSpec.executable);
  } catch (error) {
    throw Object.assign(
      new Error('O CloudOS não conseguiu verificar instâncias existentes deste executável com segurança.'),
      { code: 'EXTERNAL_INSTANCE_PROBE_FAILED', cause: error }
    );
  }

  const evaluation = evaluateExternalInstanceProbe(launch.launchSpec.executable, rows);
  if (evaluation.conflicts.length > 0) {
    throw Object.assign(
      new Error('Já existe uma instância do mesmo executável fora deste novo launch. Feche a instância existente e tente novamente para evitar handoff ou adoção entre Jobs.'),
      {
        code: 'EXTERNAL_INSTANCE_CONFLICT',
        conflictingProcessIds: evaluation.conflicts.map((item) => item.pid)
      }
    );
  }

  return { checked: true, conflicts: 0 };
}
