import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { CloudOsDrive, CloudOsDriveError, resolveCloudOsDriveRoot, windowsPathToWslPath } from '../src/storage/cloudosDrive.js';

async function withDrive(run) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'cloudos-drive-test-'));
  try {
    const drive = new CloudOsDrive(path.join(root, 'CloudOS Drive'));
    await drive.ensureReady();
    await run(drive, root);
  } finally {
    await fs.rm(root, { recursive: true, force: true });
  }
}

test('CloudOS Drive creates one canonical shared layout', async () => {
  await withDrive(async drive => {
    const status = await drive.status();
    assert.equal(status.source, 'cloudos');
    assert.equal(status.mode, 'cloudos-drive-v1');
    assert.equal(status.available, true);
    assert.equal(status.mounted, true);

    const rootEntries = await drive.list([]);
    assert.deepEqual(rootEntries.map(entry => entry.name), ['Apps', 'Home', 'Shared']);
    assert.equal(rootEntries.some(entry => entry.name === '.cloudos-system'), false);

    const homeEntries = await drive.list(['Home']);
    assert.deepEqual(homeEntries.map(entry => entry.name), ['Desktop', 'Documents', 'Downloads', 'Projects']);

    const runtime = await drive.runtimePaths();
    assert.equal(runtime.hostDownloads, path.join(runtime.hostRoot, 'Home', 'Downloads'));
    assert.equal(runtime.hostProjects, path.join(runtime.hostRoot, 'Home', 'Projects'));
    assert.equal(runtime.windowsApps, path.join(runtime.hostRoot, 'Apps', 'windows'));
    assert.equal(runtime.linuxApps, path.join(runtime.hostRoot, 'Apps', 'linux'));
  });
});

test('native Windows runtime and backend resolve the same stable CloudOS Drive root', () => {
  const environment = { LOCALAPPDATA: 'C:\\Users\\cloudos\\AppData\\Local' };
  assert.equal(
    resolveCloudOsDriveRoot(environment, 'win32'),
    'C:\\Users\\cloudos\\AppData\\Local\\CloudOS\\Drive',
  );
  assert.equal(
    resolveCloudOsDriveRoot({ ...environment, CLOUDOS_DRIVE_DIR: 'D:\\CloudOS Data' }, 'win32'),
    'D:\\CloudOS Data',
  );
});

test('CloudOS Drive reads and writes the same physical file in chunks', async () => {
  await withDrive(async drive => {
    const filePath = ['Home', 'Downloads', 'arquivo compartilhado.txt'];
    await drive.write(filePath, Buffer.from('CloudOS '), { truncate: true, offset: 0 });
    await drive.write(filePath, Buffer.from('Drive'), { offset: 8 });

    const first = await drive.read(filePath, 0, 4);
    const second = await drive.read(filePath, 4, 64);
    assert.equal(Buffer.from(first.data, 'base64').toString('utf8'), 'Clou');
    assert.equal(Buffer.from(second.data, 'base64').toString('utf8'), 'dOS Drive');
    assert.equal(second.eof, true);

    const entries = await drive.list(['Home', 'Downloads']);
    assert.equal(entries.length, 1);
    assert.equal(entries[0].name, 'arquivo compartilhado.txt');
    assert.equal(entries[0].kind, 'file');
  });
});

test('CloudOS Drive move, copy and trash stay inside the canonical root', async () => {
  await withDrive(async drive => {
    await drive.write(['Home', 'Documents', 'nota.txt'], Buffer.from('nota'), { truncate: true });
    await drive.copy(['Home', 'Documents', 'nota.txt'], ['Shared', 'nota.txt']);
    assert.equal(Buffer.from((await drive.read(['Shared', 'nota.txt'])).data, 'base64').toString(), 'nota');

    await drive.move(['Shared', 'nota.txt'], ['Home', 'Projects', 'nota.txt']);
    await assert.rejects(() => drive.read(['Shared', 'nota.txt']), error => error instanceof CloudOsDriveError && error.code === 'CLOUDOS_DRIVE_NOT_FOUND');

    const trashed = await drive.trash(['Home', 'Projects', 'nota.txt']);
    assert.match(trashed.id, /^[a-f0-9]{32}$/);
    assert.equal((await drive.listTrash()).length, 1);
    await drive.restoreTrash(trashed.id);
    assert.equal(Buffer.from((await drive.read(['Home', 'Projects', 'nota.txt'])).data, 'base64').toString(), 'nota');

    const trashedAgain = await drive.trash(['Home', 'Projects', 'nota.txt']);
    await drive.deleteTrash(trashedAgain.id);
    assert.equal((await drive.listTrash()).length, 0);
  });
});

test('CloudOS Drive rejects traversal, reserved internals and symlink traversal', async () => {
  await withDrive(async (drive, tempRoot) => {
    await assert.rejects(() => drive.list(['..']), error => error instanceof CloudOsDriveError && error.code === 'CLOUDOS_DRIVE_PATH_INVALID');
    await assert.rejects(() => drive.list(['.cloudos-system']), error => error instanceof CloudOsDriveError && error.code === 'CLOUDOS_DRIVE_PATH_INVALID');

    const runtime = await drive.runtimePaths();
    const outside = path.join(tempRoot, 'outside');
    await fs.mkdir(outside);
    const link = path.join(runtime.hostRoot, 'Shared', 'escape-link');
    try {
      await fs.symlink(outside, link, process.platform === 'win32' ? 'junction' : 'dir');
      const entries = await drive.list(['Shared']);
      assert.equal(entries.find(entry => entry.name === 'escape-link')?.kind, 'symlink');
      await assert.rejects(() => drive.list(['Shared', 'escape-link']), error => error instanceof CloudOsDriveError && error.code === 'CLOUDOS_DRIVE_SYMLINK_BLOCKED');
    } catch (error) {
      if (process.platform !== 'win32' || !['EPERM', 'EACCES'].includes(error?.code)) throw error;
    }
  });
});

test('Windows paths are converted to the WSL view without copying', () => {
  assert.equal(windowsPathToWslPath('C:\\CloudOS Data\\drive'), '/mnt/c/CloudOS Data/drive');
  assert.equal(windowsPathToWslPath('d:/CloudOS/drive'), '/mnt/d/CloudOS/drive');
  assert.equal(windowsPathToWslPath('/var/lib/cloudos'), null);
});
