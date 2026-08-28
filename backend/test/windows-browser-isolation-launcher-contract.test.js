import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '../..');
const common = fs.readFileSync(path.join(repoRoot, 'scripts/launch/cloudos-launcher-common.ps1'), 'utf8');
const launcher = fs.readFileSync(path.join(repoRoot, 'scripts/launch/start-cloudos.ps1'), 'utf8');
const catalog = fs.readFileSync(path.join(repoRoot, 'backend/src/apps/appCatalog.js'), 'utf8');

test('Full mode fornece ao backend nativo um CLOUDOS_DATA_DIR absoluto criado pela sessão', () => {
  assert.match(common, /\$script:CloudOSRoot\s*=\s*\(Resolve-Path\s+\(Join-Path\s+\$PSScriptRoot\s+'\.\.\\\.\.'\)\)\.Path/);
  assert.match(common, /dataDirectory=\(Join-Path\s+\$sessionDir\s+'data'\)/);
  assert.match(common, /New-Item\s+-ItemType\s+Directory\s+-Force\s+-Path\s+\$session\.runtimeDirectory,\$session\.dataDirectory/);

  assert.match(launcher, /\$env:CLOUDOS_DATA_DIR\s*=\s*\$session\.dataDirectory/);
  assert.match(launcher, /CLOUDOS_NATIVE_HOST\s*=\s*if\s*\(\$Mode\s+-in\s+@\('Full','BrowserValidation'\)\)/);
  assert.match(launcher, /Start-CloudOSLoggedProcess[\s\S]*?CLOUDOS_DATA_DIR=\$session\.dataDirectory[\s\S]*?CLOUDOS_SESSION_ID=\$session\.id/);
});

test('catálogo de navegador usa somente o root local absoluto entregue pelo launcher', () => {
  assert.match(catalog, /process\.env\.CLOUDOS_LOCAL_ROOT\s*\|\|\s*process\.env\.CLOUDOS_DATA_DIR\s*\|\|\s*''/);
  assert.match(catalog, /path\.win32\.isAbsolute\(root\)/);
  assert.match(catalog, /BROWSER_PROFILE_ISOLATION_UNAVAILABLE/);
});
