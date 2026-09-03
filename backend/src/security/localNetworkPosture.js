import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { safeChildEnvironment } from '../wsl/distroService.js';

const execFileAsync = promisify(execFile);
const MAX_OUTPUT = 256 * 1024;

const WINDOWS_POSTURE_SCRIPT = [
  "$ErrorActionPreference='Stop'",
  '$firewall = @(Get-NetFirewallProfile | Select-Object Name,Enabled,DefaultInboundAction,DefaultOutboundAction)',
  '$profiles = @(Get-NetConnectionProfile | Select-Object InterfaceAlias,Name,NetworkCategory,IPv4Connectivity,IPv6Connectivity)',
  '$listeners = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Sort-Object LocalPort,LocalAddress | Select-Object -First 256 LocalAddress,LocalPort,OwningProcess)',
  '[pscustomobject]@{firewall=$firewall;networkProfiles=$profiles;listeners=$listeners} | ConvertTo-Json -Depth 5 -Compress',
].join('; ');

function arrayOf(value) {
  if (Array.isArray(value)) return value;
  if (value === null || value === undefined) return [];
  return [value];
}

function normalizedBoolean(value) {
  return value === true || value === 'True' || value === 'true' || value === 1;
}

function listenerExposure(address) {
  const value = String(address || '').trim().toLowerCase();
  if (value === '127.0.0.1' || value === '::1') return 'loopback';
  if (value === '0.0.0.0' || value === '::' || value === '*') return 'all-interfaces';
  return value ? 'specific-interface' : 'unknown';
}

export function analyzeLocalNetworkPosture(raw) {
  const firewall = arrayOf(raw?.firewall).map(item => ({
    name: String(item?.Name || item?.name || 'Unknown').slice(0, 64),
    enabled: normalizedBoolean(item?.Enabled ?? item?.enabled),
    defaultInboundAction: String(item?.DefaultInboundAction ?? item?.defaultInboundAction ?? 'NotConfigured').slice(0, 32),
    defaultOutboundAction: String(item?.DefaultOutboundAction ?? item?.defaultOutboundAction ?? 'NotConfigured').slice(0, 32),
  }));

  const networkProfiles = arrayOf(raw?.networkProfiles).map(item => ({
    interfaceAlias: String(item?.InterfaceAlias ?? item?.interfaceAlias ?? '').slice(0, 128),
    name: String(item?.Name ?? item?.name ?? '').slice(0, 128),
    category: String(item?.NetworkCategory ?? item?.category ?? 'Unknown').slice(0, 64),
    ipv4Connectivity: String(item?.IPv4Connectivity ?? item?.ipv4Connectivity ?? 'Unknown').slice(0, 64),
    ipv6Connectivity: String(item?.IPv6Connectivity ?? item?.ipv6Connectivity ?? 'Unknown').slice(0, 64),
  }));

  const listeners = arrayOf(raw?.listeners).map(item => {
    const localAddress = String(item?.LocalAddress ?? item?.localAddress ?? '').slice(0, 64);
    const port = Number(item?.LocalPort ?? item?.localPort);
    const processId = Number(item?.OwningProcess ?? item?.owningProcess);
    return {
      localAddress,
      port: Number.isInteger(port) && port >= 1 && port <= 65535 ? port : null,
      processId: Number.isInteger(processId) && processId >= 0 ? processId : null,
      exposure: listenerExposure(localAddress),
    };
  }).filter(item => item.port !== null).slice(0, 256);

  const disabledFirewallProfiles = firewall.filter(item => !item.enabled).map(item => item.name);
  const wildcardListeners = listeners.filter(item => item.exposure === 'all-interfaces');
  const loopbackListeners = listeners.filter(item => item.exposure === 'loopback');
  const specificListeners = listeners.filter(item => item.exposure === 'specific-interface');
  const recommendations = [];
  let highestAttention = 'info';

  if (firewall.length === 0) recommendations.push('Não foi possível ler os perfis do Firewall do Windows; confirme manualmente se a proteção de rede está ativa.');
  if (disabledFirewallProfiles.length) {
    highestAttention = 'high';
    recommendations.push(`Firewall desativado em: ${disabledFirewallProfiles.join(', ')}. Reative o perfil salvo se isso não fizer parte de uma exceção administrada.`);
  }
  if (wildcardListeners.length > 0) {
    if (highestAttention === 'info') highestAttention = 'medium';
    recommendations.push(`Há ${wildcardListeners.length} porta(s) TCP escutando em todas as interfaces. Confirme se cada serviço precisa estar exposto à rede e aplique regras de firewall quando apropriado.`);
  }
  if (networkProfiles.some(item => /public/i.test(item.category))) {
    recommendations.push('Existe perfil de rede Pública ativo. Isso normalmente aplica regras mais restritivas; confirme se a classificação corresponde ao ambiente atual.');
  }
  if (!recommendations.length) recommendations.push('Os perfis de firewall lidos estão ativos e não há indicador básico adicional nesta coleta. Continue revisando listeners e regras conforme a função da máquina.');

  return {
    firewall,
    networkProfiles,
    listeners,
    summary: {
      highestAttention,
      firewallProfiles: firewall.length,
      disabledFirewallProfiles,
      listeners: listeners.length,
      wildcardListeners: wildcardListeners.length,
      loopbackListeners: loopbackListeners.length,
      specificListeners: specificListeners.length,
    },
    recommendations: recommendations.slice(0, 8),
  };
}

export async function getLocalNetworkPosture() {
  if (process.platform !== 'win32') {
    return {
      available: false,
      source: 'unsupported-host',
      collectedAt: new Date().toISOString(),
      firewall: [], networkProfiles: [], listeners: [],
      summary: { highestAttention: 'info', firewallProfiles: 0, disabledFirewallProfiles: [], listeners: 0, wildcardListeners: 0, loopbackListeners: 0, specificListeners: 0 },
      recommendations: ['A postura local desta versão é coletada pelo Windows PowerShell e não está disponível neste host.'],
      policy: { readOnly: true, localMachineOnly: true, arbitraryArguments: false },
    };
  }

  try {
    const { stdout } = await execFileAsync('powershell.exe', [
      '-NoLogo', '-NoProfile', '-NonInteractive', '-Command', WINDOWS_POSTURE_SCRIPT,
    ], {
      encoding: 'utf8', windowsHide: true, timeout: 12_000,
      maxBuffer: MAX_OUTPUT, env: safeChildEnvironment(),
    });
    const parsed = JSON.parse(String(stdout || '').trim() || '{}');
    return {
      available: true,
      source: 'windows-powershell-fixed-posture',
      collectedAt: new Date().toISOString(),
      ...analyzeLocalNetworkPosture(parsed),
      policy: {
        readOnly: true,
        localMachineOnly: true,
        arbitraryArguments: false,
        processNamesExposed: false,
        firewallMutation: false,
      },
    };
  } catch {
    return {
      available: false,
      source: 'windows-powershell-fixed-posture',
      collectedAt: new Date().toISOString(),
      firewall: [], networkProfiles: [], listeners: [],
      summary: { highestAttention: 'info', firewallProfiles: 0, disabledFirewallProfiles: [], listeners: 0, wildcardListeners: 0, loopbackListeners: 0, specificListeners: 0 },
      recommendations: ['Não foi possível coletar a postura de rede local nesta sessão. Nenhuma configuração foi alterada.'],
      policy: { readOnly: true, localMachineOnly: true, arbitraryArguments: false, firewallMutation: false },
    };
  }
}
