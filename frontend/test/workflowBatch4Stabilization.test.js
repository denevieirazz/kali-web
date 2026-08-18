import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('C-01 Notes nao reemite workflow-changed quando o indice nao mudou', () => {
  const workspace = source('src/services/workflowWorkspace.ts');
  const guard = workspace.indexOf('if (JSON.stringify(next) === JSON.stringify(existing)) return;');
  const write = workspace.indexOf('writeJson(NOTES_INDEX_KEY, next);', guard);
  const emit = workspace.indexOf('emitChanged();', write);
  assert.ok(guard >= 0, 'indice de Notes precisa de guarda de igualdade');
  assert.ok(write > guard, 'a escrita precisa ocorrer depois da guarda');
  assert.ok(emit > write, 'o evento precisa ocorrer somente depois de uma escrita real');
});

test('A-01 Notes persiste rascunho antes de trocar nota workspace ou resultado', () => {
  const workspace = source('src/apps/WorkflowWorkspace/WorkflowWorkspace.tsx');
  assert.match(workspace, /const persistDirtyWorkspaceNote = useCallback\(async \(\) =>/);
  assert.match(workspace, /if \(!\(await persistDirtyWorkspaceNote\(\)\)\) return;\s*setActiveId\(workspace\.id\)/);
  assert.match(workspace, /const selectNote = useCallback\(async/);
  assert.match(workspace, /const jumpToHit = useCallback\(async/);
  assert.match(workspace, /beforeunload/);
  assert.match(workspace, /workspaceDraftRef/);
});

test('A-02 atalhos do Files so respondem na janela ativa', () => {
  const files = source('src/apps/CloudOSFiles/CloudOSFiles.tsx');
  assert.match(files, /if \(windowId && useWindowManager\.getState\(\)\.activeWindowId !== windowId\) return;/);
  assert.match(files, /window\.addEventListener\('keydown', onKeyDown\)/);
});

test('A-03 export ZIP usa o Workspace exibido e nao interceptacao global por texto', () => {
  const workspace = source('src/apps/WorkflowWorkspace/WorkflowWorkspace.tsx');
  const shell = source('src/components/Workflow/WorkflowBatch4Shell.tsx');
  assert.match(workspace, /downloadWorkspaceZip\(active\)/);
  assert.doesNotMatch(workspace, /downloadWorkspaceExport\(active\)/);
  assert.doesNotMatch(shell, /textContent\?\.trim\(\) !== 'Exportar'/);
  assert.doesNotMatch(shell, /stopImmediatePropagation\(\)/);
});

test('A-04 Evidence rapida aceita identidade explicita do Workspace exibido', () => {
  const evidence = source('src/services/workflowQuickEvidence.ts');
  const shell = source('src/components/Workflow/WorkflowBatch4Shell.tsx');
  const workspace = source('src/apps/WorkflowWorkspace/WorkflowWorkspace.tsx');
  assert.match(evidence, /captureClipboardToActiveEvidence\(workspaceId\?: string\)/);
  assert.match(evidence, /workspaceId \? getWorkspace\(workspaceId\) : getActiveWorkspace\(\)/);
  assert.match(workspace, /data-workspace-id=\{active\?\.id \|\| ''\}/);
  assert.match(shell, /\.window\.active \.workflow-workspace\[data-workspace-id\]/);
  assert.match(shell, /captureEvidence\(workspaceId\)/);
});

test('A-05 aba de Terminal invisivel reinicializa quando volta a ficar visivel', () => {
  const terminal = source('src/apps/CloudOSTerminal/TerminalSession.tsx');
  assert.match(terminal, /previousVisibleRef/);
  assert.match(terminal, /const becameVisible = visible && !previousVisibleRef\.current/);
  assert.match(terminal, /status\.label === 'Layout indisponível'/);
  assert.match(terminal, /setRestartGeneration\(value => value \+ 1\)/);
});

test('A-06 lixeira Windows confirma metadata antes de remover a origem', () => {
  const windows = source('src/apps/CloudOSFiles/windowsDirectorySource.ts');
  const start = windows.indexOf('async trash(path: string[], entry: WindowsFileEntry)');
  const end = windows.indexOf('async listTrash()', start);
  const body = windows.slice(start, end);
  const metadataWrite = body.indexOf('await writeTrashMeta(meta);');
  const sourceDelete = body.indexOf('await sourceDir.removeEntry(entry.name');
  assert.ok(metadataWrite >= 0, 'trash precisa persistir metadata');
  assert.ok(sourceDelete > metadataWrite, 'origem so pode ser removida depois da metadata');
  assert.match(windows, /Metadados da lixeira Windows estão corrompidos; nenhuma operação destrutiva foi executada/);
});
