import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { pathToFileURL } from 'node:url';
import { resolveSetupResetEnabled } from '../src/config/index.js';

function probeResetEndpoint(environmentOverrides) {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'cloudos-reset-policy-'));
  const appModule = pathToFileURL(path.resolve('backend/src/app.js')).href;
  const environment = {
    ...process.env,
    NODE_ENV: 'production',
    CLOUDOS_DATA_DIR: dataDir,
    ...environmentOverrides
  };
  delete environment.DATABASE_PATH;

  const result = spawnSync(process.execPath, ['--input-type=module', '--eval', `
    import { createApp } from ${JSON.stringify(appModule)};
    const server = createApp(0).listen(0, '127.0.0.1', async () => {
      try {
        const port = server.address().port;
        const response = await fetch('http://127.0.0.1:' + port + '/api/setup/reset', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ confirm: true })
        });
        process.stdout.write(String(response.status));
      } finally {
        server.close();
      }
    });
  `], {
    cwd: path.resolve('.'),
    env: environment,
    encoding: 'utf8',
    shell: false,
    timeout: 20_000
  });

  fs.rmSync(dataDir, { recursive: true, force: true });
  assert.equal(result.status, 0, result.stderr);
  return Number(result.stdout);
}

test('política de reset só permite teste ou desenvolvimento explicitamente habilitado', () => {
  assert.equal(resolveSetupResetEnabled({ NODE_ENV: 'production' }), false);
  assert.equal(resolveSetupResetEnabled({ NODE_ENV: 'production', CLOUDOS_ALLOW_SETUP_RESET: '1' }), false);
  assert.equal(resolveSetupResetEnabled({ NODE_ENV: 'development' }), false);
  assert.equal(resolveSetupResetEnabled({ NODE_ENV: 'development', CLOUDOS_ALLOW_SETUP_RESET: '1' }), true);
  assert.equal(resolveSetupResetEnabled({ NODE_ENV: 'test' }), true);
  assert.equal(resolveSetupResetEnabled({
    NODE_ENV: 'test',
    CLOUDOS_NATIVE_HOST: '1',
    CLOUDOS_ALLOW_SETUP_RESET: '1'
  }), false);
});

test('endpoint de reset não existe em produção nem no host nativo', () => {
  assert.equal(probeResetEndpoint({ NODE_ENV: 'production', CLOUDOS_ALLOW_SETUP_RESET: '1' }), 404);
  assert.equal(probeResetEndpoint({
    NODE_ENV: 'test',
    CLOUDOS_NATIVE_HOST: '1',
    CLOUDOS_ALLOW_SETUP_RESET: '1'
  }), 404);
});
