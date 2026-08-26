import crypto from 'node:crypto';

const CAPABILITY_TTL_MS = 30_000;
const MAX_PENDING_CAPABILITIES = 256;
const capabilities = new Map();

function capabilityError(code, message) {
  return Object.assign(new Error(message), { code });
}

function cleanupExpired(now = Date.now()) {
  for (const [id, entry] of capabilities) {
    if (entry.expiresAt <= now) capabilities.delete(id);
  }
}

export function issueNativeLaunchCapability({ principal, launch, now = Date.now() }) {
  cleanupExpired(now);
  if (!principal || typeof principal !== 'string' || !launch || typeof launch !== 'object') {
    throw capabilityError('APP_LAUNCH_CAPABILITY_INVALID', 'Não foi possível emitir a capability de lançamento.');
  }
  if (capabilities.size >= MAX_PENDING_CAPABILITIES) {
    throw capabilityError('APP_LAUNCH_CAPABILITY_LIMIT', 'Há muitas capabilities de lançamento pendentes.');
  }

  const id = `native-${crypto.randomBytes(12).toString('hex')}`;
  const expiresAt = now + CAPABILITY_TTL_MS;
  capabilities.set(id, Object.freeze({ principal, launch, expiresAt }));
  return Object.freeze({ id, expiresAt });
}

export function consumeNativeLaunchCapability(id, principal, now = Date.now()) {
  cleanupExpired(now);
  const entry = capabilities.get(id);
  if (!entry) return null;
  if (entry.principal !== principal) {
    throw capabilityError('APP_LAUNCH_CAPABILITY_NOT_FOUND', 'Capability de lançamento não encontrada.');
  }
  capabilities.delete(id);
  return entry.launch;
}

export function resetNativeLaunchCapabilitiesForTests() {
  capabilities.clear();
}
