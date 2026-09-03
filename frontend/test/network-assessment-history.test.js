import test from 'node:test';
import assert from 'node:assert/strict';
import {
  MAX_NETWORK_ASSESSMENT_HISTORY,
  appendNetworkAssessmentHistory,
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
