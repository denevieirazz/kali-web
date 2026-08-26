import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildXpraStartCommand } from '../src/linuxRuntime/xpraPoc.js';
import {
  buildCloudOsDriveSandboxMounts,
  cloudOsDriveSandboxPolicy,
  mapCloudOsDriveFilePath,
  normalizeWslCloudOsDriveRoot,
} from '../src/linuxRuntime/cloudOsDriveSandbox.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const runtimePath = path.resolve(here, '../src/linuxRuntime/xpraPoc.js');
const driveRoot = '/mnt/c/Users/cloudos/AppData/Local/CloudOS/Drive';

test('Linux sandbox accepts only a canonical WSL view of CloudOS Drive', () => {
  assert.equal(normalizeWslCloudOsDriveRoot(driveRoot), driveRoot);
  assert.equal(normalizeWslCloudOsDriveRoot(`${driveRoot}/`), driveRoot);
  assert.equal(normalizeWslCloudOsDriveRoot('/home/cloudos/Drive'), null);
  assert.equal(normalizeWslCloudOsDriveRoot('/mnt/c/Users/cloudos/../escape'), null);
  assert.equal(normalizeWslCloudOsDriveRoot('/mnt/c'), null);
  assert.equal(normalizeWslCloudOsDriveRoot('/mnt/c/CloudOS/Drive\nboom'), null);
});

test('file handoff maps only approved CloudOS Drive areas into the private namespace', () => {
  assert.equal(
    mapCloudOsDriveFilePath(`${driveRoot}/Home/Downloads/report.pdf`, driveRoot),
    '/run/cloudos-drive/Downloads/report.pdf',
  );
  assert.equal(
    mapCloudOsDriveFilePath(`${driveRoot}/Home/Projects/client one/readme.md`, driveRoot),
    '/run/cloudos-drive/Projects/client one/readme.md',
  );
  assert.equal(
    mapCloudOsDriveFilePath(`${driveRoot}/Shared/evidence.txt`, driveRoot),
    '/run/cloudos-drive/Shared/evidence.txt',
  );

  assert.throws(() => mapCloudOsDriveFilePath(`${driveRoot}/Apps/linux/tool`, driveRoot), /OUTSIDE_SANDBOX/);
  assert.throws(() => mapCloudOsDriveFilePath(`${driveRoot}/.cloudos-system/trash/item`, driveRoot), /OUTSIDE_SANDBOX/);
  assert.throws(() => mapCloudOsDriveFilePath('/mnt/c/Windows/System32/calc.exe', driveRoot), /OUTSIDE_SANDBOX/);
});

test('mount policy exposes five explicit writable noexec areas and never the Drive root', () => {
  const commands = buildCloudOsDriveSandboxMounts({
    wslRoot: driveRoot,
    containedHome: '/var/lib/cloudos/contained-homes/1000-testprofile',
    uid: 1000,
    gid: 1000,
  }).join('; ');

  assert.deepEqual(cloudOsDriveSandboxPolicy.bindings.map(binding => binding.name), [
    'Desktop', 'Documents', 'Downloads', 'Projects', 'Shared',
  ]);
  for (const binding of cloudOsDriveSandboxPolicy.bindings) {
    const source = `${driveRoot}/${binding.source.join('/')}`;
    assert.ok(commands.includes(`mount --bind '${source}' '/run/cloudos-drive/${binding.name}'`));
    assert.ok(commands.includes(`remount,bind,rw,nosuid,nodev,noexec '/run/cloudos-drive/${binding.name}'`));
    assert.ok(commands.includes(`mount --bind '/run/cloudos-drive/${binding.name}' '/var/lib/cloudos/contained-homes/1000-testprofile/${binding.name}'`));
  }
  assert.ok(!commands.includes(`mount --bind '${driveRoot}' `));
  assert.doesNotMatch(commands, /\/Apps\/(?:windows|linux)|\.cloudos-system/);
  assert.match(commands, /CLOUDOS_DRIVE_BIND_INVALID/);
});

test('Xpra sandbox captures approved Drive binds before hiding all Windows mounts', () => {
  const command = buildXpraStartCommand({
    appArgv: ['/usr/bin/l3afpad', '--new-window'],
    port: 14500,
    sessionId: 'cloudos-drive-sandbox',
    password: '0123456789abcdef0123456789abcdef',
    launchIdentity: { uid: 1000, gid: 1000, name: 'cloudos', home: '/home/cloudos' },
    cloudOsDriveRoot: driveRoot,
  });

  const bindDownload = command.indexOf(`mount --bind '${driveRoot}/Home/Downloads'`);
  const hideWindowsMounts = command.indexOf('mount -t tmpfs -o mode=755,nosuid,nodev,noexec tmpfs /mnt');
  assert.ok(bindDownload >= 0, 'Downloads must be captured from the canonical Drive before /mnt is hidden');
  assert.ok(hideWindowsMounts > bindDownload, '/mnt must be hidden only after approved bind mounts exist');

  assert.match(command, /tmpfs \/home/);
  assert.match(command, /tmpfs \/var\/tmp/);
  assert.match(command, /tmpfs \/dev\/shm/);
  assert.match(command, /CLOUDOS_HOST_MOUNT_VISIBLE/);
  assert.doesNotMatch(command, /\/home\/cloudos\/\.local\/bin/);
  assert.doesNotMatch(command, /mount --bind '[^']*\/Drive' \/run\/cloudos-drive(?:;|')/);
  assert.doesNotMatch(command, /\/Drive\/Apps\/|\/Drive\/\.cloudos-system/);
});

test('production Linux launch resolves the Drive server-side and blocks user-local app homes', () => {
  const source = fs.readFileSync(runtimePath, 'utf8');
  assert.match(source, /driveRuntimePaths = await cloudOsDrive\.runtimePaths\(\)/);
  assert.match(source, /normalizeWslCloudOsDriveRoot\(driveRuntimePaths\.wslRoot\)/);
  assert.match(source, /mapCloudOsDriveFilePath\(requestedFilePath, cloudOsDriveRoot\)/);
  assert.match(source, /LINUX_USER_LOCAL_APP_OUTSIDE_SANDBOX/);
  assert.match(source, /cloudOsDriveRoot \}\);/);
});

test('malformed Drive roots fail closed before command construction', () => {
  assert.throws(() => buildXpraStartCommand({
    appArgv: ['/usr/bin/l3afpad'],
    port: 14500,
    password: '0123456789abcdef',
    cloudOsDriveRoot: '/tmp/not-the-drive',
  }), /Drive WSL root inválido/);
});
