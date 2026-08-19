import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  buildXpraProbeCommand,
  buildXpraStartCommand,
  displayForPort,
  getAllowedLinuxPocApps,
  normalizePocApp,
} from '../src/linuxRuntime/xpraPoc.js';
import { __test as proxyTest } from '../src/linuxRuntime/xpraProxy.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '../..');

test('POC1 allowlist remains intentionally small and blocks arbitrary commands', () => {
  assert.deepEqual(getAllowedLinuxPocApps().map(item => item.id), ['xclock', 'xeyes', 'xterm', 'gedit']);
  assert.equal(normalizePocApp('xclock'), 'xclock');
  assert.equal(normalizePocApp('Firefox'), null);
  assert.equal(normalizePocApp('sh -c calc.exe'), null);
});

test('POC1 launches Xpra seamless on localhost only and strips WSLg display variables', () => {
  const command = buildXpraStartCommand({ appCommand: 'xclock', port: 14500, sessionId: 'test-session' });
  assert.match(command, /xpra seamless :100/);
  assert.match(command, /--session-name='cloudos-poc1-test-session'/);
  assert.match(command, /--start-child='xclock'/);
  assert.match(command, /--bind-tcp=127\.0\.0\.1:14500,auth=allow/);
  assert.match(command, /--html=on/);
  assert.match(command, /--start-new-commands=no/);
  assert.match(command, /unset DISPLAY WAYLAND_DISPLAY PULSE_SERVER/);
  assert.doesNotMatch(command, /0\.0\.0\.0/);
  assert.doesNotMatch(command, /wslg|weston|rail/i);
  assert.equal(displayForPort(14549), 149);
});

test('POC1 preflight requires Xpra and selected app instead of installing them', () => {
  const probe = buildXpraProbeCommand('xeyes');
  assert.match(probe, /command -v xpra/);
  assert.match(probe, /XPRA_MISSING/);
  assert.match(probe, /command -v 'xeyes'/);
  assert.match(probe, /APP_MISSING:xeyes/);
  assert.doesNotMatch(probe, /apt|dnf|pacman|zypper|snap|flatpak/);
});

test('POC1 rejects ports outside its loopback range', () => {
  assert.throws(() => buildXpraStartCommand({ appCommand: 'xclock', port: 80 }), /fora da faixa/);
  assert.throws(() => buildXpraStartCommand({ appCommand: 'xclock', port: 16000 }), /fora da faixa/);
});

test('POC1 CloudOS proxy strips capability prefix before forwarding to Xpra', () => {
  const parsed = proxyTest.parseProxyRequest('/__cloudos/linux-runtime/poc1/xpra-1/secret/js/Client.js?x=1');
  assert.deepEqual(parsed, {
    id: 'xpra-1',
    token: 'secret',
    targetPath: '/js/Client.js?x=1',
  });
  assert.equal(proxyTest.parseProxyRequest('/api/linux-runtime/poc1'), null);
});

test('POC1 dev server forwards capability HTTP and WebSocket traffic to the backend', () => {
  const viteConfig = fs.readFileSync(path.join(repoRoot, 'frontend', 'vite.config.ts'), 'utf8');
  assert.match(viteConfig, /['"]\/__cloudos['"]\s*:\s*\{[^}]*target:\s*backendHttpTarget[^}]*ws:\s*true[^}]*changeOrigin:\s*false/s);
  assert.match(viteConfig, /const backendHttpTarget = `http:\/\/127\.0\.0\.1:\$\{backendPort\}`/);
});

test('POC1 proxy rewrites frame policy for contained same-origin embedding', () => {
  assert.equal(proxyTest.rewriteCsp("default-src 'self'; frame-ancestors 'none'"), "default-src 'self'; frame-ancestors 'self'");
  assert.equal(proxyTest.rewriteCsp(null), "frame-ancestors 'self'");
});

test('POC1 proxy rewrites Xpra absolute redirects back into capability path', () => {
  const session = { id: 'xpra-1', proxyToken: 'abc', port: 14500 };
  assert.equal(
    proxyTest.rewriteLocation('http://127.0.0.1:14500/connect.html?x=1', session),
    '/__cloudos/linux-runtime/poc1/xpra-1/abc/connect.html?x=1',
  );
  assert.equal(
    proxyTest.rewriteLocation('/connect.html', session),
    '/__cloudos/linux-runtime/poc1/xpra-1/abc/connect.html',
  );
});
