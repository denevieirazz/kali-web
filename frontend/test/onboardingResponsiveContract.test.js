import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const css = fs.readFileSync(path.join(root, 'src/components/Setup/SetupWizard.css'), 'utf8');
const setup = fs.readFileSync(path.join(root, 'src/components/Setup/SetupWizard.tsx'), 'utf8');
const lock = fs.readFileSync(path.join(root, 'src/components/LockScreen/LockScreen.tsx'), 'utf8');
const recoveryActions = fs.readFileSync(path.join(root, 'src/services/recoveryCodeActions.ts'), 'utf8');
const globalCss = fs.readFileSync(path.join(root, 'src/index.css'), 'utf8');

test('onboarding prevents horizontal overflow and keeps focus geometry stable', () => {
  assert.match(css, /overflow-x:\s*hidden/);
  assert.match(css, /scrollbar-gutter:\s*stable/);
  assert.match(css, /box-sizing:\s*border-box/);
  assert.match(css, /grid-template-columns:\s*repeat\(2,\s*minmax\(0,\s*1fr\)\)/);
  assert.match(css, /@media \(max-width:\s*620px\)[\s\S]*?\.setup-password-grid\s*\{\s*grid-template-columns:\s*minmax\(0,\s*1fr\)/);
  assert.match(css, /\.setup-input:focus-visible[\s\S]*?outline-color/);
  const focusBlock = css.match(/\.setup-input:focus-visible\s*\{([^}]+)\}/)?.[1] || '';
  assert.equal(/\bwidth\s*:|\bpadding\s*:|\bmargin\s*:|border-width\s*:/.test(focusBlock), false);
});

test('shell typography never depends on a remote font CDN', () => {
  assert.doesNotMatch(globalCss, /fonts\.(?:googleapis|gstatic)\.com/i);
  assert.doesNotMatch(globalCss, /@import\s+url\(\s*['"]?https?:\/\//i);
  assert.match(globalCss, /--font-family:\s*'Inter',\s*'Segoe UI Variable',\s*'Segoe UI',\s*system-ui/);
});

test('password hints and controls expose the eight-character policy consistently', () => {
  assert.ok(setup.includes('minLength={8}'));
  assert.ok(setup.includes('Mínimo de 8 caracteres'));
  assert.ok(lock.includes('Mínimo de 8 caracteres'));
  assert.equal(setup.includes('Use de 10 a 128'), false);
  assert.equal(lock.includes('Use de 10 a 128'), false);
});

test('recovery UX only saves after an explicit picker and offers copy save print plus file input', () => {
  assert.ok(recoveryActions.includes('showSaveFilePicker'));
  assert.equal(recoveryActions.includes('localStorage'), false);
  assert.equal(recoveryActions.includes('indexedDB'), false);
  assert.equal(recoveryActions.includes('navigator.storage'), false);
  for (const label of ['Copiar', 'Salvar arquivo de recuperação', 'Imprimir']) assert.ok(setup.includes(label));
  assert.ok(lock.includes('Selecionar arquivo .txt'));
  assert.ok(lock.includes('type="file"'));
  assert.ok(lock.includes('setRotatedCode(null)'));
});
