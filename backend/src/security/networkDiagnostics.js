import dns from 'node:dns';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { safeChildEnvironment } from '../wsl/distroService.js';
import { parseArpTable, parseIpv4RoutePrint } from './networkInsights.js';

const execFileAsync = promisify(execFile);

function clean(value, max = 64 * 1024) {
  return String(value || '').replace(/\u0000/g, '').slice(0, max).trim();
}

async function runReadOnlyWindowsCommand(file, args, timeout = 8000) {
  if (process.platform !== 'win32') return { available: false, output: '', source: 'unsupported-host' };
  try {
    const { stdout } = await execFileAsync(file, args, {
      encoding: 'utf8', windowsHide: true, timeout, maxBuffer: 128 * 1024, env: safeChildEnvironment(),
    });
    return { available: true, output: clean(stdout), source: `windows-${file.toLowerCase()}` };
  } catch (error) {
    return { available: false, output: clean(error?.stdout || ''), source: `windows-${file.toLowerCase()}` };
  }
}

export async function getNetworkDiagnostics() {
  const [arp, route] = await Promise.all([
    runReadOnlyWindowsCommand('arp.exe', ['-a']),
    runReadOnlyWindowsCommand('route.exe', ['print', '-4']),
  ]);

  const dnsServers = dns.getServers().filter(server => typeof server === 'string').slice(0, 16);
  const neighbors = arp.available ? parseArpTable(arp.output).slice(0, 512) : [];
  const defaultRoutes = route.available ? parseIpv4RoutePrint(route.output).slice(0, 16) : [];

  return {
    collectedAt: new Date().toISOString(),
    dnsServers,
    neighbors,
    defaultRoutes,
    capabilities: {
      neighbors: arp.available,
      routes: route.available,
      dns: dnsServers.length > 0,
    },
    sources: {
      neighbors: arp.source,
      routes: route.source,
      dns: 'node-dns-getServers',
    },
    policy: {
      readOnly: true,
      activeProbe: false,
      arbitraryArguments: false,
    },
  };
}
