import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  __test as preflightTest,
  buildPreflightDryRunCommand,
  resolveXpraPreflightProxySession,
} from '../src/linuxRuntime/preflightEngine.js';
import { __test as proxyTest, xpraHttpProxyMiddleware } from '../src/linuxRuntime/xpraProxy.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

test('EF2-P0-006: Preflight dry-run requires ephemeral auth=env and never uses auth=allow', () => {
  const secret = crypto.randomBytes(24).toString('hex');
  const command = buildPreflightDryRunCommand({
    display: 100,
    port: 14500,
    runId: 'auth-test-run',
    password: secret,
  });

  assert.match(command, new RegExp(`export XPRA_PASSWORD='${secret}'`));
  assert.match(command, /--bind-tcp=127\.0\.0\.1:14500,auth=env/);
  assert.doesNotMatch(command, /auth=allow/);
  assert.doesNotMatch(command, /--start-child/);
  assert.doesNotMatch(command, /xclock/i);
});

test('EF2-P0-006: Preflight dry-run rejects missing or weak password', () => {
  assert.throws(() => buildPreflightDryRunCommand({ display: 100, port: 14500, runId: 'r1', password: '' }), /Capability Xpra inválida/);
  assert.throws(() => buildPreflightDryRunCommand({ display: 100, port: 14500, runId: 'r2', password: '123' }), /Capability Xpra inválida/);
  assert.throws(() => buildPreflightDryRunCommand({ display: 100, port: 14500, runId: 'r3', password: null }), /Capability Xpra inválida/);
});

test('EF2-P0-006: Complete redaction of ephemeral secret from logs and data structures', () => {
  const ephemeralSecret = '0123456789abcdef0123456789abcdef';
  const rawLog = `DRY_RUN_COMMAND set -eu; export XPRA_PASSWORD='${ephemeralSecret}'; exec xpra seamless :100`;
  const sanitized = preflightTest.redactSecret(rawLog, ephemeralSecret);

  assert.equal(sanitized.includes(ephemeralSecret), false);
  assert.match(sanitized, /\[REDACTED_XPRA_PASSWORD\]/);

  const rawStructure = {
    url: `/__cloudos/linux-runtime/poc1/session-1/token-1/?password=${ephemeralSecret}&foo=bar`,
    nested: {
      evidence: `auth=env; password=${ephemeralSecret}`,
      items: [`token=${ephemeralSecret}`, 'safe-item']
    }
  };
  const sanitizedStructure = preflightTest.redactSecret(rawStructure, ephemeralSecret);
  assert.equal(JSON.stringify(sanitizedStructure).includes(ephemeralSecret), false);
  assert.equal(sanitizedStructure.nested.items[0], 'token=[REDACTED_XPRA_PASSWORD]');
  assert.equal(sanitizedStructure.nested.items[1], 'safe-item');
});

test('EF2-P0-006: Global codebase verification: zero occurrences of auth=allow in runtime/preflight code', () => {
  const engineSource = fs.readFileSync(path.join(root, 'src/linuxRuntime/preflightEngine.js'), 'utf8');
  const pocSource = fs.readFileSync(path.join(root, 'src/linuxRuntime/xpraPoc.js'), 'utf8');

  assert.doesNotMatch(engineSource, /auth=allow/);
  assert.doesNotMatch(pocSource, /auth=allow/);
});

test('EF2-P0-006: Capability proxy session resolution rejects missing/wrong token and timing attack', () => {
  const token = 'correct-token-0123456789abcdef';

  assert.equal(resolveXpraPreflightProxySession('non-existent', token), null);
  assert.equal(resolveXpraPreflightProxySession('', ''), null);
  assert.equal(resolveXpraPreflightProxySession(null, null), null);
});

test('EF2-P0-006: WebSocket upgrade serializer attaches Authorization Basic header securely', () => {
  const mockSession = {
    id: 'test-ws-session',
    port: 14500,
    proxyToken: 'tok123',
    xpraPassword: 'ephemeral-secret-password-xyz',
  };

  const req = {
    headers: {
      host: 'localhost:5000',
      origin: 'http://localhost:5000',
      'sec-websocket-key': 'dGhlIHNhbXBsZSBub25jZQ==',
      'sec-websocket-version': '13',
      cookie: 'secret=123',
    }
  };

  const serialized = proxyTest.serializeUpgradeRequest(req, '/index.html', mockSession);

  assert.match(serialized, /^GET \/index\.html HTTP\/1\.1\r\n/);
  assert.match(serialized, /Host: 127\.0\.0\.1:14500\r\n/);
  assert.match(serialized, /Origin: http:\/\/127\.0\.0\.1:14500\r\n/);

  // Authorization Basic é injetado com as credenciais da sessão
  const expectedAuth = Buffer.from('xpra:ephemeral-secret-password-xyz').toString('base64');
  assert.match(serialized, new RegExp(`Authorization: Basic ${expectedAuth}\r\n`));

  // Headers sensíveis do cliente externo (cookies) são despojados
  assert.doesNotMatch(serialized, /cookie:/i);
});

test('EF2-P0-006: Client URL is completely clean of passwords across all preflight and POC1 public sessions', () => {
  const preflightEngineSource = fs.readFileSync(path.join(root, 'src/linuxRuntime/preflightEngine.js'), 'utf8');
  const xpraPocSource = fs.readFileSync(path.join(root, 'src/linuxRuntime/xpraPoc.js'), 'utf8');

  // Nenhuma atribuição de clientUrl contém ?password=
  assert.doesNotMatch(preflightEngineSource, /clientUrl\s*=\s*`[^`]*password=/);
  assert.doesNotMatch(xpraPocSource, /clientUrl:\s*\[[^\]]*\]\.includes\([^)]*\)\s*\?\s*`[^`]*password=/);
});
