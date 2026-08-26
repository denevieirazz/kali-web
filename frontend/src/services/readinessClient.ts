import { apiClient } from './apiClient';
import { nativeHostBridge, type NativeHostState } from './nativeHostBridge';
import {
  READINESS_CONTRACT,
  READINESS_SCHEMA_VERSION,
  createReadinessContractFailure,
  fullscreenReadinessObservation,
  validateReadinessContract,
} from './readinessContract.js';

export type ReadinessProfile = 'hybrid-dev' | 'shell-preview' | 'shell-candidate';
export type ReadinessDeliveryState = 'implemented' | 'pending' | 'blocked';
export type ReadinessObservation = 'pass' | 'warning' | 'fail' | 'unknown' | 'not-applicable';
export type ReadinessVerdict = 'ready' | 'conditional' | 'not-ready';

export interface ReadinessEvidence {
  kind: string;
  value?: unknown;
  code?: string | null;
  observedAt?: string;
  label?: string;
}

export interface ReadinessCheck {
  id: string;
  group: string;
  label: string;
  detail: string;
  deliveryState: ReadinessDeliveryState;
  observation: ReadinessObservation;
  gating: 'hard' | 'soft' | 'none';
  source: string;
  evidence?: ReadinessEvidence;
  actionId?: string | null;
  blocking?: boolean;
}

export interface ReadinessLimitation {
  id: string;
  title: string;
  detail: string;
  source: string;
}

export interface ReadinessSummary {
  verdict: ReadinessVerdict;
  blockingCheckIds: string[];
  counts: {
    total: number;
    passed: number;
    warnings: number;
    failed: number;
    unknown: number;
    pending: number;
    blocked: number;
  };
}

export interface ReadinessSnapshot {
  contract: typeof READINESS_CONTRACT;
  schemaVersion: number;
  profile: ReadinessProfile;
  generatedAt: string;
  checks: ReadinessCheck[];
  limitations: ReadinessLimitation[];
  summary: ReadinessSummary;
}

type UnknownRecord = Record<string, unknown>;

const CHECK_GROUPS: Record<string, string> = {
  host: 'host',
  loopback: 'security',
  'data-directory-writable': 'storage',
  'data-directory-free-space': 'storage',
  'windows-edition': 'windows',
  'explorer-fallback': 'recovery',
  'current-shell': 'boot',
  'wsl-snapshot': 'linux',
  'wslg-ready': 'linux',
  'operation-journal': 'recovery',
  'shell-launcher-license': 'boot',
  'break-glass-admin': 'recovery',
  'windows-recovery-environment': 'recovery',
  'rollback-artifact': 'recovery',
  'host-package-trust': 'security'
};

const POLICY_LIMITATIONS: ReadinessLimitation[] = [
  {
    id: 'policy.windows-substrate',
    title: 'O Windows continua sendo a base nesta fase',
    detail: 'A compatibilidade Win32, drivers, WSL e WSLg depende dos componentes do Windows. Esta verificação não remove nem desativa esses componentes.',
    source: 'policy'
  },
  {
    id: 'policy.secure-desktop',
    title: 'Telas protegidas continuam sob controle do Windows',
    detail: 'UAC, Ctrl+Alt+Del, aplicativos elevados, conteúdo protegido e alguns sistemas anti-cheat podem aparecer fora da interface CloudOS.',
    source: 'policy'
  },
  {
    id: 'policy.native-surfaces',
    title: 'Aplicativos externos usam superfícies nativas',
    detail: 'Win32 e WSLg criam janelas do Windows. O host pode coordenar janelas atribuíveis, mas não promete incorporar ou controlar universalmente todas elas.',
    source: 'policy'
  }
];

function isRecord(value: unknown): value is UnknownRecord {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function textValue(value: unknown, fallback: string) {
  return typeof value === 'string' && value.trim() ? value.trim() : fallback;
}

function normalizeDelivery(value: unknown): ReadinessDeliveryState {
  const normalized = String(value || '').toLowerCase();
  if (['implemented', 'implementado', 'ready', 'complete', 'completed'].includes(normalized)) return 'implemented';
  if (['blocked', 'bloqueado', 'constrained', 'unsupported'].includes(normalized)) return 'blocked';
  return 'pending';
}

function normalizeObservation(value: unknown): ReadinessObservation {
  const normalized = String(value || '').toLowerCase().replace(/_/g, '-');
  if (['pass', 'passed', 'ok', 'ready', 'success', 'operational'].includes(normalized)) return 'pass';
  if (['warning', 'warn', 'attention', 'partial', 'degraded'].includes(normalized)) return 'warning';
  if (['fail', 'failed', 'error', 'unavailable'].includes(normalized)) return 'fail';
  if (['not-applicable', 'na', 'n/a'].includes(normalized)) return 'not-applicable';
  return 'unknown';
}

function normalizeGating(value: unknown): ReadinessCheck['gating'] {
  return value === 'hard' || value === 'soft' || value === 'none' ? value : 'none';
}

function normalizeEvidence(value: unknown): ReadinessEvidence | undefined {
  if (value === undefined || value === null) return undefined;
  if (!isRecord(value)) return { kind: 'value', value };
  const structuredEnvelope = ['kind', 'value', 'code', 'observedAt', 'label'].some((key) => key in value);
  if (!structuredEnvelope) return { kind: 'measurement', value };
  return {
    kind: textValue(value.kind, 'value'),
    value: value.value,
    code: typeof value.code === 'string' ? value.code : null,
    observedAt: typeof value.observedAt === 'string' ? value.observedAt : undefined,
    label: typeof value.label === 'string' ? value.label : undefined
  };
}

function normalizeCheck(value: unknown, index: number): ReadinessCheck {
  const row = isRecord(value) ? value : {};
  const result = isRecord(row.result) ? row.result : null;
  const rawObservation = row.observation ?? result?.status ?? row.resultStatus ?? row.status;
  const deliveryCandidate = row.deliveryState ?? row.delivery ?? row.implementation;
  const observation = normalizeObservation(rawObservation);
  const id = textValue(row.id, `agent.unknown-${index}`);
  const evidence = normalizeEvidence(row.evidence ?? result?.evidence);
  if (evidence && !evidence.code && typeof row.code === 'string') evidence.code = row.code;
  return {
    id,
    group: textValue(row.group, CHECK_GROUPS[id] || 'system'),
    label: textValue(row.label ?? row.title ?? row.name, 'Verificação sem identificação'),
    detail: textValue(row.detail ?? row.description ?? (typeof row.summary === 'string' ? row.summary : undefined) ?? result?.detail, 'O agente não forneceu detalhes para esta verificação.'),
    deliveryState: normalizeDelivery(deliveryCandidate),
    observation,
    gating: row.required === true ? 'hard' : normalizeGating(row.gating),
    source: textValue(row.source, 'agent'),
    evidence,
    actionId: typeof row.actionId === 'string' ? row.actionId : null,
    blocking: row.blocking === true
  };
}

function normalizeLimitation(value: unknown, index: number): ReadinessLimitation {
  if (typeof value === 'string') {
    return { id: `agent.limitation-${index}`, title: 'Limite conhecido', detail: value, source: 'agent' };
  }
  const row = isRecord(value) ? value : {};
  return {
    id: textValue(row.id, `agent.limitation-${index}`),
    title: textValue(row.title ?? row.label, 'Limite conhecido'),
    detail: textValue(row.detail ?? row.description, 'O agente não forneceu detalhes para este limite.'),
    source: textValue(row.source, 'agent')
  };
}

function normalizeBackendSnapshot(value: unknown, requestedProfile: ReadinessProfile, observedAt: string) {
  const validation = validateReadinessContract(value, requestedProfile);
  if (!validation.valid) {
    return {
      contract: READINESS_CONTRACT,
      schemaVersion: READINESS_SCHEMA_VERSION,
      profile: requestedProfile,
      generatedAt: observedAt,
      checks: [createReadinessContractFailure(validation, observedAt)],
      limitations: [] as ReadinessLimitation[],
      blockingCheckIds: ['agent.contract'],
      upstreamVerdict: 'not-ready' as ReadinessVerdict
    };
  }

  const row = value as UnknownRecord;
  const profile = row.profile as ReadinessProfile;
  const checks = Array.isArray(row.checks) ? row.checks.map(normalizeCheck) : [];
  const limitations = Array.isArray(row.limitations) ? row.limitations.map(normalizeLimitation) : [];
  const rawSummary = isRecord(row.summary) ? row.summary : {};
  const blockingCheckIds = Array.isArray(rawSummary.blockingCheckIds)
    ? rawSummary.blockingCheckIds.filter((item): item is string => typeof item === 'string')
    : [];
  const rawStatus = String(rawSummary.verdict ?? rawSummary.status ?? '');
  const upstreamVerdict: ReadinessVerdict | undefined = rawStatus === 'ready'
    ? 'ready'
    : rawStatus === 'conditional'
      ? 'conditional'
      : ['blocked', 'pending', 'not-ready', 'unknown'].includes(rawStatus)
        ? 'not-ready'
        : undefined;
  return {
    contract: READINESS_CONTRACT,
    schemaVersion: READINESS_SCHEMA_VERSION,
    profile,
    generatedAt: typeof row.generatedAt === 'string' ? row.generatedAt : new Date().toISOString(),
    checks,
    limitations,
    blockingCheckIds,
    upstreamVerdict
  };
}

function createHostChecks(state: NativeHostState | null, profile: ReadinessProfile, observedAt: string, error?: Error): ReadinessCheck[] {
  const nativeRequired = profile !== 'hybrid-dev';
  if (!state) {
    return [{
      id: 'native.bridge',
      group: 'host',
      label: 'Host nativo e bridge WebView2',
      detail: error?.message || 'A interface atual não expôs a bridge do host nativo.',
      deliveryState: 'implemented',
      observation: nativeRequired ? 'fail' : 'warning',
      gating: nativeRequired ? 'hard' : 'soft',
      source: 'native-host',
      evidence: { kind: 'boolean', value: false, code: 'NATIVE_HOST_UNAVAILABLE', observedAt }
    }];
  }

  return [
    {
      id: 'native.bridge',
      group: 'host',
      label: 'Host nativo e bridge WebView2',
      detail: 'A interface respondeu pelo canal nativo restrito do CloudOS.',
      deliveryState: 'implemented',
      observation: state.nativeHost ? 'pass' : 'fail',
      gating: nativeRequired ? 'hard' : 'soft',
      source: 'native-host',
      evidence: { kind: 'version', value: state.version || 'carregado', observedAt }
    },
    {
      id: 'native.fullscreen',
      group: 'boot',
      label: 'Interface em tela cheia',
      detail: state.fullscreen
        ? 'O workspace CloudOS ocupa a área principal da sessão.'
        : 'O host está em modo janela. Isso é seguro para desenvolvimento, mas não representa uma prévia de shell.',
      deliveryState: 'implemented',
      observation: fullscreenReadinessObservation(profile, state.fullscreen),
      gating: nativeRequired ? 'hard' : 'soft',
      source: 'native-host',
      evidence: { kind: 'boolean', value: state.fullscreen, observedAt }
    },
    {
      id: 'native.kiosk',
      group: 'boot',
      label: 'Modo kiosk',
      detail: state.kiosk
        ? 'O fechamento comum está protegido e a saída de recuperação permanece disponível.'
        : 'O modo kiosk não está ativo nesta sessão. Ele continua opcional enquanto o shell do Windows não for substituído.',
      deliveryState: 'implemented',
      observation: state.kiosk ? 'pass' : 'warning',
      gating: 'soft',
      source: 'native-host',
      evidence: { kind: 'boolean', value: state.kiosk, observedAt }
    },
    {
      id: 'native.window-management',
      group: 'windows',
      label: 'Gerenciador de janelas nativas',
      detail: state.managedWindows
        ? 'O host declarou suporte a foco, estado e fechamento das janelas atribuíveis.'
        : 'A sessão não confirmou o gerenciador de janelas nativas.',
      deliveryState: 'implemented',
      observation: state.managedWindows ? 'pass' : 'fail',
      gating: nativeRequired ? 'hard' : 'soft',
      source: 'native-host',
      evidence: { kind: 'boolean', value: state.managedWindows, observedAt }
    }
  ];
}

async function inspectNativeHost(profile: ReadinessProfile, observedAt: string) {
  if (!nativeHostBridge.available) return createHostChecks(null, profile, observedAt);
  try {
    const state = await nativeHostBridge.getHostState();
    return createHostChecks(state, profile, observedAt);
  } catch (error) {
    return createHostChecks(null, profile, observedAt, error instanceof Error ? error : undefined);
  }
}

async function inspectOpfs(observedAt: string): Promise<ReadinessCheck> {
  const supported = typeof navigator !== 'undefined'
    && 'storage' in navigator
    && typeof navigator.storage?.getDirectory === 'function';
  if (!supported) {
    return {
      id: 'browser.opfs',
      group: 'storage',
      label: 'Armazenamento local do CloudOS',
      detail: 'Este contexto não oferece Origin Private File System.',
      deliveryState: 'implemented',
      observation: 'fail',
      gating: 'hard',
      source: 'browser',
      evidence: { kind: 'boolean', value: false, code: 'OPFS_UNAVAILABLE', observedAt }
    };
  }
  try {
    await navigator.storage.getDirectory();
    return {
      id: 'browser.opfs',
      group: 'storage',
      label: 'Armazenamento local do CloudOS',
      detail: 'O diretório privado da interface foi aberto com sucesso.',
      deliveryState: 'implemented',
      observation: 'pass',
      gating: 'hard',
      source: 'browser',
      evidence: { kind: 'boolean', value: true, observedAt }
    };
  } catch {
    return {
      id: 'browser.opfs',
      group: 'storage',
      label: 'Armazenamento local do CloudOS',
      detail: 'A API existe, mas o navegador recusou o acesso ao diretório privado.',
      deliveryState: 'implemented',
      observation: 'fail',
      gating: 'hard',
      source: 'browser',
      evidence: { kind: 'boolean', value: false, code: 'OPFS_ACCESS_FAILED', observedAt }
    };
  }
}

function shellActivationPolicy(profile: ReadinessProfile, observedAt: string): ReadinessCheck[] {
  if (profile !== 'shell-candidate') return [];
  return [{
    id: 'policy.shell-activation',
    group: 'recovery',
    label: 'Ativação como shell do Windows',
    detail: 'Bloqueada por projeto nesta versão. Ainda não há watchdog, rollback e recuperação validados para substituir a interface do Windows.',
    deliveryState: 'blocked',
    observation: 'not-applicable',
    gating: 'hard',
    source: 'policy',
    evidence: { kind: 'policy', value: 'activation-disabled', code: 'SHELL_ACTIVATION_DISABLED', observedAt },
    blocking: true
  }];
}

function failedBackendCheck(error: unknown, observedAt: string): ReadinessCheck {
  return {
    id: 'agent.readiness-api',
    group: 'runtime',
    label: 'Serviço de prontidão do agente',
    detail: error instanceof Error ? error.message : 'O agente não respondeu à verificação de prontidão.',
    deliveryState: 'implemented',
    observation: 'fail',
    gating: 'hard',
    source: 'agent',
    evidence: { kind: 'error', value: false, code: 'READINESS_API_FAILED', observedAt }
  };
}

function deduplicateById<T extends { id: string }>(items: T[]) {
  const result = new Map<string, T>();
  for (const item of items) result.set(item.id, item);
  return [...result.values()];
}

function verdictRank(value: ReadinessVerdict | undefined) {
  return value === 'not-ready' ? 2 : value === 'conditional' ? 1 : value === 'ready' ? 0 : -1;
}

function summarize(checks: ReadinessCheck[], upstreamBlockers: string[], upstreamVerdict?: ReadinessVerdict): ReadinessSummary {
  const upstream = new Set(upstreamBlockers);
  const blockingCheckIds = checks
    .filter((check) => upstream.has(check.id) || check.blocking === true || (
      check.gating === 'hard'
      && (check.deliveryState !== 'implemented' || ['fail', 'unknown'].includes(check.observation))
    ))
    .map((check) => check.id);
  const counts = {
    total: checks.length,
    passed: checks.filter((check) => check.observation === 'pass').length,
    warnings: checks.filter((check) => check.observation === 'warning').length,
    failed: checks.filter((check) => check.observation === 'fail').length,
    unknown: checks.filter((check) => check.observation === 'unknown').length,
    pending: checks.filter((check) => check.deliveryState === 'pending').length,
    blocked: checks.filter((check) => check.deliveryState === 'blocked').length
  };
  const localVerdict: ReadinessVerdict = blockingCheckIds.length
    ? 'not-ready'
    : counts.warnings || counts.failed || counts.pending || counts.blocked || counts.unknown
      ? 'conditional'
      : 'ready';
  const verdict = verdictRank(upstreamVerdict) > verdictRank(localVerdict) ? upstreamVerdict! : localVerdict;
  return { verdict, blockingCheckIds: [...new Set(blockingCheckIds)], counts };
}

export const readinessClient = {
  async scan(profile: ReadinessProfile, refresh = true): Promise<ReadinessSnapshot> {
    const observedAt = new Date().toISOString();
    const endpoint = `/api/readiness?profile=${encodeURIComponent(profile)}${refresh ? '&refresh=1' : ''}`;
    const [backendResult, nativeChecks, opfsCheck] = await Promise.all([
      apiClient<unknown>(endpoint, { timeoutMs: 30_000 })
        .then((value) => ({ ok: true as const, value }))
        .catch((error: unknown) => ({ ok: false as const, error })),
      inspectNativeHost(profile, observedAt),
      inspectOpfs(observedAt)
    ]);

    const backend = backendResult.ok
      ? normalizeBackendSnapshot(backendResult.value, profile, observedAt)
      : {
          contract: READINESS_CONTRACT,
          schemaVersion: READINESS_SCHEMA_VERSION,
          profile,
          generatedAt: observedAt,
          checks: [failedBackendCheck(backendResult.error, observedAt)],
          limitations: [] as ReadinessLimitation[],
          blockingCheckIds: [] as string[],
          upstreamVerdict: undefined
        };
    const checks = deduplicateById([
      ...backend.checks,
      ...nativeChecks,
      opfsCheck,
      ...shellActivationPolicy(profile, observedAt)
    ]);
    const limitations = deduplicateById([...backend.limitations, ...POLICY_LIMITATIONS]);
    return {
      contract: READINESS_CONTRACT,
      schemaVersion: backend.schemaVersion,
      profile,
      generatedAt: backend.generatedAt,
      checks,
      limitations,
      summary: summarize(checks, backend.blockingCheckIds, backend.upstreamVerdict)
    };
  }
};
