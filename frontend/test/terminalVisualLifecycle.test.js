import test from 'node:test';
import assert from 'node:assert/strict';
import {
  TerminalFrameScheduler,
  hasUsableTerminalGeometry,
  sanitizeTerminalLifecycleError,
  waitForTerminalGeometry,
} from '../src/apps/CloudOSTerminal/terminalVisualLifecycle.js';

test('terminal host requires connected usable geometry before open or fit', () => {
  assert.equal(hasUsableTerminalGeometry(null), false);
  assert.equal(hasUsableTerminalGeometry({ isConnected: true, clientWidth: 0, clientHeight: 400 }), false);
  assert.equal(hasUsableTerminalGeometry({ isConnected: false, clientWidth: 900, clientHeight: 400 }), false);
  assert.equal(hasUsableTerminalGeometry({ isConnected: true, clientWidth: 900, clientHeight: 400 }), true);
});

test('geometry waiter resolves only after a later usable frame', async () => {
  const host = { isConnected: true, clientWidth: 0, clientHeight: 0 };
  const callbacks = [];
  const promise = waitForTerminalGeometry(host, { requestFrame: cb => { callbacks.push(cb); return callbacks.length; }, maxFrames: 4 });
  assert.equal(callbacks.length, 1);
  host.clientWidth = 800; host.clientHeight = 420;
  callbacks.shift()();
  assert.equal(await promise, true);
});

test('fit scheduler coalesces resize storms and never calls task after dispose', () => {
  const callbacks = new Map(); let seq = 0; let calls = 0;
  const scheduler = new TerminalFrameScheduler({
    requestFrame: cb => { const id=++seq; callbacks.set(id,cb); return id; },
    cancelFrame: id => callbacks.delete(id),
    task: () => { calls += 1; },
  });
  for (let index=0; index<50; index += 1) scheduler.schedule();
  assert.equal(callbacks.size, 1);
  const cb=[...callbacks.values()][0]; callbacks.clear(); cb();
  assert.equal(calls, 1);
  scheduler.schedule();
  assert.equal(callbacks.size, 1);
  scheduler.dispose();
  assert.equal(callbacks.size, 0);
  scheduler.schedule();
  assert.equal(callbacks.size, 0);
  assert.equal(calls, 1);
});

test('lifecycle errors stay bounded and redact obvious credentials', () => {
  const value=sanitizeTerminalLifecycleError(new Error('dimensions failed token=abc123 password:secret'));
  assert.ok(value.length <= 220);
  assert.equal(value.includes('abc123'), false);
  assert.equal(value.includes('secret'), false);
});
