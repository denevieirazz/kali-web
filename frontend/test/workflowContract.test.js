import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = path => fs.readFileSync(new URL(path, import.meta.url), 'utf8');
const files = read('../src/apps/CloudOSFiles/CloudOSFiles.tsx');
const facade = read('../src/apps/CloudOSFiles/fileSourceFacade.ts');
const preview = read('../src/apps/CloudOSFiles/FilePreviewPanel.tsx');
const workspace = read('../src/apps/WorkflowWorkspace/WorkflowWorkspace.tsx');
const workspaceService = read('../src/services/workflowWorkspace.ts');
const clipboard = read('../src/services/workflowClipboard.ts');
const shell = read('../src/components/Workflow/WorkflowShell.tsx');
const filesBridge = read('../src/components/Workflow/FilesWorkflowBridge.tsx');
const terminal = read('../src/apps/CloudOSTerminal/TerminalSession.tsx');
const terminalTransport = read('../src/apps/CloudOSTerminal/terminalSessionTransport.js');
const app = read('../src/App.tsx');
const registry = read('../src/core/appRegistry.ts');

function has(text, expression, message) {
  assert.match(text, expression, message);
}

test('workspace hub exposes required daily-work surfaces without a database', () => {
  for (const label of ['Notes', 'Downloads', 'Evidence', 'Reports', 'Files', 'Terminal', 'Browser']) has(workspace, new RegExp(label));
  has(workspaceService, /workspace\.json/);
  has(workspaceService, /WORKSPACE_FOLDERS/);
  assert.doesNotMatch(workspaceService, /sqlite|database|indexedDB/i);
  has(registry, /'workflow-workspace'/);
  has(app, /<WorkflowShell \/>/);
});

test('workspace 3.5 supports rename archive duplicate metadata and search without moving the root on rename', () => {
  for (const token of ['updateWorkspaceMetadata', 'archiveWorkspace', 'duplicateWorkspace', 'searchWorkspaces']) has(workspaceService, new RegExp(token));
  has(workspaceService, /Rename is metadata-only/);
  has(workspace, /Renomear \/ editar/);
  has(workspace, />Duplicar</);
  has(workspace, /Arquivar/);
  has(workspace, /Pesquisar workspace/);
  for (const label of ['Última atividade', 'Status', 'Tags', 'Cliente', 'Tipo']) has(workspace, new RegExp(label, 'i'));
});

test('Notes searches loaded content and keeps a bounded global text index', () => {
  has(workspace, /note\.title}\\n\$\{note\.content/);
  has(workspaceService, /MAX_NOTE_INDEX_CONTENT_CHARS = 8192/);
  has(workspaceService, /searchText: note\.content\.slice\(0, MAX_NOTE_INDEX_CONTENT_CHARS\)/);
  has(shell, /searchText: note\.searchText/);
});

test('Files keeps cross-provider transfer assisted, confirmed and separate from normal paste', () => {
  for (const label of ['Abrir Terminal aqui', 'Enviar para Linux', 'Enviar para Windows', 'Copiar para Workspace']) has(files, new RegExp(label));
  has(files, /window\.confirm/);
  has(facade, /copyAcrossProviders/);
  has(facade, /O destino já contém/);
  has(facade, /entry\.kind !== 'file'/);
  has(facade, /clipboard\.source !== source/);
});

test('Files 3.5 routes safe double-click text to Notes and exposes contextual productivity actions', () => {
  has(filesBridge, /dblclick/);
  has(filesBridge, /workflowFileOpenMode/);
  has(filesBridge, /openTextFileInNotes/);
  for (const label of ['Abrir no Terminal', 'Abrir em Notes', 'Adicionar à Evidence']) has(filesBridge, new RegExp(label));
  has(filesBridge, /Lixeira CloudOS dentro da pasta Windows autorizada/);
  assert.doesNotMatch(filesBridge, /exec\(|spawn\(|shell:/);
});

test('image Viewer supports bounded zoom pan fit original-size and keyboard/wheel controls', () => {
  for (const token of ['stepViewerZoom', 'onWheel', 'onPointerDown', 'onPointerMove', 'Fit', '1:1']) has(preview, new RegExp(token));
  has(preview, /event\.key === '0'/);
  has(preview, /event\.key === '\+'/);
  has(preview, /event\.key === '-'/);
  has(preview, /sandbox=""/);
});

test('Terminal here does not weaken terminal handshake with cwd or command injection', () => {
  has(terminal, /buildWslCdCommand/);
  has(terminal, /transport\?\.input\(`\$\{command\}\\r`\)/);
  assert.doesNotMatch(terminalTransport, /cwd\s*:/);
  assert.doesNotMatch(terminalTransport, /command\s*:/);
});

test('clipboard and Notes productivity controls are reachable', () => {
  has(clipboard, /cloudos:clipboard-changed/);
  has(clipboard, /type === 'password'/);
  has(shell, /event\.code === 'Space'/);
  has(shell, /Ctrl\+Alt\+V/);
  has(workspace, /Ctrl\+N cria, Ctrl\+S salva e Ctrl\+F pesquisa/);
  has(workspace, /setTimeout\(\(\) => \{ void saveActiveNote\(\); \}, 650\)/);
});

test('window workflow exposes half-screen maximize restore and handles shortcuts before launcher focus navigation', () => {
  has(shell, /snapWorkflowWindow\(targetWindow, 'left'\)/);
  has(shell, /snapWorkflowWindow\(targetWindow, 'right'\)/);
  has(shell, /maximizeWorkflowWindow/);
  has(shell, /restoreWorkflowWindow/);
  const shortcutPosition = shell.indexOf('const snapLeft = event.altKey');
  const launcherPosition = shell.indexOf('if (launcherOpen) {', shortcutPosition);
  assert.ok(shortcutPosition >= 0 && launcherPosition > shortcutPosition, 'window shortcut gate must run before launcher navigation');
  has(shell, /inputRef\.current\?\.focus\(\)/);
});

test('download destination defaults to active workspace in UX but native Browser integration stays frozen', () => {
  for (const label of ['Workspace atual', 'OPFS', 'Windows grant', 'Linux Home']) has(workspace, new RegExp(label));
  has(workspace, /Por padrão, quando não existe preferência salva, o destino é o Workspace ativo/);
  has(workspace, /Browser nativo está congelado/);
  has(workspaceService, /active \? \{ kind: 'workspace', workspaceId: active\.id \} : \{ kind: 'opfs' \}/);
  assert.doesNotMatch(files, /nativeHostBridge\.openBrowser/);
});

test('WebOnly launcher explains Browser Full-only capability and offers default browser without editing native Browser', () => {
  has(shell, /nativeHostBridge\.available/);
  has(shell, /Browser disponível apenas em modo Full/);
  has(shell, /Abrir navegador padrão/);
  assert.doesNotMatch(shell, /\.\.\/\.\.\/apps\/Browser/);
});
