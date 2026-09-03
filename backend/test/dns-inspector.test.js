import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeDnsName, summarizeDnsRecords } from '../src/security/dnsInspector.js';

test('normalizes exact DNS names and international domains without accepting URLs', () => {
  assert.equal(normalizeDnsName('Example.COM.'), 'example.com');
  assert.equal(normalizeDnsName('www.example.com'), 'www.example.com');
  assert.match(normalizeDnsName('exemplo.com.br'), /exemplo\.com\.br/);
  for (const value of ['https://example.com', 'example.com/path', 'example.com:443', '--help', 'localhost', 'bad name.com']) {
    assert.throws(() => normalizeDnsName(value), /DNS|hostname|domínio/i);
  }
});

test('summarizes only record types that actually contain answers', () => {
  const summary = summarizeDnsRecords({
    A: { status: 'ok', records: ['192.0.2.1'] },
    AAAA: { status: 'empty', records: [] },
    CNAME: { status: 'empty', records: [] },
    MX: { status: 'ok', records: [{ exchange: 'mail.example.com', priority: 10 }] },
    NS: { status: 'ok', records: ['ns1.example.com'] },
    TXT: { status: 'ok', records: ['v=spf1 -all'] },
  });
  assert.deepEqual(summary.presentTypes, ['A', 'MX', 'NS', 'TXT']);
  assert.ok(summary.recommendations.some(item => /endereços publicados/i.test(item)));
  assert.ok(summary.recommendations.some(item => /MX/i.test(item)));
  assert.ok(summary.recommendations.some(item => /TXT/i.test(item)));
  assert.ok(summary.recommendations.every(item => !/senha|brute force/i.test(item)));
});

test('empty DNS result produces a troubleshooting recommendation instead of inventing data', () => {
  const summary = summarizeDnsRecords({
    A: { status: 'empty', records: [] }, AAAA: { status: 'empty', records: [] }, CNAME: { status: 'empty', records: [] },
    MX: { status: 'empty', records: [] }, NS: { status: 'empty', records: [] }, TXT: { status: 'empty', records: [] },
  });
  assert.deepEqual(summary.presentTypes, []);
  assert.match(summary.recommendations[0], /Nenhum dos tipos consultados/i);
});
