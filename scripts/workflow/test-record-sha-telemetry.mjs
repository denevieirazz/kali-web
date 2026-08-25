import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const scriptPath = path.resolve(__dirname, 'record-sha-telemetry.mjs');
const repoRoot = path.resolve(__dirname, '../..');

function resolveHeadSha() {
  try {
    return execFileSync('git', ['rev-parse', 'HEAD'], { cwd: repoRoot, encoding: 'utf8' }).trim();
  } catch {
    try {
      return execFileSync('git.exe', ['rev-parse', 'HEAD'], { cwd: repoRoot, encoding: 'utf8' }).trim();
    } catch {
      return 'fa4e4443c7a5dbe809a59449f32d9e2b50ddcfb0';
    }
  }
}

const actualHeadSha = resolveHeadSha();

console.log('🧪 INICIANDO SUÍTE DE TESTES UNITÁRIOS COM NODE:ASSERT/STRICT...');

function withTempContext(fn) {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'sha-telemetry-test-'));
  const tempSummaryFile = path.join(tempDir, 'step-summary.md');
  const tempOutputDir = path.join(tempDir, 'output');
  try {
    const run = (env = {}, args = [], cwd = repoRoot) => {
      const result = spawnSync(process.execPath, [scriptPath, ...args], {
        cwd,
        env: {
          ...process.env,
          TELEMETRY_OUTPUT_DIR: tempOutputDir,
          GITHUB_STEP_SUMMARY: tempSummaryFile,
          ...env,
        },
        encoding: 'utf8',
      });
      const summary = fs.existsSync(tempSummaryFile) ? fs.readFileSync(tempSummaryFile, 'utf8') : '';
      const telemetryFile = path.join(tempOutputDir, 'sha-telemetry.json');
      const telemetryJson = fs.existsSync(telemetryFile) ? JSON.parse(fs.readFileSync(telemetryFile, 'utf8')) : null;
      return {
        status: result.status,
        stdout: result.stdout || '',
        stderr: result.stderr || '',
        summary,
        telemetryJson,
      };
    };
    return fn({ tempDir, tempSummaryFile, tempOutputDir, run });
  } finally {
    try {
      fs.rmSync(tempDir, { recursive: true, force: true });
    } catch {}
  }
}

// 1. Match Válido
console.log('1. Testando Match Válido...');
withTempContext(({ run }) => {
  const res = run({
    GITHUB_EVENT_NAME: 'push',
    EXPECTED_SHA: actualHeadSha,
  }, ['--gate']);
  assert.equal(res.status, 0, 'Match válido deveria retornar exit code 0');
  assert.match(res.stdout, /MATCH=true/);
  assert.match(res.summary, /PASS \(Match Confirmado\)/);
  assert.equal(res.telemetryJson?.match, true);
  assert.equal(res.telemetryJson?.errorCode, 'NONE');
  console.log('   ✅ Match válido passou com status 0 e JSON íntegro');
});

// 2. Mismatch Proposital
console.log('2. Testando Mismatch Proposital...');
withTempContext(({ run }) => {
  const mismatchedSha = '1111111111111111111111111111111111111111';
  const res = run({
    GITHUB_EVENT_NAME: 'pull_request',
    EXPECTED_SHA: mismatchedSha,
  }, ['--gate']);
  assert.notEqual(res.status, 0, 'Mismatch deveria retornar exit code != 0');
  assert.match(res.stderr, /SHA_MISMATCH/);
  assert.match(res.summary, /FAIL \(SHA_MISMATCH\)/);
  assert.equal(res.telemetryJson?.match, false);
  assert.equal(res.telemetryJson?.errorCode, 'SHA_MISMATCH');
  console.log('   ✅ Mismatch proposital falhou fail-closed com SHA_MISMATCH');
});

// 3. Evento Push
console.log('3. Testando Evento Push...');
withTempContext(({ run }) => {
  const res = run({
    GITHUB_EVENT_NAME: 'push',
    GITHUB_REF: 'refs/heads/stabilization/cloudos-workflow-batch-4',
    GITHUB_SHA: actualHeadSha,
  }, ['--gate']);
  assert.equal(res.status, 0, 'Push válido deveria passar');
  assert.match(res.summary, /`push`/);
  assert.equal(res.telemetryJson?.eventName, 'push');
  console.log('   ✅ Evento push verificado');
});

// 4. Evento Workflow Dispatch
console.log('4. Testando Evento Workflow Dispatch...');
withTempContext(({ run }) => {
  const res = run({
    GITHUB_EVENT_NAME: 'workflow_dispatch',
    GITHUB_REF: 'refs/heads/poc/cloudos-linux-runtime-xpra',
    EXPECTED_SHA: actualHeadSha,
  }, ['--gate']);
  assert.equal(res.status, 0, 'workflow_dispatch válido deveria passar');
  assert.match(res.summary, /`workflow_dispatch`/);
  assert.equal(res.telemetryJson?.eventName, 'workflow_dispatch');
  console.log('   ✅ Evento workflow_dispatch verificado');
});

// 5. Pull Request Simulado
console.log('5. Testando Pull Request Simulado...');
withTempContext(({ run }) => {
  const baseSha = 'ae08460f8c813ed9264ca330ef918071c6f3c2aa';
  const mergeSha = '2222222222222222222222222222222222222222';
  const res = run({
    GITHUB_EVENT_NAME: 'pull_request',
    GITHUB_REF: 'refs/pull/99/merge',
    PR_HEAD_SHA: actualHeadSha,
    PR_BASE_SHA: baseSha,
    GITHUB_SHA: mergeSha,
    EXPECTED_SHA: actualHeadSha,
  }, ['--gate']);
  assert.equal(res.status, 0, 'pull_request simulado deveria passar');
  assert.match(res.summary, /`pull_request`/);
  assert.match(res.summary, new RegExp(baseSha));
  assert.match(res.summary, new RegExp(mergeSha));
  assert.equal(res.telemetryJson?.headSha, actualHeadSha);
  assert.equal(res.telemetryJson?.baseSha, baseSha);
  assert.equal(res.telemetryJson?.mergeSha, mergeSha);
  console.log('   ✅ Evento pull_request simulado validado com head, base e merge');
});

// 6. Escaping Robusto no GITHUB_STEP_SUMMARY
console.log('6. Testando Escaping de Caracteres Especiais no Summary...');
withTempContext(({ run }) => {
  const res = run({
    GITHUB_EVENT_NAME: 'inject|pipe`break\nnewline',
    GITHUB_REF: 'refs/heads/feature|weird`name\r\ntest',
    PR_HEAD_SHA: actualHeadSha,
    EXPECTED_SHA: actualHeadSha,
  }, ['--gate']);
  assert.equal(res.status, 0, 'Escaping deveria executar sem crash');
  assert.doesNotMatch(res.summary, /\nnewline`/);
  assert.match(res.summary, /inject\\|pipe\\`break newline/);
  console.log('   ✅ Escaping de tabela Markdown verificado');
});

// 7. Falha de Escrita no GITHUB_STEP_SUMMARY (Fail-Loud)
console.log('7. Testando Falha de Escrita no GITHUB_STEP_SUMMARY...');
withTempContext(({ tempDir, tempOutputDir }) => {
  // Criar um diretório com o mesmo nome do summary file para forçar erro de appendFileSync
  const blockedSummaryPath = path.join(tempDir, 'blocked_dir_as_file');
  fs.mkdirSync(blockedSummaryPath);

  const res = spawnSync(process.execPath, [scriptPath, '--gate'], {
    cwd: repoRoot,
    env: {
      ...process.env,
      TELEMETRY_OUTPUT_DIR: tempOutputDir,
      GITHUB_STEP_SUMMARY: blockedSummaryPath,
      EXPECTED_SHA: actualHeadSha,
    },
    encoding: 'utf8',
  });
  assert.notEqual(res.status, 0, 'Erro de escrita de summary deve falhar o processo ruidosamente');
  assert.match(res.stderr + res.stdout, /EISDIR|EPERM|ERR/i, 'Erro de sistema de arquivos deve ser exibido');
  console.log('   ✅ Falha de escrita no summary encerrou com exit code != 0');
});

// 8. Execução Fora de Repositório Git (Git Failure Fail-Closed)
console.log('8. Testando Execução Fora de Repositório Git...');
withTempContext(({ tempDir, tempOutputDir, tempSummaryFile }) => {
  const isolatedDir = path.join(tempDir, 'not_a_git_repo');
  fs.mkdirSync(isolatedDir);

  const res = spawnSync(process.execPath, [scriptPath, '--gate'], {
    cwd: isolatedDir,
    env: {
      ...process.env,
      TELEMETRY_OUTPUT_DIR: tempOutputDir,
      GITHUB_STEP_SUMMARY: tempSummaryFile,
      EXPECTED_SHA: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    },
    encoding: 'utf8',
  });
  assert.notEqual(res.status, 0, 'Execução fora de git deve falhar fechado');
  assert.match(res.stderr, /INVALID_TESTED_SHA/, 'Esperava INVALID_TESTED_SHA no stderr');
  console.log('   ✅ Execução fora de repositório git falhou fail-closed com INVALID_TESTED_SHA');
});

// 9. Validação de Formato Inválido de SHA (Texto Arbitrário / Git Error)
console.log('9. Testando Rejeição de SHA com Formato Inválido...');
withTempContext(({ run }) => {
  const res = run({
    EXPECTED_SHA: 'git-error: fatal: not a git repo',
  }, ['--gate']);
  assert.notEqual(res.status, 0, 'SHA não-hexadecimal deve falhar fechado');
  assert.match(res.stderr, /INVALID_EXPECTED_SHA/, 'Esperava INVALID_EXPECTED_SHA');
  assert.equal(res.telemetryJson?.errorCode, 'INVALID_EXPECTED_SHA');
  console.log('   ✅ String não-hash rejeitada com código INVALID_EXPECTED_SHA');
});

console.log('\n🎉 TODOS OS 9 TESTES UNITÁRIOS COM NODE:ASSERT/STRICT PASSARAM COM SUCESSO!\n');
