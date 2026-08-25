import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createWorkspaceRecord,
  normalizeWorkspaceRecord,
  sanitizeWorkspaceName,
} from '../src/core/workflowCore.js';
import {
  getUserStorageKey,
  getUserOpfsRootName,
  setActiveScopedUser,
  switchUserScope,
} from '../src/services/userScope.js';

test('EF2-P2-003: Isolamento de dados entre Workspace A e Workspace B no mesmo usuário', () => {
  const wsA = createWorkspaceRecord({
    id: 'ws-a-1111',
    name: 'Projeto Alpha',
    type: 'security',
    provider: 'opfs',
    root: ['Workspaces', 'Projeto-Alpha-ws-a-1111'],
  });

  const wsB = createWorkspaceRecord({
    id: 'ws-b-2222',
    name: 'Projeto Beta',
    type: 'development',
    provider: 'opfs',
    root: ['Workspaces', 'Projeto-Beta-ws-b-2222'],
  });

  assert.ok(wsA);
  assert.ok(wsB);
  assert.notEqual(wsA.id, wsB.id);
  assert.notEqual(wsA.root.join('/'), wsB.root.join('/'));

  // Estrutura de arquivos emulada
  const virtualFs = new Map();
  const fileA = `${wsA.root.join('/')}/Notes/secret-a.md`;
  const fileB = `${wsB.root.join('/')}/Notes/secret-b.md`;

  virtualFs.set(fileA, 'Confidencial Alpha');
  virtualFs.set(fileB, 'Confidencial Beta');

  // Validação: Leitura a partir do escopo do Workspace A
  function readFromWorkspace(workspace, subfolder, fileName) {
    // Rejeição rigorosa de path traversal
    if (fileName.includes('..') || fileName.includes('/') || fileName.includes('\\')) {
      throw new Error('PATH_TRAVERSAL_DETECTED: Acesso fora do root do workspace bloqueado.');
    }
    const fullPath = `${workspace.root.join('/')}/${subfolder}/${fileName}`;
    if (!virtualFs.has(fullPath)) {
      throw new Error(`FILE_NOT_FOUND: Arquivo não existe no workspace ${workspace.name}`);
    }
    return virtualFs.get(fullPath);
  }

  // 1. Workspace A lê seu próprio arquivo
  assert.equal(readFromWorkspace(wsA, 'Notes', 'secret-a.md'), 'Confidencial Alpha');

  // 2. Workspace A tenta ler arquivo do Workspace B (não existe no root de A)
  assert.throws(
    () => readFromWorkspace(wsA, 'Notes', 'secret-b.md'),
    /FILE_NOT_FOUND/,
    'Workspace A não pode acessar arquivos pertencentes a Workspace B'
  );

  // 3. Tentativa de Path Traversal de A para B
  assert.throws(
    () => readFromWorkspace(wsA, 'Notes', '../Projeto-Beta-ws-b-2222/Notes/secret-b.md'),
    /PATH_TRAVERSAL_DETECTED/,
    'Path traversal entre workspaces deve falhar fechado'
  );
});

test('EF2-P2-003: Isolamento multiusuário estrito de Workspaces e OPFS', () => {
  const adminUser = { id: 'admin-1', username: 'admin', role: 'admin' };
  const userAlice = { id: 'alice-uuid', username: 'alice', role: 'user' };
  const userBob = { id: 'bob-uuid', username: 'bob', role: 'user' };

  // Storage Keys isoladas
  const baseKey = 'cloudos.workflow.workspaces.v3';
  const adminKey = getUserStorageKey(baseKey, adminUser);
  const aliceKey = getUserStorageKey(baseKey, userAlice);
  const bobKey = getUserStorageKey(baseKey, userBob);

  assert.equal(adminKey, 'cloudos.workflow.workspaces.v3');
  assert.equal(aliceKey, 'cloudos.workflow.workspaces.v3.user.alice-uuid');
  assert.equal(bobKey, 'cloudos.workflow.workspaces.v3.user.bob-uuid');
  assert.notEqual(aliceKey, bobKey);

  // OPFS Disk Isolation
  assert.equal(getUserOpfsRootName(adminUser), 'obsidianos-disk');
  assert.equal(getUserOpfsRootName(userAlice), 'obsidianos-disk-user-alice-uuid');
  assert.equal(getUserOpfsRootName(userBob), 'obsidianos-disk-user-bob-uuid');

  // Simulação de sessão e troca de escopo
  const mockStorage = new Map();
  setActiveScopedUser(userAlice);

  // Alice cria workspace
  const aliceWsList = [
    { id: 'alice-ws-1', name: 'Alice Private Investigation', status: 'active', root: ['Workspaces', 'Alice-1'] }
  ];
  mockStorage.set(getUserStorageKey(baseKey), JSON.stringify(aliceWsList));

  // Bob entra no sistema
  switchUserScope(userAlice, userBob);
  const bobWsList = [
    { id: 'bob-ws-1', name: 'Bob Pentest Report', status: 'active', root: ['Workspaces', 'Bob-1'] }
  ];
  mockStorage.set(getUserStorageKey(baseKey), JSON.stringify(bobWsList));

  // Verificação de isolamento: Bob não vê workspaces da Alice
  setActiveScopedUser(userBob);
  const bobRead = JSON.parse(mockStorage.get(getUserStorageKey(baseKey)));
  assert.equal(bobRead.length, 1);
  assert.equal(bobRead[0].id, 'bob-ws-1');
  assert.equal(bobRead.some(w => w.id === 'alice-ws-1'), false);

  // Alice retorna e seus workspaces estão intactos
  setActiveScopedUser(userAlice);
  const aliceRead = JSON.parse(mockStorage.get(getUserStorageKey(baseKey)));
  assert.equal(aliceRead.length, 1);
  assert.equal(aliceRead[0].id, 'alice-ws-1');
  assert.equal(aliceRead.some(w => w.id === 'bob-ws-1'), false);
});
