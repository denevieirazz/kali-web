import test from 'node:test';
import assert from 'node:assert/strict';
import { buildCloudOsDriveSandboxMounts } from '../src/linuxRuntime/cloudOsDriveSandbox.js';
import {
  buildReadOnlyRootfsFinalize,
  buildWritableContainedHomeMount,
  linuxRootfsSandboxPolicy,
} from '../src/linuxRuntime/linuxRootfsSandbox.js';
import { buildXpraStartCommand } from '../src/linuxRuntime/xpraPoc.js';

const containedHome = '/var/lib/cloudos/contained-homes/1000-testprofile';
const driveRoot = '/mnt/c/Users/cloudos/AppData/Local/CloudOS/Drive';
const identity = { uid: 1000, gid: 1000 };

test('rootfs policy keeps only the contained HOME writable and non-executable', () => {
  const homeCommands = buildWritableContainedHomeMount({ containedHome, ...identity });
  assert.deepEqual(homeCommands, [
    `mount --bind '${containedHome}' '${containedHome}'`,
    `mount -o remount,bind,rw,nosuid,nodev,noexec '${containedHome}'`,
  ]);
  assert.equal(linuxRootfsSandboxPolicy.rootReadOnly, true);
  assert.deepEqual([...linuxRootfsSandboxPolicy.rootFlags], ['ro', 'nosuid', 'nodev']);
  assert.deepEqual([...linuxRootfsSandboxPolicy.containedHomeFlags], ['rw', 'nosuid', 'nodev', 'noexec']);
});

test('rootfs seal is VFS-mount scoped and verifies fail-closed through mountinfo', () => {
  const commands = buildReadOnlyRootfsFinalize({ containedHome, ...identity });
  assert.equal(commands[0], 'mount -o remount,bind,ro,nosuid,nodev /');
  assert.doesNotMatch(commands[0], /remount,ro \/$/);
  assert.match(commands.join('; '), /\/proc\/self\/mountinfo/);
  assert.match(commands.join('; '), /CLOUDOS_ROOTFS_WRITABLE/);
  assert.match(commands.join('; '), /CLOUDOS_CONTAINED_HOME_READONLY/);
  assert.match(commands.join('; '), /cloudos_home_rw=1/);
});

test('Drive mounts are captured before the rootfs becomes read-only', () => {
  const commands = buildCloudOsDriveSandboxMounts({
    wslRoot: driveRoot,
    containedHome,
    ...identity,
  });
  const text = commands.join('; ');
  const homeBind = text.indexOf(`mount --bind '${containedHome}' '${containedHome}'`);
  const driveBind = text.indexOf(`mount --bind '${driveRoot}/Home/Downloads'`);
  const rootSeal = text.indexOf('mount -o remount,bind,ro,nosuid,nodev /');

  assert.ok(homeBind >= 0, 'contained HOME must have its own writable mount');
  assert.ok(driveBind > homeBind, 'Drive binds must live below the writable contained HOME mount');
  assert.ok(rootSeal > driveBind, 'rootfs must become read-only only after approved Drive binds exist');
  assert.ok(text.indexOf('CLOUDOS_DRIVE_BIND_MISSING') < rootSeal, 'Drive mount verification must run before sealing rootfs');
});

test('production Xpra command carries the read-only rootfs seal only when the trusted Drive root is supplied', () => {
  const contained = buildXpraStartCommand({
    appArgv: ['/usr/bin/l3afpad'],
    port: 14500,
    sessionId: 'rootfs-sandbox-test',
    password: '0123456789abcdef0123456789abcdef',
    launchIdentity: { uid: 1000, gid: 1000, name: 'cloudos', home: '/home/cloudos' },
    cloudOsDriveRoot: driveRoot,
  });
  assert.match(contained, /remount,bind,ro,nosuid,nodev \/;/);
  assert.match(contained, /CLOUDOS_ROOTFS_WRITABLE/);
  assert.match(contained, /CLOUDOS_CONTAINED_HOME_READONLY/);

  const characterizationOnly = buildXpraStartCommand({
    appArgv: ['/usr/bin/l3afpad'],
    port: 14500,
    sessionId: 'rootfs-no-drive-test',
    password: '0123456789abcdef0123456789abcdef',
  });
  assert.doesNotMatch(characterizationOnly, /CLOUDOS_ROOTFS_WRITABLE/);
});

test('rootfs builders reject untrusted writable-home paths and identities', () => {
  assert.throws(() => buildWritableContainedHomeMount({ containedHome: '/home/cloudos', ...identity }), /CLOUDOS_CONTAINED_HOME_INVALID/);
  assert.throws(() => buildReadOnlyRootfsFinalize({ containedHome, uid: 0, gid: 1000 }), /CLOUDOS_CONTAINED_IDENTITY_INVALID/);
});
