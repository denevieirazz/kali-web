import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const app = fs.readFileSync(new URL('../src/apps/CloudOSFiles/CloudOSFiles.tsx', import.meta.url), 'utf8');
const facade = fs.readFileSync(new URL('../src/apps/CloudOSFiles/fileSourceFacade.ts', import.meta.url), 'utf8');
const policy = fs.readFileSync(new URL('../src/apps/CloudOSFiles/fileSourcePolicy.ts', import.meta.url), 'utf8');
const windows = fs.readFileSync(new URL('../src/apps/CloudOSFiles/windowsDirectorySource.ts', import.meta.url), 'utf8');
const wsl = fs.readFileSync(new URL('../src/apps/CloudOSFiles/wslFileSource.ts', import.meta.url), 'utf8');
const preview = fs.readFileSync(new URL('../src/apps/CloudOSFiles/FilePreviewPanel.tsx', import.meta.url), 'utf8');

test('existing CloudOS Files owns all three sources instead of adding a parallel app', () => {
  assert.match(app, /useState<FileSourceKind>\('opfs'\)/);
  assert.match(app, /value="opfs"/);
  assert.match(app, /value="windows"/);
  assert.match(app, /value="wsl"/);
  assert.match(app, /data-files-source=\{source\}/);
  assert.match(facade, /'opfs'|'windows'|'wsl'/);
});

test('Windows real access is only created by explicit directory picker and handle stays in memory', () => {
  assert.match(windows, /showDirectoryPicker/);
  assert.match(windows, /mode: 'readwrite'/);
  assert.match(windows, /let mountedRoot: FileSystemDirectoryHandle \| null = null/);
  assert.doesNotMatch(windows, /localStorage|sessionStorage|indexedDB/);
  assert.match(app, /Selecionar pasta do Windows/);
});

test('frontend file paths are normalized as segments and reject traversal', () => {
  assert.match(policy, /value === '\.\.'/);
  assert.match(policy, /value\.includes\('\/'\)/);
  assert.match(policy, /value\.includes\('\\\\'\)/);
  assert.match(policy, /TextEncoder/);
  assert.doesNotMatch(policy, /path\.resolve|path\.join/);
});

test('WSL requests always carry explicit user-ui actor', () => {
  assert.match(wsl, /X-CloudOS-File-Actor/);
  assert.match(wsl, /USER_FILE_ACTOR/);
  assert.match(policy, /export const USER_FILE_ACTOR: FileActor = 'user-ui'/);
  assert.match(app, /data-files-actor="user-ui"/);
});

test('symlinks are visible but not opened copied renamed or trashed', () => {
  assert.match(app, /Link não seguido/);
  assert.match(preview, /Link simbólico não é seguido/);
  assert.match(facade, /Link simbólico não pode ser copiado/);
  assert.match(facade, /Link simbólico não entra na lixeira transacional/);
});

test('real copy exposes cancellation and progress, and closing Files cancels active work', () => {
  assert.match(app, /AbortController/);
  assert.match(app, /cancelActiveOperation/);
  assert.match(app, /cancelWslOperation/);
  assert.match(app, /operationController\.current\?\.abort\(\)/);
  assert.match(app, /progress max=\{100\}/);
  assert.match(windows, /signal\.aborted/);
  assert.match(windows, /removeEntry\(destinationName/);
});

test('preview remains bounded and PDF stays sandboxed', () => {
  assert.match(app, /classifyPreview/);
  assert.match(preview, /HASH_LIMIT = 25 \* 1024 \* 1024/);
  assert.match(preview, /sandbox=""/);
  assert.match(preview, /crypto\.subtle\.digest\('SHA-256'/);
});

test('cross-provider transfer fails closed until a dedicated transactional gate exists', () => {
  assert.match(facade, /clipboard\.source !== source/);
  assert.match(facade, /Transferência entre origens será habilitada somente após o gate transacional entre providers/);
});
