import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const routes = fs.readFileSync(new URL('../src/files/routes.js', import.meta.url), 'utf8');
const rpc = fs.readFileSync(new URL('../src/files/wslFilesRpcSession.js', import.meta.url), 'utf8');
const service = fs.readFileSync(new URL('../src/files/wslFilesService.js', import.meta.url), 'utf8');
const transactions = fs.readFileSync(new URL('../src/files/wslFileTransactions.js', import.meta.url), 'utf8');
const operations = fs.readFileSync(new URL('../src/operations/operationManager.js', import.meta.url), 'utf8');
const app = fs.readFileSync(new URL('../src/app.js', import.meta.url), 'utf8');
const coreServer = fs.readFileSync(new URL('../../core/wsl/cloudos-core/internal/server/server.go', import.meta.url), 'utf8');
const coreFiles = fs.readFileSync(new URL('../../core/wsl/cloudos-core/internal/files/files.go', import.meta.url), 'utf8');

test('real WSL Files routes require auth plus explicit user-ui actor', () => {
  assert.match(routes, /filesRouter\.use\(authenticateToken\)/);
  assert.match(routes, /x-cloudos-file-actor/);
  assert.match(routes, /!== 'user-ui'/);
  assert.match(routes, /FILES_EXPLICIT_USER_INTENT_REQUIRED/);
  assert.match(app, /app\.use\('\/api\/files\/wsl', filesRouter\)/);
});

test('all WSL Files mutations require explicit confirmation', () => {
  for (const route of ['write', 'mkdir', 'move', 'copy', 'trash', 'trash/restore', 'trash/delete']) {
    const escaped = route.replaceAll('/', '\\/');
    assert.match(routes, new RegExp(`post\\('\\/${escaped}', requireConfirmed`));
  }
  assert.match(routes, /confirmed !== true/);
});

test('HTTP path contract accepts relative segments only and rejects traversal syntax', () => {
  assert.match(routes, /Array\.isArray\(value\)/);
  assert.match(routes, /segment === '\.\.'/);
  assert.match(routes, /segment\.includes\('\/'\)/);
  assert.match(routes, /segment\.includes\('\\\\'\)/);
  assert.match(routes, /Buffer\.byteLength\(segment, 'utf8'\) > MAX_NAME/);
  assert.doesNotMatch(routes, /path\.resolve|path\.join|realpath/);
});

test('WSL Files client reuses approved v2 frame codec and never invokes a shell', () => {
  assert.match(rpc, /SecureFrameCodec/);
  assert.match(rpc, /deriveChannelMaterial/);
  assert.match(rpc, /connectLoopbackWithReadiness/);
  assert.match(rpc, /parseBootstrapRecord/);
  assert.match(rpc, /shell: false/);
  assert.doesNotMatch(rpc, /createCipheriv|createDecipheriv/);
  assert.match(service, /CLOUDOS_WSL_CORE_FILES === '1'/);
  assert.doesNotMatch(service, /FALLBACK/);
});

test('Linux core exposes descriptor-relative no-follow file operations', () => {
  for (const token of ['syscall.Openat', 'syscall.Renameat', 'syscall.Mkdirat', 'syscall.O_NOFOLLOW']) assert.match(coreFiles, new RegExp(token.replace('.', '\\.')));
  assert.match(coreFiles, /part == "\.\."/);
  assert.match(coreFiles, /FILES_SYMLINK_DENIED/);
  assert.match(coreFiles, /Fchmod/);
  assert.match(coreFiles, /\.cloudos-trash/);
  assert.match(coreServer, /handleFilesRequest/);
});

test('managed file copy has cancel, progress and destination rollback', () => {
  assert.match(operations, /activeManaged/);
  assert.match(operations, /new AbortController\(\)/);
  assert.match(operations, /status: 'cancelling'/);
  assert.match(operations, /managed\.abort\(\)/);
  assert.match(transactions, /copiedBytes/);
  assert.match(transactions, /progress:/);
  assert.match(transactions, /rollbackDestination/);
  assert.match(transactions, /fs\.trash/);
  assert.match(transactions, /fs\.trash\.delete/);
  assert.match(transactions, /CHUNK_SIZE = 256 \* 1024/);
});
