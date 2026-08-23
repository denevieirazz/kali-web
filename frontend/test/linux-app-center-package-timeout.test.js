import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const frontendRoot = path.resolve(__dirname, '..');
const storeSource = fs.readFileSync(path.join(frontendRoot, 'src/apps/ObsidianStore/ObsidianStore.tsx'), 'utf8');
const apiClientSource = fs.readFileSync(path.join(frontendRoot, 'src/services/apiClient.ts'), 'utf8');

test('Linux App Center does not abort package installation at the generic 10 second HTTP timeout', () => {
  assert.match(apiClientSource, /timeoutMs\s*=\s*10000/, 'generic API requests keep the 10s default');

  const timeoutMatch = storeSource.match(/const PACKAGE_INSTALL_TIMEOUT_MS\s*=\s*([\d_]+)/);
  assert.ok(timeoutMatch, 'package-install timeout constant must be explicit');

  const installTimeoutMs = Number(timeoutMatch[1].replaceAll('_', ''));
  assert.ok(installTimeoutMs > 120_000, 'browser timeout must outlive the backend package-manager timeout');

  assert.match(
    storeSource,
    /packages\/\$\{pkg\.id\}\/install[\s\S]{0,320}timeoutMs:\s*PACKAGE_INSTALL_TIMEOUT_MS/,
    'package install request must override the generic 10s timeout'
  );
});

test('Linux App Center records elapsed install time before refreshing the installed catalog', () => {
  assert.match(storeSource, /const startedAt = Date\.now\(\)/);
  assert.match(storeSource, /const elapsedSeconds = \(\(Date\.now\(\) - startedAt\) \/ 1000\)\.toFixed\(1\)/);
  assert.match(storeSource, /Instalação concluída com sucesso em \$\{elapsedSeconds\}s!/);
  assert.match(storeSource, /await fetchPackages\(\)/, 'installed state is refreshed after package completion');
});
