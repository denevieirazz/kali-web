import crypto from 'node:crypto';

function optionalSecret(value) {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function secretsMatch(expected, provided) {
  if (!expected || typeof provided !== 'string' || provided.length === 0) return false;

  const expectedDigest = crypto.createHash('sha256').update(expected, 'utf8').digest();
  const providedDigest = crypto.createHash('sha256').update(provided, 'utf8').digest();
  return crypto.timingSafeEqual(expectedDigest, providedDigest);
}

export function createHostTrustPolicy(environment = process.env, testHooks = {}) {
  return Object.freeze({
    supervisorToken: optionalSecret(environment.CLOUDOS_SUPERVISOR_TOKEN),
    hostLeaseToken: optionalSecret(environment.CLOUDOS_HOST_LEASE_TOKEN),
    allowTestHostHeader: environment.NODE_ENV === 'test'
      && testHooks.allowTestHostHeader === true
  });
}

export function hasSupervisorTrust(req, policy) {
  return secretsMatch(
    policy?.supervisorToken,
    req.get('X-CloudOS-Supervisor-Token')
  );
}

export function hasNativeHostTrust(req, policy) {
  if (hasSupervisorTrust(req, policy)) return true;
  if (secretsMatch(policy?.hostLeaseToken, req.get('X-CloudOS-Host-Token'))) return true;
  return policy?.allowTestHostHeader === true
    && req.get('X-CloudOS-Test-Host') === '1';
}
