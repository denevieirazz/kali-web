import test from 'node:test';
import assert from 'node:assert/strict';
import {
  MAX_TERMINAL_TABS,
  activateTerminalTab,
  addTerminalTab,
  closeTerminalTab,
  createTerminalTab,
  cycleTerminalTab,
  normalizeTerminalWorkspace,
  serializableTerminalWorkspace,
  toggleTerminalSplit,
  updateTerminalTab,
} from '../src/core/terminalWorkspaceState.js';

const ps = id => createTerminalTab('powershell', '', id);
const wsl = (id, distro = 'kali-linux') => createTerminalTab('wsl', distro, id);

test('normalizes workspace without persisting arbitrary fields', () => {
  const workspace = normalizeTerminalWorkspace({
    tabs: [{ id: 'safe', profile: 'wsl', distribution: 'kali-linux', command: 'ignored', token: 'ignored' }],
    activeId: 'safe',
    splitId: null,
  }, ps('fallback'));
  assert.deepEqual(workspace.tabs, [{ id: 'safe', profile: 'wsl', distribution: 'kali-linux' }]);
  assert.deepEqual(serializableTerminalWorkspace(workspace), workspace);
});

test('adds, activates, cycles and closes tabs deterministically', () => {
  let workspace = normalizeTerminalWorkspace({ tabs: [ps('one')], activeId: 'one' }, ps('one'));
  workspace = addTerminalTab(workspace, wsl('two'));
  assert.equal(workspace.activeId, 'two');
  workspace = activateTerminalTab(workspace, 'one');
  assert.equal(workspace.activeId, 'one');
  workspace = cycleTerminalTab(workspace, 1);
  assert.equal(workspace.activeId, 'two');
  workspace = closeTerminalTab(workspace, 'two', ps('fallback'));
  assert.equal(workspace.activeId, 'one');
  assert.equal(workspace.tabs.length, 1);
});

test('closing the final tab creates a safe fallback session', () => {
  const workspace = closeTerminalTab(
    normalizeTerminalWorkspace({ tabs: [wsl('only')], activeId: 'only' }, wsl('only')),
    'only',
    ps('fallback'),
  );
  assert.deepEqual(workspace, { tabs: [ps('fallback')], activeId: 'fallback', splitId: null });
});

test('split uses a second session and collapses safely', () => {
  let workspace = normalizeTerminalWorkspace({ tabs: [ps('one'), wsl('two')], activeId: 'one' }, ps('one'));
  workspace = toggleTerminalSplit(workspace);
  assert.equal(workspace.splitId, 'two');
  workspace = activateTerminalTab(workspace, 'two');
  assert.equal(workspace.activeId, 'two');
  assert.equal(workspace.splitId, null);
});

test('workspace enforces a bounded PTY count', () => {
  let workspace = normalizeTerminalWorkspace({ tabs: [ps('0')], activeId: '0' }, ps('0'));
  for (let index = 1; index < MAX_TERMINAL_TABS + 4; index += 1) {
    workspace = addTerminalTab(workspace, ps(String(index)));
  }
  assert.equal(workspace.tabs.length, MAX_TERMINAL_TABS);
});

test('changing a tab profile never carries a distribution into PowerShell', () => {
  const workspace = normalizeTerminalWorkspace({ tabs: [wsl('one')], activeId: 'one' }, wsl('one'));
  const updated = updateTerminalTab(workspace, 'one', { profile: 'powershell', distribution: 'must-not-survive' });
  assert.deepEqual(updated.tabs[0], { id: 'one', profile: 'powershell', distribution: '' });
});
