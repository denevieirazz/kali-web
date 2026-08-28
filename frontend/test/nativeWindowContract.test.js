import test from 'node:test';
import assert from 'node:assert/strict';
import { nativeSessionForLaunch, nativeSessionListsEqual, nativeSurfaceLayoutChanged, nativeViewportBounds } from '../src/services/nativeWindowContract.js';

test('normalizes and clips a DOM slot to the visible WebView viewport', () => {
  assert.deepEqual(
    nativeViewportBounds({ x: -12.4, y: 20.2, width: 400.7, height: 500 }, { width: 320, height: 240 }),
    { x: 0, y: 20, width: 320, height: 220 }
  );
  assert.equal(nativeViewportBounds({ x: 0, y: 0, width: 0, height: 100 }, { width: 320, height: 240 }), null);
  assert.equal(nativeViewportBounds({ x: Number.NaN, y: 0, width: 10, height: 10 }, { width: 320, height: 240 }), null);
});

test('skips duplicate native layout IPC but preserves visibility and geometry changes', () => {
  const bounds = { x: 10, y: 20, width: 640, height: 480 };
  const previous = { bounds, visible: true };
  assert.equal(nativeSurfaceLayoutChanged(null, bounds, true), true);
  assert.equal(nativeSurfaceLayoutChanged(previous, { ...bounds }, true), false);
  assert.equal(nativeSurfaceLayoutChanged(previous, { ...bounds, x: 11 }, true), true);
  assert.equal(nativeSurfaceLayoutChanged(previous, { ...bounds }, false), true);
  assert.equal(nativeSurfaceLayoutChanged(previous, null, true), false);
});

test('deduplicates native session events only when observable state is identical', () => {
  const session = {
    sessionId: 'window-one',
    title: 'Editor',
    processId: 42,
    launchProcessId: 42,
    minimized: false,
    maximized: false,
    contained: true,
    containmentMode: 'anchored-overlay',
    visible: true,
    bounds: { x: 10, y: 20, width: 640, height: 480 }
  };

  assert.equal(nativeSessionListsEqual([session], [{ ...session, bounds: { ...session.bounds } }]), true);
  assert.equal(nativeSessionListsEqual([session], [{ ...session, title: 'Editor 2' }]), false);
  assert.equal(nativeSessionListsEqual([session], [{ ...session, launchProcessId: 84 }]), false);
  assert.equal(nativeSessionListsEqual([session], [{ ...session, visible: false }]), false);
  assert.equal(nativeSessionListsEqual([session], [{ ...session, minimized: true }]), false);
  assert.equal(nativeSessionListsEqual([session], [{ ...session, bounds: { ...session.bounds, width: 641 } }]), false);
  assert.equal(nativeSessionListsEqual([session], []), false);
});

test('correlates by opaque session id before a unique launch/process fallback', () => {
  const sessions = [
    { sessionId: 'window-one', processId: 42 },
    { sessionId: 'window-two', processId: 42 }
  ];
  assert.equal(nativeSessionForLaunch(sessions, { sessionId: 'window-two', pid: 42 })?.sessionId, 'window-two');
  assert.equal(nativeSessionForLaunch(sessions, { pid: 42 }), null);
  assert.equal(nativeSessionForLaunch([sessions[0]], { pid: 42 })?.sessionId, 'window-one');
  assert.equal(nativeSessionForLaunch(sessions, { pid: 0 }), null);
});
