import test from 'node:test';
import assert from 'node:assert/strict';
import {
  buildWebFindings,
  isPublicWebAddress,
  normalizePublicWebUrl,
  parseSetCookieMetadata,
} from '../src/security/webInspector.js';

test('Web Inspector accepts ordinary public IP families and rejects local/reserved destinations', () => {
  assert.equal(isPublicWebAddress('1.1.1.1'), true);
  assert.equal(isPublicWebAddress('8.8.8.8'), true);
  assert.equal(isPublicWebAddress('2606:4700:4700::1111'), true);

  for (const address of [
    '0.0.0.0', '10.0.0.1', '100.64.0.1', '127.0.0.1', '169.254.169.254',
    '172.16.0.1', '192.168.1.1', '192.0.2.10', '198.18.0.1', '198.51.100.10',
    '203.0.113.4', '224.0.0.1', '::1', 'fe80::1', 'fd00::1', 'ff02::1', '2001:db8::1',
  ]) {
    assert.equal(isPublicWebAddress(address), false, address);
  }
});

test('Web Inspector normalizes one exact HTTP/HTTPS URL and strips fragments', () => {
  assert.equal(normalizePublicWebUrl('https://example.com/path?q=1#frag'), 'https://example.com/path?q=1');
  assert.equal(normalizePublicWebUrl('http://example.com:8080/health'), 'http://example.com:8080/health');
  assert.equal(normalizePublicWebUrl('https://EXAMPLE.com./'), 'https://example.com/');
  assert.equal(normalizePublicWebUrl('https://[2606:4700:4700::1111]/'), 'https://[2606:4700:4700::1111]/');
});

test('Web Inspector blocks non-web schemes, embedded credentials and unsafe ports', () => {
  assert.throws(() => normalizePublicWebUrl('file:///etc/passwd'), error => error.code === 'WEB_SCHEME_NOT_ALLOWED');
  assert.throws(() => normalizePublicWebUrl('ftp://example.com/file'), error => error.code === 'WEB_SCHEME_NOT_ALLOWED');
  assert.throws(() => normalizePublicWebUrl('https://admin:secret@example.com/'), error => error.code === 'WEB_CREDENTIALS_NOT_ALLOWED');
  assert.throws(() => normalizePublicWebUrl('https://example.com:22/'), error => error.code === 'WEB_PORT_NOT_ALLOWED');
});

test('Web Inspector blocks obvious localhost/private/metadata targets before any request', () => {
  for (const url of [
    'http://localhost/',
    'http://service.local/',
    'http://127.0.0.1/',
    'http://10.0.0.1/',
    'http://169.254.169.254/latest/meta-data/',
    'http://192.168.1.1/',
    'http://[::1]/',
    'http://[fe80::1]/',
    'http://[fd00::1]/',
  ]) {
    assert.throws(() => normalizePublicWebUrl(url), error => error.code === 'WEB_TARGET_NOT_PUBLIC');
  }
});

test('cookie evidence never exposes cookie values', () => {
  const cookies = parseSetCookieMetadata([
    'session=super-secret-token; Path=/; Secure; HttpOnly; SameSite=Lax',
    'theme=dark; Path=/app',
  ]);
  assert.deepEqual(cookies[0], {
    name: 'session', secure: true, httpOnly: true, sameSite: 'lax', domain: null, path: '/', valueExposed: false,
  });
  assert.equal(cookies[1].name, 'theme');
  assert.equal(cookies[1].secure, false);
  assert.equal(cookies[1].httpOnly, false);
  assert.equal(JSON.stringify(cookies).includes('super-secret-token'), false);
  assert.equal(JSON.stringify(cookies).includes('dark'), false);
});

test('web findings describe observed hygiene and do not claim automatic exploitation', () => {
  const findings = buildWebFindings({
    finalUrl: 'https://example.com/',
    status: 200,
    headers: {
      'content-type': 'text/html',
      'access-control-allow-origin': '*',
      'x-powered-by': 'Example 1.0',
    },
    cookies: [{ name: 'sid', secure: false, httpOnly: false, sameSite: null }],
  });
  assert.ok(findings.some(item => item.id === 'hsts-missing'));
  assert.ok(findings.some(item => item.id === 'csp-missing'));
  assert.ok(findings.some(item => item.id === 'cookie-secure-sid'));
  assert.ok(findings.every(item => item.certainty === 'observed-hygiene'));
  const serialized = JSON.stringify(findings).toLowerCase();
  assert.equal(serialized.includes('exploit confirmado'), false);
  assert.equal(serialized.includes('vulnerabilidade confirmada'), false);
});
