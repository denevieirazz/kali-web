import test from 'node:test';
import assert from 'node:assert/strict';
import {
  LatestRequestGate,
  LINUX_SYSTEM_CENTER_MAX_ROWS,
  LINUX_SYSTEM_CENTER_POLL_MS,
  normalizeCgroupCapabilities,
  normalizeLinuxFilters,
  normalizeLinuxMetrics,
  normalizeLinuxProcessInfo,
  normalizeLinuxProcessPage,
  normalizeLinuxStatus,
  processMatches,
  safeSystemCenterError,
  sortLinuxProcesses,
} from '../src/apps/TaskManager/linuxSystemCenterModel.js';

test('polling and row limits are conservative', () => {
  assert.ok(LINUX_SYSTEM_CENTER_POLL_MS >= 2000);
  assert.ok(LINUX_SYSTEM_CENTER_MAX_ROWS <= 100);
  const filters = normalizeLinuxFilters({ pageSize: 999, query: 'x'.repeat(200) });
  assert.equal(filters.pageSize, 100);
  assert.equal(filters.query.length, 128);
});

test('latest request gate aborts stale request and disposal', () => {
  const gate = new LatestRequestGate();
  const first = gate.next();
  const second = gate.next();
  assert.equal(first.signal.aborted, true);
  assert.equal(first.current(), false);
  assert.equal(second.current(), true);
  gate.dispose();
  assert.equal(second.signal.aborted, true);
  assert.equal(second.current(), false);
});

test('search filter and ordering do not mix process identity', () => {
  const rows = [
    { pid: 2, name: 'sleep', user: 'alice', uid: 1000, state: 'S', cpuPercent: 1, rssBytes: 200, args: ['sleep', '30'] },
    { pid: 1, name: 'init', user: 'root', uid: 0, state: 'S', cpuPercent: 0, rssBytes: 100, args: [] },
  ];
  assert.equal(processMatches(rows[0], { query: 'sleep 30', user: '1000', state: 'S' }), true);
  assert.equal(processMatches(rows[1], { user: 'alice' }), false);
  assert.equal(sortLinuxProcesses(rows, 'memory', 'desc')[0].pid, 2);
});

test('errors are bounded and redact obvious sensitive labels', () => {
  const message = safeSystemCenterError(new Error('token=abcdef secret:thing pid=123 port=9999'));
  assert.ok(message.length <= 240);
  assert.ok(!message.includes('abcdef'));
});

test('physical e417 wire shape normalizes without any dimensions object', () => {
  const status = normalizeLinuxStatus({
    enabled: true,
    available: true,
    fallbackAllowed: false,
    distribution: 'kali-linux',
    wsl2: true,
    corePathConfigured: true,
    protocol: 2,
    protection: 'aes-256-gcm-seq',
    source: 'linux-real',
    mode: 'wsl-core-v2',
  });
  assert.equal(status.available, true);
  assert.equal(status.protocol, 2);
  assert.equal(status.mode, 'wsl-core-v2');

  const page = normalizeLinuxProcessPage({
    source: 'linux-real',
    mode: 'wsl-core-v2',
    total: 20,
    page: 1,
    pageSize: 100,
    truncated: false,
    sampledAt: '2026-08-16T04:30:00Z',
    processes: [{
      pid: 4242,
      ppid: 4100,
      state: 'S',
      uid: 1000,
      user: 'cloudos',
      name: 'sleep',
      executable: '/usr/bin/sleep',
      args: ['sleep', '73'],
      cpuPercent: 0.1,
      rssBytes: 1884160,
      virtualBytes: 2973696,
      threads: 1,
      startTimeTicks: 987654,
      uptimeSeconds: 4.5,
      cgroup: '/user.slice/user-1000.slice/session.scope',
      protected: false,
    }],
  });
  assert.equal(page.total, 20);
  assert.equal(page.processes.length, 1);
  assert.equal(page.processes[0].pid, 4242);
  assert.equal(page.processes[0].uid, 1000);
  assert.equal(page.processes[0].rssBytes, 1884160);
  assert.equal(page.droppedRows, 0);
  assert.equal(page.partialRows, 0);

  const metrics = normalizeLinuxMetrics({
    source: 'linux-real',
    mode: 'wsl-core-v2',
    uptimeSeconds: 1234.5,
    load1: 0.11,
    load5: 0.22,
    load15: 0.33,
    memoryTotalBytes: 8589934592,
    memoryAvailableBytes: 5368709120,
    processCount: 20,
    cgroupV2: true,
    cgroupPath: '/user.slice/user-1000.slice/session.scope',
    cgroupMetrics: { 'memory.current': '104857600' },
    cgroupCapabilities: {
      version: 2,
      mounted: true,
      currentPath: '/user.slice/user-1000.slice/session.scope',
      controllersAvailable: ['cpu', 'memory', 'pids'],
      controllersDelegated: [],
      writableFiles: { 'cgroup.procs': false, 'memory.max': false },
      controllerSupport: { cpu: false, memory: false, pids: false },
      systemd: true,
      controlEnabled: false,
      controlAvailable: false,
      readOnly: true,
      reason: 'feature-flag-disabled',
    },
    resourceMetrics: {
      cgroupPath: '/user.slice/user-1000.slice/session.scope',
      memoryCurrentBytes: 104857600,
      pidsCurrent: 20,
      cpuStat: { usage_usec: 123456 },
    },
  });
  assert.equal(metrics.partial, false);
  assert.equal(metrics.memoryTotalBytes, 8589934592);
  assert.equal(metrics.processCount, 20);
  assert.equal(metrics.cgroupCapabilities.readOnly, true);
  assert.equal(metrics.cgroupCapabilities.controlAvailable, false);
});

test('partial process row preserves available Linux identity and metrics', () => {
  const process = normalizeLinuxProcessInfo({
    pid: 31337,
    uid: 1000,
    state: 'S',
    cpuPercent: 12.5,
    rssBytes: 4096,
    threads: 3,
    cgroup: '/cloudos',
    startTimeTicks: 12345,
    protected: false,
  });
  assert.ok(process);
  assert.equal(process.pid, 31337);
  assert.equal(process.uid, 1000);
  assert.equal(process.state, 'S');
  assert.equal(process.cpuPercent, 12.5);
  assert.equal(process.rssBytes, 4096);
  assert.equal(process.threads, 3);
  assert.equal(process.cgroup, '/cloudos');
  assert.equal(process.ppid, 0);
  assert.equal(process.virtualBytes, 0);
  assert.equal(process.args.length, 0);
  assert.equal(process.user, 'UID 1000');
});

test('one malformed process does not discard valid siblings', () => {
  const page = normalizeLinuxProcessPage({
    total: 3,
    page: 1,
    pageSize: 3,
    processes: [
      { pid: 10, ppid: 1, state: 'S', uid: 1000, user: 'cloudos', name: 'good-a', cpuPercent: 1, rssBytes: 100, virtualBytes: 200, threads: 1, startTimeTicks: 10, protected: false },
      { name: 'missing-pid', uid: 1000, rssBytes: 999 },
      { pid: 12, uid: 1000, state: 'R', cpuPercent: 2, rssBytes: 300, threads: 2, cgroup: '/demo', startTimeTicks: 12, protected: false },
    ],
  });
  assert.deepEqual(page.processes.map(process => process.pid), [10, 12]);
  assert.equal(page.droppedRows, 1);
  assert.equal(page.partialRows, 1);
  assert.equal(page.total, 3);
  assert.equal(page.processes[1].rssBytes, 300);
});

test('missing process start identity is retained but made non-actionable', () => {
  const process = normalizeLinuxProcessInfo({ pid: 99, uid: 1000, state: 'S', name: 'partial', cpuPercent: 0, rssBytes: 1, virtualBytes: 2, threads: 1, protected: false });
  assert.ok(process);
  assert.equal(process.pid, 99);
  assert.equal(process.protected, true);
  assert.equal(process.protectedReason, 'identity-incomplete');
});

test('partial metrics are conservative and cannot enable cgroup writes', () => {
  const metrics = normalizeLinuxMetrics({
    load1: 0.5,
    memoryTotalBytes: 1024,
    cgroupCapabilities: { mounted: true, controlAvailable: true },
  });
  assert.equal(metrics.partial, true);
  assert.ok(metrics.missingFields.includes('resourceMetrics'));
  assert.equal(metrics.load1, 0.5);
  assert.equal(metrics.memoryTotalBytes, 1024);
  assert.equal(metrics.memoryAvailableBytes, 0);
  assert.equal(metrics.cgroupCapabilities.readOnly, true);
  assert.equal(metrics.cgroupCapabilities.controlAvailable, false);
});

test('missing cgroup capability object defaults to explicit read-only unavailable state', () => {
  const capabilities = normalizeCgroupCapabilities(undefined);
  assert.equal(capabilities.version, 0);
  assert.equal(capabilities.mounted, false);
  assert.equal(capabilities.readOnly, true);
  assert.equal(capabilities.controlAvailable, false);
  assert.equal(capabilities.reason, 'metrics-incomplete');
});
