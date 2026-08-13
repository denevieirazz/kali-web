export const ACCOUNT_RECOVERY_ENDPOINT = '/api/auth/recovery/reset';

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
  if (typeof password !== 'string' || password.length < 10) return 'A senha deve conter pelo menos 10 caracteres.';
  if (password.length > 128) return 'A senha deve ter no máximo 128 caracteres.';
  if (password !== confirmPassword) return 'A confirmação de senha não confere.';
  return null;
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
  return typeof code === 'string' ? code.trim() : null;
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
    recoveryCode: String(recoveryCode || '').trim(),
    ...(String(username || '').trim() ? { newUsername: String(username).trim() } : {}),
    ...(String(displayName || '').trim() ? { displayName: String(displayName).trim() } : {}),
    password,
    confirmPassword
  };
}
