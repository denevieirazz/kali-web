import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const workflowsDir = path.resolve(__dirname, '../../.github/workflows');

console.log('🧪 INICIANDO TESTE DE CONTRATO ESTÁTICO DOS WORKFLOWS GITHUB ACTIONS...');

function readWorkflow(filename) {
  const filePath = path.join(workflowsDir, filename);
  assert.ok(fs.existsSync(filePath), `Workflow ${filename} deve existir no repositório`);
  return fs.readFileSync(filePath, 'utf8');
}

// 1. Drone CI Contract
console.log('1. Validando contrato do Workflow Drone CI...');
const droneYml = readWorkflow('workflow-drone-ci.yml');
assert.doesNotMatch(droneYml, /ref:\s*stabilization\/cloudos-workflow-batch-4/, 'Drone CI não pode ter ref de branch hardcoded');
assert.match(droneYml, /ref:\s*\$\{\{\s*github\.event\.pull_request\.head\.sha\s*\|\|\s*github\.sha\s*\}\}/, 'Drone CI deve usar ${{ github.event.pull_request.head.sha || github.sha }}');
assert.match(droneYml, /name:\s*Verify checked out SHA integrity/, 'Drone CI deve conter o step de verificação de integridade');
assert.match(droneYml, /TELEMETRY_OUTPUT_DIR:\s*test-results\/drone/, 'Drone CI deve configurar o diretório de telemetria test-results/drone');
assert.match(droneYml, /run:\s*node scripts\/workflow\/record-sha-telemetry\.mjs --gate/, 'Drone CI deve acionar o gate com --gate');
assert.match(droneYml, /test-results\/drone\/\*\*/, 'Drone CI deve fazer upload do diretório de telemetria');
console.log('   ✅ Contrato do Drone CI validado');

// 2. Stabilization CI Contract
console.log('2. Validando contrato do Workflow Batch 4 Stabilization CI...');
const stabYml = readWorkflow('workflow-batch4-stabilization-ci.yml');
assert.doesNotMatch(stabYml, /ref:\s*stabilization\/cloudos-workflow-batch-4/, 'Stabilization CI não pode ter ref de branch hardcoded');

// Jobs: linux-stabilization, windows-stabilization, human-user-simulation
const requiredJobs = ['linux-stabilization', 'windows-stabilization', 'human-user-simulation'];
for (const job of requiredJobs) {
  assert.ok(stabYml.includes(job), `Stabilization CI deve conter o job ${job}`);
}
assert.match(stabYml, /TELEMETRY_OUTPUT_DIR:\s*test-results\/linux/, 'Linux job deve configurar test-results/linux');
assert.match(stabYml, /TELEMETRY_OUTPUT_DIR:\s*test-results\/windows/, 'Windows job deve configurar test-results/windows');
assert.match(stabYml, /TELEMETRY_OUTPUT_DIR:\s*test-results\/human-simulation/, 'Human simulation job deve configurar test-results/human-simulation');
assert.match(stabYml, /test-results\/linux\/\*\*/, 'Linux job deve possuir upload de telemetria');
assert.match(stabYml, /test-results\/windows\/\*\*/, 'Windows job deve possuir upload de telemetria');
assert.match(stabYml, /test-results\/human-simulation\/\*\*/, 'Human simulation job deve possuir upload de telemetria');
console.log('   ✅ Contrato do Batch 4 Stabilization CI validado');

// 3. Integration Workflows Unmodified Contract
console.log('3. Validando que workflows de integração permanecem intactos...');
const baselineYml = readWorkflow('cloudos-ci.yml');
assert.match(baselineYml, /uses:\s*actions\/checkout@v4/, 'CloudOS CI baseline deve usar checkout v4');
// Não deve ter sido introduzido ref hardcoded de branch estranha
assert.doesNotMatch(baselineYml, /ref:\s*stabilization\/cloudos-workflow-batch-4/);

const terminalYml = readWorkflow('visible-terminal-wsl-core.yml');
assert.match(terminalYml, /uses:\s*actions\/checkout@v4/, 'Visible terminal workflow deve usar checkout v4');

console.log('\n🎉 TODOS OS CONTRATOS ESTÁTICOS DOS WORKFLOWS PASSARAM COM SUCESSO!\n');
