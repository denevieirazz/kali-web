import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildXpraProbeCommand, buildXpraStartCommand, displayForPort, getAllowedLinuxPocApps, normalizePocApp } from '../src/linuxRuntime/xpraPoc.js';
import { scopedOwnerId } from '../src/linuxRuntime/routes.js';
import { __test as proxyTest } from '../src/linuxRuntime/xpraProxy.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '../..');

test('POC1 allowlist remains intentionally small and blocks arbitrary commands', () => { assert.ok(getAllowedLinuxPocApps().some(item => item.id === 'xclock')); assert.equal(normalizePocApp('xclock'), 'xclock'); assert.equal(normalizePocApp('invalid-app-xyz'), null); assert.equal(normalizePocApp('sh -c calc.exe'), null); });
test('B-01: Xpra loopback socket requires a per-session capability password', () => { const command = buildXpraStartCommand({ appCommand: 'xclock', port: 14500, sessionId: 'test-session', password: '0123456789abcdef0123456789abcdef' }); assert.match(command, /export XPRA_PASSWORD=/); assert.match(command, /--bind-tcp=0\.0\.0\.0:14500,auth=env/); assert.doesNotMatch(command, /auth=allow/); assert.match(command, /--start-new-commands=no/); assert.equal(displayForPort(14549), 149); });
test('B-02: owner namespace changes with authenticated principal', () => { const a = scopedOwnerId('user-a', 'window-1'); const b = scopedOwnerId('user-b', 'window-1'); assert.notEqual(a, b); assert.match(a, /^[a-f0-9]{24}:window-1$/); assert.equal(scopedOwnerId('user-a', 'window-1'), a); });
test('B-03: proxy enforces opaque-origin CSP sandbox and strips cookies', () => { const csp = proxyTest.rewriteCsp("default-src 'self'; frame-ancestors 'none'; sandbox allow-same-origin allow-scripts"); assert.match(csp, /sandbox allow-scripts allow-forms allow-pointer-lock/); assert.doesNotMatch(csp, /allow-same-origin/); assert.match(csp, /frame-ancestors 'self'/); const headers = proxyTest.buildResponseHeaders({ 'set-cookie': 'secret=x', 'content-type': 'text/html' }, { id: 'x', proxyToken: 't', port: 14500 }); assert.equal(headers['set-cookie'], undefined); assert.equal(headers['Referrer-Policy'], 'no-referrer'); });
test('B-04: runtime source fails closed when WSLInterop remains enabled', () => { const source = fs.readFileSync(path.join(repoRoot, 'backend', 'src', 'linuxRuntime', 'xpraPoc.js'), 'utf8'); assert.match(source, /\/proc\/sys\/fs\/binfmt_misc\/WSLInterop/); assert.match(source, /WSL_INTEROP_ENABLED/); assert.match(source, /if \(!interop\.ok\) return \{ ready: false/); });
test('POC1 preflight requires Xpra and selected app instead of installing them', () => { const probe = buildXpraProbeCommand('xeyes'); assert.match(probe, /command -v xpra/); assert.match(probe, /APP_MISSING:xeyes/); assert.doesNotMatch(probe, /apt|dnf|pacman|zypper|snap|flatpak/); });
test('POC1 rejects ports outside its loopback range', () => { assert.throws(() => buildXpraStartCommand({ appCommand: 'xclock', port: 80, password: '0123456789abcdef' }), /fora da faixa/); assert.throws(() => buildXpraStartCommand({ appCommand: 'xclock', port: 16000, password: '0123456789abcdef' }), /fora da faixa/); });
test('POC1 CloudOS proxy strips capability prefix before forwarding to Xpra', () => { assert.deepEqual(proxyTest.parseProxyRequest('/__cloudos/linux-runtime/poc1/xpra-1/secret/js/Client.js?x=1'), { id: 'xpra-1', token: 'secret', targetPath: '/js/Client.js?x=1' }); });
test('POC1 dev server still forwards capability HTTP and WebSocket traffic to backend', () => { const viteConfig = fs.readFileSync(path.join(repoRoot, 'frontend', 'vite.config.ts'), 'utf8'); assert.match(viteConfig, /['"]\/__cloudos['"]\s*:\s*\{[^}]*target:\s*backendHttpTarget[^}]*ws:\s*true/s); });
test('CloudOS minimize preserves mounted app lifecycle', () => { const source = fs.readFileSync(path.join(repoRoot, 'frontend', 'src', 'components', 'Window', 'Window.tsx'), 'utf8'); assert.doesNotMatch(source, /if\s*\(\s*!win\s*\|\|\s*win\.isMinimized\s*\)\s*return\s+null/); assert.match(source, /display:\s*win\.isMinimized\s*\?\s*['"]none['"]\s*:\s*undefined/); });
test('POC1 proxy rewrites Xpra redirects back into capability path', () => { const session = { id: 'xpra-1', proxyToken: 'abc', port: 14500 }; assert.equal(proxyTest.rewriteLocation('/connect.html', session), '/__cloudos/linux-runtime/poc1/xpra-1/abc/connect.html'); });
