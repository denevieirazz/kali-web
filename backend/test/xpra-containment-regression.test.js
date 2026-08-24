import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildXpraProbeCommand, buildXpraStartCommand, resolvePocApp } from '../src/linuxRuntime/xpraPoc.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const runtimePath = path.resolve(here, '../src/linuxRuntime/xpraPoc.js');

test('Xpra runtime contains no native GUI fallback or detached direct app launch', () => {
  const source = fs.readFileSync(runtimePath, 'utf8');
  assert.doesNotMatch(source, /mode\s*:\s*['"]wslg['"]/i);
  assert.doesNotMatch(source, /return\s+\{[^}]*mode\s*:\s*['"]wslg['"]/is);
  assert.doesNotMatch(source, /nohup/i);
  assert.doesNotMatch(source, /mode\s*:\s*['"](?:native|rail)['"]/i);
  assert.doesNotMatch(source, /ALLOWED_APPS/);
  assert.doesNotMatch(source, /cleanBinary/);
  assert.match(source, /const pair = await reservePair\(readiness\.distribution\)/);
  assert.match(source, /mode: 'xpra'/);
});

test('an unavailable Xpra probe fails closed and has no secondary application probe', () => {
  const source = fs.readFileSync(runtimePath, 'utf8');
  const probeStart = source.indexOf('async function probe(');
  const probeEnd = source.indexOf('async function probeWslServer', probeStart);
  assert.ok(probeStart >= 0 && probeEnd > probeStart);
  const probeSource = source.slice(probeStart, probeEnd);
  assert.match(probeSource, /XPRA_NOT_INSTALLED/);
  assert.match(probeSource, /XPRA_PROBE_FAILED/);
  assert.doesNotMatch(probeSource, /command -v.*\|\| which/s);
  assert.equal((probeSource.match(/return\s+\{\s*ok:\s*true/g) || []).length, 1);
  assert.match(probeSource, /return\s+\{\s*ok:\s*true[^}]*mode:\s*'xpra'/s);
});

test('probe and start commands keep one private X11/Xpra route', () => {
  const probe = buildXpraProbeCommand(null, ['/usr/bin/l3afpad']);
  assert.match(probe, /command -v xpra/);
  assert.match(probe, /APP_MISSING:l3afpad/);

  const command = buildXpraStartCommand({
    appArgv: ['/usr/bin/l3afpad', 'literal;not-shell', '$(not-expanded)'],
    port: 14500,
    sessionId: 'contained-editor',
    password: '0123456789abcdef0123456789abcdef'
  });
  assert.match(command, /unset DISPLAY WAYLAND_DISPLAY WAYLAND_SOCKET PULSE_SERVER/);
  assert.match(command, /unshare --mount --pid --fork --kill-child=KILL --mount-proc=\/proc --propagation private/);
  assert.match(command, /mount -t tmpfs[^;]*\/tmp/);
  assert.match(command, /mount -t tmpfs[^;]*\/run\/user/);
  assert.match(command, /mount -t tmpfs[^;]*\/run\/xpra/);
  assert.doesNotMatch(command, /CloudOS\/Downloads|CloudOS\/Documents|gtk-3\.0\/bookmarks/);
  assert.match(command, /mount --bind[^;]*\/mnt\/wslg/);
  assert.match(command, /mount --bind[^;]*\/run\/WSL/);
  assert.match(command, /mount --bind[^;]*\/run\/systemd/);
  assert.match(command, /mount --bind[^;]*\/run\/dbus/);
  assert.match(command, /mount --bind[^;]*\/init/);
  assert.match(command, /remount,bind,ro,noexec,nosuid,nodev \/init/);
  assert.match(command, /setpriv --reuid=65534 --regid=65534 --clear-groups/);
  assert.match(command, /XDG_RUNTIME_DIR=\/run\/user\/65534/);
  assert.match(command, /HOME=[^;]*\/var\/lib\/cloudos\/contained-homes\//);
  assert.match(command, /env -u WAYLAND_DISPLAY [^;]*-u WSL_INTEROP/);
  assert.match(command, /WSL_INTEROP_BYPASS/);
  assert.match(command, /WSL_PE_BYPASS/);
  assert.match(command, /WSLG_ABSTRACT_SOCKET_PRESENT/);
  assert.match(command, /setpriv [^;]*--no-new-privs [^;]*--bounding-set=-all/);
  assert.match(command, /export GDK_BACKEND=x11/);
  assert.match(command, /export QT_QPA_PLATFORM=xcb/);
  assert.match(command, /exec setpriv [^;]*-- xpra seamless :100/);
  assert.match(command, /-u XPRA_PASSWORD/);
  assert.match(command, /--start-child=/);
  assert.match(command, /literal;not-shell/);
  assert.match(command, /\$\(not-expanded\)/);
});

test('an opaque-looking client ID still requires a server-side registry match', async () => {
  const resolved = await resolvePocApp('linux-ffffffffffffffffffffffffffffffff', 'test-distro', async () => null);
  assert.equal(resolved, null);
});
