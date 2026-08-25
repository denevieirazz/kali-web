import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, '../..');

function getGit(args) {
  try {
    return execFileSync('git', args, { cwd: repoRoot, encoding: 'utf8' }).trim();
  } catch {
    try {
      return execFileSync('git.exe', args, { cwd: repoRoot, encoding: 'utf8' }).trim();
    } catch {
      return null;
    }
  }
}

console.log('🛡️ VERIFICANDO INTEGRIDADE E NÃO-MUTAÇÃO DOS SPECS...');

// 1. Checar se existem modificações em arquivos de teste
const status = getGit(['status', '--porcelain', '--', 'tests/playwright/']);
if (status && status.length > 0) {
  console.error('::error::SPEC_TAMPERING_DETECTED: Arquivos de teste em tests/playwright foram modificados em runtime:');
  console.error(status);
  process.exit(1);
}

// 2. Checar integridade estrutural do spec v2
const v2Path = path.join(repoRoot, 'tests/playwright/workflow-human-simulation-v2.spec.ts');
assert.ok(fs.existsSync(v2Path), 'Arquivo workflow-human-simulation-v2.spec.ts deve existir');
const content = fs.readFileSync(v2Path, 'utf8');

assert.match(content, /test\.describe\('Workflow Human User Simulation v2'/, 'Spec v2 deve declarar describe padronizado');
assert.match(content, /async function ensureFiles\(page:\s*import\('@playwright\/test'\)\.Page\)/, 'Spec v2 deve conter o helper ensureFiles canônico');
assert.match(content, /test\('1 CLIENTE NOVO'/, 'Spec v2 deve conter as missões canônicas');

console.log('✅ INTEGRIDADE DOS SPECS CONFIRMADA: Nenhum spec foi mutado ou reescrito em runtime.');
