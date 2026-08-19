import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  __test,
  buildPreflightDryRunCommand,
  recordXpraPreflightProxyEvent,
  resolveXpraPreflightProxySession,
} from '../src/linuxRuntime/preflightEngine.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

test('EF2-P0-006: Preflight dry-run requires ephemeral auth=env and never uses auth=allow', () => {
  const secret = crypto.randomBytes(24).toString('hex');
  const command = buildPreflightDryRunCommand({
    display: 100,
    port: 14500,
    runId: 'auth-test-run',
    password: secret,
  });

  // 1. Injeta a variável de ambiente XPRA_PASSWORD com a capability efêmera
  assert.match(command, new RegExp(`export XPRA_PASSWORD='${secret}'`));

  // 2. Configura listener TCP com auth=env
  assert.match(command, /--bind-tcp=127\.0\.0\.1:14500,auth=env/);

  // 3. Proíbe expressamente auth=allow
  assert.doesNotMatch(command, /auth=allow/);

  // 4. Garante que nunca inicia processos filhos nem xclock
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
  const sanitized = __test.redactSecret(rawLog, ephemeralSecret);

  assert.equal(sanitized.includes(ephemeralSecret), false);
  assert.match(sanitized, /\[REDACTED_XPRA_PASSWORD\]/);

  const rawStructure = {
    url: `/__cloudos/linux-runtime/poc1/session-1/token-1/?password=${ephemeralSecret}&foo=bar`,
    nested: {
      evidence: `auth=env; password=${ephemeralSecret}`,
      items: [`token=${ephemeralSecret}`, 'safe-item']
    }
  };
  const sanitizedStructure = __test.redactSecret(rawStructure, ephemeralSecret);
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
