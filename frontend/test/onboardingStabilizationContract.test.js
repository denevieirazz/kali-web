import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const setup = fs.readFileSync(new URL('../src/components/Setup/SetupWizard.tsx', import.meta.url), 'utf8');
const lock = fs.readFileSync(new URL('../src/components/LockScreen/LockScreen.tsx', import.meta.url), 'utf8');
const actions = fs.readFileSync(new URL('../src/services/recoveryCodeActions.ts', import.meta.url), 'utf8');

test('eight-character password is required with clear guidance', () => {
  assert.match(setup, /minLength=\{8\}/);
  assert.match(setup, /Mínimo de 8 caracteres/);
  assert.match(setup, /Recomendamos uma frase maior/);
  assert.match(setup, /Não exigimos maiúsculas, números ou símbolos/);
});

test('recovery language is understandable and permits explicit skip with warning', () => {
  assert.match(setup, /PROTEJA SUA CONTA/);
  assert.match(setup, /Este arquivo permite criar uma nova senha/);
  assert.match(setup, /Salvar arquivo de recuperação/);
  assert.match(setup, /Continuar sem salvar/);
  assert.match(setup, /window\.confirm/);
  assert.match(setup, /setRecoveryCode\(null\)/);
});

test('recovery export never persists automatically and uses explicit picker', () => {
  assert.match(actions, /showSaveFilePicker/);
  assert.doesNotMatch(actions, /localStorage|indexedDB|navigator\.storage/);
  assert.match(actions, /copyRecoveryCode/);
  assert.match(actions, /printRecoveryCode/);
});

test('forgot-password flow accepts pasted or selected local recovery file and clears rotated secret', () => {
  assert.match(lock, /Esqueci minha senha/);
  assert.match(lock, /Selecionar arquivo \.txt/);
  assert.match(lock, /readRecoveryCodeTextFile/);
  assert.match(lock, /setRecoveryCode\(''\)/);
  assert.match(lock, /setRotatedCode\(null\)/);
});
