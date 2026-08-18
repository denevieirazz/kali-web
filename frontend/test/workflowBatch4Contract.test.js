import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  createTerminalTab,
  normalizeTerminalWorkspace,
  serializableTerminalWorkspace,
} from '../src/core/terminalWorkspaceState.js';
import { workflowFileOpenMode } from '../src/core/workflowCore.js';

const source = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('Files abre somente extensoes textuais permitidas no Notes', () => {
  for (const name of ['a.txt', 'README.md', 'config.json', 'run.log']) assert.equal(workflowFileOpenMode(name), 'notes');
  for (const name of ['run.sh', 'deploy.ps1', 'tool.exe', 'script.js']) assert.equal(workflowFileOpenMode(name), 'info');
  const bridge = source('src/components/Workflow/FilesWorkflowBridge.tsx');
  assert.match(bridge, /addEventListener\('dblclick', onDoubleClick, true\)/);
  assert.match(bridge, /openTextFileInNotes/);
});

test('Terminal persiste a ultima aba ativa e Batch 4 traduz atalhos canonicos sem protocolo novo', () => {
  const one = createTerminalTab('powershell', '', 'one');
  const two = createTerminalTab('wsl', 'kali-linux', 'two');
  const workspace = normalizeTerminalWorkspace({ tabs: [one, two], activeId: 'two', splitId: null }, one);
  assert.equal(serializableTerminalWorkspace(workspace).activeId, 'two');

  const shell = source('src/components/Workflow/WorkflowBatch4Shell.tsx');
  assert.match(shell, /dispatchTerminalShortcut\('t', true\)/);
  assert.match(shell, /dispatchTerminalShortcut\('w', true\)/);
  assert.match(shell, /event\.key === 'Tab'/);
  assert.match(shell, /PageUp/);
  assert.match(shell, /PageDown/);
  assert.doesNotMatch(shell, /\/ws\/terminal|WSL_CORE_MODE|terminalSessionTransport/);
});

test('atalhos de produtividade e Evidence rapida permanecem no workflow shell', () => {
  const shell = source('src/components/Workflow/WorkflowBatch4Shell.tsx');
  assert.match(shell, /event\.ctrlKey && event\.shiftKey && key === 'e'/);
  assert.match(shell, /event\.ctrlKey && event\.altKey && key === 'w'/);
  assert.match(shell, /key === '1'/);
  assert.match(shell, /key === '2'/);
  assert.match(shell, /key === '3'/);
  assert.match(shell, /captureClipboardToActiveEvidence/);
});

test('Workspace ZIP coleta somente Notes Evidence e Metadata no export Batch 4', () => {
  const zip = source('src/services/workflowWorkspaceZip.ts');
  assert.match(zip, /Metadata\/workspace\.json/);
  assert.match(zip, /Metadata\/export\.json/);
  assert.match(zip, /collectFolder\(current, \['Notes'\]/);
  assert.match(zip, /collectFolder\(current, \['Evidence'\]/);
  assert.match(zip, /application\/zip/);
  assert.match(zip, /\.cloudos-workspace\.zip/);
  assert.doesNotMatch(zip, /buildWorkspaceExport|fetch\(|apiClient|upload\(/);
});

test('Favoritos e Fixados usam armazenamento local limitado', () => {
  const marks = source('src/services/workflowFileMarks.ts');
  assert.match(marks, /cloudos\.workflow\.file-marks\.v1/);
  assert.match(marks, /MAX_FILE_MARKS = 100/);
  assert.match(marks, /favorite/);
  assert.match(marks, /pinned/);
});
