export const READINESS_CONTRACT = 'cloudos.readiness/v1';
export const READINESS_SCHEMA_VERSION = 1;

const COMMON_REQUIRED_CHECK_IDS = Object.freeze([
  'host',
  'loopback',
  'data-directory-writable',
  'data-directory-free-space',
  'windows-edition',
  'explorer-fallback',
  'current-shell',
  'wsl-snapshot'
]);

export const REQUIRED_READINESS_CHECK_IDS = Object.freeze({
  'hybrid-dev': COMMON_REQUIRED_CHECK_IDS,
  'shell-preview': Object.freeze([
    ...COMMON_REQUIRED_CHECK_IDS,
    'wslg-ready',
    'operation-journal'
  ]),
  'shell-candidate': Object.freeze([
    ...COMMON_REQUIRED_CHECK_IDS,
    'wslg-ready',
    'operation-journal',
    'shell-launcher-license',
    'break-glass-admin',
    'windows-recovery-environment',
    'rollback-artifact',
    'host-package-trust'
  ])
});

function isRecord(value) {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

const DELIVERY_STATES = new Set(['implemented', 'pending', 'blocked']);
const OBSERVATIONS = new Set(['pass', 'fail', 'unknown']);
const SUMMARY_STATUSES = new Set(['ready', 'blocked', 'pending', 'not-ready', 'unknown']);

function isValidCheckEntry(check) {
  return isRecord(check)
    && typeof check.id === 'string'
    && Boolean(check.id.trim())
    && typeof check.title === 'string'
    && Boolean(check.title.trim())
    && typeof check.required === 'boolean'
    && DELIVERY_STATES.has(check.deliveryState)
    && OBSERVATIONS.has(check.observation)
    && typeof check.code === 'string'
    && Boolean(check.code.trim())
    && typeof check.summary === 'string'
    && Boolean(check.summary.trim());
}

/**
 * Validates the untrusted readiness response before the UI normalizes any data.
 * A report is useful as evidence only when it is exactly the contract/profile
 * requested and contains every probe required for that profile.
 */
export function validateReadinessContract(value, requestedProfile) {
  const requiredCheckIds = REQUIRED_READINESS_CHECK_IDS[requestedProfile] || [];
  const errors = [];
  const row = isRecord(value) ? value : null;

  if (!row) {
    return {
      valid: false,
      errors: ['INVALID_RESPONSE'],
      missingCheckIds: [...requiredCheckIds]
    };
  }

  if (row.contract !== READINESS_CONTRACT) errors.push('CONTRACT_MISMATCH');
  if (row.schemaVersion !== READINESS_SCHEMA_VERSION) errors.push('SCHEMA_VERSION_MISMATCH');
  if (row.profile !== requestedProfile) errors.push('PROFILE_MISMATCH');
  if (typeof row.generatedAt !== 'string' || Number.isNaN(Date.parse(row.generatedAt))) {
    errors.push('GENERATED_AT_INVALID');
  }
  if (!isRecord(row.summary)
    || !SUMMARY_STATUSES.has(row.summary.status)
    || typeof row.summary.ready !== 'boolean') {
    errors.push('SUMMARY_INVALID');
  }

  const checkIds = new Set();
  const seenCheckIds = new Set();
  if (!Array.isArray(row.checks) || row.checks.length === 0) {
    errors.push('CHECKS_INVALID');
  } else {
    for (const check of row.checks) {
      const candidateId = isRecord(check) && typeof check.id === 'string'
        ? check.id.trim()
        : '';
      if (candidateId) {
        if (seenCheckIds.has(candidateId)) errors.push('CHECK_ID_DUPLICATED');
        seenCheckIds.add(candidateId);
      }
      if (!isValidCheckEntry(check)) {
        errors.push('CHECK_ENTRY_INVALID');
        continue;
      }
      checkIds.add(candidateId);
    }
  }

  const missingCheckIds = requiredCheckIds.filter((id) => !checkIds.has(id));
  if (missingCheckIds.length) errors.push('REQUIRED_CHECKS_MISSING');

  return {
    valid: errors.length === 0,
    errors: [...new Set(errors)],
    missingCheckIds
  };
}

function contractFailureDetail(validation) {
  if (validation.missingCheckIds.length) {
    return `O agente omitiu verificacoes obrigatorias deste perfil: ${validation.missingCheckIds.join(', ')}.`;
  }
  if (validation.errors.includes('CONTRACT_MISMATCH')) {
    return 'O agente respondeu com um contrato de prontidao ausente ou incompativel.';
  }
  if (validation.errors.includes('SCHEMA_VERSION_MISMATCH')) {
    return 'O agente respondeu com uma versao de esquema incompativel.';
  }
  if (validation.errors.includes('PROFILE_MISMATCH')) {
    return 'O agente respondeu para um perfil diferente do solicitado.';
  }
  return 'A resposta do agente esta vazia ou malformada e nao pode comprovar a prontidao.';
}

export function createReadinessContractFailure(validation, observedAt) {
  return {
    id: 'agent.contract',
    group: 'runtime',
    label: 'Contrato de prontidao do agente',
    detail: contractFailureDetail(validation),
    deliveryState: 'implemented',
    observation: 'fail',
    gating: 'hard',
    source: 'agent',
    evidence: {
      kind: 'contract',
      value: {
        expected: READINESS_CONTRACT,
        errors: validation.errors,
        missingCheckIds: validation.missingCheckIds
      },
      code: 'READINESS_CONTRACT_INVALID',
      observedAt
    },
    blocking: true
  };
}

export function fullscreenReadinessObservation(profile, fullscreen) {
  if (fullscreen === true) return 'pass';
  return profile === 'hybrid-dev' ? 'warning' : 'fail';
}
