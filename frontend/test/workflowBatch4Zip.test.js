import test from 'node:test';
import assert from 'node:assert/strict';
import { crc32, createStoreZip } from '../src/core/zipStore.js';

test('CRC32 usa vetor canonico', () => {
  const bytes = new TextEncoder().encode('123456789');
  assert.equal(crc32(bytes), 0xcbf43926);
});

test('ZIP store gera headers e nomes UTF-8 sem cloud', () => {
  const zip = createStoreZip([
    { name: 'Metadata/workspace.json', data: '{"name":"Projeto"}' },
    { name: 'Notes/nota.md', data: '# Nota' },
    { name: 'Evidence/log.log', data: 'evidence' },
  ]);
  assert.equal(zip[0], 0x50);
  assert.equal(zip[1], 0x4b);
  const text = new TextDecoder().decode(zip);
  assert.match(text, /Metadata\/workspace\.json/);
  assert.match(text, /Notes\/nota\.md/);
  assert.match(text, /Evidence\/log\.log/);
  assert.equal(zip.at(-22), 0x50);
  assert.equal(zip.at(-21), 0x4b);
  assert.equal(zip.at(-20), 0x05);
  assert.equal(zip.at(-19), 0x06);
});

test('ZIP rejeita path traversal', () => {
  assert.throws(() => createStoreZip([{ name: '../secret.txt', data: 'no' }]), /inválido/);
});
