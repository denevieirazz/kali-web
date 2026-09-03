import dns from 'node:dns/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { safeChildEnvironment } from '../wsl/distroService.js';
import { normalizeAssessmentTarget } from './networkAssessment.js';
import { getNetworkDiagnostics } from './networkDiagnostics.js';

const execFileAsync = promisify(execFile);
const MAX_COMMAND_OUTPUT = 64 * 1024;
const MAX_HOPS = 8;

function clean(value, max = MAX_COMMAND_OUTPUT) {
  return String(value || '').replace(/\u0000/g, '').slice(0, max).trim();
}

function boundedAverage(values) {
  if (!Array.isArray(values) || values.length === 0) return null;
  return Math.round((values.reduce((sum, value) => sum + value, 0) / values.length) * 10) / 10;
}

export function parsePingOutput(output, attempts = 3) {
  const samplesMs = [];
  let ttl = null;
  for (const line of String(output || '').split(/\r?\n/)) {
    const timeMatch = line.match(/(?:time|tempo)?\s*([=<])\s*(\d+)\s*ms/i);
    const ttlMatch = line.match(/ttl\s*=\s*(\d+)/i);
    if (timeMatch) samplesMs.push(Number(timeMatch[2]));
    if (ttlMatch && ttl === null) ttl = Number(ttlMatch[1]);
  }
  const replies = Math.min(Math.max(0, attempts), samplesMs.length);
  return {
    reachable: replies > 0,
    attempts,
    replies,
    lossPercent: attempts > 0 ? Math.max(0, Math.min(100, Math.round(((attempts - replies) / attempts) * 100))) : null,
    samplesMs,
    minMs: samplesMs.length ? Math.min(...samplesMs) : null,
    maxMs: samplesMs.length ? Math.max(...samplesMs) : null,
    averageMs: boundedAverage(samplesMs),
    ttl,
  };
}

function looksLikeIpv4(value) {
  const parts = String(value || '').split('.');
  if (parts.length !== 4 || parts.some(part => !/^\d{1,3}$/.test(part))) return false;
  return parts.every(part => Number(part) >= 0 && Number(part) <= 255);
}

export function parseTracerouteOutput(output) {
  const hops = [];
  for (const rawLine of String(output || '').split(/\r?\n/)) {
    const match = rawLine.match(/^\s*(\d{1,2})\s+(.+)$/);
    if (!match) continue;
    const hop = Number(match[1]);
    if (!Number.isInteger(hop) || hop < 1 || hop > MAX_HOPS) continue;
    const remainder = match[2];
    const address = remainder.match(/\b(?:\d{1,3}\.){3}\d{1,3}\b/)?.[0] || null;
    const safeAddress = address && looksLikeIpv4(address) ? address : null;
    const timesMs = [...remainder.matchAll(/<?(\d+)\s*ms/gi)].map(item => Number(item[1])).slice(0, 3);
    hops.push({
      hop,
      address: safeAddress,
      averageMs: boundedAverage(timesMs),
      samplesMs: timesMs,
      timedOut: safeAddress === null && timesMs.length === 0,
    });
  }
  return hops.slice(0, MAX_HOPS);
}

async function runPing(target) {
  const windows = process.platform === 'win32';
  const file = windows ? 'ping.exe' : 'ping';
  const args = windows ? ['-n', '3', '-w', '1200', target] : ['-c', '3', '-W', '1', target];
  let output = '';
  let available = true;
  try {
    const result = await execFileAsync(file, args, {
      encoding: 'utf8', windowsHide: true, timeout: 6000,
      maxBuffer: MAX_COMMAND_OUTPUT, env: safeChildEnvironment(),
    });
    output = result.stdout;
  } catch (error) {
    if (error?.code === 'ENOENT') available = false;
    output = error?.stdout || '';
  }
  return {
    available,
    ...parsePingOutput(output, 3),
    rawSummary: clean(output, 12 * 1024),
    source: windows ? 'windows-ping' : 'host-ping',
  };
}

async function runTraceroute(target) {
  const windows = process.platform === 'win32';
  const file = windows ? 'tracert.exe' : 'traceroute';
  const args = windows
    ? ['-d', '-h', String(MAX_HOPS), '-w', '800', target]
    : ['-n', '-m', String(MAX_HOPS), '-w', '1', target];
  let output = '';
  let available = true;
  try {
    const result = await execFileAsync(file, args, {
      encoding: 'utf8', windowsHide: true, timeout: 12_000,
      maxBuffer: MAX_COMMAND_OUTPUT, env: safeChildEnvironment(),
    });
    output = result.stdout;
  } catch (error) {
    if (error?.code === 'ENOENT') available = false;
    output = error?.stdout || '';
  }
  const hops = parseTracerouteOutput(output);
  return {
    available,
    hops,
    hopCount: hops.filter(item => item.address).length,
    rawSummary: clean(output, 16 * 1024),
    source: windows ? 'windows-tracert' : 'host-traceroute',
  };
}

async function reverseDns(target) {
  const timeout = new Promise(resolve => setTimeout(() => resolve([]), 2500));
  try {
    const names = await Promise.race([dns.reverse(target), timeout]);
    return Array.isArray(names) ? names.filter(name => typeof name === 'string' && name.length <= 255).slice(0, 8) : [];
  } catch {
    return [];
  }
}

function buildDefensiveNextSteps({ reachability, neighbor, route, reverseNames, isGateway }) {
  const steps = [];
  if (neighbor) steps.push('O dispositivo aparece no cache ARP local; confirme o proprietário e a função do ativo antes de aprofundar a avaliação.');
  if (isGateway) steps.push('O alvo coincide com o gateway preferido; priorize revisão de firmware, configuração administrativa e segmentação, sem executar testes destrutivos.');
  if (reachability.reachable) steps.push('O host respondeu ao diagnóstico de conectividade; compare esse estado com inventários anteriores para detectar mudanças inesperadas.');
  else steps.push('O host não respondeu ao ICMP nesta coleta; isso pode ser filtragem e não prova que o dispositivo esteja offline.');
  if (route.hopCount > 1) steps.push('O caminho contém mais de um salto; registre o segmento/roteador intermediário para contextualizar regras de firewall e ACL.');
  if (reverseNames.length) steps.push('Há nome(s) PTR disponível(is); use-os apenas como pista de inventário e confirme a identidade do ativo por uma fonte administrativa.');
  if (!steps.length) steps.push('Colete inventário administrativo do ativo e compare com a superfície observada antes de concluir qualquer risco.');
  return steps.slice(0, 6);
}

export async function getHostDiagnostics(rawTarget) {
  const target = normalizeAssessmentTarget(rawTarget, { allowCidr: false });
  const startedAt = new Date().toISOString();
  const started = Date.now();

  const [reachability, route, reverseNames, network] = await Promise.all([
    runPing(target),
    runTraceroute(target),
    reverseDns(target),
    getNetworkDiagnostics(),
  ]);

  const neighbor = network.neighbors.find(item => item.address === target) || null;
  const matchingRoute = network.defaultRoutes.find(item => item.gateway === target) || null;
  const isGateway = Boolean(matchingRoute);

  return {
    schemaVersion: 1,
    kind: 'cloudos-private-host-diagnostics',
    target,
    startedAt,
    completedAt: new Date().toISOString(),
    durationMs: Date.now() - started,
    identity: {
      reverseDns: reverseNames,
      mac: neighbor?.mac || null,
      neighborState: neighbor?.state || null,
      interfaceAddress: neighbor?.interfaceAddress || matchingRoute?.interfaceAddress || null,
      isDefaultGateway: isGateway,
    },
    reachability,
    route,
    localNetwork: {
      defaultGateway: network.defaultRoutes[0]?.gateway || null,
      dnsServers: network.dnsServers,
    },
    nextSteps: buildDefensiveNextSteps({ reachability, neighbor, route, reverseNames, isGateway }),
    policy: {
      privateIpv4Only: true,
      activeProbe: true,
      methods: ['icmp-echo', 'bounded-traceroute', 'reverse-dns', 'passive-arp-correlation'],
      maxTracerouteHops: MAX_HOPS,
      arbitraryArguments: false,
      credentialAttacks: false,
      activeWirelessAttacks: false,
    },
  };
}
