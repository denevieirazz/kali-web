import { execFile, execFileSync, spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
const WINDOWS_DIRECTORY = process.env.WINDIR || process.env.SystemRoot || 'C:\\Windows';
export const WSL_EXE = path.join(WINDOWS_DIRECTORY, 'System32', 'wsl.exe');
const POWERSHELL_EXE = path.join(WINDOWS_DIRECTORY, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
const SAFE_NAME = /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$/;

export function safeChildEnvironment(extra = {}) {
  const environment = {};
  for (const [key, value] of Object.entries(process.env)) {
    if (/(?:SECRET|TOKEN|PASSWORD|CREDENTIAL|PRIVATE_KEY|API_KEY|JWT)/i.test(key)) continue;
    if (typeof value === 'string') environment[key] = value;
  }
  return { ...environment, ...extra };
}

function normalizeOutput(value) {
  if (typeof value === 'string') return value.replace(/\0/g, '').replace(/^\uFEFF/, '');
  const buffer = Buffer.isBuffer(value) ? value : Buffer.from(value || '');
  let zeroes = 0;
  for (let index = 1; index < Math.min(buffer.length, 200); index += 2) {
    if (buffer[index] === 0) zeroes += 1;
  }
  const likelyUtf16 = buffer.length > 3 && zeroes > Math.min(10, Math.floor(buffer.length / 10));
  return buffer.toString(likelyUtf16 ? 'utf16le' : 'utf8').replace(/\0/g, '').replace(/^\uFEFF/, '');
}

async function runWsl(args, timeout = 8000) {
  if (process.platform !== 'win32' || !fs.existsSync(WSL_EXE)) {
    const error = new Error('WSL só está disponível no host Windows.');
    error.code = 'WSL_NOT_FOUND';
    throw error;
  }
  try {
    const { stdout, stderr } = await execFileAsync(WSL_EXE, args, {
      encoding: 'buffer',
      env: safeChildEnvironment(),
      timeout,
      windowsHide: true,
      maxBuffer: 2 * 1024 * 1024
    });
    return normalizeOutput(stdout || stderr);
  } catch (error) {
    const diagnostic = [error.stderr, error.stdout].find((value) =>
      Buffer.isBuffer(value) ? value.length > 0 : typeof value === 'string' && value.length > 0
    ) || error.message;
    const detail = normalizeOutput(diagnostic).trim();
    const normalized = new Error(detail || 'O WSL não respondeu à solicitação.');
    normalized.code = classifyWslError(detail, error);
    normalized.cause = error;
    throw normalized;
  }
}

export function classifyWslError(detail, error = {}) {
  const text = String(detail || '').toLowerCase();
  if (error.code === 'ENOENT') return 'WSL_NOT_FOUND';
  if (error.killed || error.signal === 'SIGTERM') return 'WSL_TIMEOUT';
  if (text.includes('e_accessdenied') || text.includes('access is denied') || text.includes('acesso negado')) return 'WSL_ACCESS_DENIED';
  if (text.includes('requires elevation') || text.includes('administrator') || text.includes('administrador')) return 'ELEVATION_REQUIRED';
  if (text.includes('reboot') || text.includes('reinici')) return 'REBOOT_REQUIRED';
  return 'WSL_COMMAND_FAILED';
}

export function getRawWslListOutput() {
  try {
    const raw = execFileSync(WSL_EXE, ['--list', '--verbose'], { timeout: 3000 });
    return normalizeOutput(raw);
  } catch {
    return '';
  }
}

export function parseWslListOutput(output) {
  const lines = normalizeOutput(output)
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  const distros = [];
  for (const line of lines) {
    const upper = line.toUpperCase();
    if ((upper.includes('NAME') || upper.includes('NOME')) && (upper.includes('STATE') || upper.includes('ESTADO'))) continue;
    if (/^(distribui|default|padrão|padrao)/i.test(line)) continue;
    const isDefault = line.startsWith('*');
    const cleanLine = line.replace(/^\*\s*/, '').trim();
    const match = cleanLine.match(/^(.*?)\s+(Running|Stopped|Installing|Uninstalling|Convertendo|Em execu[cç][aã]o|Parado|Instalando)\s+(\d+)$/i);
    if (match) {
      distros.push({ name: match[1].trim(), state: match[2], version: Number.parseInt(match[3], 10), isDefault });
      continue;
    }
    const parts = cleanLine.split(/\s+/);
    const version = Number.parseInt(parts.at(-1), 10);
    if (parts.length >= 3 && Number.isFinite(version)) {
      distros.push({ name: parts.slice(0, -2).join(' '), state: parts.at(-2), version, isDefault });
    }
  }
  return distros.filter((distro) => distro.name && distro.name.length <= 80);
}

export function parseOnlineCatalogOutput(output) {
  const lines = normalizeOutput(output).split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  const catalog = [];
  for (const line of lines) {
    if (/^(the following|a seguir|name\s+friendly|nome\s+nome)/i.test(line)) continue;
    if (/^[-=]{3,}/.test(line)) continue;
    const columns = line.split(/\s{2,}/).map((column) => column.trim()).filter(Boolean);
    const id = columns[0];
    if (!id || !SAFE_NAME.test(id) || /^(NAME|NOME)$/i.test(id)) continue;
    catalog.push({ id, name: columns.slice(1).join(' ') || id });
  }
  return catalog;
}

export function parseWslVersionOutput(output) {
  const result = { wslVersion: null, kernelVersion: null, wslgVersion: null };
  for (const rawLine of normalizeOutput(output).split(/\r?\n/)) {
    const line = rawLine.trim();
    const value = line.match(/:\s*(.+)$/)?.[1]?.trim() || null;
    if (!value) continue;
    if (/WSLg/i.test(line)) result.wslgVersion = value;
    else if (/^WSL(?:\s+version|\s+vers[aã]o|\s+sürüm|\s+versi[oó]n)/i.test(line) || /^vers[aã]o do WSL\s*:/i.test(line)) result.wslVersion = value;
    else if (/kernel/i.test(line)) result.kernelVersion = value;
  }
  return result;
}

export async function getWslVersionInfo() {
  return parseWslVersionOutput(await runWsl(['--version']));
}

export async function getWslSnapshot() {
  if (process.platform !== 'win32' || !fs.existsSync(WSL_EXE)) {
    return {
      installed: false,
      operational: false,
      errorCode: 'WSL_NOT_FOUND',
      error: 'WSL não está disponível neste host.',
      distributions: [],
      default: null,
      preferred: null
    };
  }
  try {
    const output = await runWsl(['--list', '--verbose']);
    const distributions = parseWslListOutput(output);
    const defaultDistro = distributions.find((distro) => distro.isDefault)?.name || distributions[0]?.name || null;
    const preferred = distributions.find((distro) => distro.name.toLowerCase() === 'kali-linux')?.name || defaultDistro;
    return { installed: true, operational: true, errorCode: null, error: null, distributions, default: defaultDistro, preferred };
  } catch (error) {
    return { installed: true, operational: false, errorCode: error.code, error: error.message, distributions: [], default: null, preferred: null };
  }
}

export async function getHostCapabilities() {
  const wsl = await getWslSnapshot();
  const nativeHostActive = process.env.CLOUDOS_NATIVE_HOST === '1';
  let versionInfo = { wslVersion: null, kernelVersion: null, wslgVersion: null };
  if (wsl.installed) {
    try { versionInfo = await getWslVersionInfo(); } catch {}
  }
  const wslgReady = wsl.operational && Boolean(versionInfo.wslgVersion) && wsl.distributions.some((distro) => distro.version === 2);
  return {
    host: {
      platform: process.platform,
      release: os.release(),
      architecture: os.arch(),
      hostname: os.hostname(),
      windows: process.platform === 'win32'
    },
    wsl: { ...wsl, ...versionInfo },
    integration: {
      terminal: true,
      windowsApps: process.platform === 'win32',
      linuxGuiApps: wslgReady,
      windowMode: nativeHostActive ? 'native-managed' : 'native-external',
      nativeHostActive,
      managedNativeWindows: nativeHostActive,
      embeddedNativeWindows: false,
      nativeHostRequired: !nativeHostActive
    },
    limitations: nativeHostActive ? [
      'Aplicativos Windows e WSLg continuam sendo superfícies nativas, mas o host CloudOS acompanha foco, estado e fechamento.',
      'Aplicativos elevados, DRM, anti-cheat e janelas protegidas podem recusar gerenciamento.'
    ] : [
      'Aplicativos Windows e WSLg são abertos como janelas nativas pelo modo web atual.',
      'Gerenciar essas janelas a partir do desktop CloudOS exige o host WebView2.'
    ]
  };
}

export async function listOnlineCatalog() {
  const output = await runWsl(['--list', '--online'], 20000);
  return parseOnlineCatalogOutput(output);
}

export async function isCatalogDistro(name) {
  if (!SAFE_NAME.test(normalizeName(name))) return false;
  const catalog = await listOnlineCatalog();
  return catalog.some((item) => item.id.toLowerCase() === normalizeName(name).toLowerCase());
}

export function createInstallArgs(name) {
  const norm = normalizeName(name);
  if (!SAFE_NAME.test(norm)) throw new Error('Identificador de distribuição inválido.');
  return ['--install', '--distribution', norm, '--no-launch'];
}

export function launchDetached(executable, args, options = {}) {
  const child = spawn(executable, args, {
    cwd: options.cwd,
    env: options.env || safeChildEnvironment(),
    detached: true,
    shell: false,
    stdio: 'ignore',
    windowsHide: false
  });
  child.unref();
  return child.pid;
}

export async function startDistribution(name) {
  if (!await validateInstalledAsync(name)) throw Object.assign(new Error('Distribuição não instalada.'), { code: 'DISTRO_NOT_INSTALLED' });
  return launchDetached(WSL_EXE, ['--distribution', normalizeName(name), '--exec', '/bin/true']);
}

export async function stopDistribution(name) {
  if (!await validateInstalledAsync(name)) throw Object.assign(new Error('Distribuição não instalada.'), { code: 'DISTRO_NOT_INSTALLED' });
  await runWsl(['--terminate', normalizeName(name)], 30000);
}

export async function setDefaultDistribution(name) {
  if (!await validateInstalledAsync(name)) throw Object.assign(new Error('Distribuição não instalada.'), { code: 'DISTRO_NOT_INSTALLED' });
  await runWsl(['--set-default', normalizeName(name)], 30000);
}

export function listInstalled() {
  return parseWslListOutput(getRawWslListOutput());
}

export function getDefault() {
  const distros = listInstalled();
  return distros.find((distro) => distro.isDefault)?.name || distros[0]?.name || null;
}

export function getPreferred() {
  const distros = listInstalled();
  return distros.find((distro) => distro.name.toLowerCase() === 'kali-linux')?.name || getDefault();
}

export function normalizeName(name) {
  return typeof name === 'string' ? name.trim() : '';
}

export function isInstalled(name) {
  const norm = normalizeName(name).toLowerCase();
  return Boolean(norm) && listInstalled().some((distro) => distro.name.toLowerCase() === norm);
}

export function validateAllowlisted(name) {
  const norm = normalizeName(name);
  return SAFE_NAME.test(norm) && isInstalled(norm);
}

export async function validateInstalledAsync(name) {
  const norm = normalizeName(name);
  if (!SAFE_NAME.test(norm)) return false;
  const snapshot = await getWslSnapshot();
  return snapshot.distributions.some((distro) => distro.name.toLowerCase() === norm.toLowerCase());
}

export { POWERSHELL_EXE, SAFE_NAME, runWsl };
