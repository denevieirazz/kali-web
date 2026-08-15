import test from 'node:test';
import assert from 'node:assert/strict';
import { KALI_TOOL_MANIFEST, parseToolInventory, publicToolManifest } from '../src/security/toolInventory.js';

test('Kali tool manifest has unique fixed IDs and commands', () => {
  assert.ok(KALI_TOOL_MANIFEST.length >= 20);
  assert.equal(new Set(KALI_TOOL_MANIFEST.map(tool => tool.id)).size, KALI_TOOL_MANIFEST.length);
  assert.equal(new Set(KALI_TOOL_MANIFEST.map(tool => tool.command)).size, KALI_TOOL_MANIFEST.length);
  for (const tool of KALI_TOOL_MANIFEST) {
    assert.match(tool.id, /^[a-z0-9][a-z0-9-]{0,63}$/);
    assert.match(tool.command, /^[a-zA-Z0-9][a-zA-Z0-9._+-]{0,79}$/);
    assert.ok(tool.name.length > 0);
    assert.ok(tool.description.length > 0);
  }
});

test('parseToolInventory only maps known manifest commands', () => {
  const manifest = KALI_TOOL_MANIFEST.slice(0, 3);
  const output = `${manifest[0].command}\x1f1\n${manifest[1].command}\x1f0\nunknown-tool\x1f1\n`;
  const result = parseToolInventory(output, manifest);
  assert.equal(result.length, 3);
  assert.equal(result[0].installed, true);
  assert.equal(result[1].installed, false);
  assert.equal(result[2].installed, false);
  assert.equal(result.some(tool => tool.command === 'unknown-tool'), false);
});

test('public manifest never exposes executable paths or argv', () => {
  const result = publicToolManifest();
  for (const tool of result) {
    assert.equal(Object.hasOwn(tool, 'path'), false);
    assert.equal(Object.hasOwn(tool, 'argv'), false);
    assert.equal(Object.hasOwn(tool, 'executable'), false);
    assert.equal(tool.installed, false);
  }
});
