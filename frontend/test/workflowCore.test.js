import test from 'node:test';
import assert from 'node:assert/strict';
import {
  MAX_CLIPBOARD_ITEM_BYTES,
  MAX_CLIPBOARD_ITEMS,
  WORKSPACE_FOLDERS,
  buildWorkspaceManifest,
  buildWslCdCommand,
  clipboardTextPolicy,
  createWorkspaceRecord,
  snapBounds,
  terminalHereCapability,
} from '../src/core/workflowCore.js';

test('workspace scaffold is fixed and manifest records the required metadata', () => {
  assert.deepEqual([...WORKSPACE_FOLDERS], ['Notes', 'Downloads', 'Evidence', 'Reports', 'Files', 'Terminal', 'Browser']);
  const workspace = createWorkspaceRecord({
    id: '12345678-abcd',
    type: 'client',
    name: 'Cliente ACME',
    description: 'Ticket 42',
    provider: 'opfs',
    root: ['Workspaces', 'cliente-acme-12345678'],
    originPath: ['Downloads'],
    now: '2026-08-17T20:00:00.000Z',
  });
  assert.ok(workspace);
  const manifest = buildWorkspaceManifest(workspace);
  assert.equal(manifest.nome, 'Cliente ACME');
  assert.equal(manifest.descricao, 'Ticket 42');
  assert.equal(manifest.data, '2026-08-17T20:00:00.000Z');
  assert.equal(manifest.ultimoAcesso, '2026-08-17T20:00:00.000Z');
  assert.deepEqual(manifest.origem, { provider: 'opfs', caminhoInicial: ['Downloads'] });
  assert.deepEqual(manifest.estrutura, [...WORKSPACE_FOLDERS]);
});

test('clipboard enforces 30 entries, 5 MiB/item and rejects credential-shaped text', () => {
  assert.equal(MAX_CLIPBOARD_ITEMS, 30);
  assert.equal(MAX_CLIPBOARD_ITEM_BYTES, 5 * 1024 * 1024);
  assert.equal(clipboardTextPolicy('anotação operacional').allowed, true);
  assert.equal(clipboardTextPolicy('password=segredo123').allowed, false);
  assert.equal(clipboardTextPolicy('Authorization: Bearer abcdefghijklmnopqrstuvwxyz').allowed, false);
  assert.equal(clipboardTextPolicy('eyJabcdefghijk.eyJabcdefghijk.abcdefghijklmno').allowed, false);
  assert.equal(clipboardTextPolicy('x'.repeat(MAX_CLIPBOARD_ITEM_BYTES + 1)).reason, 'too-large');
});

test('Terminal here is fail-closed outside Linux Home and quotes WSL path segments', () => {
  assert.equal(terminalHereCapability('wsl').supported, true);
  assert.equal(terminalHereCapability('opfs').supported, false);
  assert.equal(terminalHereCapability('windows').supported, false);
  assert.equal(buildWslCdCommand([]), 'cd -- "$HOME"');
  assert.equal(buildWslCdCommand(['cliente', "ticket's"]), 'cd -- "$HOME"/\'cliente\'/\'ticket\'"\'"\'s\'');
  assert.throws(() => buildWslCdCommand(['..']), /inválido/);
  assert.throws(() => buildWslCdCommand(['linha\nquebrada']), /inválido/);
});

test('window half layout covers the viewport without overlap', () => {
  const left = snapBounds('left', 1365, 900, 0, 48);
  const right = snapBounds('right', 1365, 900, 0, 48);
  assert.deepEqual(left, { x: 0, y: 0, width: 682, height: 852 });
  assert.deepEqual(right, { x: 682, y: 0, width: 683, height: 852 });
  assert.equal(left.width + right.width, 1365);
});
