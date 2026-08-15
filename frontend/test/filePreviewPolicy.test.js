import test from 'node:test';
import assert from 'node:assert/strict';
import { PREVIEW_LIMITS, classifyPreview, fileExtension } from '../src/core/filePreviewPolicy.js';
import { validatePastePath } from '../src/core/fileOperationPolicy.js';

test('classifies safe preview types without executing markup', () => {
  assert.equal(classifyPreview({ name: 'readme.md', type: 'text/markdown', size: 100 }).kind, 'text');
  assert.equal(classifyPreview({ name: 'image.png', type: 'image/png', size: 100 }).kind, 'image');
  assert.equal(classifyPreview({ name: 'manual.pdf', type: 'application/pdf', size: 100 }).kind, 'pdf');
  assert.equal(classifyPreview({ name: 'track.mp3', type: 'audio/mpeg', size: 100 }).kind, 'audio');
  assert.equal(classifyPreview({ name: 'clip.webm', type: 'video/webm', size: 100 }).kind, 'video');
});

test('treats SVG as text instead of active image content in the privileged shell', () => {
  const preview = classifyPreview({ name: 'diagram.svg', type: 'image/svg+xml', size: 300 });
  assert.deepEqual(preview, { kind: 'text', allowed: true, limit: PREVIEW_LIMITS.text, reason: '' });
});

test('blocks preview when the file exceeds the bounded limit', () => {
  const preview = classifyPreview({ name: 'huge.txt', type: 'text/plain', size: PREVIEW_LIMITS.text + 1 });
  assert.equal(preview.allowed, false);
  assert.equal(preview.kind, 'text');
  assert.match(preview.reason, /excede/i);
});

test('unsupported binary formats fail closed', () => {
  assert.deepEqual(classifyPreview({ name: 'archive.7z', type: 'application/x-7z-compressed', size: 10 }), {
    kind: 'unsupported', allowed: false, limit: 0, reason: 'Formato sem preview seguro.'
  });
  assert.equal(fileExtension('.env'), '');
});

test('prevents copying a directory into itself or a descendant', () => {
  const self = validatePastePath({ sourcePath: ['projects'], entryName: 'app', kind: 'directory', destinationPath: ['projects', 'app'] });
  assert.equal(self.ok, false);
  const descendant = validatePastePath({ sourcePath: ['projects'], entryName: 'app', kind: 'directory', destinationPath: ['projects', 'app', 'src'] });
  assert.equal(descendant.ok, false);
});

test('allows sibling copy and treats cut in the same directory as a no-op', () => {
  const sibling = validatePastePath({ sourcePath: ['projects'], entryName: 'app', kind: 'directory', destinationPath: ['backup'], action: 'copy' });
  assert.deepEqual(sibling, { ok: true, sameDirectory: false, reason: '' });

  const same = validatePastePath({ sourcePath: ['projects'], entryName: 'notes.txt', kind: 'file', destinationPath: ['projects'], action: 'cut' });
  assert.deepEqual(same, { ok: true, sameDirectory: true, reason: '' });
});
