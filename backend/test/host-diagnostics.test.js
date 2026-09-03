import test from 'node:test';
import assert from 'node:assert/strict';
import { getHostDiagnostics, parsePingOutput, parseTracerouteOutput } from '../src/security/hostDiagnostics.js';

test('parses English and Portuguese ping latency without depending on full localized sentence', () => {
  const english = parsePingOutput([
    'Reply from 192.168.1.1: bytes=32 time=2ms TTL=64',
    'Reply from 192.168.1.1: bytes=32 time<1ms TTL=64',
    'Reply from 192.168.1.1: bytes=32 time=4ms TTL=64',
  ].join('\n'));
  assert.equal(english.reachable, true);
  assert.equal(english.replies, 3);
  assert.equal(english.lossPercent, 0);
  assert.equal(english.minMs, 1);
  assert.equal(english.maxMs, 4);
  assert.equal(english.ttl, 64);

  const portuguese = parsePingOutput([
    'Resposta de 192.168.1.1: bytes=32 tempo=3ms TTL=128',
    'Resposta de 192.168.1.1: bytes=32 tempo=5ms TTL=128',
  ].join('\n'));
  assert.equal(portuguese.reachable, true);
  assert.equal(portuguese.replies, 2);
  assert.equal(portuguese.lossPercent, 33);
  assert.equal(portuguese.averageMs, 4);
});

test('parses a bounded traceroute and ignores non-hop lines', () => {
  const hops = parseTracerouteOutput([
    'Tracing route to 192.168.1.20 over a maximum of 8 hops:',
    '  1    <1 ms    <1 ms    1 ms  192.168.1.1',
    '  2     2 ms     3 ms    2 ms  192.168.1.20',
    'Trace complete.',
  ].join('\n'));
  assert.deepEqual(hops.map(item => item.address), ['192.168.1.1', '192.168.1.20']);
  assert.equal(hops[0].hop, 1);
  assert.equal(hops[1].averageMs, 2.3);
});

test('records timed-out hops without inventing an address', () => {
  const hops = parseTracerouteOutput('  1     *        *        *     Request timed out.');
  assert.equal(hops.length, 1);
  assert.equal(hops[0].address, null);
  assert.equal(hops[0].timedOut, true);
});

test('host diagnostics rejects public, CIDR and command-like targets before running probes', async () => {
  for (const target of ['8.8.8.8', '192.168.1.0/24', '192.168.1.1 -t', 'example.com']) {
    await assert.rejects(() => getHostDiagnostics(target));
  }
});
