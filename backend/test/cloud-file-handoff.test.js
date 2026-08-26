import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { CloudOsDrive, CloudOsDriveError } from '../src/storage/cloudosDrive.js';
import { resolveCloudFileRef, validateCloudFileRef } from '../src/storage/cloudFileHandoff.js';
import { applyCloudFileHandoff } from '../src/apps/fileHandoff.js';

async function withDrive(run) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'cloudos-file-handoff-'));
  try {
    const drive = new CloudOsDrive(path.join(root, 'Drive'));
    await drive.ensureReady();
    await run(drive, root);
  } finally {
    await fs.rm(root, { recursive: true, force: true });
  }
}

test('file ref accepts only logical Home/Shared paths', () => {
  assert.deepEqual(
    validateCloudFileRef({ provider: 'cloudos', path: ['Home', 'Downloads', 'report.pdf'] }),
    { provider: 'cloudos', path: ['Home', 'Downloads', 'report.pdf'] },
  );
  assert.throws(() => validateCloudFileRef({ provider: 'cloudos', path: ['Apps', 'windows', 'secret.exe'] }), error => error instanceof CloudOsDriveError && error.code === 'CLOUDOS_FILE_REF_SCOPE_DENIED');
  assert.throws(() => validateCloudFileRef({ provider: 'cloudos', path: ['Home', '..', 'escape.txt'] }), error => error instanceof CloudOsDriveError && error.code === 'CLOUDOS_FILE_REF_INVALID');
  assert.throws(() => validateCloudFileRef({ provider: 'windows', path: ['C:', 'Windows'] }), error => error instanceof CloudOsDriveError && error.code === 'CLOUDOS_FILE_REF_INVALID');
  assert.throws(() => validateCloudFileRef({ provider: 'cloudos', path: ['Home', 'file.txt'], absolutePath: 'C:\\Windows\\win.ini' }), error => error instanceof CloudOsDriveError && error.code === 'CLOUDOS_FILE_REF_INVALID');
});

test('resolver returns the existing physical file without copying', async () => {
  await withDrive(async drive => {
    const logical = ['Home', 'Downloads', 'zero copy.txt'];
    await drive.write(logical, Buffer.from('same-file'), { truncate: true });
    const resolved = await resolveCloudFileRef({ provider: 'cloudos', path: logical }, drive);
    const runtime = await drive.runtimePaths();
    assert.equal(resolved.absolutePath, path.join(runtime.hostRoot, ...logical));
    assert.equal(await fs.readFile(resolved.absolutePath, 'utf8'), 'same-file');
  });
});

test('resolver blocks symlink or junction traversal before runtime handoff', async () => {
  await withDrive(async (drive, tempRoot) => {
    const runtime = await drive.runtimePaths();
    const outside = path.join(tempRoot, 'outside');
    await fs.mkdir(outside);
    await fs.writeFile(path.join(outside, 'secret.txt'), 'host-secret');
    const link = path.join(runtime.hostRoot, 'Home', 'Downloads', 'escape');
    try {
      await fs.symlink(outside, link, process.platform === 'win32' ? 'junction' : 'dir');
      await assert.rejects(
        () => resolveCloudFileRef({ provider: 'cloudos', path: ['Home', 'Downloads', 'escape', 'secret.txt'] }, drive),
        error => error instanceof CloudOsDriveError && error.code === 'CLOUDOS_DRIVE_SYMLINK_BLOCKED',
      );
    } catch (error) {
      if (process.platform !== 'win32' || !['EPERM', 'EACCES'].includes(error?.code)) throw error;
    }
  });
});

test('Windows handoff appends one broker-resolved path and upgrades shortcut-direct to argv', async () => {
  await withDrive(async drive => {
    const logical = ['Home', 'Downloads', 'report.pdf'];
    await drive.write(logical, Buffer.from('pdf'), { truncate: true });
    const fileRef = { provider: 'cloudos', path: logical };
    const launch = {
      id: 'native-example',
      launchKind: 'windows-shortcut-direct',
      launchSpec: { executable: 'C:\\Program Files\\Viewer\\viewer.exe', arguments: [], workingDirectory: 'C:\\Program Files\\Viewer' },
    };

    const result = await applyCloudFileHandoff(launch, fileRef, ref => resolveCloudFileRef(ref, drive));
    const runtime = await drive.runtimePaths();
    assert.equal(result.launchKind, 'windows-shortcut-argv');
    assert.deepEqual(result.launchSpec.arguments, [path.join(runtime.hostRoot, ...logical)]);
    assert.deepEqual(result.fileHandoff, fileRef);
    assert.deepEqual(launch.launchSpec.arguments, [], 'original catalog launch capability must remain immutable by convention');
  });
});

test('existing shortcut argv is preserved before the brokered file argument', async () => {
  const resolvedPath = 'C:\\CloudOS\\Drive\\Home\\Documents\\notes.txt';
  const result = await applyCloudFileHandoff({
    launchKind: 'windows-shortcut-argv',
    launchSpec: { executable: 'C:\\Editor\\editor.exe', arguments: ['--safe-mode'] },
  }, { provider: 'cloudos', path: ['Home', 'Documents', 'notes.txt'] }, async fileRef => ({ fileRef, absolutePath: resolvedPath }));
  assert.deepEqual(result.launchSpec.arguments, ['--safe-mode', resolvedPath]);
});

test('BAT/CMD handoff stays fail-closed until its quoting contract is explicitly extended', async () => {
  await assert.rejects(
    () => applyCloudFileHandoff({
      launchKind: 'windows-script-direct',
      launchSpec: { executable: 'C:\\Windows\\System32\\cmd.exe', arguments: ['/d', '/s', '/v:off', '/c', 'call', 'C:\\Tools\\run.cmd'] },
    }, { provider: 'cloudos', path: ['Home', 'Downloads', 'file.txt'] }),
    error => error?.code === 'APP_FILE_HANDOFF_UNSUPPORTED',
  );
});
