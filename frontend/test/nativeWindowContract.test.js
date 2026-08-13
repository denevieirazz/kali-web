import test from 'node:test';
import assert from 'node:assert/strict';
import { nativeSessionForLaunch, nativeViewportBounds } from '../src/services/nativeWindowContract.js';

test('normalizes and clips a DOM slot to the visible WebView viewport', () => {
  assert.deepEqual(
    nativeViewportBounds({ x: -12.4, y: 20.2, width: 400.7, height: 500 }, { width: 320, height: 240 }),
    { x: 0, y: 20, width: 320, height: 220 }
  );
  assert.equal(nativeViewportBounds({ x: 0, y: 0, width: 0, height: 100 }, { width: 320, height: 240 }), null);
  assert.equal(nativeViewportBounds({ x: Number.NaN, y: 0, width: 10, height: 10 }, { width: 320, height: 240 }), null);
});

test('correlates a launch to a native session by opaque id before process id', () => {
  const sessions = [
    { sessionId: 'window-one', processId: 42 },
    { sessionId: 'window-two', processId: 42 }
  ];
  assert.equal(nativeSessionForLaunch(sessions, { sessionId: 'window-two', pid: 42 })?.sessionId, 'window-two');
  assert.equal(nativeSessionForLaunch(sessions, { pid: 42 })?.sessionId, 'window-one');
  assert.equal(nativeSessionForLaunch(sessions, { pid: 0 }), null);
});

