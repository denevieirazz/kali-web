import test from 'node:test';
import assert from 'node:assert/strict';
import { analyzeWifiPosture, classifyWifiSecurity } from '../src/security/wifiInsights.js';

test('classifies common Wi-Fi protection modes without claiming exploitability', () => {
  assert.deepEqual(classifyWifiSecurity('WPA3-Personal', 'CCMP'), { attention: 'info', label: 'WPA3' });
  assert.deepEqual(classifyWifiSecurity('WPA2-Personal', 'CCMP'), { attention: 'low', label: 'WPA2' });
  assert.equal(classifyWifiSecurity('Open', 'None').attention, 'high');
  assert.equal(classifyWifiSecurity('WPA-Personal', 'TKIP').attention, 'medium');
  assert.equal(classifyWifiSecurity('WPA2-Personal', 'WEP').attention, 'high');
});

test('wifi posture highlights weak connection protection and crowded current channel', () => {
  const posture = analyzeWifiPosture({
    connected: {
      ssid: 'Lab', signal: '38%', channel: '6', authentication: 'WPA-Personal', cipher: 'TKIP',
    },
    networks: [
      { ssid: 'Lab', authentication: 'WPA-Personal', cipher: 'TKIP', radios: [{ channel: '6' }, { channel: '6' }] },
      { ssid: 'Guest', authentication: 'Open', cipher: 'None', radios: [{ channel: '6' }] },
      { ssid: 'Neighbor', authentication: 'WPA2-Personal', cipher: 'CCMP', radios: [{ channel: '6' }] },
    ],
  });

  assert.equal(posture.highestAttention, 'high');
  assert.equal(posture.signalPercent, 38);
  assert.equal(posture.currentChannel, '6');
  assert.equal(posture.currentChannelOccupancy, 4);
  assert.equal(posture.openOrLegacyNetworks, 1);
  assert.ok(posture.recommendations.some(item => /WPA2\/WPA3/i.test(item)));
  assert.ok(posture.recommendations.some(item => /sinal/i.test(item)));
  assert.ok(posture.recommendations.some(item => /canal 6/i.test(item)));
});

test('wifi posture keeps modern healthy connection informational', () => {
  const posture = analyzeWifiPosture({
    connected: {
      ssid: 'Secure', signal: '91%', channel: '44', authentication: 'WPA3-Personal', cipher: 'GCMP',
    },
    networks: [
      { ssid: 'Secure', authentication: 'WPA3-Personal', cipher: 'GCMP', radios: [{ channel: '44' }] },
    ],
  });
  assert.equal(posture.highestAttention, 'info');
  assert.equal(posture.signalPercent, 91);
  assert.equal(posture.currentChannelOccupancy, 1);
  assert.equal(posture.openOrLegacyNetworks, 0);
  assert.match(posture.note, /não testa senhas/i);
});
