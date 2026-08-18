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

test('SCALE-01 catalogo aceita Workspace 101 sem truncar os existentes', () => {
  const workspace = source('src/services/workflowWorkspace.ts');
  assert.match(workspace, /export const MAX_WORKSPACES = 1000;/);
  assert.doesNotMatch(workspace, /if \(output\.length >= MAX_WORKSPACES\) break;/);
  assert.doesNotMatch(workspace, /writeJson\(WORKSPACES_KEY, items\.slice\(0, MAX_WORKSPACES\)\)/);
  assert.doesNotMatch(workspace, /\[workspace, \.\.\.persistedWorkspaces\(\)[^\n]*\.slice\(0, MAX_WORKSPACES\)/);
});

test('SCALE-02 limite de Workspace rejeita antes de criar e nunca descarta catalogo', () => {
  const workspace = source('src/services/workflowWorkspace.ts');
  const createStart = workspace.indexOf('export async function createWorkspace');
  const runtime = workspace.indexOf('const runtime = await fileSourceFacade.runtime(input.provider);', createStart);
  const guard = workspace.indexOf('assertWorkspaceCapacityForCreate();', createStart);
  assert.ok(guard > createStart && guard < runtime, 'capacidade precisa falhar antes de tocar provider');
  assert.match(workspace, /if \(count >= MAX_WORKSPACES\)/);
  assert.match(workspace, /Nenhum Workspace existente foi descartado/);
  assert.match(workspace, /function saveWorkspaceList\(items: WorkspaceRecord\[\]\) \{\s*\/\/ Never truncate[\s\S]*?writeJson\(WORKSPACES_KEY, items\);/);
});

test('SCALE-03 listWorkspaceNotes retorna somente metadata sem ler conteudo', () => {
  const workspace = source('src/services/workflowWorkspace.ts');
  assert.match(workspace, /export type WorkflowNoteMeta = \{/);
  assert.match(workspace, /export type WorkflowNoteContent = WorkflowNoteMeta & \{\s*content: string;/);
  const start = workspace.indexOf('export async function listWorkspaceNotes');
  const end = workspace.indexOf('\nexport async function loadWorkspaceNote', start);
  const body = workspace.slice(start, end);
  assert.match(body, /Promise<WorkflowNoteMeta\[\]>/);
  assert.match(body, /\.map\(entry => noteMeta\(workspace, entry\)\)/);
  assert.doesNotMatch(body, /readFile\(/);
  assert.doesNotMatch(body, /\.text\(\)/);
});

test('SCALE-04 somente nota ativa e carregada sob demanda', () => {
  const service = source('src/services/workflowWorkspace.ts');
  const ui = source('src/apps/WorkflowWorkspace/WorkflowWorkspace.tsx');
  const loadStart = service.indexOf('export async function loadWorkspaceNote');
  const loadEnd = service.indexOf('\nfunction collectTextHits', loadStart);
  const loadBody = service.slice(loadStart, loadEnd);
  assert.match(loadBody, /fileSourceFacade\.readFile/);
  assert.match(loadBody, /content: await file\.text\(\)/);
  assert.match(ui, /useState<WorkflowNoteMeta\[\]>\(\[\]\)/);
  assert.match(ui, /const loaded = chosen \? await loadWorkspaceNote\(workspace, chosen\) : null;/);
  assert.match(ui, /const loaded = await loadWorkspaceNote\(active, note\);/);
  assert.doesNotMatch(ui, /note\.content/);
});

test('SCALE-05 busca percorre Notes incrementalmente sem materializar todos documentos', () => {
  const service = source('src/services/workflowWorkspace.ts');
  const ui = source('src/apps/WorkflowWorkspace/WorkflowWorkspace.tsx');
  const start = service.indexOf('export async function searchWorkspaceNotes');
  const end = service.indexOf('\nfunction sanitizeNoteFileName', start);
  const body = service.slice(start, end);
  assert.match(body, /for \(const meta of notes\)/);
  assert.match(body, /cancelled\(\)/);
  assert.match(body, /activeDocument/);
  assert.match(body, /await fileSourceFacade\.readFile/);
  assert.doesNotMatch(body, /Promise\.all/);
  assert.match(ui, /searchWorkspaceNotes\(active, notes, noteSearch/);
  assert.match(ui, /activeDocument: activeNoteFile \? \{ fileName: activeNoteFile, content: noteContent \} : null/);
  assert.match(ui, /setNoteSearchBusy\(true\)/);
});

test('SCALE-06 metadata lazy preserva indice global e regressao de save', () => {
  const workspace = source('src/services/workflowWorkspace.ts');
  const start = workspace.indexOf('function indexNoteMetadata');
  const end = workspace.indexOf('\nexport async function listWorkspaceNotes', start);
  const metadataBody = workspace.slice(start, end);
  assert.match(workspace, /function indexNoteMetadata\(notes: WorkflowNoteMeta\[\]\)/);
  assert.match(workspace, /searchText: current\?\.searchText \|\| ''/);
  assert.match(workspace, /indexNoteMetadata\(notes\);\s*return notes;/);
  assert.match(workspace, /indexNotes\(\[document\]\);/);
  assert.match(workspace, /indexNotes\(\[indexed\]\);/);
  assert.match(workspace, /const noteSaveChains = new Map<string, Promise<void>>\(\)/);
  assert.match(metadataBody, /note\.modified > 0 \? new Date\(note\.modified\)\.toISOString\(\) : \(current\?\.updatedAt \|\| new Date\(0\)\.toISOString\(\)\)/);
  assert.doesNotMatch(metadataBody, /note\.modified \|\| Date\.now\(\)/);
});

test('TERMINAL-RESTORE preserva tabs persistidas quando o probe WSL falha', () => {
  const terminal = source('src/apps/CloudOSTerminal/CloudOSTerminal.tsx');
  assert.match(terminal, /const restored = readPersistedTerminalWorkspace\(!launchParams\.explicit\);/);
  const catchStart = terminal.indexOf('.catch(error => {');
  const catchEnd = terminal.indexOf('\n      });', catchStart);
  const catchBody = terminal.slice(catchStart, catchEnd);
  assert.match(catchBody, /setWorkspace\(normalizeTerminalWorkspace\(restored, fallbackTab\)\)/);
  assert.doesNotMatch(catchBody, /normalizeTerminalWorkspace\(null, fallbackTab\)/);
});
