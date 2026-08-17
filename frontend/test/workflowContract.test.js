import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = path => fs.readFileSync(new URL(path, import.meta.url), 'utf8');
const files = read('../src/apps/CloudOSFiles/CloudOSFiles.tsx');
const facade = read('../src/apps/CloudOSFiles/fileSourceFacade.ts');
const workspace = read('../src/apps/WorkflowWorkspace/WorkflowWorkspace.tsx');
const workspaceService = read('../src/services/workflowWorkspace.ts');
const clipboard = read('../src/services/workflowClipboard.ts');
const shell = read('../src/components/Workflow/WorkflowShell.tsx');
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

test('Files keeps cross-provider transfer assisted, confirmed and separate from normal paste', () => {
  for (const label of ['Abrir Terminal aqui', 'Enviar para Linux', 'Enviar para Windows', 'Copiar para Workspace']) has(files, new RegExp(label));
  has(files, /window\.confirm/);
  has(facade, /copyAcrossProviders/);
  has(facade, /O destino já contém/);
  has(facade, /entry\.kind !== 'file'/);
  has(facade, /clipboard\.source !== source/);
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

test('window workflow exposes half-screen, maximize and restore equivalents', () => {
  has(shell, /snapWorkflowWindow\(targetWindow, 'left'\)/);
  has(shell, /snapWorkflowWindow\(targetWindow, 'right'\)/);
  has(shell, /maximizeWorkflowWindow/);
  has(shell, /restoreWorkflowWindow/);
});

test('download destination is explicit but native Browser integration remains intentionally unwired', () => {
  for (const label of ['Workspace atual', 'OPFS', 'Windows grant', 'Linux Home']) has(workspace, new RegExp(label));
  has(workspace, /Browser nativo está congelado/);
  assert.doesNotMatch(files, /nativeHostBridge\.openBrowser/);
});
