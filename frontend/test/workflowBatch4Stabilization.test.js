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

test('A-01 final Notes serializa autosave e save-before-navigation por nota', () => {
  const workspace = source('src/services/workflowWorkspace.ts');
  assert.match(workspace, /const noteSaveChains = new Map<string, Promise<void>>\(\)/);
  const saveStart = workspace.indexOf('export async function saveWorkspaceNote');
  const saveEnd = workspace.indexOf('\nfunction indexNotes', saveStart);
  const body = workspace.slice(saveStart, saveEnd);
  const previous = body.indexOf('const previous = noteSaveChains.get(key) || Promise.resolve();');
  const waitPrevious = body.indexOf('await previous.catch(() => undefined);');
  const write = body.indexOf('await fileSourceFacade.writeText', waitPrevious);
  const release = body.indexOf('release();', write);
  assert.ok(previous >= 0, 'save precisa encadear pela nota');
  assert.ok(waitPrevious > previous, 'save novo precisa aguardar o anterior');
  assert.ok(write > waitPrevious, 'escrita so pode comecar depois do save anterior');
  assert.ok(release > write, 'fila so pode liberar depois da escrita');
  assert.match(body, /if \(noteSaveChains\.get\(key\) === chain\) noteSaveChains\.delete\(key\)/);
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

test('A-05 final Terminal recupera layout mesmo se falha chegar depois de visible=true', () => {
  const terminal = source('src/apps/CloudOSTerminal/TerminalSession.tsx');
  assert.match(terminal, /layoutRecoveryRequestedRef/);
  assert.doesNotMatch(terminal, /becameVisible/);
  assert.doesNotMatch(terminal, /previousVisibleRef/);
  assert.match(terminal, /if \(!visible\) \{\s*layoutRecoveryRequestedRef\.current = false;/);
  assert.match(terminal, /status\.state === 'failed' && status\.label === 'Layout indisponível' && !layoutRecoveryRequestedRef\.current/);
  assert.match(terminal, /layoutRecoveryRequestedRef\.current = true;\s*setRestartGeneration\(value => value \+ 1\)/);
  assert.match(terminal, /fitSchedulerRef\.current = fitScheduler;\s*layoutRecoveryRequestedRef\.current = false;/);
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
