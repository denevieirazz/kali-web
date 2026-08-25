import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { workflowFileOpenMode } from '../src/core/workflowCore.js';

const read = path => fs.readFileSync(new URL(path, import.meta.url), 'utf8').replace(/\r\n?/g, '\n');
const audit = read('../../WORKFLOW_AUDIT.md');
const review = read('../../WORKFLOW_PRODUCTIVITY_REVIEW.md');
const files = read('../src/apps/CloudOSFiles/CloudOSFiles.tsx');
const facade = read('../src/apps/CloudOSFiles/fileSourceFacade.ts');
const preview = read('../src/apps/CloudOSFiles/FilePreviewPanel.tsx');
const workspace = read('../src/apps/WorkflowWorkspace/WorkflowWorkspace.tsx');
const workspaceService = read('../src/services/workflowWorkspace.ts');
const workspaceTransfer = read('../src/services/workflowWorkspaceTransfer.ts');
const recentFiles = read('../src/services/workflowRecentFiles.ts');
const workflowLaunch = read('../src/services/workflowLaunch.ts');
const clipboard = read('../src/services/workflowClipboard.ts');
const shell = read('../src/components/Workflow/WorkflowShell.tsx');
const filesBridge = read('../src/components/Workflow/FilesWorkflowBridge.tsx');
const terminalApp = read('../src/apps/CloudOSTerminal/CloudOSTerminal.tsx');
const terminal = read('../src/apps/CloudOSTerminal/TerminalSession.tsx');
const terminalTransport = read('../src/apps/CloudOSTerminal/terminalSessionTransport.js');
const terminalWorkspace = read('../src/core/terminalWorkspaceState.js');
const workflowCore = read('../src/core/workflowCore.js');
const app = read('../src/App.tsx');
const registry = read('../src/core/appRegistry.ts');

function has(text, expression, message) {
  assert.match(text, expression, message);
}

test('workspace hub exposes required daily-work surfaces without a database', () => {
  for (const label of ['Notes', 'Downloads', 'Evidence', 'Reports', 'Files', 'Terminal', 'Browser']) has(workspace, new RegExp(label));
  has(workspaceService, /workspace\.json/);
  has(workspaceService, /WORKSPACE_FOLDERS/);
  assert.doesNotMatch(`${workspaceService}\n${workspaceTransfer}`, /sqlite|indexedDB/i);
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

test('Batch 3.6 workspace can export import and move without pretending cross-provider atomicity', () => {
  for (const token of ['downloadWorkspaceExport', 'importWorkspaceFile', 'moveWorkspaceSafely']) has(workspaceTransfer, new RegExp(`export async function ${token}\\b`));
  has(workspace, /importWorkspaceFile/);
  has(workspace, /moveWorkspaceSafely/);
  has(workspace, /downloadWorkspaceZip\(active\)/);
  has(workspaceTransfer, /cloudos-workspace-export\/v1/);
  has(workspaceTransfer, /MAX_WORKSPACE_EXPORT_ENTRIES = 2000/);
  has(workspaceTransfer, /MAX_WORKSPACE_EXPORT_BYTES = 64 \* 1024 \* 1024/);
  has(workspaceTransfer, /MAX_WORKSPACE_EXPORT_FILE_BYTES = 16 \* 1024 \* 1024/);
  has(workspaceTransfer, /link simbólico e não será seguido/);
  has(workspaceTransfer, /await archiveWorkspace\(workspace\.id, true\)/);
  has(workspaceTransfer, /sourceDeleted: false/);
  has(workspace, /origem antiga arquivada, não apagada/);
});

test('file association remains OS-like but fail-closed for scripts executables and symlinks', () => {
  for (const extension of ['txt', 'md', 'json', 'log']) assert.equal(workflowFileOpenMode(`arquivo.${extension}`), 'notes', `${extension} deve abrir em Notes`);
  for (const extension of ['png', 'jpg', 'jpeg', 'webp', 'pdf']) assert.equal(workflowFileOpenMode(`arquivo.${extension}`), 'viewer', `${extension} deve abrir no Viewer`);
  for (const extension of ['exe', 'bat', 'cmd', 'ps1', 'sh', 'js']) assert.equal(workflowFileOpenMode(`arquivo.${extension}`), 'info', `${extension} deve permanecer fail-closed`);
  assert.equal(workflowFileOpenMode('pasta', 'directory'), 'directory');
  assert.equal(workflowFileOpenMode('seguro.txt', 'file', true), 'info', 'symlink nunca deve herdar associação de Notes');
  assert.equal(workflowFileOpenMode('seguro.txt', 'symlink'), 'info', 'kind symlink deve permanecer informativo');
});

test('Notes search stays lazy while the global text index remains bounded', () => {
  const searchStart = workspaceService.indexOf('export async function searchWorkspaceNotes');
  const searchEnd = workspaceService.indexOf('\nfunction sanitizeNoteFileName', searchStart);
  assert.ok(searchStart >= 0 && searchEnd > searchStart, 'searchWorkspaceNotes precisa existir como caminho lazy dedicado');
  const searchBody = workspaceService.slice(searchStart, searchEnd);
  has(searchBody, /for \(const meta of notes\)/);
  has(searchBody, /await fileSourceFacade\.readFile/);
  assert.doesNotMatch(searchBody, /Promise\.all/);
  has(workspace, /searchWorkspaceNotes\(active, notes, noteSearch/);
  has(workspaceService, /MAX_NOTE_INDEX_CONTENT_CHARS = 8192/);
  has(workspaceService, /searchText: note\.content\.slice\(0, MAX_NOTE_INDEX_CONTENT_CHARS\)/);
  has(shell, /searchText: note\.searchText/);
});

test('Batch 3.6 Notes search exposes highlights results and bounded jumps in real loaded content', () => {
  has(workspace, /MAX_VISIBLE_SEARCH_HITS = 100/);
  has(workspace, /function textHits/);
  has(workspace, /<mark key=/);
  has(workspace, /setSelectionRange\(hit\.start, hit\.end\)/);
  has(workspace, /resultado\(s\)/);
  has(workspace, /F3\/Shift\+F3 salta resultados/);
  assert.doesNotMatch(workspace, /embedding|vector|llm|openai/i);
});

test('Batch 3.6 external text editor has explicit save save-as close and dirty protection', () => {
  for (const label of ['Salvar', 'Salvar como', 'Fechar', 'Arquivo modificado']) has(workspace, new RegExp(label, 'i'));
  has(workspace, /const externalDirty = Boolean/);
  has(workspace, /beforeunload/);
  has(workspace, /Salvar Como aceita somente txt, md, json ou log/);
  has(workspace, /Salvar Como não sobrescreve arquivos/);
  has(workspace, /if \(externalFile\) return;\n\s*const dirty = Boolean\(active/);
  has(workspace, /Ctrl\+Shift\+S salva como/);
});

test('Files keeps cross-provider transfer assisted confirmed and separate from normal paste', () => {
  for (const label of ['Abrir Terminal aqui', 'Enviar para Linux', 'Enviar para Windows', 'Copiar para Workspace']) has(files, new RegExp(label));
  has(files, /window\.confirm/);
  has(facade, /copyAcrossProviders/);
  has(facade, /O destino já contém/);
  has(facade, /entry\.kind !== 'file'/);
  has(facade, /clipboard\.source !== source/);
});

test('Files 3.6 records real opens and exposes one breadcrumb recent-documents and download context', () => {
  has(filesBridge, /recordRecentFile/);
  has(filesBridge, /listRecentFiles\('documents'\)/);
  has(filesBridge, /wf-files-breadcrumbs/);
  has(filesBridge, /Abrir recente/);
  has(filesBridge, /Documentos recentes/);
  has(filesBridge, /Destino atual de downloads/);
  has(filesBridge, /Browser nativo congelado ainda não suporta redirecionamento físico/);
  has(recentFiles, /MAX_RECENT_FILES = 30/);
  has(recentFiles, /workflowFileOpenMode/);
  assert.doesNotMatch(recentFiles, /sqlite|indexedDB|fetch\(/i);
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

test('Terminal tabs stay frontend-only and now support create rename close without protocol changes', () => {
  has(terminalWorkspace, /renameTerminalTab/);
  has(terminalWorkspace, /title: safeTitle/);
  has(terminalWorkspace, /slice\(0, 60\)/);
  has(terminalApp, /Renomear aba/);
  has(terminalApp, /\+ PowerShell/);
  has(terminalApp, /\+ WSL/);
  has(terminalApp, /Fechar aba/);
  has(terminalApp, /onDoubleClick=\{\(\) => renameTab\(tab\)\}/);
  assert.doesNotMatch(terminalTransport, /\btitle\b|renameTerminalTab|cwd\s*:|command\s*:/);
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
  has(workspace, /ww-permanent-destination/);
  assert.doesNotMatch(files, /nativeHostBridge\.openBrowser/);
});

test('WebOnly launcher explains Browser Full-only capability without offering impossible native app result', () => {
  has(shell, /nativeHostBridge\.available/);
  has(shell, /filter\(app => nativeHostBridge\.available \|\| app\.id !== 'browser'\)/);
  has(shell, /Browser disponível apenas no modo Full/);
  has(shell, /nenhuma janela externa será aberta/);
  assert.doesNotMatch(shell, /Abrir navegador padrão|openDefaultBrowser|window\.open/);
  assert.doesNotMatch(shell, /\.\.\/\.\.\/apps\/Browser/);
});

test('WebOnly Browser fails closed before the generic CloudOS Browser launch', () => {
  const start = workflowLaunch.indexOf('export function openExistingBrowser()');
  const end = workflowLaunch.indexOf('\nexport function openSettings()', start);
  assert.ok(start >= 0 && end > start, 'openExistingBrowser precisa existir como fluxo isolável');
  const body = workflowLaunch.slice(start, end);
  const guard = body.indexOf('if (!nativeHostBridge.available) {');
  const blocked = body.indexOf("throw new Error('Browser CloudOS disponível apenas no modo Full. Nenhuma janela externa foi aberta.');", guard);
  const guardedEnd = body.indexOf("\n  }\n  return launchWorkflowApp('browser');", blocked);
  const cloudosLaunch = body.indexOf("return launchWorkflowApp('browser');", guard);
  assert.ok(guard >= 0, 'WebOnly precisa de guard explícito de Native Host');
  assert.ok(blocked > guard, 'WebOnly precisa bloquear antes de sair do branch protegido');
  assert.ok(guardedEnd > blocked, 'o bloqueio WebOnly precisa permanecer dentro do branch protegido');
  assert.ok(cloudosLaunch > guardedEnd, 'Browser CloudOS só pode ser lançado depois do branch WebOnly retornar');
  has(body, /Browser CloudOS disponível apenas no modo Full/);
  has(body, /Nenhuma janela externa foi aberta/);
  assert.doesNotMatch(workflowLaunch, /openDefaultBrowser|window\.open|about:blank/);
});

test('Batch 3.6 productivity review remains factual and names the remaining system boundaries', () => {
  for (const heading of ['O que ainda obriga abrir Windows', 'O que ainda obriga abrir Linux diretamente', 'O que ainda parece três sistemas diferentes', 'O que já parece um sistema único']) has(review, new RegExp(heading));
  has(review, /Cliques removidos: \*\*não medido\*\*/);
  has(review, /Tempo economizado por fluxo: \*\*não medido\*\*/);
  has(review, /Validação física do Batch 3\.6: \*\*não executada/);
  has(review, /não promove, não publica release e não altera a linha Productization RC/);
});

test('Batch 3.5 audit keeps historical productivity metrics factual', () => {
  has(audit, /# WORKFLOW AUDIT — CloudOS Batch 3\.5/);
  has(audit, /## Cliques removidos\n\n\*\*Não medido\.\*\*/);
  has(audit, /## Passos removidos\n\n\*\*Não medido como número agregado\.\*\*/);
  has(audit, /Browser nativo continua congelado/);
});
