import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const files = fs.readFileSync(new URL('../src/apps/CloudOSFiles/CloudOSFiles.tsx', import.meta.url), 'utf8');
const visual = fs.readFileSync(new URL('../src/apps/CloudOSFiles/FileVisual.tsx', import.meta.url), 'utf8');
const facade = fs.readFileSync(new URL('../src/apps/CloudOSFiles/fileSourceFacade.ts', import.meta.url), 'utf8');
const windows = fs.readFileSync(new URL('../src/apps/CloudOSFiles/windowsDirectorySource.ts', import.meta.url), 'utf8');

test('one Files app keeps OPFS Windows grant and Linux Home isolated', () => {
  for (const value of ['value="opfs"', 'value="windows"', 'value="wsl"']) assert.match(files, new RegExp(value));
  assert.match(files, /data-files-source=\{source\}/);
  assert.match(facade, /clipboard\.source !== source/);
});

test('visual layer is provider-neutral and reads thumbnails through the bounded facade', () => {
  assert.match(visual, /fileSourceFacade\.readFile\(source, path, entry, MAX_THUMBNAIL_READ_BYTES\)/);
  assert.match(visual, /entry\.size <= MAX_THUMBNAIL_READ_BYTES/);
  assert.match(visual, /entry\.kind === 'file'/);
  assert.match(visual, /!entry\.symlink/);
  assert.doesNotMatch(visual, /opfsFileService/);
});

test('Windows grant remains explicit and memory-only', () => {
  assert.match(windows, /showDirectoryPicker/);
  assert.match(windows, /let mountedRoot: FileSystemDirectoryHandle \| null = null/);
  assert.doesNotMatch(windows, /localStorage|sessionStorage|indexedDB/);
});

test('storage terminology never represents OPFS as physical disk', () => {
  assert.doesNotMatch(files, /OPFS\s*10\s*GB/i);
  assert.doesNotMatch(files, /HD\s+CloudOS/i);
});
