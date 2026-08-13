import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { createApp } from '../src/app.js';
import { resetLocalDatabase } from '../src/database/index.js';
import { createReadinessRouter } from '../src/readiness/routes.js';
import {
  classifyShell,
  createReadinessService,
  inspectOperationJournal,
  InvalidReadinessProfileError,
  READINESS_PROFILES,
  READINESS_SCHEMA_VERSION,
  selectCurrentShell
} from '../src/readiness/readinessService.js';

function startServer(app) {
  return new Promise((resolve, reject) => {
    const server = app.listen(0, '127.0.0.1', () => {
      resolve({ server, port: server.address().port });
    });
    server.on('error', reject);
  });
}

function makeRequest(port, options, body) {
  return new Promise((resolve, reject) => {
    const request = http.request(`http://127.0.0.1:${port}${options.path}`, {
      method: options.method || 'GET',
      headers: options.headers || {}
    }, (response) => {
      let data = '';
      response.on('data', (chunk) => { data += chunk; });
      response.on('end', () => resolve({ status: response.statusCode, body: data }));
    });
    request.on('error', reject);
    if (body) request.write(body);
    request.end();
  });
}

function deterministicDependencies(overrides = {}) {
  return {
    platform: () => 'win32',
    architecture: () => 'x64',
    release: () => '10.0.26100',
    nativeHostActive: () => true,
    configuredHost: () => '127.0.0.1',
    dataDirectoryWritable: async () => true,
    dataDirectoryFreeSpace: async () => 10 * 1024 * 1024 * 1024,
    windowsEdition: async () => ({
      productName: 'Windows 11 Enterprise',
      editionId: 'Enterprise',
      displayVersion: '24H2',
      build: '26100'
    }),
    explorerFallbackPresent: async () => true,
    currentShell: async () => ({ source: 'system-default', kind: 'explorer' }),
    wslSnapshot: async () => ({
      installed: true,
      operational: true,
      errorCode: null,
      distributions: [{ name: 'private-distro-name', version: 2, state: 'Running' }],
      default: 'private-distro-name'
    }),
    wslVersionInfo: async () => ({
      wslVersion: '2.7.11.0',
      kernelVersion: '6.6.87.2',
      wslgVersion: '1.0.73'
    }),
    operationJournalPresence: async () => ({ present: true, valid: true, sizeBytes: 512, entryCount: 2 }),
    ...overrides
  };
}

test('readiness: contrato v1 e perfis implementados produzem observações reais', async () => {
  const service = createReadinessService(deterministicDependencies());
  const report = await service.getReport('shell-preview', { localAddress: '127.0.0.1' });

  assert.equal(report.schemaVersion, READINESS_SCHEMA_VERSION);
  assert.equal(report.schemaVersion, 1);
  assert.equal(report.contract, 'cloudos.readiness/v1');
  assert.equal(report.profile, 'shell-preview');
  assert.equal(report.probeMode, 'read-only');
  assert.equal(report.summary.status, 'ready');
  assert.equal(report.summary.ready, true);
  assert.deepEqual(READINESS_PROFILES, ['hybrid-dev', 'shell-preview', 'shell-candidate']);

  const ids = new Set(report.checks.map((check) => check.id));
  for (const expected of [
    'host',
    'loopback',
    'data-directory-writable',
    'data-directory-free-space',
    'windows-edition',
    'explorer-fallback',
    'current-shell',
    'wsl-snapshot',
    'wslg-ready',
    'operation-journal'
  ]) {
    assert.ok(ids.has(expected), expected);
  }

  const serialized = JSON.stringify(report);
  assert.equal(serialized.includes('private-distro-name'), false);
  assert.equal(serialized.includes('C:\\Users\\'), false);
});

test('readiness: classificador de shell só reconhece valores canônicos exatos', () => {
  assert.equal(classifyShell('explorer.exe'), 'explorer');
  assert.equal(classifyShell('  ExPlOrEr.ExE  '), 'explorer');

  for (const malicious of [
    'cmd.exe /c explorer.exe',
    'explorer.exe & calc.exe',
    'C:\\Windows\\explorer.exe',
    'C:\\malware\\explorer.exe',
    'evil-explorer.exe',
    'powershell.exe -Command "explorer.exe"',
    '"explorer.exe"'
  ]) {
    assert.equal(classifyShell(malicious), 'custom', malicious);
  }

  const canonicalCloudOs = 'C:\\Program Files\\CloudOS\\CloudOS.Bootstrap.exe';
  const verifiedOptions = {
    cloudOsBootstrapExecutable: canonicalCloudOs,
    fileExists: (candidate) => candidate === canonicalCloudOs
  };
  assert.equal(classifyShell(canonicalCloudOs, verifiedOptions), 'cloudos-bootstrap');
  assert.equal(classifyShell(`"${canonicalCloudOs}"`, verifiedOptions), 'cloudos-bootstrap');
  assert.equal(classifyShell(`${canonicalCloudOs} --kiosk`, verifiedOptions), 'custom');
  assert.equal(classifyShell('C:\\Temp\\CloudOS.Bootstrap.exe', verifiedOptions), 'custom');
  assert.equal(classifyShell('C:\\Program Files\\CloudOS\\nested\\..\\CloudOS.Bootstrap.exe', verifiedOptions), 'custom');
  assert.equal(classifyShell('C:/Program Files/CloudOS/CloudOS.Bootstrap.exe', verifiedOptions), 'custom');
  assert.equal(classifyShell(canonicalCloudOs, {
    cloudOsBootstrapExecutable: canonicalCloudOs,
    fileExists: () => false
  }), 'custom');
});

test('readiness: precedência do shell considera política, HKCU Winlogon e depois HKLM', () => {
  assert.deepEqual(selectCurrentShell({
    userPolicy: null,
    userWinlogon: 'explorer.exe',
    systemDefault: 'custom-shell.exe'
  }), { source: 'user-winlogon', kind: 'explorer' });

  assert.deepEqual(selectCurrentShell({
    userPolicy: 'cmd.exe /c explorer.exe',
    userWinlogon: 'explorer.exe',
    systemDefault: 'explorer.exe'
  }), { source: 'user-policy', kind: 'custom' });

  assert.deepEqual(selectCurrentShell({
    userPolicy: ' ',
    userWinlogon: null,
    systemDefault: 'explorer.exe'
  }), { source: 'system-default', kind: 'explorer' });
});

test('readiness: WSL 2 sem versão real do WSLg reprova os perfis de shell', async () => {
  const service = createReadinessService(deterministicDependencies({
    wslVersionInfo: async () => ({
      wslVersion: '2.7.11.0',
      kernelVersion: '6.6.87.2',
      wslgVersion: null
    })
  }));
  for (const profile of ['shell-preview', 'shell-candidate']) {
    const report = await service.getReport(profile, { localAddress: '127.0.0.1' });
    const wslg = report.checks.find((check) => check.id === 'wslg-ready');
    assert.equal(wslg.required, true);
    assert.equal(wslg.observation, 'fail');
    assert.equal(wslg.code, 'WSLG_VERSION_NOT_FOUND');
    assert.equal(wslg.evidence.wslgVersion, null);
    assert.equal(report.summary.ready, false);
  }
});

test('readiness: journal ausente no primeiro boot passa; array válido passa; corrompido falha', async (t) => {
  const directory = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'cloudos-readiness-'));
  const journalPath = path.join(directory, 'operations.json');
  t.after(async () => {
    await fs.promises.rm(directory, { recursive: true, force: true });
  });

  const missing = await inspectOperationJournal(journalPath);
  assert.deepEqual(missing, { present: false, valid: true, sizeBytes: 0, entryCount: 0 });
  let report = await createReadinessService(deterministicDependencies({
    operationJournalPresence: async () => missing
  })).getReport('shell-preview', { localAddress: '127.0.0.1' });
  let journal = report.checks.find((check) => check.id === 'operation-journal');
  assert.equal(journal.observation, 'pass');
  assert.equal(journal.code, 'OPERATION_JOURNAL_AVAILABLE_EMPTY');

  await fs.promises.writeFile(journalPath, '[{"id":"one"}]\n', 'utf8');
  const valid = await inspectOperationJournal(journalPath);
  assert.equal(valid.present, true);
  assert.equal(valid.valid, true);
  assert.equal(valid.entryCount, 1);
  report = await createReadinessService(deterministicDependencies({
    operationJournalPresence: async () => valid
  })).getReport('shell-preview', { localAddress: '127.0.0.1' });
  journal = report.checks.find((check) => check.id === 'operation-journal');
  assert.equal(journal.observation, 'pass');
  assert.equal(journal.code, 'OPERATION_JOURNAL_VALID');

  await fs.promises.writeFile(journalPath, '{"id":"not-an-array"}\n', 'utf8');
  const nonArray = await inspectOperationJournal(journalPath);
  assert.equal(nonArray.present, true);
  assert.equal(nonArray.valid, false);

  await fs.promises.writeFile(journalPath, '{not-json', 'utf8');
  const corrupt = await inspectOperationJournal(journalPath);
  assert.equal(corrupt.present, true);
  assert.equal(corrupt.valid, false);
  report = await createReadinessService(deterministicDependencies({
    operationJournalPresence: async () => corrupt
  })).getReport('shell-preview', { localAddress: '127.0.0.1' });
  journal = report.checks.find((check) => check.id === 'operation-journal');
  assert.equal(journal.observation, 'fail');
  assert.equal(journal.code, 'OPERATION_JOURNAL_INVALID');
  assert.equal(report.summary.status, 'not-ready');
});

test('readiness: falha parcial vira unknown sem propagar detalhes sensíveis', async () => {
  const service = createReadinessService(deterministicDependencies({
    wslSnapshot: async () => {
      throw new Error('C:\\Users\\private\\token-super-secret.txt');
    }
  }));
  const report = await service.getReport('hybrid-dev', { localAddress: '127.0.0.1' });
  const wsl = report.checks.find((check) => check.id === 'wsl-snapshot');

  assert.equal(wsl.deliveryState, 'implemented');
  assert.equal(wsl.observation, 'unknown');
  assert.equal(wsl.code, 'PROBE_UNAVAILABLE');
  assert.equal(report.summary.status, 'unknown');
  assert.equal(JSON.stringify(report).includes('token-super-secret'), false);
  assert.equal(JSON.stringify(report).includes('C:\\Users\\private'), false);
});

test('readiness: checagens futuras do shell-candidate ficam pending e nunca pass', async () => {
  const service = createReadinessService(deterministicDependencies());
  const report = await service.getReport('shell-candidate', { localAddress: '127.0.0.1' });
  const futureIds = new Set([
    'shell-launcher-license',
    'break-glass-admin',
    'windows-recovery-environment',
    'rollback-artifact',
    'host-package-trust'
  ]);
  const futureChecks = report.checks.filter((check) => futureIds.has(check.id));

  assert.equal(futureChecks.length, futureIds.size);
  assert.ok(futureChecks.every((check) => check.deliveryState === 'pending'));
  assert.ok(futureChecks.every((check) => check.observation === 'unknown'));
  assert.ok(futureChecks.every((check) => check.observation !== 'pass'));
  assert.equal(report.summary.status, 'pending');
  assert.equal(report.summary.ready, false);
});

test('readiness: service rejeita perfil inválido', async () => {
  const service = createReadinessService(deterministicDependencies());
  await assert.rejects(
    () => service.getReport('unsafe-shell'),
    (error) => error instanceof InvalidReadinessProfileError && error.code === 'INVALID_READINESS_PROFILE'
  );
});

test('GET /api/readiness exige autenticação, retorna 200 e rejeita perfil inválido com 400', async () => {
  resetLocalDatabase();
  const app = createApp(0);
  const { server, port } = await startServer(app);
  try {
    const unauthenticated = await makeRequest(port, { path: '/api/readiness?profile=hybrid-dev' });
    assert.equal(unauthenticated.status, 401);

    const setup = await makeRequest(port, {
      path: '/api/setup/admin',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({
      username: 'readiness-admin',
      password: 'readiness-password',
      confirmPassword: 'readiness-password'
    }));
    assert.equal(setup.status, 201);
    const token = JSON.parse(setup.body).token;

    const valid = await makeRequest(port, {
      path: '/api/readiness?profile=hybrid-dev',
      headers: { Authorization: `Bearer ${token}` }
    });
    assert.equal(valid.status, 200);
    const report = JSON.parse(valid.body);
    assert.equal(report.contract, 'cloudos.readiness/v1');
    assert.equal(report.schemaVersion, 1);
    assert.equal(report.profile, 'hybrid-dev');
    assert.ok(Array.isArray(report.checks));
    assert.equal(valid.body.includes('C:\\Users\\'), false);

    const invalid = await makeRequest(port, {
      path: '/api/readiness?profile=invalid-profile',
      headers: { Authorization: `Bearer ${token}` }
    });
    assert.equal(invalid.status, 400);
    assert.deepEqual(JSON.parse(invalid.body).allowedProfiles, READINESS_PROFILES);
  } finally {
    server.close();
    resetLocalDatabase();
  }
});

test('GET /api/readiness preserva HTTP 200 quando o relatório contém observation unknown', async () => {
  resetLocalDatabase();
  const bootstrapApp = createApp(0);
  const bootstrap = await startServer(bootstrapApp);
  let token;
  try {
    const setup = await makeRequest(bootstrap.port, {
      path: '/api/setup/admin',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, JSON.stringify({
      username: 'partial-admin',
      password: 'partial-password',
      confirmPassword: 'partial-password'
    }));
    token = JSON.parse(setup.body).token;
  } finally {
    bootstrap.server.close();
  }

  const partialService = {
    async getReport(profile) {
      return {
        schemaVersion: 1,
        profile,
        generatedAt: new Date().toISOString(),
        summary: { status: 'unknown', ready: false, requiredChecks: 1, totalChecks: 1, counts: { pass: 0, fail: 0, unknown: 1, pending: 0, blocked: 0 } },
        checks: [{
          id: 'wsl-snapshot',
          title: 'Estado do WSL',
          required: true,
          deliveryState: 'implemented',
          observation: 'unknown',
          code: 'PROBE_UNAVAILABLE',
          summary: 'A observação não pôde ser concluída neste momento.'
        }]
      };
    }
  };
  const app = express();
  app.use('/api/readiness', createReadinessRouter(partialService));
  const { server, port } = await startServer(app);
  try {
    const response = await makeRequest(port, {
      path: '/api/readiness?profile=hybrid-dev',
      headers: { Authorization: `Bearer ${token}` }
    });
    assert.equal(response.status, 200);
    assert.equal(JSON.parse(response.body).checks[0].observation, 'unknown');
  } finally {
    server.close();
    resetLocalDatabase();
  }
});
