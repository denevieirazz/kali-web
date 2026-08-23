import test from 'node:test';
import assert from 'node:assert/strict';
import {
  EXPECTED_BRANCH,
  evaluateScope,
  resolveScopeContext,
} from './test-batch4-stabilization-scope.mjs';

const BASE_SHA = '2f6d0d62a47eef30d745cf298139284ff5f50e1c';

test('Batch 4 scope gate validates the exact PR base revision instead of the feature head', () => {
  const context = resolveScopeContext(
    {
      GITHUB_REF_NAME: '11/merge',
      GITHUB_HEAD_REF: 'poc/cloudos-linux-runtime-xpra',
      GITHUB_BASE_REF: EXPECTED_BRANCH,
    },
    {
      pull_request: {
        base: { ref: EXPECTED_BRANCH, sha: BASE_SHA },
        head: { ref: 'poc/cloudos-linux-runtime-xpra', sha: '11e20fb6d13a8e93ddcd3fb1ad01f26745af61b4' },
      },
    }
  );

  assert.equal(context.mode, 'pull-request-base');
  assert.equal(context.scopeRef, BASE_SHA);
  assert.notEqual(context.scopeRef, 'HEAD');
});

test('Batch 4 scope gate falls back to the fetched base ref only when event payload lacks a base SHA', () => {
  const calls = [];
  const context = resolveScopeContext(
    {
      GITHUB_HEAD_REF: 'poc/cloudos-linux-runtime-xpra',
      GITHUB_BASE_REF: EXPECTED_BRANCH,
    },
    { pull_request: { base: { ref: EXPECTED_BRANCH } } },
    (...args) => {
      calls.push(args);
      return BASE_SHA;
    }
  );

  assert.deepEqual(calls, [['rev-parse', `refs/remotes/origin/${EXPECTED_BRANCH}`]]);
  assert.equal(context.scopeRef, BASE_SHA);
});

test('Batch 4 scope gate remains strict on direct stabilization branch runs', () => {
  const context = resolveScopeContext({ GITHUB_REF_NAME: EXPECTED_BRANCH });
  assert.equal(context.mode, 'stabilization-head');
  assert.equal(context.scopeRef, 'HEAD');
});

test('Batch 4 scope gate rejects PRs targeting another branch', () => {
  assert.throws(
    () => resolveScopeContext({ GITHUB_HEAD_REF: 'feature/x', GITHUB_BASE_REF: 'main' }),
    error => error?.code === 'BATCH4_STABILIZATION_WRONG_BRANCH'
  );
});

test('Batch 4 allowlist still rejects product files outside stabilization scope', () => {
  const result = evaluateScope([
    'frontend/src/apps/CloudOSFiles/CloudOSFiles.tsx',
    'frontend/src/apps/CloudOSFiles/windowsDirectorySource.ts',
    'frontend/src/apps/CloudOSTerminal/TerminalSession.tsx',
    'frontend/src/apps/WorkflowWorkspace/WorkflowWorkspace.tsx',
    'frontend/src/components/Workflow/WorkflowBatch4Shell.tsx',
    'frontend/src/services/workflowQuickEvidence.ts',
    'frontend/src/services/workflowWorkspace.ts',
    'frontend/test/workflowBatch4Stabilization.test.js',
    'backend/src/linuxRuntime/xpraPoc.js',
  ]);

  assert.deepEqual(result.unexpected, ['backend/src/linuxRuntime/xpraPoc.js']);
  assert.deepEqual(result.missing, []);
});
