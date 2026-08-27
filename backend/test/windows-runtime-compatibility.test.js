import test from 'node:test';
import assert from 'node:assert/strict';
import {
  WINDOWS_RUNTIME_STATUS,
  classifyCatalogRuntime,
  validateRuntimeQualification
} from '../src/apps/windowsRuntimeCompatibility.js';

test('direct Windows candidate remains unqualified without physical evidence', () => {
  const result = classifyCatalogRuntime({
    source: 'windows',
    kind: 'windows-executable',
    runtimeClass: 'win32-direct-candidate'
  });
  assert.equal(result.status, WINDOWS_RUNTIME_STATUS.UNQUALIFIED);
  assert.match(result.reason, /physical captured-surface qualification/i);
});

test('brokered start app fails closed', () => {
  const result = classifyCatalogRuntime({
    source: 'windows',
    kind: 'windows-start-app',
    runtimeClass: 'brokered-start-app'
  });
  assert.equal(result.status, WINDOWS_RUNTIME_STATUS.BROKER_UNSAFE);
});

test('unresolved shortcut does not masquerade as capture support', () => {
  const result = classifyCatalogRuntime({
    source: 'windows',
    kind: 'windows-shortcut',
    runtimeClass: 'win32-shortcut-unresolved'
  });
  assert.equal(result.status, WINDOWS_RUNTIME_STATUS.CAPTURE_BLOCKED);
});

test('physical qualification can promote a candidate only through explicit persisted evidence', () => {
  const qualification = validateRuntimeQualification({
    status: WINDOWS_RUNTIME_STATUS.CAPTURE_SUPPORTED,
    reason: 'physical fixture and application harness passed',
    qualifiedAt: '2026-08-27T10:00:00Z',
    evidenceRevision: 'sha256:example'
  });
  assert.ok(qualification);

  const result = classifyCatalogRuntime({
    source: 'windows',
    kind: 'windows-executable',
    runtimeClass: 'win32-direct-candidate'
  }, qualification);
  assert.equal(result.status, WINDOWS_RUNTIME_STATUS.CAPTURE_SUPPORTED);
  assert.equal(result.evidenceRevision, 'sha256:example');
});

test('qualification validator rejects unsupported status and missing reason', () => {
  assert.equal(validateRuntimeQualification({ status: 'MAGIC', reason: 'x' }), null);
  assert.equal(validateRuntimeQualification({ status: WINDOWS_RUNTIME_STATUS.CAPTURE_SUPPORTED, reason: '' }), null);
  assert.equal(classifyCatalogRuntime({ source: 'linux' }), null);
});
