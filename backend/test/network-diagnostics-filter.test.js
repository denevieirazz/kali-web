import test from 'node:test';
import assert from 'node:assert/strict';
import { filterDisplayableNeighbors } from '../src/security/networkDiagnostics.js';

test('device map keeps only private IPv4 neighbors with unicast MACs', () => {
  const filtered = filterDisplayableNeighbors([
    { address: '192.168.1.1', mac: 'aa:bb:cc:dd:ee:fe', state: 'dynamic' },
    { address: '10.0.0.25', mac: '02:11:22:33:44:55', state: 'dynamic' },
    { address: '224.0.0.22', mac: '01:00:5e:00:00:16', state: 'static' },
    { address: '239.255.255.250', mac: '01:00:5e:7f:ff:fa', state: 'static' },
    { address: '192.168.1.255', mac: 'ff:ff:ff:ff:ff:ff', state: 'static' },
    { address: '8.8.8.8', mac: '10:20:30:40:50:60', state: 'dynamic' },
    { address: '192.168.1.40', mac: '00:00:00:00:00:00', state: 'invalid' },
  ]);

  assert.deepEqual(filtered.map(item => item.address), ['192.168.1.1', '10.0.0.25']);
});

test('device map deduplicates repeated private IP/MAC observations', () => {
  const filtered = filterDisplayableNeighbors([
    { interfaceAddress: '192.168.1.20', address: '192.168.1.5', mac: 'aa:bb:cc:dd:ee:00', state: 'dynamic' },
    { interfaceAddress: '192.168.1.30', address: '192.168.1.5', mac: 'aa:bb:cc:dd:ee:00', state: 'dynamic' },
  ]);
  assert.equal(filtered.length, 1);
});
