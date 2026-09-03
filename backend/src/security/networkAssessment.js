import os from 'node:os';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { WSL_EXE, getWslSnapshot, safeChildEnvironment, validateInstalledAsync } from '../wsl/distroService.js';

const execFileAsync = promisify(execFile);
const MAX_OUTPUT = 512 * 1024;

function parseIpv4(value) {
  const parts = String(value || '').split('.');
  if (parts.length !== 4 || parts.some(part => !/^\d{1,3}$/.test(part))) return null;
  const octets = parts.map(Number);
  if (octets.some(part => part < 0 || part > 255)) return null;
  return octets;
}

export function isPrivateIpv4(value) {
  const ip = parseIpv4(value);
  if (!ip) return false;
  const [a, b] = ip;
  return a === 10 || a === 127 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 169 && b === 254);
}

export function normalizeAssessmentTarget(value, { allowCidr = true } = {}) {
  const raw = String(value || '').trim();
  if (!raw || raw.length > 64 || /\s/.test(raw)) {
    const error = new Error('Informe um IPv4 privado/local válido.');
    error.code = 'INVALID_ASSESSMENT_TARGET';
    throw error;
  }

  const [address, prefixRaw, ...rest] = raw.split('/');
  if (rest.length || !isPrivateIpv4(address)) {
    const error = new Error('A avaliação guiada aceita apenas IPv4 privado/local.');
    error.code = 'TARGET_OUTSIDE_LOCAL_SCOPE';
    throw error;
  }

  if (prefixRaw === undefined) return address;
  if (!allowCidr) {
    const error = new Error('Este preset aceita somente um dispositivo, não uma faixa CIDR.');
    error.code = 'CIDR_NOT_ALLOWED';
    throw error;
  }
  if (!/^\d{1,2}$/.test(prefixRaw)) {
    const error = new Error('Prefixo CIDR inválido.');
    error.code = 'INVALID_CIDR';
    throw error;
  }
  const prefix = Number(prefixRaw);
  // At most 256 addresses. This keeps one-click discovery bounded and local.
  if (prefix < 24 || prefix > 32) {
    const error = new Error('A descoberta guiada limita a faixa a /24 ou menor (até 256 endereços).');
    error.code = 'CIDR_TOO_LARGE';
    throw error;
  }
  return `${address}/${prefix}`;
}

function prefixFromNetmask(netmask) {
  const octets = parseIpv4(netmask);
  if (!octets) return null;
  const bits = octets.map(octet => octet.toString(2).padStart(8, '0')).join('');
  if (!/^1*0*$/.test(bits)) return null;
  return bits.indexOf('0') === -1 ? 32 : bits.indexOf('0');
}

function networkAddress(address, prefix) {
  const ip = parseIpv4(address);
  if (!ip || !Number.isInteger(prefix)) return null;
  const value = (((ip[0] << 24) >>> 0) + (ip[1] << 16) + (ip[2] << 8) + ip[3]) >>> 0;
  const mask = prefix === 0 ? 0 : (0xffffffff << (32 - prefix)) >>> 0;
  const network = (value & mask) >>> 0;
  return `${network >>> 24}.${(network >>> 16) & 255}.${(network >>> 8) & 255}.${network & 255}/${prefix}`;
}

export function getLocalNetworkOverview() {
  const interfaces = [];
  for (const [name, entries] of Object.entries(os.networkInterfaces())) {
    for (const entry of entries || []) {
      if (entry.family !== 'IPv4') continue;
      const prefix = entry.cidr ? Number(entry.cidr.split('/')[1]) : prefixFromNetmask(entry.netmask);
      const privateLocal = isPrivateIpv4(entry.address);
      interfaces.push({
        name,
        address: entry.address,
        netmask: entry.netmask,
        cidr: Number.isInteger(prefix) ? networkAddress(entry.address, prefix) : null,
        internal: Boolean(entry.internal),
        privateLocal,
        suggestedDiscoveryTarget: privateLocal && Number.isInteger(prefix)
          ? networkAddress(entry.address, Math.max(24, prefix))
          : null,
      });
    }
  }
  return {
    host: os.hostname(),
    platform: process.platform,
    interfaces,
    suggestedTargets: [...new Set(interfaces.map(item => item.suggestedDiscoveryTarget).filter(Boolean))],
  };
}

function cleanCommandOutput(value, maxLength = 48 * 1024) {
  return String(value || '').replace(/\u0000/g, '').slice(0, maxLength).trim();
}

async function netshWlan(args) {
  if (process.platform !== 'win32') return { available: false, output: '' };
  try {
    const { stdout } = await execFileAsync('netsh.exe', ['wlan', ...args], {
      encoding: 'utf8', windowsHide: true, timeout: 10_000, maxBuffer: 128 * 1024,
      env: safeChildEnvironment(),
    });
    return { available: true, output: cleanCommandOutput(stdout) };
  } catch (error) {
    return { available: false, output: cleanCommandOutput(error?.stdout || '') };
  }
}

export async function getWifiDiagnostics() {
  const [interfaces, networks] = await Promise.all([
    netshWlan(['show', 'interfaces']),
    netshWlan(['show', 'networks', 'mode=bssid']),
  ]);
  return {
    available: interfaces.available || networks.available,
    source: process.platform === 'win32' ? 'windows-netsh' : 'unsupported-host',
    interfaces: interfaces.output,
    visibleNetworks: networks.output,
    note: 'Diagnóstico somente leitura: não ativa monitor mode, deauth, injeção ou captura de credenciais.',
  };
}

function parseGreppableNmap(output) {
  const hosts = new Map();
  for (const line of String(output || '').split(/\r?\n/)) {
    if (!line.startsWith('Host: ')) continue;
    const ip = line.match(/^Host:\s+(\S+)/)?.[1];
    if (!ip) continue;
    const current = hosts.get(ip) || { address: ip, hostname: '', up: false, ports: [] };
    const hostname = line.match(/^Host:\s+\S+\s+\(([^)]*)\)/)?.[1];
    if (hostname) current.hostname = hostname;
    if (/\bStatus:\s+Up\b/i.test(line)) current.up = true;
    const portsPart = line.match(/\bPorts:\s+(.+?)(?:\s+Ignored State:|$)/)?.[1];
    if (portsPart) {
      current.ports = portsPart.split(',').map(item => item.trim()).filter(Boolean).map(item => {
        const fields = item.split('/');
        return {
          port: Number(fields[0]) || null,
          state: fields[1] || 'unknown',
          protocol: fields[2] || '',
          service: fields[4] || '',
          version: fields[6] || '',
        };
      }).filter(port => port.port !== null);
      current.up = true;
    }
    hosts.set(ip, current);
  }
  return [...hosts.values()];
}

const PRESETS = Object.freeze({
  discover: {
    label: 'Descobrir dispositivos',
    allowCidr: true,
    timeout: 45_000,
    args: target => ['-sn', '-n', '--max-retries', '1', '--host-timeout', '5s', '-oG', '-', target],
  },
  services: {
    label: 'Inventariar serviços',
    allowCidr: false,
    timeout: 50_000,
    args: target => ['-sT', '-sV', '--version-light', '-n', '--top-ports', '50', '--max-retries', '1', '--host-timeout', '30s', '-oG', '-', target],
  },
  commonPorts: {
    label: 'Checar portas comuns',
    allowCidr: false,
    timeout: 35_000,
    args: target => ['-sT', '-n', '--top-ports', '25', '--max-retries', '1', '--host-timeout', '20s', '-oG', '-', target],
  },
});

export function publicNetworkAssessmentPresets() {
  return Object.entries(PRESETS).map(([id, preset]) => ({ id, label: preset.label }));
}

export async function runNetworkAssessment({ preset: presetId, target: rawTarget, distribution: requestedDistribution }) {
  const preset = PRESETS[presetId];
  if (!preset) {
    const error = new Error('Preset de avaliação desconhecido.');
    error.code = 'UNKNOWN_ASSESSMENT_PRESET';
    throw error;
  }
  const target = normalizeAssessmentTarget(rawTarget, { allowCidr: preset.allowCidr });
  const snapshot = await getWslSnapshot();
  if (!snapshot.operational) {
    const error = new Error(snapshot.error || 'WSL não está operacional.');
    error.code = snapshot.errorCode || 'WSL_NOT_OPERATIONAL';
    throw error;
  }
  const distribution = typeof requestedDistribution === 'string' && requestedDistribution.trim()
    ? requestedDistribution.trim()
    : snapshot.preferred || snapshot.default;
  if (!distribution || !await validateInstalledAsync(distribution)) {
    const error = new Error('Distribuição WSL não encontrada.');
    error.code = 'DISTRO_NOT_INSTALLED';
    throw error;
  }

  try {
    const { stdout, stderr } = await execFileAsync(WSL_EXE, [
      '--distribution', distribution, '--exec', 'nmap', ...preset.args(target),
    ], {
      encoding: 'utf8', env: safeChildEnvironment(), windowsHide: true,
      timeout: preset.timeout, maxBuffer: MAX_OUTPUT,
    });
    return {
      preset: presetId,
      label: preset.label,
      target,
      distribution,
      hosts: parseGreppableNmap(stdout),
      rawSummary: cleanCommandOutput(stdout, 24 * 1024),
      warnings: cleanCommandOutput(stderr, 8 * 1024),
      completedAt: new Date().toISOString(),
    };
  } catch (error) {
    const wrapped = new Error(error?.code === 'ENOENT'
      ? 'Nmap não está instalado na distribuição selecionada.'
      : 'A avaliação de rede não foi concluída. Verifique o Nmap e a conectividade local.');
    wrapped.code = error?.code === 'ENOENT' ? 'NMAP_NOT_INSTALLED' : 'NETWORK_ASSESSMENT_FAILED';
    throw wrapped;
  }
}
