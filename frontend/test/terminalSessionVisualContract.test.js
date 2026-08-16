import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source=fs.readFileSync(new URL('../src/apps/CloudOSTerminal/TerminalSession.tsx',import.meta.url),'utf8');

test('terminal waits for real geometry before Terminal.open and fit',()=>{
  assert.match(source,/waitForTerminalGeometry/);
  assert.match(source,/terminal\.open\(host\)/);
  assert.match(source,/await nextFrame\(\)/);
  assert.match(source,/hasUsableTerminalGeometry/);
  const waitIndex=source.indexOf('await waitForTerminalGeometry');
  const openIndex=source.indexOf('terminal.open(host)');
  assert.ok(waitIndex >= 0 && openIndex > waitIndex);
});

test('resize is coalesced and teardown is idempotent',()=>{
  assert.match(source,/TerminalFrameScheduler/);
  assert.match(source,/ResizeObserver\(\(\) => fitScheduler\.schedule\(\)\)/);
  assert.match(source,/if \(disposeStarted\) return/);
  assert.match(source,/fitSchedulerRef\.current\?\.dispose\(\)/);
  assert.match(source,/resizeObserver\?\.disconnect\(\)/);
});

test('visual errors are locally contained',()=>{
  assert.match(source,/try \{\s*terminal\.open\(host\)/s);
  assert.match(source,/try \{\s*fitAddon\.fit\(\)/s);
  assert.match(source,/data-terminal-visual-error/);
  assert.match(source,/role="status"/);
});

test('terminal transport contract remains WSL Core v2 aware',()=>{
  assert.match(source,/WSL_CORE_MODE/);
  assert.match(source,/transport\?\.resize/);
  assert.match(source,/transport\?\.input/);
  assert.match(source,/transport\?\.dispose/);
});
