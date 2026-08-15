import test from 'node:test';
import assert from 'node:assert/strict';
import {
  MAX_SCOPE_ASSETS,
  addScopeAsset,
  normalizeScopeAsset,
  normalizeSecurityWorkspace,
  removeScopeAsset,
  selectScopeAsset,
} from '../src/core/securityWorkspaceState.js';

test('accepts normalized domains, IPv4, CIDR and HTTP(S) URLs', () => {
  assert.equal(normalizeScopeAsset('Example.COM'), 'example.com');
  assert.equal(normalizeScopeAsset('192.168.1.15'), '192.168.1.15');
  assert.equal(normalizeScopeAsset('10.0.0.0/24'), '10.0.0.0/24');
  assert.equal(normalizeScopeAsset('https://example.com/path#fragment'), 'https://example.com/path');
});

test('rejects unsafe or malformed scope values', () => {
  assert.equal(normalizeScopeAsset('javascript:alert(1)'), null);
  assert.equal(normalizeScopeAsset('https://user:pass@example.com/'), null);
  assert.equal(normalizeScopeAsset('not a host'), null);
  assert.equal(normalizeScopeAsset('999.1.1.1'), null);
  assert.equal(normalizeScopeAsset('10.0.0.0/99'), null);
});

test('workspace normalization drops unknown fields and invalid scopes', () => {
  const workspace = normalizeSecurityWorkspace({
    projectName: '  Auditoria interna  ',
    notes: ' janela autorizada ',
    scopes: ['example.com', 'javascript:bad', 'example.com'],
    activeScope: 'example.com',
    token: 'must-not-survive',
  });

  assert.deepEqual(workspace, {
    projectName: 'Auditoria interna',
    notes: 'janela autorizada',
    scopes: ['example.com'],
    activeScope: 'example.com',
  });
  assert.equal(Object.hasOwn(workspace, 'token'), false);
});

test('adding scopes is bounded and rejects duplicates', () => {
  let workspace = normalizeSecurityWorkspace(null);
  let first = addScopeAsset(workspace, 'example.com');
  assert.equal(first.added, true);
  workspace = first.workspace;

  const duplicate = addScopeAsset(workspace, 'EXAMPLE.COM');
  assert.equal(duplicate.added, false);
  assert.match(duplicate.reason, /já está/i);

  for (let index = 0; index < MAX_SCOPE_ASSETS - 1; index += 1) {
    workspace = addScopeAsset(workspace, `host-${index}.example.com`).workspace;
  }
  assert.equal(workspace.scopes.length, MAX_SCOPE_ASSETS);
  const overflow = addScopeAsset(workspace, 'overflow.example.com');
  assert.equal(overflow.added, false);
  assert.match(overflow.reason, /limite/i);
});

test('active scope remains valid when selecting and removing assets', () => {
  let workspace = normalizeSecurityWorkspace({ scopes: ['one.example.com', 'two.example.com'] });
  workspace = selectScopeAsset(workspace, 'two.example.com');
  assert.equal(workspace.activeScope, 'two.example.com');
  workspace = removeScopeAsset(workspace, 'two.example.com');
  assert.equal(workspace.activeScope, 'one.example.com');
  assert.deepEqual(workspace.scopes, ['one.example.com']);
});
