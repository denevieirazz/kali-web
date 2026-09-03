import test from 'node:test';
import assert from 'node:assert/strict';
import {
  MAX_NETWORK_ASSESSMENT_HISTORY,
  appendNetworkAssessmentHistory,
  diffNetworkAssessmentRecords,
  normalizeNetworkAssessmentHistory,
  sanitizeNetworkAssessmentRecord,
} from '../src/core/networkAssessmentHistory.js';

test('network assessment history strips unexpected executable fields', () => {
  const clean = sanitizeNetworkAssessmentRecord({
    target: '192.168.1.10', preset: 'services', label: 'Serviços', distribution: 'kali-linux',
    command: 'nmap', argv: ['--script', 'x'], token: 'secret',
    hosts: [{ address: '192.168.1.10', up: true, command: 'bad', ports: [{ port: 80, state: 'open', service: 'http', argv: ['bad'] }] }],
  });
  const serialized = JSON.stringify(clean);
  assert.equal(serialized.includes('command'), false);
  assert.equal(serialized.includes('argv'), false);
  assert.equal(serialized.includes('secret'), false);
  assert.equal(clean.hosts[0].ports[0].port, 80);
});

test('assessment history remains bounded to the newest records', () => {
  let history = [];
  for (let index = 0; index < MAX_NETWORK_ASSESSMENT_HISTORY + 7; index += 1) {
    history = appendNetworkAssessmentHistory(history, {
      target: `192.168.1.${index + 1}`, preset: 'services', label: 'Serviços', distribution: 'kali-linux', hosts: [],
    });
  }
  assert.equal(history.length, MAX_NETWORK_ASSESSMENT_HISTORY);
});

test('normalization rejects malformed records', () => {
  const history = normalizeNetworkAssessmentHistory([null, {}, { target: '192.168.1.1', preset: 'discover' }]);
  assert.equal(history.length, 1);
});

test('comparison reports new hosts and port changes without interpreting them as attacks', () => {
  const previous = {
    target: '192.168.1.10', preset: 'services',
    hosts: [
      { address: '192.168.1.10', up: true, ports: [{ port: 80, protocol: 'tcp', state: 'open', service: 'http' }, { port: 22, protocol: 'tcp', state: 'open', service: 'ssh' }] },
    ],
  };
  const current = {
    target: '192.168.1.10', preset: 'services',
    hosts: [
      { address: '192.168.1.10', up: true, ports: [{ port: 80, protocol: 'tcp', state: 'open', service: 'http' }, { port: 443, protocol: 'tcp', state: 'open', service: 'https' }] },
      { address: '192.168.1.11', up: true, ports: [] },
    ],
  };
  const diff = diffNetworkAssessmentRecords(previous, current);
  assert.equal(diff.comparable, true);
  assert.deepEqual(diff.addedHosts, ['192.168.1.11']);
  assert.deepEqual(diff.changedHosts[0].openedPorts, ['443/tcp']);
  assert.deepEqual(diff.changedHosts[0].closedPorts, ['22/tcp']);
});

test('comparison refuses unrelated targets or presets', () => {
  const diff = diffNetworkAssessmentRecords(
    { target: '192.168.1.10', preset: 'services', hosts: [] },
    { target: '192.168.1.0/24', preset: 'discover', hosts: [] },
  );
  assert.equal(diff.comparable, false);
});
