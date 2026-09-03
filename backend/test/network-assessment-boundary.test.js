import test from 'node:test';
import assert from 'node:assert/strict';
import { isPrivateIpv4, normalizeAssessmentTarget } from '../src/security/networkAssessment.js';

test('accepts private and local IPv4 targets', () => {
  assert.equal(isPrivateIpv4('10.0.0.1'), true);
  assert.equal(isPrivateIpv4('172.16.10.2'), true);
  assert.equal(isPrivateIpv4('192.168.1.50'), true);
  assert.equal(isPrivateIpv4('127.0.0.1'), true);
  assert.equal(isPrivateIpv4('169.254.10.3'), true);
});

test('rejects public IPv4 and hostnames', () => {
  assert.equal(isPrivateIpv4('8.8.8.8'), false);
  assert.throws(() => normalizeAssessmentTarget('8.8.8.8'), /privado\/local/i);
  assert.throws(() => normalizeAssessmentTarget('example.com'), /privado\/local/i);
});

test('bounds one-click discovery to at most a /24', () => {
  assert.equal(normalizeAssessmentTarget('192.168.1.0/24'), '192.168.1.0/24');
  assert.equal(normalizeAssessmentTarget('10.0.0.8/32'), '10.0.0.8/32');
  assert.throws(() => normalizeAssessmentTarget('10.0.0.0/16'), /\/24/i);
});

test('service inventory cannot receive a CIDR range', () => {
  assert.equal(normalizeAssessmentTarget('192.168.1.10', { allowCidr: false }), '192.168.1.10');
  assert.throws(() => normalizeAssessmentTarget('192.168.1.0/24', { allowCidr: false }), /somente um dispositivo/i);
});

test('rejects argument-like payloads instead of passing them to nmap', () => {
  for (const value of ['192.168.1.1 -A', '--script vuln', '192.168.1.1;whoami', '192.168.1.1\n-A']) {
    assert.throws(() => normalizeAssessmentTarget(value));
  }
});
