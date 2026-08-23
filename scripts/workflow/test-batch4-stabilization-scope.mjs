import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

export const EXPECTED_BRANCH = 'stabilization/cloudos-workflow-batch-4';
export const FREEZE_HEAD = 'ae08460f8c813ed9264ca330ef918071c6f3c2aa';
export const allowed = new Set([
  '.github/workflows/workflow-batch4-stabilization-ci.yml',
  '.github/workflows/workflow-drone-ci.yml',
  'DRONE_REPORT.md',
  'DRONE_TRIAGE.md',
  'HUMAN_SIMULATION_REPORT.md',
  'WORKFLOW_CAPACITY_AUDIT.md',
  'WORKFLOW_HARDENING_REPORT.md',
  'WORKFLOW_LONG_SESSION_AUDIT.md',
  'WORKFLOW_SCALE_DESIGN.md',
  'WORKFLOW_STABILIZATION_AUDIT_2.md',
  'frontend/src/apps/CloudOSFiles/CloudOSFiles.tsx',
  'frontend/src/apps/CloudOSFiles/fileSourceFacade.ts',
  'frontend/src/apps/CloudOSFiles/windowsDirectorySource.ts',
  'frontend/src/apps/CloudOSTerminal/CloudOSTerminal.css',
  'frontend/src/apps/CloudOSTerminal/CloudOSTerminal.tsx',
  'frontend/src/apps/CloudOSTerminal/TerminalSession.tsx',
  'frontend/src/apps/CloudOSTerminal/terminalVisualLifecycle.d.ts',
  'frontend/src/apps/CloudOSTerminal/terminalVisualLifecycle.js',
  'frontend/src/apps/WorkflowWorkspace/WorkflowWorkspace.tsx',
  'frontend/src/components/Workflow/FilesWorkflowBridge.css',
  'frontend/src/components/Workflow/WorkflowBatch4Shell.tsx',
  'frontend/src/components/Workflow/WorkflowBatch4Shell.css',
  'frontend/src/services/workflowFileMarks.ts',
  'frontend/src/services/workflowQuickEvidence.ts',
  'frontend/src/services/workflowRecentFiles.ts',
  'frontend/src/services/workflowWorkspace.ts',
  'frontend/test/visibleTerminalComponentContract.test.js',
  'frontend/test/workflowBatch4Stabilization.test.js',
  'frontend/test/workflowContract.test.js',
  'frontend/test/workflowDroneReport.test.js',
  'playwright.drone.config.ts',
  'playwright.human.config.ts',
  'scripts/Get-GitContext.ps1',
  'scripts/test-git-branch-resolution-contract.ps1',
  'scripts/workflow/record-sha-telemetry.mjs',
  'scripts/workflow/render-drone-report.mjs',
  'scripts/workflow/run-hardening-regressions.mjs',
  'scripts/workflow/test-batch4-stabilization-scope-contract.mjs',
  'scripts/workflow/test-batch4-stabilization-scope.mjs',
  'scripts/workflow/test-record-sha-telemetry.mjs',
  'scripts/workflow/test-verify-spec-integrity.mjs',
  'scripts/workflow/test-workflow-sha-contract.mjs',
  'scripts/workflow/verify-spec-integrity.mjs',
  'tests/playwright/fixtures/cloudos.fixture.ts',
  'tests/playwright/workflow-drone.spec.ts',
  'tests/playwright/workflow-hardening-resilience.spec.ts',
  'tests/playwright/workflow-human-simulation.spec.ts',
  'tests/playwright/workflow-human-simulation-v2.spec.ts',
]);

export const required = [
  'frontend/src/apps/CloudOSFiles/CloudOSFiles.tsx',
  'frontend/src/apps/CloudOSFiles/windowsDirectorySource.ts',
  'frontend/src/apps/CloudOSTerminal/TerminalSession.tsx',
  'frontend/src/apps/WorkflowWorkspace/WorkflowWorkspace.tsx',
  'frontend/src/components/Workflow/WorkflowBatch4Shell.tsx',
  'frontend/src/services/workflowQuickEvidence.ts',
  'frontend/src/services/workflowWorkspace.ts',
  'frontend/test/workflowBatch4Stabilization.test.js',
];

function git(...args) {
  return execFileSync('git', args, { encoding: 'utf8' }).trim();
}

function policyError(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}

function readEventPayload(env) {
  const eventPath = env.GITHUB_EVENT_PATH;
  if (!eventPath) return null;
  try {
    return JSON.parse(fs.readFileSync(eventPath, 'utf8'));
  } catch {
    return null;
  }
}

function validSha(value) {
  return typeof value === 'string' && /^[0-9a-f]{40}$/i.test(value);
}

export function resolveScopeContext(env = process.env, eventPayload = null, gitResolver = git) {
  const refName = env.GITHUB_REF_NAME || '';
  const headRef = env.GITHUB_HEAD_REF || '';
  const baseRef = env.GITHUB_BASE_REF || '';
  const isPullRequest = Boolean(baseRef);

  if (isPullRequest) {
    if (baseRef !== EXPECTED_BRANCH) {
      throw policyError(
        'BATCH4_STABILIZATION_WRONG_BRANCH',
        `ref=${refName || '-'} head=${headRef || '-'} base=${baseRef || '-'}`
      );
    }

    const payload = eventPayload || readEventPayload(env);
    const payloadBaseRef = payload?.pull_request?.base?.ref;
    const payloadBaseSha = payload?.pull_request?.base?.sha;
    if (payloadBaseRef && payloadBaseRef !== EXPECTED_BRANCH) {
      throw policyError(
        'BATCH4_STABILIZATION_WRONG_BRANCH',
        `event-base=${payloadBaseRef}`
      );
    }

    let scopeRef = validSha(payloadBaseSha) ? payloadBaseSha : null;
    if (!scopeRef) {
      const remoteBase = gitResolver('rev-parse', `refs/remotes/origin/${baseRef}`);
      if (validSha(remoteBase)) scopeRef = remoteBase;
    }
    if (!scopeRef) {
      throw policyError(
        'BATCH4_STABILIZATION_BASE_SHA_UNRESOLVED',
        `base=${baseRef}`
      );
    }

    return {
      mode: 'pull-request-base',
      scopeRef,
      refName,
      headRef,
      baseRef,
    };
  }

  if ((refName || headRef) && refName !== EXPECTED_BRANCH && headRef !== EXPECTED_BRANCH) {
    throw policyError(
      'BATCH4_STABILIZATION_WRONG_BRANCH',
      `ref=${refName || '-'} head=${headRef || '-'} base=${baseRef || '-'}`
    );
  }

  return {
    mode: 'stabilization-head',
    scopeRef: 'HEAD',
    refName,
    headRef,
    baseRef,
  };
}

export function evaluateScope(changed) {
  const unexpected = changed.filter(filePath => !allowed.has(filePath));
  const missing = required.filter(filePath => !changed.includes(filePath));
  return { unexpected, missing };
}

export function runScopeGate(env = process.env) {
  let context;
  try {
    context = resolveScopeContext(env);
  } catch (error) {
    console.error(`${error.code || 'BATCH4_STABILIZATION_SCOPE_CONTEXT_FAILED'}: ${error.message}`);
    return 1;
  }

  const changed = git('diff', '--name-only', `${FREEZE_HEAD}...${context.scopeRef}`).split(/\r?\n/).filter(Boolean);
  if (!changed.length) {
    console.error('BATCH4_STABILIZATION_EMPTY_SCOPE');
    return 1;
  }

  const { unexpected, missing } = evaluateScope(changed);
  if (unexpected.length) {
    console.error('BATCH4_STABILIZATION_SCOPE_VIOLATION');
    for (const filePath of unexpected) console.error(` - ${filePath}`);
    return 1;
  }

  if (missing.length) {
    console.error('BATCH4_STABILIZATION_REQUIRED_FILE_MISSING');
    for (const filePath of missing) console.error(` - ${filePath}`);
    return 1;
  }

  console.log(`BATCH4_STABILIZATION_SCOPE_OK freeze=${FREEZE_HEAD} scope=${context.scopeRef} mode=${context.mode} files=${changed.length}`);
  for (const filePath of changed) console.log(` + ${filePath}`);
  return 0;
}

const invokedDirectly = Boolean(process.argv[1]) && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href;
if (invokedDirectly) process.exit(runScopeGate());
