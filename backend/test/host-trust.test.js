import assert from 'node:assert/strict';
import test from 'node:test';
import {
  createHostTrustPolicy,
  hasNativeHostTrust,
  hasSupervisorTrust
} from '../src/auth/hostTrust.js';

function requestWith(headers = {}) {
  const normalized = new Map(
    Object.entries(headers).map(([name, value]) => [name.toLowerCase(), value])
  );
  return {
    get(name) {
      return normalized.get(name.toLowerCase());
    }
  };
}

test('header de host de teste fica desativado fora de NODE_ENV=test', () => {
  const policy = createHostTrustPolicy(
    { NODE_ENV: 'production' },
    { allowTestHostHeader: true }
  );
  const request = requestWith({ 'X-CloudOS-Test-Host': '1' });

  assert.equal(policy.allowTestHostHeader, false);
  assert.equal(hasNativeHostTrust(request, policy), false);
});

test('header de host de teste exige valor exato e política de teste', () => {
  const disabledByDefault = createHostTrustPolicy({ NODE_ENV: 'test' });
  const policy = createHostTrustPolicy(
    { NODE_ENV: 'test' },
    { allowTestHostHeader: true }
  );

  assert.equal(hasNativeHostTrust(requestWith({ 'X-CloudOS-Test-Host': '1' }), disabledByDefault), false);
  assert.equal(hasNativeHostTrust(requestWith({ 'X-CloudOS-Test-Host': '1' }), policy), true);
  assert.equal(hasNativeHostTrust(requestWith({ 'X-CloudOS-Test-Host': 'true' }), policy), false);
});

test('produção aceita apenas tokens exatos do supervisor ou lease do host', () => {
  const environment = {
    NODE_ENV: 'production',
    CLOUDOS_SUPERVISOR_TOKEN: 'supervisor-secret-value',
    CLOUDOS_HOST_LEASE_TOKEN: 'host-lease-secret-value'
  };
  const policy = createHostTrustPolicy(environment);

  assert.equal(hasSupervisorTrust(requestWith({
    'X-CloudOS-Supervisor-Token': environment.CLOUDOS_SUPERVISOR_TOKEN
  }), policy), true);
  assert.equal(hasNativeHostTrust(requestWith({
    'X-CloudOS-Host-Token': environment.CLOUDOS_HOST_LEASE_TOKEN
  }), policy), true);
  assert.equal(hasNativeHostTrust(requestWith({
    'X-CloudOS-Supervisor-Token': `${environment.CLOUDOS_SUPERVISOR_TOKEN}-wrong`
  }), policy), false);
  assert.equal(hasNativeHostTrust(requestWith({
    'X-CloudOS-Supervisor-Token': 'supervisor-secret-valuE'
  }), policy), false);
  assert.equal(hasNativeHostTrust(requestWith({
    'X-CloudOS-Supervisor-Token': ''
  }), policy), false);
  assert.equal(hasNativeHostTrust(requestWith({
    'X-CloudOS-Host-Token': `${environment.CLOUDOS_HOST_LEASE_TOKEN}-wrong`
  }), policy), false);
});

test('política captura o ambiente na criação e não segue mutações posteriores', () => {
  const environment = {
    NODE_ENV: 'production',
    CLOUDOS_SUPERVISOR_TOKEN: 'original-supervisor-secret'
  };
  const policy = createHostTrustPolicy(environment);

  environment.NODE_ENV = 'test';
  environment.CLOUDOS_SUPERVISOR_TOKEN = 'mutated-supervisor-secret';

  assert.equal(hasNativeHostTrust(requestWith({ 'X-CloudOS-Test-Host': '1' }), policy), false);
  assert.equal(hasSupervisorTrust(requestWith({
    'X-CloudOS-Supervisor-Token': 'original-supervisor-secret'
  }), policy), true);
  assert.equal(hasSupervisorTrust(requestWith({
    'X-CloudOS-Supervisor-Token': 'mutated-supervisor-secret'
  }), policy), false);
});
