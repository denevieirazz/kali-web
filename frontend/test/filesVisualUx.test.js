import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { classifyFileVisual, canGenerateImageThumbnail, FILE_VISUAL_KINDS } from '../src/apps/CloudOSFiles/fileVisualPolicy.js';
import { MAX_THUMBNAIL_SOURCE_BYTES, ThumbnailScheduler, thumbnailEligible } from '../src/apps/CloudOSFiles/thumbnailManager.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

test('classifies every requested visual file kind', () => {
  const cases = [
    [{ kind: 'directory', name: 'docs' }, 'folder'],
    [{ kind: 'file', name: 'notes.txt' }, 'text'],
    [{ kind: 'file', name: 'README.md' }, 'markdown'],
    [{ kind: 'file', name: 'main.ts' }, 'code'],
    [{ kind: 'file', name: 'data.json' }, 'json'],
    [{ kind: 'file', name: 'manual.pdf' }, 'pdf'],
    [{ kind: 'file', name: 'photo.webp' }, 'image'],
    [{ kind: 'file', name: 'song.flac' }, 'audio'],
    [{ kind: 'file', name: 'movie.mp4' }, 'video'],
    [{ kind: 'file', name: 'backup.zip' }, 'archive'],
    [{ kind: 'file', name: 'installer.exe' }, 'executable'],
    [{ kind: 'symlink', name: 'outside' }, 'symlink'],
    [{ kind: 'file', name: 'unknown.bin' }, 'unknown'],
  ];
  assert.equal(FILE_VISUAL_KINDS.length, 13);
  for (const [entry, expected] of cases) assert.equal(classifyFileVisual(entry), expected);
});

test('symlink is metadata-only and never eligible for thumbnails', () => {
  const link = { kind: 'symlink', name: 'image.jpg', size: 1024, isSymlink: true };
  assert.equal(classifyFileVisual(link), 'symlink');
  assert.equal(canGenerateImageThumbnail(link, 'image/jpeg'), false);
});

test('large image is rejected before decoder/object URL work', () => {
  assert.equal(thumbnailEligible({ size: MAX_THUMBNAIL_SOURCE_BYTES }), true);
  assert.equal(thumbnailEligible({ size: MAX_THUMBNAIL_SOURCE_BYTES + 1 }), false);
  const source = fs.readFileSync(path.join(root, 'src/apps/CloudOSFiles/thumbnailManager.js'), 'utf8');
  const sizeCheck = source.indexOf('thumbnailEligible(file, maxBytes)');
  const objectUrl = source.indexOf('URL.createObjectURL(file)');
  assert.ok(sizeCheck >= 0 && objectUrl > sizeCheck, 'size limit must run before object URL creation');
  assert.equal(source.includes('.arrayBuffer('), false);
  assert.equal(source.includes('file.text('), false);
  assert.ok(source.includes('URL.revokeObjectURL'));
});

test('thumbnail scheduler enforces bounded concurrency', async () => {
  const scheduler = new ThumbnailScheduler(3);
  let active = 0;
  let peak = 0;
  const jobs = Array.from({ length: 12 }, (_, index) => scheduler.schedule(async () => {
    active += 1;
    peak = Math.max(peak, active);
    await new Promise(resolve => setTimeout(resolve, 8));
    active -= 1;
    return index;
  }));
  const results = await Promise.all(jobs);
  assert.deepEqual(results, Array.from({ length: 12 }, (_, index) => index));
  assert.equal(peak, 3);
});

test('queued thumbnails are cancelable and removed before execution', async () => {
  const scheduler = new ThumbnailScheduler(1);
  let release;
  const blocker = scheduler.schedule(() => new Promise(resolve => { release = resolve; }));
  const controller = new AbortController();
  let ran = false;
  const queued = scheduler.schedule(() => { ran = true; return 'unexpected'; }, controller.signal);
  controller.abort();
  await assert.rejects(queued, error => error?.name === 'AbortError');
  release('done');
  await blocker;
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(ran, false);
});
