import test from 'node:test';
import assert from 'node:assert/strict';
import {
  getUserStorageKey,
  getUserOpfsRootName,
  isPrimaryUser,
  setActiveScopedUser,
  getActiveScopedUser,
  switchUserScope
} from '../src/services/userScope.js';

test('isPrimaryUser correctly identifies admin vs secondary users', () => {
  assert.equal(isPrimaryUser({ role: 'admin' }), true);
  assert.equal(isPrimaryUser({ role: 'user' }), false);
  assert.equal(isPrimaryUser(null), true);
});

test('getUserStorageKey preserves legacy keys for admin and scopes for secondary users', () => {
  const admin = { id: 'admin-1', username: 'rootadmin', role: 'admin' };
  const userA = { id: 'user-a-123', username: 'alice', role: 'user' };
  const userB = { id: 'user-b-456', username: 'bob', role: 'user' };

  // 1. Admin / Primary Account
  assert.equal(getUserStorageKey('cloudos.native-settings.v1', admin), 'cloudos.native-settings.v1');
  assert.equal(getUserStorageKey('cloudos.kali-tool-center.workspace.v1', admin), 'cloudos.kali-tool-center.workspace.v1');
  assert.equal(getUserStorageKey('cloudos.terminal.workspace.v1', admin), 'cloudos.terminal.workspace.v1');
  assert.equal(getUserStorageKey('cloudos-unified-desktop-icons-v2', admin), 'cloudos-unified-desktop-icons-v2');
  assert.equal(getUserStorageKey('cloudos.customWallpaper.v1', admin), 'cloudos.customWallpaper.v1');

  // 2. User A
  assert.equal(getUserStorageKey('cloudos.native-settings.v1', userA), 'cloudos.native-settings.v1.user.user-a-123');
  assert.equal(getUserStorageKey('cloudos.kali-tool-center.workspace.v1', userA), 'cloudos.kali-tool-center.workspace.v1.user.user-a-123');
  assert.equal(getUserStorageKey('cloudos.terminal.workspace.v1', userA), 'cloudos.terminal.workspace.v1.user.user-a-123');
  assert.equal(getUserStorageKey('cloudos-unified-desktop-icons-v2', userA), 'cloudos-unified-desktop-icons-v2.user.user-a-123');

  // 3. User B
  assert.equal(getUserStorageKey('cloudos.native-settings.v1', userB), 'cloudos.native-settings.v1.user.user-b-456');
  assert.notEqual(getUserStorageKey('cloudos.native-settings.v1', userA), getUserStorageKey('cloudos.native-settings.v1', userB));
});

test('getUserOpfsRootName preserves legacy root for admin and isolates secondary users', () => {
  const admin = { id: 'admin-1', username: 'rootadmin', role: 'admin' };
  const userA = { id: 'user-a-123', username: 'alice', role: 'user' };
  const userB = { id: 'user-b-456', username: 'bob', role: 'user' };

  assert.equal(getUserOpfsRootName(admin), 'obsidianos-disk');
  assert.equal(getUserOpfsRootName(userA), 'obsidianos-disk-user-user-a-123');
  assert.equal(getUserOpfsRootName(userB), 'obsidianos-disk-user-user-b-456');
});

test('Fluxo multiusuário completo: Admin -> User A -> User B -> Admin com isolamento de persistência', () => {
  const admin = { id: 'admin-0', username: 'admin', role: 'admin' };
  const userA = { id: 'uuid-alice', username: 'alice', role: 'user' };
  const userB = { id: 'uuid-bob', username: 'bob', role: 'user' };

  const storage = new Map();
  const mockLocalStorage = {
    getItem: (k) => storage.get(k) ?? null,
    setItem: (k, v) => storage.set(k, String(v)),
    removeItem: (k) => storage.delete(k)
  };

  // 1. Início com Admin
  setActiveScopedUser(admin);
  mockLocalStorage.setItem(getUserStorageKey('cloudos.native-settings.v1'), JSON.stringify({ theme: 'dark', accent: '#6366f1' }));
  mockLocalStorage.setItem(getUserStorageKey('cloudos.kali-tool-center.workspace.v1'), JSON.stringify({ projectName: 'Admin Audit' }));
  mockLocalStorage.setItem(getUserStorageKey('cloudos.terminal.workspace.v1'), JSON.stringify({ tabs: ['admin-tab'] }));

  assert.equal(storage.get('cloudos.native-settings.v1'), '{"theme":"dark","accent":"#6366f1"}');
  assert.equal(storage.get('cloudos.kali-tool-center.workspace.v1'), '{"projectName":"Admin Audit"}');

  // 2. Troca de usuário para Alice (User A)
  switchUserScope(admin, userA);
  assert.equal(getActiveScopedUser()?.username, 'alice');

  // Alice não enxerga dados de Admin nas suas chaves scoped
  assert.equal(mockLocalStorage.getItem(getUserStorageKey('cloudos.native-settings.v1')), null);
  assert.equal(mockLocalStorage.getItem(getUserStorageKey('cloudos.kali-tool-center.workspace.v1')), null);

  // Alice grava suas próprias configurações
  mockLocalStorage.setItem(getUserStorageKey('cloudos.native-settings.v1'), JSON.stringify({ theme: 'light', accent: '#ef4444' }));
  mockLocalStorage.setItem(getUserStorageKey('cloudos.kali-tool-center.workspace.v1'), JSON.stringify({ projectName: 'Alice Pentest' }));
  mockLocalStorage.setItem(getUserStorageKey('cloudos.terminal.workspace.v1'), JSON.stringify({ tabs: ['alice-tab'] }));

  // 3. Troca de usuário para Bob (User B)
  switchUserScope(userA, userB);
  assert.equal(getActiveScopedUser()?.username, 'bob');

  // Bob não enxerga dados de Alice nem de Admin
  assert.equal(mockLocalStorage.getItem(getUserStorageKey('cloudos.native-settings.v1')), null);
  assert.equal(mockLocalStorage.getItem(getUserStorageKey('cloudos.kali-tool-center.workspace.v1')), null);

  // Bob grava suas configurações
  mockLocalStorage.setItem(getUserStorageKey('cloudos.native-settings.v1'), JSON.stringify({ theme: 'dark', accent: '#22c55e' }));
  mockLocalStorage.setItem(getUserStorageKey('cloudos.kali-tool-center.workspace.v1'), JSON.stringify({ projectName: 'Bob CTF' }));

  // 4. Retorno para o Admin
  switchUserScope(userB, admin);
  assert.equal(getActiveScopedUser()?.username, 'admin');

  // Dados legados do Admin permanecem estritamente preservados
  assert.equal(mockLocalStorage.getItem(getUserStorageKey('cloudos.native-settings.v1')), '{"theme":"dark","accent":"#6366f1"}');
  assert.equal(mockLocalStorage.getItem(getUserStorageKey('cloudos.kali-tool-center.workspace.v1')), '{"projectName":"Admin Audit"}');
  assert.equal(mockLocalStorage.getItem(getUserStorageKey('cloudos.terminal.workspace.v1')), '{"tabs":["admin-tab"]}');

  // Verificar que todas as 3 instâncias coexistem no storage de forma isolada
  assert.equal(storage.get('cloudos.native-settings.v1'), '{"theme":"dark","accent":"#6366f1"}');
  assert.equal(storage.get('cloudos.native-settings.v1.user.uuid-alice'), '{"theme":"light","accent":"#ef4444"}');
  assert.equal(storage.get('cloudos.native-settings.v1.user.uuid-bob'), '{"theme":"dark","accent":"#22c55e"}');
});
