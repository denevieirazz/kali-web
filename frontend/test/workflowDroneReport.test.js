import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const renderer = fileURLToPath(new URL('../../scripts/workflow/render-drone-report.mjs', import.meta.url));

function createFixture() {
  const root = mkdtempSync(join(tmpdir(), 'cloudos-drone-report-'));
  const drone = join(root, 'test-results', 'drone');
  mkdirSync(drone, { recursive: true });
  writeFileSync(join(drone, 'snapshots.json'), '[]\n', 'utf8');
  return { root, drone };
}

function runRenderer(root, args = []) {
  return spawnSync(process.execPath, [renderer, ...args], {
    cwd: root,
    env: { ...process.env, GITHUB_SHA: 'drone-report-regression' },
    encoding: 'utf8',
  });
}

test('Drone preserva observacoes brutas mas findings.json contem somente defeitos efetivos', () => {
  const fixture = createFixture();
  try {
    writeFileSync(join(fixture.drone, 'findings.json'), JSON.stringify([
      {
        id: 'RAW-Z-1',
        severity: 'ALTO',
        category: 'ux',
        title: 'Janela ativa abaixo de outra janela',
        evidence: 'comparacao global de z-index sem prova geometrica',
      },
      {
        id: 'LOW-1',
        severity: 'BAIXO',
        category: 'environment',
        title: 'WSL indisponivel no runner WebOnly',
        evidence: '503',
      },
    ], null, 2), 'utf8');
    writeFileSync(join(fixture.drone, 'regressions.json'), JSON.stringify({ ok: true, results: [] }, null, 2), 'utf8');

    const run = runRenderer(fixture.root);
    assert.equal(run.status, 0, run.stderr || run.stdout);

    const observations = JSON.parse(readFileSync(join(fixture.drone, 'observations.json'), 'utf8'));
    const findings = JSON.parse(readFileSync(join(fixture.drone, 'findings.json'), 'utf8'));

    assert.equal(observations.length, 2, 'evidencia bruta precisa ser preservada');
    assert.equal(findings.length, 1, 'candidato sem prova geometrica nao pode permanecer como finding efetivo');
    assert.equal(findings[0].id, 'LOW-1');
    assert.match(run.stdout, /DRONE_COUNTS critical=0 high=0 medium=0 low=1/);
  } finally {
    rmSync(fixture.root, { recursive: true, force: true });
  }
});

test('Drone gera findings.json e permanece fail-closed quando regressao ou patrulha falham', () => {
  const fixture = createFixture();
  try {
    writeFileSync(join(fixture.drone, 'regressions.json'), JSON.stringify({
      ok: false,
      results: [{ label: 'frontend', ok: false, status: 1, error: 'contract failed' }],
    }, null, 2), 'utf8');

    const run = runRenderer(fixture.root, ['--gate']);
    assert.equal(run.status, 1, 'gate precisa continuar vermelho');

    const findings = JSON.parse(readFileSync(join(fixture.drone, 'findings.json'), 'utf8'));
    const ids = new Set(findings.map(item => item.id));
    assert.ok(ids.has('DRONE-INFRA-0001'), 'ausencia da patrulha precisa virar finding critico');
    assert.ok(ids.has('DRONE-REGRESSION-0001'), 'falha de regressao precisa permanecer no gate');
    assert.ok(findings.every(item => item.severity === 'CRÍTICO'));
  } finally {
    rmSync(fixture.root, { recursive: true, force: true });
  }
});

test('Drone nao duplica finding de regressao quando renderiza relatorio e gate em sequencia', () => {
  const fixture = createFixture();
  try {
    writeFileSync(join(fixture.drone, 'findings.json'), JSON.stringify([
      {
        id: 'LOW-ENV-1',
        severity: 'BAIXO',
        category: 'environment',
        title: 'WSL indisponivel no runner WebOnly',
        evidence: '503',
      },
    ], null, 2), 'utf8');
    writeFileSync(join(fixture.drone, 'regressions.json'), JSON.stringify({
      ok: false,
      results: [{ label: 'backend', ok: false, status: 1, error: 'contract failed' }],
    }, null, 2), 'utf8');

    const reportRun = runRenderer(fixture.root);
    assert.equal(reportRun.status, 0, reportRun.stderr || reportRun.stdout);

    const gateRun = runRenderer(fixture.root, ['--gate']);
    assert.equal(gateRun.status, 1, 'segunda renderizacao precisa continuar fail-closed');

    const findings = JSON.parse(readFileSync(join(fixture.drone, 'findings.json'), 'utf8'));
    assert.equal(findings.filter(item => item.id === 'DRONE-REGRESSION-0001').length, 1, 'finding gerado precisa ser idempotente');
    assert.equal(findings.filter(item => item.id === 'LOW-ENV-1').length, 1, 'finding de runtime precisa ser preservado');
    assert.match(gateRun.stdout, /DRONE_COUNTS critical=1 high=0 medium=0 low=1/);

    const observations = JSON.parse(readFileSync(join(fixture.drone, 'observations.json'), 'utf8'));
    assert.deepEqual(observations.map(item => item.id), ['LOW-ENV-1'], 'observacoes brutas nao devem receber finding derivado do renderer');
  } finally {
    rmSync(fixture.root, { recursive: true, force: true });
  }
});
