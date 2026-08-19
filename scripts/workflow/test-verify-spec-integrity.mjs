import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const scriptPath = path.resolve(__dirname, 'verify-spec-integrity.mjs');
const repoRoot = path.resolve(__dirname, '../..');
const specPath = path.join(repoRoot, 'tests/playwright/workflow-human-simulation-v2.spec.ts');
const originalSpecContent = fs.readFileSync(specPath, 'utf8');

console.log('🧪 INICIANDO TESTE DO GUARDIÃO VERIFY-SPEC-INTEGRITY.MJS...');

function runGuardian() {
  const res = spawnSync(process.execPath, [scriptPath], {
    cwd: repoRoot,
    encoding: 'utf8',
  });
  return {
    status: res.status,
    stdout: res.stdout || '',
    stderr: res.stderr || '',
  };
}

// 1. Cenário Limpo (Pass)
console.log('1. Testando execução em árvore limpa...');
const res1 = runGuardian();
assert.equal(res1.status, 0, 'Guardião deveria passar em árvore limpa');
assert.match(res1.stdout, /INTEGRIDADE DOS SPECS CONFIRMADA/);
console.log('   ✅ Árvore limpa passou com status 0');

// 2. Cenário: Modificação em spec rastreado (Fail)
console.log('2. Testando detecção de modificação em spec rastreado...');
try {
  fs.writeFileSync(specPath, `${originalSpecContent}\n// mutation comment`, 'utf8');
  const res2 = runGuardian();
  assert.notEqual(res2.status, 0, 'Guardião deve reprovar spec rastreado modificado');
  assert.match(res2.stderr, /SPEC_TAMPERING_DETECTED/);
  console.log('   ✅ Modificação em spec rastreado reprovada com SPEC_TAMPERING_DETECTED');
} finally {
  fs.writeFileSync(specPath, originalSpecContent, 'utf8');
}

// 3. Cenário: Arquivo não-rastreado em tests/playwright (Fail)
console.log('3. Testando detecção de arquivo não-rastreado em tests/playwright...');
const untrackedFile = path.join(repoRoot, 'tests/playwright/untracked-injected.spec.ts');
try {
  fs.writeFileSync(untrackedFile, 'test("injected", () => {});\n', 'utf8');
  const res3 = runGuardian();
  assert.notEqual(res3.status, 0, 'Guardião deve reprovar arquivo de spec não-rastreado');
  assert.match(res3.stderr, /SPEC_TAMPERING_DETECTED/);
  console.log('   ✅ Arquivo não-rastreado reprovado com SPEC_TAMPERING_DETECTED');
} finally {
  if (fs.existsSync(untrackedFile)) fs.unlinkSync(untrackedFile);
}

// 4. Cenário: Remoção do helper canônico ensureFiles (Fail)
console.log('4. Testando detecção de ausência do helper canônico ensureFiles...');
try {
  const corruptedSpec = originalSpecContent.replace('async function ensureFiles', 'async function corruptedEnsureFiles');
  fs.writeFileSync(specPath, corruptedSpec, 'utf8');
  const res4 = runGuardian();
  assert.notEqual(res4.status, 0, 'Guardião deve reprovar spec sem ensureFiles canônico');
  console.log('   ✅ Ausência de helper canônico reprovada');
} finally {
  fs.writeFileSync(specPath, originalSpecContent, 'utf8');
}

console.log('\n🎉 TODOS OS 4 TESTES DO GUARDIÃO VERIFY-SPEC-INTEGRITY PASSARAM COM SUCESSO!\n');
