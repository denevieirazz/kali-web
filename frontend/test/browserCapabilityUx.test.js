import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const browser=fs.readFileSync(new URL('../src/apps/Browser/Browser.tsx',import.meta.url),'utf8');
const start=fs.readFileSync(new URL('../src/components/StartMenu/StartMenu.tsx',import.meta.url),'utf8');

test('browser unavailable without Native Host is explained as Full-mode capability',()=>{
  assert.match(browser,/Este recurso exige o modo Full/);
  assert.match(browser,/data-browser-capability/);
  assert.match(browser,/NATIVE_HOST_UNAVAILABLE/);
  assert.doesNotMatch(browser,/<code className="browser-launcher-error-code"/);
});

test('browser does not offer impossible retry when host cannot exist in session',()=>{
  assert.match(browser,/launcher\.status === 'error' && !hostUnavailable/);
  assert.match(browser,/hostUnavailable &&/);
  assert.match(browser,/\>\s*Fechar\s*</);
});

test('start menu marks and blocks Browser before the centralized launch in no-host session',()=>{
  assert.match(start,/appUnavailable\(app\)/);
  assert.match(start,/appLaunchUnavailableReason/);
  assert.match(start,/setCapabilityNotice\(unavailableReason\)/);
  assert.match(start,/data-app-capability=\{unavailable \? 'requires-full'/);
  const guard=start.indexOf('if (unavailableReason)');
  const launch=start.indexOf('launchWorkflowApp(app.id', guard);
  assert.ok(guard >= 0 && launch > guard);
});

test('browser still uses native bridge and never default Windows browser fallback',()=>{
  assert.match(browser,/nativeHostBridge\.openBrowser\(\)/);
  assert.doesNotMatch(browser,/window\.open|location\.href|shellExecute|Start-Process/);
});
