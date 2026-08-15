import test from 'node:test';
import assert from 'node:assert/strict';
import {
  TASKBAR_SIZE,
  calculateShellLayout,
  normalizeTaskbarPosition,
} from '../src/core/shellLayout.js';

test('normalizes unsupported taskbar positions to bottom', () => {
  assert.equal(normalizeTaskbarPosition('LEFT'), 'left');
  assert.equal(normalizeTaskbarPosition('diagonal'), 'bottom');
  assert.equal(normalizeTaskbarPosition(null), 'bottom');
});

test('calculates bottom taskbar without covering desktop work area', () => {
  const layout = calculateShellLayout({ width: 1920, height: 1080 }, 'bottom');
  assert.deepEqual(layout.taskbar, { x: 0, y: 1080 - TASKBAR_SIZE, width: 1920, height: TASKBAR_SIZE });
  assert.deepEqual(layout.desktop, { x: 0, y: 0, width: 1920, height: 1080 - TASKBAR_SIZE });
});

test('calculates top taskbar work area', () => {
  const layout = calculateShellLayout({ width: 1366, height: 768 }, 'top');
  assert.deepEqual(layout.taskbar, { x: 0, y: 0, width: 1366, height: TASKBAR_SIZE });
  assert.deepEqual(layout.desktop, { x: 0, y: TASKBAR_SIZE, width: 1366, height: 768 - TASKBAR_SIZE });
});

test('calculates left and right taskbar work areas', () => {
  const left = calculateShellLayout({ width: 1280, height: 720 }, 'left');
  assert.deepEqual(left.taskbar, { x: 0, y: 0, width: TASKBAR_SIZE, height: 720 });
  assert.deepEqual(left.desktop, { x: TASKBAR_SIZE, y: 0, width: 1280 - TASKBAR_SIZE, height: 720 });

  const right = calculateShellLayout({ width: 1280, height: 720 }, 'right');
  assert.deepEqual(right.taskbar, { x: 1280 - TASKBAR_SIZE, y: 0, width: TASKBAR_SIZE, height: 720 });
  assert.deepEqual(right.desktop, { x: 0, y: 0, width: 1280 - TASKBAR_SIZE, height: 720 });
});

test('clamps tiny or malformed viewports instead of producing negative geometry', () => {
  const tiny = calculateShellLayout({ width: 20, height: 10 }, 'bottom', 48);
  assert.deepEqual(tiny.taskbar, { x: 0, y: 0, width: 20, height: 10 });
  assert.deepEqual(tiny.desktop, { x: 0, y: 0, width: 20, height: 0 });

  const malformed = calculateShellLayout({ width: Number.NaN, height: -3 }, 'right');
  assert.deepEqual(malformed.taskbar, { x: 0, y: 0, width: 0, height: 0 });
  assert.deepEqual(malformed.desktop, { x: 0, y: 0, width: 0, height: 0 });
});
