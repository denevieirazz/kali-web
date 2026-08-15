import test from 'node:test';
import assert from 'node:assert/strict';
import {
  SYSTEM_CENTER_HISTORY_LIMIT,
  appendHistory,
  clampPercent,
  diskPercent,
  healthSummary,
  isSystemProcess,
  memoryPercent,
  sortProcesses,
} from '../src/core/systemCenterMetrics.js';

test('percent helpers use the real SystemResource field names', () => {
  assert.equal(clampPercent(-10), 0);
  assert.equal(clampPercent(140), 100);
  assert.equal(clampPercent(Number.NaN), 0);
  assert.equal(memoryPercent({ usedMemory: 512, totalMemory: 1024 }), 50);
  assert.equal(diskPercent({ usedDisk: 90, totalDisk: 100 }), 90);
  assert.equal(diskPercent({ diskUsed: 90, diskTotal: 100 }), 0);
});

test('performance history is bounded', () => {
  let history = [];
  for (let index = 0; index < SYSTEM_CENTER_HISTORY_LIMIT + 20; index += 1) {
    history = appendHistory(history, index);
  }
  assert.equal(history.length, SYSTEM_CENTER_HISTORY_LIMIT);
  assert.ok(history.every(value => value >= 0 && value <= 100));
});

test('health summary reports only observable alert conditions', () => {
  const health = healthSummary({
    processes: [{ status: 'suspended' }],
    services: [{ status: 'failed' }],
    drivers: [{ status: 'not_found' }],
    resources: { cpuUsage: 97, usedMemory: 950, totalMemory: 1000 },
  });
  assert.equal(health.status, 'attention');
  assert.equal(health.failedServices, 1);
  assert.equal(health.failedDrivers, 1);
  assert.equal(health.suspended, 1);
  assert.equal(health.alerts.length, 4);
});

test('system process boundary follows the kernel reserved PID range', () => {
  assert.equal(isSystemProcess({ pid: 4 }), true);
  assert.equal(isSystemProcess({ pid: 99 }), true);
  assert.equal(isSystemProcess({ pid: 100 }), false);
});

test('process sorting uses actual Process fields', () => {
  const processes = [
    { pid: 4, title: 'Beta', name: 'beta.obx', memoryUsage: 100, cpuUsage: 1 },
    { pid: 102, title: 'Alpha', name: 'alpha.obx', memoryUsage: 200, cpuUsage: 9 },
  ];
  assert.equal(sortProcesses(processes, 'memory')[0].pid, 102);
  assert.equal(sortProcesses(processes, 'cpu')[0].pid, 102);
  assert.equal(sortProcesses(processes, 'pid')[0].pid, 4);
  assert.equal(sortProcesses(processes, 'name')[0].title, 'Alpha');
});
