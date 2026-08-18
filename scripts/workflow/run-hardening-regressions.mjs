import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(process.cwd(), 'test-results/drone');
const findingsFile = path.join(root, 'findings.json');
const regressionsFile = path.join(root, 'regressions.json');

const commands = [
  ['npm', ['run', 'test:frontend'], 'frontend'],
  ['npm', ['test'], 'backend'],
  ['npm', ['run', 'test:e2e'], 'e2e'],
  ['npm', ['run', 'lint'], 'lint'],
];

function initializeEvidence() {
  fs.mkdirSync(root, { recursive: true });
  fs.writeFileSync(findingsFile, JSON.stringify([{
    id: 'DRONE-INFRA-PENDING',
    severity: 'CRÍTICO',
    category: 'drone',
    title: 'Patrulha runtime ainda não concluída',
    evidence: 'findings.json foi inicializado antes das regressões. A patrulha runtime deve substituir este marcador; se ela não executar, o gate permanece fail-closed.',
  }], null, 2) + '\n', 'utf8');
}

export function runHardeningRegressions() {
  initializeEvidence();
  const startedAt = new Date().toISOString();
  const results = [];

  for (const [command, args, label] of commands) {
    console.log(`HARDENING_REGRESSION_START ${label}`);
    const result = spawnSync(command, args, {
      cwd: process.cwd(),
      env: process.env,
      stdio: 'inherit',
      shell: process.platform === 'win32',
    });
    const ok = !result.error && result.status === 0;
    const item = {
      label,
      command,
      args,
      ok,
      status: result.status ?? null,
      signal: result.signal ?? null,
      error: result.error ? (result.error.stack || result.error.message) : null,
    };
    results.push(item);
    if (ok) console.log(`HARDENING_REGRESSION_OK ${label}`);
    else console.error(`HARDENING_REGRESSION_FAILED ${label} exit=${result.status ?? 'signal'}${item.error ? ` error=${item.error}` : ''}`);
  }

  const summary = {
    ok: results.every(item => item.ok),
    startedAt,
    finishedAt: new Date().toISOString(),
    commit: process.env.GITHUB_SHA || null,
    results,
  };
  fs.writeFileSync(regressionsFile, JSON.stringify(summary, null, 2) + '\n', 'utf8');
  console.log(summary.ok ? 'HARDENING_REGRESSIONS_OK' : 'HARDENING_REGRESSIONS_FAILED');
  return summary;
}

export default async function globalSetup() {
  runHardeningRegressions();
}

const invokedPath = process.argv[1] ? path.resolve(process.argv[1]) : '';
const modulePath = path.resolve(fileURLToPath(import.meta.url));
if (invokedPath === modulePath) {
  const summary = runHardeningRegressions();
  if (!summary.ok) process.exitCode = 1;
}
