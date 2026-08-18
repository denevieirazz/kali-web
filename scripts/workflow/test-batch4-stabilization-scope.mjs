import { execFileSync } from 'node:child_process';

const EXPECTED_BRANCH = 'stabilization/cloudos-workflow-batch-4';
const FREEZE_HEAD = 'ae08460f8c813ed9264ca330ef918071c6f3c2aa';
const allowed = new Set([
  '.github/workflows/workflow-batch4-stabilization-ci.yml',
  'WORKFLOW_CAPACITY_AUDIT.md',
  'WORKFLOW_LONG_SESSION_AUDIT.md',
  'WORKFLOW_SCALE_DESIGN.md',
  'WORKFLOW_STABILIZATION_AUDIT_2.md',
  'frontend/src/apps/CloudOSFiles/CloudOSFiles.tsx',
  'frontend/src/apps/CloudOSFiles/windowsDirectorySource.ts',
  'frontend/src/apps/CloudOSTerminal/TerminalSession.tsx',
  'frontend/src/apps/WorkflowWorkspace/WorkflowWorkspace.tsx',
  'frontend/src/components/Workflow/WorkflowBatch4Shell.tsx',
  'frontend/src/services/workflowQuickEvidence.ts',
  'frontend/src/services/workflowWorkspace.ts',
  'frontend/test/workflowBatch4Stabilization.test.js',
  'playwright.human.config.ts',
  'tests/playwright/workflow-human-simulation.spec.ts',
  'scripts/workflow/test-batch4-stabilization-scope.mjs',
]);

function git(...args) {
  return execFileSync('git', args, { encoding: 'utf8' }).trim();
}

const changed = git('diff', '--name-only', `${FREEZE_HEAD}...HEAD`).split(/\r?\n/).filter(Boolean);
if (!changed.length) throw new Error('A estabilização não contém alterações em relação ao freeze.');

const unexpected = changed.filter(path => !allowed.has(path));
if (unexpected.length) {
  console.error('BATCH4_STABILIZATION_SCOPE_VIOLATION');
  for (const path of unexpected) console.error(` - ${path}`);
  process.exit(1);
}

const required = [
  'frontend/src/apps/CloudOSFiles/CloudOSFiles.tsx',
  'frontend/src/apps/CloudOSFiles/windowsDirectorySource.ts',
  'frontend/src/apps/CloudOSTerminal/TerminalSession.tsx',
  'frontend/src/apps/WorkflowWorkspace/WorkflowWorkspace.tsx',
  'frontend/src/components/Workflow/WorkflowBatch4Shell.tsx',
  'frontend/src/services/workflowQuickEvidence.ts',
  'frontend/src/services/workflowWorkspace.ts',
  'frontend/test/workflowBatch4Stabilization.test.js',
];
const missing = required.filter(path => !changed.includes(path));
if (missing.length) {
  console.error('BATCH4_STABILIZATION_REQUIRED_FILE_MISSING');
  for (const path of missing) console.error(` - ${path}`);
  process.exit(1);
}

const refName = process.env.GITHUB_REF_NAME;
const headRef = process.env.GITHUB_HEAD_REF;
const baseRef = process.env.GITHUB_BASE_REF;
const branchMatches = refName === EXPECTED_BRANCH || headRef === EXPECTED_BRANCH || baseRef === EXPECTED_BRANCH;
if ((refName || headRef || baseRef) && !branchMatches) {
  console.error(`BATCH4_STABILIZATION_WRONG_BRANCH: ref=${refName || '-'} head=${headRef || '-'} base=${baseRef || '-'}`);
  process.exit(1);
}

console.log(`BATCH4_STABILIZATION_SCOPE_OK base=${FREEZE_HEAD} files=${changed.length}`);
for (const path of changed) console.log(` + ${path}`);
