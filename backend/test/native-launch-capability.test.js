import test from 'node:test';
import assert from 'node:assert/strict';
import {
  consumeNativeLaunchCapability,
  issueNativeLaunchCapability,
  resetNativeLaunchCapabilitiesForTests,
} from '../src/apps/launchCapability.js';

const launch = Object.freeze({
  id: 'native-source-app',
  launchKind: 'windows-executable',
  launchSpec: Object.freeze({
    executable: 'C:\\Program Files\\CloudOS Fixture\\fixture.exe',
    arguments: Object.freeze(['C:\\CloudOS\\Drive\\Home\\Downloads\\note.txt']),
    workingDirectory: 'C:\\Program Files\\CloudOS Fixture',
  }),
});

test.afterEach(() => resetNativeLaunchCapabilitiesForTests());

test('native launch capability uses the existing Host-compatible opaque app ID shape', () => {
  const capability = issueNativeLaunchCapability({ principal: 'user-a', launch, now: 1_000 });
  assert.match(capability.id, /^native-[a-f0-9]{24}$/);
  assert.equal(capability.expiresAt, 31_000);
});

test('native launch capability is bound to one principal and consumed exactly once', () => {
  const capability = issueNativeLaunchCapability({ principal: 'user-a', launch, now: 1_000 });
  assert.equal(consumeNativeLaunchCapability(capability.id, 'user-a', 2_000), launch);
  assert.equal(consumeNativeLaunchCapability(capability.id, 'user-a', 2_001), null);
});

test('another principal cannot steal a staged launch and the owner may still redeem it', () => {
  const capability = issueNativeLaunchCapability({ principal: 'user-a', launch, now: 1_000 });
  assert.throws(
    () => consumeNativeLaunchCapability(capability.id, 'user-b', 2_000),
    error => error?.code === 'APP_LAUNCH_CAPABILITY_NOT_FOUND',
  );
  assert.equal(consumeNativeLaunchCapability(capability.id, 'user-a', 2_001), launch);
});

test('expired launch capabilities disappear fail-closed', () => {
  const capability = issueNativeLaunchCapability({ principal: 'user-a', launch, now: 1_000 });
  assert.equal(consumeNativeLaunchCapability(capability.id, 'user-a', 31_001), null);
});

test('invalid capability issuance fails closed', () => {
  assert.throws(
    () => issueNativeLaunchCapability({ principal: '', launch, now: 1_000 }),
    error => error?.code === 'APP_LAUNCH_CAPABILITY_INVALID',
  );
  assert.throws(
    () => issueNativeLaunchCapability({ principal: 'user-a', launch: null, now: 1_000 }),
    error => error?.code === 'APP_LAUNCH_CAPABILITY_INVALID',
  );
});
