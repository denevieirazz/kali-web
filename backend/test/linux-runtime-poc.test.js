import test from 'node:test';
import assert from 'node:assert/strict';
import {
  buildXpraProbeCommand,
  buildXpraStartCommand,
  displayForPort,
  getAllowedLinuxPocApps,
  normalizePocApp,
} from '../src/linuxRuntime/xpraPoc.js';

test('POC1 allowlist remains intentionally small and blocks arbitrary commands', () => {
  assert.deepEqual(getAllowedLinuxPocApps().map(item => item.id), ['xclock', 'xeyes', 'xterm', 'gedit']);
  assert.equal(normalizePocApp('xclock'), 'xclock');
  assert.equal(normalizePocApp('Firefox'), null);
  assert.equal(normalizePocApp('sh -c calc.exe'), null);
});

test('POC1 launches Xpra seamless on localhost only and strips WSLg display variables', () => {
  const command = buildXpraStartCommand({ appCommand: 'xclock', port: 14500 });
  assert.match(command, /xpra seamless :100/);
  assert.match(command, /--start-child='xclock'/);
  assert.match(command, /--bind-tcp=127\.0\.0\.1:14500,auth=allow/);
  assert.match(command, /--html=on/);
  assert.match(command, /unset DISPLAY WAYLAND_DISPLAY PULSE_SERVER/);
  assert.doesNotMatch(command, /0\.0\.0\.0/);
  assert.equal(displayForPort(14549), 149);
});

test('POC1 preflight requires Xpra and the selected Linux app instead of installing them', () => {
  const probe = buildXpraProbeCommand('xeyes');
  assert.match(probe, /command -v xpra/);
  assert.match(probe, /XPRA_MISSING/);
  assert.match(probe, /command -v 'xeyes'/);
  assert.doesNotMatch(probe, /apt|dnf|pacman|zypper|snap|flatpak/);
});

test('POC1 rejects ports outside its loopback range', () => {
  assert.throws(() => buildXpraStartCommand({ appCommand: 'xclock', port: 80 }), /fora da faixa/);
  assert.throws(() => buildXpraStartCommand({ appCommand: 'xclock', port: 16000 }), /fora da faixa/);
});
