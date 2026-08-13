import test from 'node:test';
import assert from 'node:assert/strict';
import { resolveNativeShellOrigin } from '../src/config/index.js';

test('origem virtual só é confiada no modo nativo com valor canônico exato', () => {
  const canonical = {
    CLOUDOS_NATIVE_HOST: '1',
    CLOUDOS_TRUSTED_ORIGIN: 'https://cloudos.local'
  };

  assert.equal(resolveNativeShellOrigin(canonical), 'https://cloudos.local');
  assert.equal(resolveNativeShellOrigin({ ...canonical, CLOUDOS_NATIVE_HOST: '0' }), null);
  assert.equal(resolveNativeShellOrigin({ ...canonical, CLOUDOS_TRUSTED_ORIGIN: 'https://cloudos.local.evil.example' }), null);
  assert.equal(resolveNativeShellOrigin({ ...canonical, CLOUDOS_TRUSTED_ORIGIN: 'https://cloudos.local:8080' }), null);
  assert.equal(resolveNativeShellOrigin({ ...canonical, CLOUDOS_TRUSTED_ORIGIN: 'http://cloudos.local' }), null);
});
