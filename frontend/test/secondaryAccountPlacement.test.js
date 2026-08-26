import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const lockScreen = fs.readFileSync(new URL('../src/components/LockScreen/LockScreen.tsx', import.meta.url), 'utf8');
const settings = fs.readFileSync(new URL('../src/apps/Settings/Settings.tsx', import.meta.url), 'utf8');
const userStore = fs.readFileSync(new URL('../src/stores/userStore.ts', import.meta.url), 'utf8');

test('secondary account creation is available only from an authenticated admin surface', () => {
  assert.doesNotMatch(lockScreen, /Criar outra conta|switchToCreateAccount|handleCreateAccount/);
  assert.match(lockScreen, /Configurações &gt; Contas/);
  assert.match(settings, /currentUser\?\.role==='admin'.*Criar conta local/s);
  assert.match(settings, /createAccount\(secondaryUsername\.trim\(\)/);

  const request = userStore.match(/apiClient<\{ user: unknown; recoveryCode\?: string \}>\('\/api\/auth\/accounts',[\s\S]*?\n        \}\);/u)?.[0] || '';
  assert.ok(request, 'secondary account API request should remain explicit');
  assert.doesNotMatch(request, /skipAuth|suppressUnauthorizedHandler/);
});
