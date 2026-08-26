import test from 'node:test';
import assert from 'node:assert/strict';
import {
  READINESS_CONTRACT,
  REQUIRED_READINESS_CHECK_IDS,
  createReadinessContractFailure,
  fullscreenReadinessObservation,
  validateReadinessContract
} from '../src/services/readinessContract.js';

function report(profile, overrides = {}) {
  return {
    contract: READINESS_CONTRACT,
    schemaVersion: 1,
    profile,
    generatedAt: '2026-08-12T00:00:00.000Z',
    summary: { status: 'ready', ready: true },
    checks: REQUIRED_READINESS_CHECK_IDS[profile].map((id) => ({
      id,
      title: id,
      required: true,
      deliveryState: 'implemented',
      observation: 'pass',
      code: 'CHECK_READY',
      summary: 'Check completed.'
    })),
    ...overrides
  };
}

test('accepts only a complete v1 report for the requested profile', () => {
  for (const profile of ['hybrid-dev', 'shell-preview', 'shell-candidate']) {
    assert.deepEqual(validateReadinessContract(report(profile), profile), {
      valid: true,
      errors: [],
      missingCheckIds: []
    });
  }
});

test('rejects an absent contract, a coerced schema version, and a mismatched profile', () => {
  const absentContract = report('hybrid-dev');
  delete absentContract.contract;
  assert.ok(validateReadinessContract(absentContract, 'hybrid-dev').errors.includes('CONTRACT_MISMATCH'));

  const stringVersion = report('hybrid-dev', { schemaVersion: '1' });
  assert.ok(validateReadinessContract(stringVersion, 'hybrid-dev').errors.includes('SCHEMA_VERSION_MISMATCH'));

  const wrongProfile = report('hybrid-dev', { profile: 'shell-preview' });
  assert.ok(validateReadinessContract(wrongProfile, 'hybrid-dev').errors.includes('PROFILE_MISMATCH'));
});

test('rejects empty, malformed, and duplicate check collections', () => {
  assert.equal(validateReadinessContract(null, 'hybrid-dev').valid, false);
  assert.ok(validateReadinessContract(report('hybrid-dev', { checks: [] }), 'hybrid-dev').errors.includes('CHECKS_INVALID'));
  assert.ok(validateReadinessContract(report('hybrid-dev', { checks: [{ id: '' }] }), 'hybrid-dev').errors.includes('CHECK_ENTRY_INVALID'));

  const malformedSummary = report('hybrid-dev', { summary: { ready: true } });
  assert.ok(validateReadinessContract(malformedSummary, 'hybrid-dev').errors.includes('SUMMARY_INVALID'));

  const malformedCheck = report('hybrid-dev');
  malformedCheck.checks[0].observation = 'maybe';
  assert.ok(validateReadinessContract(malformedCheck, 'hybrid-dev').errors.includes('CHECK_ENTRY_INVALID'));

  const duplicate = report('hybrid-dev');
  duplicate.checks.push({ id: duplicate.checks[0].id });
  assert.ok(validateReadinessContract(duplicate, 'hybrid-dev').errors.includes('CHECK_ID_DUPLICATED'));
});

test('requires the profile minimum and WSLg evidence for both shell profiles', () => {
  for (const profile of ['shell-preview', 'shell-candidate']) {
    const incomplete = report(profile, {
      checks: report(profile).checks.filter((check) => check.id !== 'wslg-ready')
    });
    const result = validateReadinessContract(incomplete, profile);
    assert.equal(result.valid, false);
    assert.ok(result.errors.includes('REQUIRED_CHECKS_MISSING'));
    assert.deepEqual(result.missingCheckIds, ['wslg-ready']);
  }
});

test('turns an invalid response into an explicit hard agent.contract blocker', () => {
  const validation = validateReadinessContract({}, 'shell-preview');
  const failure = createReadinessContractFailure(validation, '2026-08-12T00:00:00.000Z');
  assert.equal(failure.id, 'agent.contract');
  assert.equal(failure.observation, 'fail');
  assert.equal(failure.gating, 'hard');
  assert.equal(failure.blocking, true);
  assert.equal(failure.evidence.code, 'READINESS_CONTRACT_INVALID');
});

test('fullscreen is a hard failure for preview and candidate profiles', () => {
  assert.equal(fullscreenReadinessObservation('hybrid-dev', false), 'warning');
  assert.equal(fullscreenReadinessObservation('shell-preview', false), 'fail');
  assert.equal(fullscreenReadinessObservation('shell-candidate', false), 'fail');
  assert.equal(fullscreenReadinessObservation('shell-preview', true), 'pass');
});
