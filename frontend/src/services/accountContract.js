export const ACCOUNT_RECOVERY_ENDPOINT = '/api/auth/recovery/reset';
export const ACCOUNT_LEGACY_RECOVERY_ENDPOINT = '/api/auth/legacy-recovery/reset';
export const MIN_PASSWORD_LENGTH = 4;
export const MAX_PASSWORD_LENGTH = 128;
const RECOVERY_GROUP_LENGTHS = Object.freeze([3, 4, 4, 4, 4, 4, 4, 4, 4]);
const RECOVERY_PAYLOAD_LENGTH = RECOVERY_GROUP_LENGTHS.reduce((total, length) => total + length, 0);

export function validateUsername(value, { required = true } = {}) {
  const username = typeof value === 'string' ? value.trim() : '';
  if (!username) return required ? 'Informe o nome de usuário.' : null;
  if (username.length < 3 || username.length > 64) return 'O nome de usuário deve ter entre 3 e 64 caracteres.';
  if (!/^[a-zA-Z0-9][a-zA-Z0-9._-]*$/.test(username)) {
    return 'Comece com uma letra ou número e use apenas letras, números, ponto, hífen ou sublinhado.';
  }
  return null;
}

export function validateDisplayName(value, { required = true } = {}) {
  const displayName = typeof value === 'string' ? value.trim() : '';
  if (!displayName) return required ? 'Informe o nome de exibição.' : null;
  if (displayName.length < 2 || displayName.length > 80) return 'O nome de exibição deve ter entre 2 e 80 caracteres.';
  return null;
}

export function validateNewPassword(password, confirmPassword) {
  if (typeof password !== 'string') return 'A senha deve ser um texto válido.';
  if (/[\u0000-\u001f\u007f]/.test(password)) return 'A senha não pode conter caracteres de controle.';
  if (password.length > 0 && password.length < MIN_PASSWORD_LENGTH) {
    return `A senha deve conter pelo menos ${MIN_PASSWORD_LENGTH} caracteres ou ser deixada em branco.`;
  }
  if (password.length > MAX_PASSWORD_LENGTH) return `A senha deve ter no máximo ${MAX_PASSWORD_LENGTH} caracteres.`;
  if (password !== confirmPassword) return 'A confirmação de senha não confere.';
  return null;
}

function formatReadablePayload(payload) {
  const groups = [];
  let offset = 0;
  for (const length of RECOVERY_GROUP_LENGTHS) {
    groups.push(payload.slice(offset, offset + length));
    offset += length;
  }
  return `CLOUDOS-${groups.join('-')}`;
}

export function normalizeReadableRecoveryCode(value) {
  const input = typeof value === 'string' ? value.trim() : '';
  if (!input) return '';
  const compact = input.toUpperCase().replace(/[\s-]+/g, '');
  if (compact.startsWith('CLOUDOS')) {
    const payload = compact.slice('CLOUDOS'.length);
    if (payload.length === RECOVERY_PAYLOAD_LENGTH && /^[2-9A-HJ-NP-Z]{35}$/.test(payload)) return formatReadablePayload(payload);
  }
  return input;
}

export function extractRecoveryCodeFromText(value) {
  const text = typeof value === 'string' ? value : '';
  if (!text.trim()) return '';
  const readable = text.match(/CLOUDOS[\s-]*[2-9A-HJ-NP-Z]{3}(?:[\s-]*[2-9A-HJ-NP-Z]{4}){8}/i);
  if (readable) return normalizeReadableRecoveryCode(readable[0]);
  const legacy = text.match(/CLOUDOS-[A-Za-z0-9_-]{17,121}/);
  return legacy ? legacy[0] : '';
}

export function normalizePublicUser(value, fallback = {}) {
  const user = value && typeof value === 'object' ? value : {};
  const username = typeof user.username === 'string' && user.username.trim()
    ? user.username.trim()
    : typeof fallback.username === 'string' ? fallback.username.trim() : '';
  const displayName = typeof user.displayName === 'string' && user.displayName.trim()
    ? user.displayName.trim()
    : typeof user.display_name === 'string' && user.display_name.trim()
      ? user.display_name.trim()
      : typeof fallback.displayName === 'string' && fallback.displayName.trim()
        ? fallback.displayName.trim()
        : username;
  const avatar = typeof user.avatar === 'string' && user.avatar.startsWith('data:image/') ? user.avatar : '';
  return {
    username,
    displayName,
    avatar,
    isAdmin: user.role === 'admin' || user.isAdmin === true,
    lastLogin: Date.now()
  };
}

export function extractRecoveryCode(value) {
  if (!value || typeof value !== 'object') return null;
  const candidates = [
    value.recoveryCode,
    value.recovery_code,
    value.newRecoveryCode,
    value.new_recovery_code,
    value.recovery?.code
  ];
  const code = candidates.find((candidate) => typeof candidate === 'string' && candidate.trim());
  return typeof code === 'string' ? normalizeReadableRecoveryCode(code) : null;
}

export function canRestoreAuthenticatedSession(authenticated, recoveryConfirmationPending) {
  return authenticated === true && recoveryConfirmationPending !== true;
}

export function sanitizePersistedProfile(value) {
  if (!value || typeof value !== 'object') return null;
  const profile = normalizePublicUser(value);
  return profile.username ? profile : null;
}

export function recoveryRequestBody({ recoveryCode, username, displayName, password, confirmPassword }) {
  return {
    recoveryCode: normalizeReadableRecoveryCode(recoveryCode),
    ...(String(username || '').trim() ? { newUsername: String(username).trim() } : {}),
    ...(String(displayName || '').trim() ? { displayName: String(displayName).trim() } : {}),
    password,
    confirmPassword
  };
}

export function legacyRecoveryRequestBody({ legacyToken, username, displayName, password, confirmPassword }) {
  return {
    legacyToken: String(legacyToken || '').trim(),
    ...(String(username || '').trim() ? { newUsername: String(username).trim() } : {}),
    ...(String(displayName || '').trim() ? { displayName: String(displayName).trim() } : {}),
    password,
    confirmPassword
  };
}
