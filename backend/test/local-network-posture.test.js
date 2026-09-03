import test from 'node:test';
import assert from 'node:assert/strict';
import { analyzeLocalNetworkPosture } from '../src/security/localNetworkPosture.js';

test('flags disabled firewall profile and wildcard listeners without calling them vulnerabilities', () => {
  const result = analyzeLocalNetworkPosture({
    firewall: [
      { Name: 'Domain', Enabled: true, DefaultInboundAction: 'NotConfigured', DefaultOutboundAction: 'NotConfigured' },
      { Name: 'Private', Enabled: false, DefaultInboundAction: 'NotConfigured', DefaultOutboundAction: 'NotConfigured' },
      { Name: 'Public', Enabled: true, DefaultInboundAction: 'Block', DefaultOutboundAction: 'Allow' },
    ],
    networkProfiles: [
      { InterfaceAlias: 'Wi-Fi', Name: 'Casa', NetworkCategory: 'Private', IPv4Connectivity: 'Internet', IPv6Connectivity: 'NoTraffic' },
    ],
    listeners: [
      { LocalAddress: '0.0.0.0', LocalPort: 445, OwningProcess: 4 },
      { LocalAddress: '127.0.0.1', LocalPort: 18080, OwningProcess: 1234 },
      { LocalAddress: '192.168.1.20', LocalPort: 22, OwningProcess: 5678 },
    ],
  });

  assert.equal(result.summary.highestAttention, 'high');
  assert.deepEqual(result.summary.disabledFirewallProfiles, ['Private']);
  assert.equal(result.summary.listeners, 3);
  assert.equal(result.summary.wildcardListeners, 1);
  assert.equal(result.summary.loopbackListeners, 1);
  assert.equal(result.summary.specificListeners, 1);
  assert.ok(result.recommendations.some(item => /Firewall desativado/i.test(item)));
  assert.ok(result.recommendations.some(item => /todas as interfaces/i.test(item)));
  assert.ok(result.recommendations.every(item => !/vulnerabilidade confirmada/i.test(item)));
});

test('normalizes single PowerShell objects into arrays and filters invalid listener ports', () => {
  const result = analyzeLocalNetworkPosture({
    firewall: { Name: 'Private', Enabled: 'True' },
    networkProfiles: { InterfaceAlias: 'Ethernet', Name: 'Lab', NetworkCategory: 'Public' },
    listeners: [
      { LocalAddress: '::1', LocalPort: 3000, OwningProcess: 100 },
      { LocalAddress: '0.0.0.0', LocalPort: 70000, OwningProcess: 101 },
    ],
  });

  assert.equal(result.firewall.length, 1);
  assert.equal(result.firewall[0].enabled, true);
  assert.equal(result.networkProfiles.length, 1);
  assert.equal(result.listeners.length, 1);
  assert.equal(result.listeners[0].exposure, 'loopback');
  assert.ok(result.recommendations.some(item => /rede Pública/i.test(item)));
});
