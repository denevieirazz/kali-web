import { execFileSync } from 'node:child_process';

const EXPECTED_BRANCH = 'feature/cloudos-workflow-batch-4';
const DEFAULT_BASE = 'feature/cloudos-workflow-batch-3';
const allowed = new Set([
  '.github/workflows/workflow-batch4-ci.yml',
  'WORKFLOW_BATCH4_REVIEW.md',
  'frontend/src/App.tsx',
  'frontend/src/apps/CloudOSTerminal/CloudOSTerminal.css',
  'frontend/src/components/Workflow/WorkflowBatch4Shell.css',
  'frontend/src/components/Workflow/WorkflowBatch4Shell.tsx',
  'frontend/src/core/zipStore.d.ts',
  'frontend/src/core/zipStore.js',
  'frontend/src/services/workflowFileMarks.ts',
  'frontend/src/services/workflowQuickEvidence.ts',
  'frontend/src/services/workflowWorkspaceZip.ts',
  'frontend/test/workflowBatch4Contract.test.js',
  'frontend/test/workflowBatch4Zip.test.js',
  'scripts/workflow/test-batch4-scope.mjs',
]);

function git(...args) {
  return execFileSync('git', args, { encoding: 'utf8' }).trim();
}

function resolveBase() {
  const requested = process.env.BATCH4_BASE || DEFAULT_BASE;
  const candidates = [requested, `origin/${requested}`];
  for (const candidate of candidates) {
    try {
      git('rev-parse', '--verify', candidate);
      return candidate;
    } catch {
      // Try the next explicit ref.
    }
  }
  throw new Error(`Base do Batch 4 não encontrada: ${requested}`);
}

const base = resolveBase();
const changed = git('diff', '--name-only', `${base}...HEAD`).split(/\r?\n/).filter(Boolean);
if (!changed.length) throw new Error('Batch 4 não contém alterações em relação ao Batch 3.');

const unexpected = changed.filter(path => !allowed.has(path));
if (unexpected.length) {
  console.error('BATCH4_SCOPE_VIOLATION');
  for (const path of unexpected) console.error(` - ${path}`);
  process.exit(1);
}

const required = [
  'frontend/src/components/Workflow/WorkflowBatch4Shell.tsx',
  'frontend/src/services/workflowWorkspaceZip.ts',
  'frontend/test/workflowBatch4Contract.test.js',
  'WORKFLOW_BATCH4_REVIEW.md',
];
const missing = required.filter(path => !changed.includes(path));
if (missing.length) {
  console.error('BATCH4_REQUIRED_FILE_MISSING');
  for (const path of missing) console.error(` - ${path}`);
  process.exit(1);
}

const refName = process.env.GITHUB_REF_NAME;
if (refName && refName !== EXPECTED_BRANCH) {
  console.error(`BATCH4_WRONG_BRANCH: ${refName}`);
  process.exit(1);
}

console.log(`BATCH4_SCOPE_OK base=${base} files=${changed.length}`);
for (const path of changed) console.log(` + ${path}`);
