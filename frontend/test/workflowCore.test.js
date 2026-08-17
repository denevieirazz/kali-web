import test from 'node:test';
import assert from 'node:assert/strict';
import {
  MAX_CLIPBOARD_ITEM_BYTES,
  MAX_CLIPBOARD_ITEMS,
  MAX_VIEWER_ZOOM,
  MIN_VIEWER_ZOOM,
  WORKSPACE_FOLDERS,
  buildWorkspaceManifest,
  buildWslCdCommand,
  clipboardTextPolicy,
  createWorkspaceRecord,
  normalizeViewerZoom,
  snapBounds,
  stepViewerZoom,
  terminalHereCapability,
  workflowFileOpenMode,
  workspaceSearchText,
} from '../src/core/workflowCore.js';

test('workspace scaffold is fixed and manifest records the required metadata', () => {
  assert.deepEqual([...WORKSPACE_FOLDERS], ['Notes', 'Downloads', 'Evidence', 'Reports', 'Files', 'Terminal', 'Browser']);
  const workspace = createWorkspaceRecord({
    id: '12345678-abcd',
    type: 'client',
    name: 'Cliente ACME',
    description: 'Ticket 42',
    client: 'ACME',
    tags: ['produção', 'urgente'],
    provider: 'opfs',
    root: ['Workspaces', 'cliente-acme-12345678'],
    originPath: ['Downloads'],
    now: '2026-08-17T20:00:00.000Z',
  });
  assert.ok(workspace);
  const manifest = buildWorkspaceManifest(workspace);
  assert.equal(manifest.nome, 'Cliente ACME');
  assert.equal(manifest.descricao, 'Ticket 42');
  assert.equal(manifest.cliente, 'ACME');
  assert.deepEqual(manifest.tags, ['produção', 'urgente']);
  assert.equal(manifest.status, 'active');
  assert.equal(manifest.data, '2026-08-17T20:00:00.000Z');
  assert.equal(manifest.ultimoAcesso, '2026-08-17T20:00:00.000Z');
  assert.equal(manifest.ultimaAtividade, '2026-08-17T20:00:00.000Z');
  assert.deepEqual(manifest.origem, { provider: 'opfs', caminhoInicial: ['Downloads'] });
  assert.deepEqual(manifest.estrutura, [...WORKSPACE_FOLDERS]);
  assert.match(workspaceSearchText(workspace), /ACME/);
  assert.match(workspaceSearchText(workspace), /urgente/);
});

test('file opening is extension allowlisted and never treats scripts or symlinks as executable', () => {
  for (const name of ['nota.txt', 'README.md', 'dados.json', 'scan.log']) assert.equal(workflowFileOpenMode(name), 'notes');
  for (const name of ['foto.png', 'foto.jpg', 'foto.jpeg', 'foto.webp', 'manual.pdf']) assert.equal(workflowFileOpenMode(name), 'viewer');
  for (const name of ['script.js', 'teste.ps1', 'run.sh', 'programa.exe', 'sem-extensao']) assert.equal(workflowFileOpenMode(name), 'info');
  assert.equal(workflowFileOpenMode('pasta', 'directory'), 'directory');
  assert.equal(workflowFileOpenMode('README.md', 'symlink', true), 'info');
});

test('image viewer zoom is bounded and deterministic', () => {
  assert.equal(normalizeViewerZoom(0), MIN_VIEWER_ZOOM);
  assert.equal(normalizeViewerZoom(99), MAX_VIEWER_ZOOM);
  assert.equal(stepViewerZoom(1, 1), 1.25);
  assert.equal(stepViewerZoom(1, -1), 0.75);
  assert.equal(stepViewerZoom(MAX_VIEWER_ZOOM, 1), MAX_VIEWER_ZOOM);
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
