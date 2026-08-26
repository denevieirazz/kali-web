import { execFile } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { config } from '../config/index.js';
import { getWslSnapshot, getWslVersionInfo, safeChildEnvironment } from '../wsl/distroService.js';

const execFileAsync = promisify(execFile);
const WINDOWS_DIRECTORY = process.env.WINDIR || process.env.SystemRoot || 'C:\\Windows';
const REG_EXE = path.join(WINDOWS_DIRECTORY, 'System32', 'reg.exe');
const EXPLORER_EXE = path.join(WINDOWS_DIRECTORY, 'explorer.exe');
const OPERATION_JOURNAL = path.join(config.dataDir, 'operations.json');
const CLOUDOS_BOOTSTRAP_EXE = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../../../desktop/publish/CloudOS.Bootstrap.exe'
);
const MAX_OPERATION_JOURNAL_BYTES = 5 * 1024 * 1024;

export const READINESS_SCHEMA_VERSION = 1;
export const READINESS_PROFILES = Object.freeze([
  'hybrid-dev',
  'shell-preview',
  'shell-candidate'
]);

const PROFILE_POLICIES = Object.freeze({
  'hybrid-dev': Object.freeze({
    requireNativeHost: false,
    requireShellLauncherEdition: false,
    minimumFreeBytes: 512 * 1024 * 1024,
    requiredChecks: new Set([
      'host',
      'loopback',
      'data-directory-writable',
      'data-directory-free-space',
      'windows-edition',
      'explorer-fallback',
      'current-shell',
      'wsl-snapshot'
    ])
  }),
  'shell-preview': Object.freeze({
    requireNativeHost: true,
    requireShellLauncherEdition: false,
    minimumFreeBytes: 1024 * 1024 * 1024,
    requiredChecks: new Set([
      'host',
      'loopback',
      'data-directory-writable',
      'data-directory-free-space',
      'windows-edition',
      'explorer-fallback',
      'current-shell',
      'wsl-snapshot',
      'wslg-ready',
      'operation-journal'
    ])
  }),
  'shell-candidate': Object.freeze({
    requireNativeHost: true,
    requireShellLauncherEdition: true,
    minimumFreeBytes: 5 * 1024 * 1024 * 1024,
    requiredChecks: new Set([
      'host',
      'loopback',
      'data-directory-writable',
      'data-directory-free-space',
      'windows-edition',
      'explorer-fallback',
      'current-shell',
      'wsl-snapshot',
      'wslg-ready',
      'operation-journal',
      'shell-launcher-license',
      'break-glass-admin',
      'windows-recovery-environment',
      'rollback-artifact',
      'host-package-trust'
    ])
  })
});

const CHECK_TITLES = Object.freeze({
  host: 'Host Windows e runtime nativo',
  loopback: 'Exposição apenas em loopback',
  'data-directory-writable': 'Permissão de escrita do diretório de dados',
  'data-directory-free-space': 'Espaço livre do diretório de dados',
  'windows-edition': 'Edição do Windows',
  'explorer-fallback': 'Fallback do Windows Explorer',
  'current-shell': 'Shell atualmente configurado',
  'wsl-snapshot': 'Estado do WSL',
  'wslg-ready': 'Aplicativos gráficos Linux via WSLg',
  'operation-journal': 'Journal persistente de operações',
  'shell-launcher-license': 'Licença efetiva do Shell Launcher',
  'break-glass-admin': 'Conta administrativa de recuperação',
  'windows-recovery-environment': 'Windows Recovery Environment',
  'rollback-artifact': 'Artefato de rollback offline',
  'host-package-trust': 'Integridade e assinatura do pacote do host'
});

const SHELL_LAUNCHER_EDITIONS = new Set([
  'enterprise',
  'enterprisen',
  'enterprises',
  'enterprisesn',
  'education',
  'educationn',
  'iotenterprise',
  'iotenterprises'
]);

const ALLOWED_WSL_ERROR_CODES = new Set([
  'WSL_NOT_FOUND',
  'WSL_TIMEOUT',
  'WSL_ACCESS_DENIED',
  'ELEVATION_REQUIRED',
  'REBOOT_REQUIRED',
  'WSL_COMMAND_FAILED'
]);

export class InvalidReadinessProfileError extends Error {
  constructor() {
    super('Perfil de prontidão inválido.');
    this.code = 'INVALID_READINESS_PROFILE';
  }
}

function isLoopback(value) {
  const normalized = String(value || '').trim().toLowerCase();
  return normalized === 'localhost' || normalized === '127.0.0.1' ||
    normalized === '::1' || normalized === '::ffff:127.0.0.1';
}

function safeText(value, maxLength = 100) {
  if (typeof value !== 'string') return null;
  const sanitized = value.replace(/[\u0000-\u001f\u007f]/g, '').trim();
  return sanitized ? sanitized.slice(0, maxLength) : null;
}

function parseRegistryValue(output, name) {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = String(output || '').match(new RegExp(`^\\s*${escaped}\\s+REG_[A-Z0-9_]+\\s+(.+?)\\s*$`, 'im'));
  return match?.[1]?.trim() || null;
}

async function queryRegistryValue(key, name) {
  try {
    const { stdout } = await execFileAsync(REG_EXE, ['query', key, '/v', name], {
      encoding: 'utf8',
      env: safeChildEnvironment(),
      timeout: 3000,
      windowsHide: true,
      maxBuffer: 128 * 1024
    });
    return parseRegistryValue(stdout, name);
  } catch (error) {
    if (error.code === 1) return null;
    throw error;
  }
}

async function readWindowsEdition() {
  if (process.platform !== 'win32' || !fs.existsSync(REG_EXE)) return null;
  const key = 'HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion';
  const [productName, editionId, displayVersion, currentBuild] = await Promise.all([
    queryRegistryValue(key, 'ProductName'),
    queryRegistryValue(key, 'EditionID'),
    queryRegistryValue(key, 'DisplayVersion'),
    queryRegistryValue(key, 'CurrentBuildNumber')
  ]);
  if (!productName && !editionId) return null;
  return {
    productName: safeText(productName),
    editionId: safeText(editionId),
    displayVersion: safeText(displayVersion),
    build: safeText(currentBuild)
  };
}

function canonicalWindowsPathValue(value) {
  return value.toLowerCase();
}

function exactExecutableValue(rawValue) {
  if (typeof rawValue !== 'string') return null;
  const trimmed = rawValue.trim();
  if (!trimmed || /[\u0000-\u001f\u007f]/.test(trimmed)) return null;
  if (trimmed.startsWith('"') || trimmed.endsWith('"')) {
    if (!(trimmed.startsWith('"') && trimmed.endsWith('"')) || trimmed.length < 3) return null;
    const unquoted = trimmed.slice(1, -1);
    if (!unquoted || unquoted.includes('"')) return null;
    return unquoted;
  }
  if (trimmed.includes('"')) return null;
  return trimmed;
}

export function classifyShell(rawValue, options = {}) {
  const trimmed = typeof rawValue === 'string' ? rawValue.trim() : '';
  if (!trimmed) return 'unknown';

  // Winlogon accepts a command line. Only the canonical argument-free value
  // is recognized; commands and paths that merely mention explorer.exe are not.
  if (/^explorer\.exe$/i.test(trimmed)) return 'explorer';

  const executable = exactExecutableValue(trimmed);
  const cloudOsBootstrapExecutable = options.cloudOsBootstrapExecutable || CLOUDOS_BOOTSTRAP_EXE;
  const fileExists = options.fileExists || fs.existsSync;
  if (
    executable &&
    typeof cloudOsBootstrapExecutable === 'string' &&
    fileExists(cloudOsBootstrapExecutable) &&
    canonicalWindowsPathValue(executable) === canonicalWindowsPathValue(cloudOsBootstrapExecutable)
  ) {
    return 'cloudos-bootstrap';
  }
  return 'custom';
}

export function selectCurrentShell(values, options = {}) {
  const candidates = [
    ['user-policy', values?.userPolicy],
    ['user-winlogon', values?.userWinlogon],
    ['system-default', values?.systemDefault]
  ];
  for (const [source, rawValue] of candidates) {
    if (typeof rawValue === 'string' && rawValue.trim()) {
      return { source, kind: classifyShell(rawValue, options) };
    }
  }
  return null;
}

async function readCurrentShell() {
  if (process.platform !== 'win32' || !fs.existsSync(REG_EXE)) return null;
  const userPolicy = await queryRegistryValue(
    'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\System',
    'Shell'
  );
  const userWinlogon = await queryRegistryValue(
    'HKCU\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon',
    'Shell'
  );
  const systemDefault = await queryRegistryValue(
    'HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon',
    'Shell'
  );
  return selectCurrentShell({ userPolicy, userWinlogon, systemDefault });
}

async function checkDataDirectoryWritable() {
  try {
    await fs.promises.access(config.dataDir, fs.constants.W_OK);
    return true;
  } catch (error) {
    if (['EACCES', 'EPERM', 'EROFS'].includes(error.code)) return false;
    throw error;
  }
}

async function getDataDirectoryFreeSpace() {
  const stats = await fs.promises.statfs(config.dataDir);
  const available = BigInt(stats.bavail) * BigInt(stats.bsize);
  const maximumSafe = BigInt(Number.MAX_SAFE_INTEGER);
  return Number(available > maximumSafe ? maximumSafe : available);
}

export async function inspectOperationJournal(journalPath = OPERATION_JOURNAL) {
  try {
    const stats = await fs.promises.stat(journalPath);
    if (!stats.isFile() || stats.size > MAX_OPERATION_JOURNAL_BYTES) {
      return {
        present: true,
        valid: false,
        sizeBytes: stats.isFile() ? Math.min(stats.size, Number.MAX_SAFE_INTEGER) : 0,
        entryCount: 0
      };
    }
    let parsed;
    try {
      parsed = JSON.parse(await fs.promises.readFile(journalPath, 'utf8'));
    } catch (error) {
      if (error instanceof SyntaxError) {
        return {
          present: true,
          valid: false,
          sizeBytes: Math.min(stats.size, Number.MAX_SAFE_INTEGER),
          entryCount: 0
        };
      }
      throw error;
    }
    return {
      present: true,
      valid: Array.isArray(parsed),
      sizeBytes: Math.min(stats.size, Number.MAX_SAFE_INTEGER),
      entryCount: Array.isArray(parsed) ? parsed.length : 0
    };
  } catch (error) {
    if (error.code === 'ENOENT') {
      return { present: false, valid: true, sizeBytes: 0, entryCount: 0 };
    }
    throw error;
  }
}

function makeCheck({ id, required, observation, code, summary, evidence, deliveryState = 'implemented' }) {
  const safeObservation = deliveryState === 'implemented' ? observation : 'unknown';
  return {
    id,
    title: CHECK_TITLES[id],
    required,
    deliveryState,
    observation: safeObservation,
    code,
    summary,
    ...(evidence ? { evidence } : {})
  };
}

function unavailableCheck(id, required) {
  return makeCheck({
    id,
    required,
    observation: 'unknown',
    code: 'PROBE_UNAVAILABLE',
    summary: 'A observação não pôde ser concluída neste momento.'
  });
}

function pendingCheck(id, required, deliveryState = 'pending') {
  return makeCheck({
    id,
    required,
    deliveryState,
    observation: 'unknown',
    code: deliveryState === 'blocked' ? 'CHECK_BLOCKED' : 'CHECK_NOT_IMPLEMENTED',
    summary: deliveryState === 'blocked'
      ? 'A validação depende de uma etapa externa ainda não satisfeita.'
      : 'A validação ainda não foi implementada.'
  });
}

function requiredFor(policy, id) {
  return policy.requiredChecks.has(id);
}

function probeFactories(dependencies, policy, context) {
  const wslSnapshot = Promise.resolve().then(() => dependencies.wslSnapshot());
  let wslVersionInfo;
  const readWslVersionInfo = () => {
    wslVersionInfo ||= Promise.resolve().then(() => dependencies.wslVersionInfo());
    return wslVersionInfo;
  };
  return [
    ['host', async () => {
      const platform = dependencies.platform();
      const nativeHostActive = dependencies.nativeHostActive();
      const windows = platform === 'win32';
      const nativeRequirementMet = !policy.requireNativeHost || nativeHostActive;
      return makeCheck({
        id: 'host',
        required: requiredFor(policy, 'host'),
        observation: windows && nativeRequirementMet ? 'pass' : 'fail',
        code: !windows ? 'WINDOWS_HOST_REQUIRED' : nativeRequirementMet ? 'HOST_READY' : 'NATIVE_HOST_INACTIVE',
        summary: !windows
          ? 'Este perfil requer um host Windows.'
          : nativeRequirementMet ? 'O host atende ao perfil selecionado.' : 'O host nativo não está ativo.',
        evidence: {
          platform,
          architecture: dependencies.architecture(),
          release: safeText(dependencies.release(), 60),
          nativeHostActive
        }
      });
    }],
    ['loopback', async () => {
      const configuredLoopback = isLoopback(dependencies.configuredHost());
      const observedLoopback = isLoopback(context.localAddress);
      return makeCheck({
        id: 'loopback',
        required: requiredFor(policy, 'loopback'),
        observation: !context.localAddress ? 'unknown' : configuredLoopback && observedLoopback ? 'pass' : 'fail',
        code: !context.localAddress ? 'LOCAL_ADDRESS_UNAVAILABLE' : configuredLoopback && observedLoopback ? 'LOOPBACK_ONLY' : 'NON_LOOPBACK_EXPOSURE',
        summary: !context.localAddress
          ? 'O endereço local da conexão não foi observado.'
          : configuredLoopback && observedLoopback ? 'A API está limitada ao loopback.' : 'A API pode estar exposta fora do loopback.',
        evidence: { configuredLoopback, observedLoopback }
      });
    }],
    ['data-directory-writable', async () => {
      const writable = await dependencies.dataDirectoryWritable();
      return makeCheck({
        id: 'data-directory-writable',
        required: requiredFor(policy, 'data-directory-writable'),
        observation: writable ? 'pass' : 'fail',
        code: writable ? 'DATA_DIRECTORY_WRITABLE' : 'DATA_DIRECTORY_NOT_WRITABLE',
        summary: writable ? 'O diretório de dados permite escrita.' : 'O diretório de dados não permite escrita.',
        evidence: { writable }
      });
    }],
    ['data-directory-free-space', async () => {
      const availableBytes = await dependencies.dataDirectoryFreeSpace();
      const sufficient = availableBytes >= policy.minimumFreeBytes;
      return makeCheck({
        id: 'data-directory-free-space',
        required: requiredFor(policy, 'data-directory-free-space'),
        observation: sufficient ? 'pass' : 'fail',
        code: sufficient ? 'FREE_SPACE_SUFFICIENT' : 'FREE_SPACE_LOW',
        summary: sufficient ? 'Há espaço livre suficiente para o perfil.' : 'O espaço livre está abaixo do mínimo do perfil.',
        evidence: { availableBytes, minimumBytes: policy.minimumFreeBytes }
      });
    }],
    ['windows-edition', async () => {
      const edition = await dependencies.windowsEdition();
      if (!edition) return unavailableCheck('windows-edition', requiredFor(policy, 'windows-edition'));
      const editionKey = String(edition.editionId || '').toLowerCase();
      const shellLauncherEligible = SHELL_LAUNCHER_EDITIONS.has(editionKey);
      const suitable = !policy.requireShellLauncherEdition || shellLauncherEligible;
      return makeCheck({
        id: 'windows-edition',
        required: requiredFor(policy, 'windows-edition'),
        observation: suitable ? 'pass' : 'fail',
        code: suitable ? 'WINDOWS_EDITION_OBSERVED' : 'SHELL_LAUNCHER_EDITION_REQUIRED',
        summary: suitable
          ? 'A edição do Windows foi identificada.'
          : 'A edição observada não atende ao perfil de candidato a shell.',
        evidence: {
          productName: safeText(edition.productName),
          editionId: safeText(edition.editionId),
          displayVersion: safeText(edition.displayVersion, 40),
          build: safeText(edition.build, 40),
          shellLauncherEligible
        }
      });
    }],
    ['explorer-fallback', async () => {
      const present = await dependencies.explorerFallbackPresent();
      return makeCheck({
        id: 'explorer-fallback',
        required: requiredFor(policy, 'explorer-fallback'),
        observation: present ? 'pass' : 'fail',
        code: present ? 'EXPLORER_FALLBACK_PRESENT' : 'EXPLORER_FALLBACK_MISSING',
        summary: present ? 'O fallback do Explorer está presente.' : 'O fallback do Explorer não foi encontrado.',
        evidence: { present }
      });
    }],
    ['current-shell', async () => {
      const shell = await dependencies.currentShell();
      if (!shell) return unavailableCheck('current-shell', requiredFor(policy, 'current-shell'));
      const knownSafeKind = ['explorer', 'cloudos-bootstrap'].includes(shell.kind);
      return makeCheck({
        id: 'current-shell',
        required: requiredFor(policy, 'current-shell'),
        observation: shell.kind === 'unknown' ? 'unknown' : knownSafeKind ? 'pass' : 'fail',
        code: shell.kind === 'unknown' ? 'CURRENT_SHELL_UNKNOWN' : knownSafeKind ? 'CURRENT_SHELL_RECOGNIZED' : 'UNRECOGNIZED_CUSTOM_SHELL',
        summary: shell.kind === 'unknown'
          ? 'O shell atual não pôde ser classificado.'
          : knownSafeKind ? 'O shell atual foi reconhecido.' : 'Foi observado um shell personalizado não reconhecido.',
        evidence: { source: shell.source, kind: shell.kind }
      });
    }],
    ['wsl-snapshot', async () => {
      const snapshot = await wslSnapshot;
      const distributions = Array.isArray(snapshot?.distributions) ? snapshot.distributions : [];
      const wsl2DistributionCount = distributions.filter((item) => item?.version === 2).length;
      const errorCode = ALLOWED_WSL_ERROR_CODES.has(snapshot?.errorCode) ? snapshot.errorCode : null;
      let observation = 'pass';
      let code = 'WSL2_READY';
      let summary = 'O WSL 2 está operacional.';
      if (!snapshot?.installed) {
        observation = 'fail';
        code = 'WSL_NOT_INSTALLED';
        summary = 'O WSL não está instalado.';
      } else if (!snapshot.operational) {
        observation = 'unknown';
        code = errorCode || 'WSL_PROBE_UNAVAILABLE';
        summary = 'O estado operacional do WSL não pôde ser confirmado.';
      } else if (wsl2DistributionCount === 0) {
        observation = 'fail';
        code = 'WSL2_DISTRIBUTION_REQUIRED';
        summary = 'Nenhuma distribuição WSL 2 foi observada.';
      }
      return makeCheck({
        id: 'wsl-snapshot',
        required: requiredFor(policy, 'wsl-snapshot'),
        observation,
        code,
        summary,
        evidence: {
          installed: Boolean(snapshot?.installed),
          operational: Boolean(snapshot?.operational),
          distributionCount: distributions.length,
          wsl2DistributionCount,
          defaultConfigured: Boolean(snapshot?.default)
        }
      });
    }],
    ['wslg-ready', async () => {
      const snapshot = await wslSnapshot;
      const distributions = Array.isArray(snapshot?.distributions) ? snapshot.distributions : [];
      const wsl2DistributionCount = distributions.filter((item) => item?.version === 2).length;
      const errorCode = ALLOWED_WSL_ERROR_CODES.has(snapshot?.errorCode) ? snapshot.errorCode : null;
      let versionInfo = null;
      let observedWslgVersion = null;
      let observation = 'pass';
      let code = 'WSLG_READY';
      let summary = 'O WSLg foi confirmado para aplicativos gráficos Linux.';
      if (!snapshot?.installed) {
        observation = 'fail';
        code = 'WSL_NOT_INSTALLED';
        summary = 'O WSL precisa estar instalado antes de validar o WSLg.';
      } else if (!snapshot.operational) {
        observation = 'unknown';
        code = errorCode || 'WSL_PROBE_UNAVAILABLE';
        summary = 'O estado operacional do WSL não pôde ser confirmado.';
      } else if (wsl2DistributionCount === 0) {
        observation = 'fail';
        code = 'WSL2_DISTRIBUTION_REQUIRED';
        summary = 'O WSLg requer uma distribuição WSL 2 disponível.';
      } else {
        versionInfo = await readWslVersionInfo();
        observedWslgVersion = safeText(versionInfo?.wslgVersion, 40);
        if (!observedWslgVersion) {
          observation = 'fail';
          code = 'WSLG_VERSION_NOT_FOUND';
          summary = 'O WSL 2 está disponível, mas nenhuma versão real do WSLg foi observada.';
        }
      }
      return makeCheck({
        id: 'wslg-ready',
        required: requiredFor(policy, 'wslg-ready'),
        observation,
        code,
        summary,
        evidence: {
          wsl2DistributionCount,
          wslVersion: safeText(versionInfo?.wslVersion, 40),
          wslgVersion: observedWslgVersion
        }
      });
    }],
    ['operation-journal', async () => {
      const journal = await dependencies.operationJournalPresence();
      const valid = journal?.valid === true;
      return makeCheck({
        id: 'operation-journal',
        required: requiredFor(policy, 'operation-journal'),
        observation: valid ? 'pass' : 'fail',
        code: !journal?.present
          ? 'OPERATION_JOURNAL_AVAILABLE_EMPTY'
          : valid ? 'OPERATION_JOURNAL_VALID' : 'OPERATION_JOURNAL_INVALID',
        summary: !journal?.present
          ? 'O mecanismo do journal está disponível e iniciará vazio no primeiro uso.'
          : valid ? 'O journal de operações contém um array JSON válido.' : 'O arquivo do journal existe, mas não contém um array JSON válido.',
        evidence: {
          present: Boolean(journal?.present),
          valid,
          sizeBytes: Number(journal?.sizeBytes) || 0,
          entryCount: Number(journal?.entryCount) || 0
        }
      });
    }]
  ];
}

function summarize(checks) {
  const required = checks.filter((check) => check.required);
  const counts = {
    pass: checks.filter((check) => check.observation === 'pass').length,
    fail: checks.filter((check) => check.observation === 'fail').length,
    unknown: checks.filter((check) => check.observation === 'unknown').length,
    pending: checks.filter((check) => check.deliveryState === 'pending').length,
    blocked: checks.filter((check) => check.deliveryState === 'blocked').length
  };
  let status = 'ready';
  if (required.some((check) => check.deliveryState === 'blocked')) status = 'blocked';
  else if (required.some((check) => check.deliveryState === 'pending')) status = 'pending';
  else if (required.some((check) => check.observation === 'fail')) status = 'not-ready';
  else if (required.some((check) => check.observation === 'unknown')) status = 'unknown';
  return {
    status,
    ready: status === 'ready',
    requiredChecks: required.length,
    totalChecks: checks.length,
    counts
  };
}

const DEFAULT_DEPENDENCIES = Object.freeze({
  platform: () => process.platform,
  architecture: () => os.arch(),
  release: () => os.release(),
  nativeHostActive: () => process.env.CLOUDOS_NATIVE_HOST === '1',
  configuredHost: () => config.host,
  dataDirectoryWritable: checkDataDirectoryWritable,
  dataDirectoryFreeSpace: getDataDirectoryFreeSpace,
  windowsEdition: readWindowsEdition,
  explorerFallbackPresent: async () => process.platform === 'win32' && fs.existsSync(EXPLORER_EXE),
  currentShell: readCurrentShell,
  wslSnapshot: getWslSnapshot,
  wslVersionInfo: getWslVersionInfo,
  operationJournalPresence: inspectOperationJournal
});

export function createReadinessService(overrides = {}) {
  const dependencies = { ...DEFAULT_DEPENDENCIES, ...overrides };
  return {
    async getReport(profile = 'hybrid-dev', context = {}) {
      if (typeof profile !== 'string' || !READINESS_PROFILES.includes(profile)) {
        throw new InvalidReadinessProfileError();
      }
      const policy = PROFILE_POLICIES[profile];
      const checks = await Promise.all(probeFactories(dependencies, policy, context).map(async ([id, probe]) => {
        try {
          return await probe();
        } catch {
          return unavailableCheck(id, requiredFor(policy, id));
        }
      }));

      if (profile === 'shell-candidate') {
        checks.push(
          pendingCheck('shell-launcher-license', true),
          pendingCheck('break-glass-admin', true),
          pendingCheck('windows-recovery-environment', true),
          pendingCheck('rollback-artifact', true),
          pendingCheck('host-package-trust', true)
        );
      }

      return {
        contract: 'cloudos.readiness/v1',
        schemaVersion: READINESS_SCHEMA_VERSION,
        profile,
        probeMode: 'read-only',
        generatedAt: new Date().toISOString(),
        summary: summarize(checks),
        checks
      };
    }
  };
}

export const readinessService = createReadinessService();
