import test from 'node:test';
import assert from 'node:assert/strict';
import {
  generateRecoveryCode,
  hashRecoveryCode,
  normalizeRecoveryCodeInput,
  validRecoveryCodeInput,
  validatePassword,
  verifyRecoveryCode
} from '../src/auth/security.js';

const READABLE = /^CLOUDOS-[2-9A-HJ-NP-Z]{3}(?:-[2-9A-HJ-NP-Z]{4}){8}$/;

test('password accepts four characters, spaces and passphrases without composition rules', () => {
  assert.equal(validatePassword('1234', '1234').error, null);
  assert.equal(validatePassword('a b ', 'a b ').error, null);
  assert.equal(validatePassword('uma frase senha longa', 'uma frase senha longa').error, null);
  assert.match(validatePassword('123', '123').error, /4 e 128/);
  assert.match(validatePassword('abcd', 'abce').error, /não confere/);
});

test('recovery code is readable, grouped and backed by 175 random bits', () => {
  const values = new Set();
  for (let index = 0; index < 64; index += 1) {
    const code = generateRecoveryCode();
    assert.match(code, READABLE);
    assert.equal(code.slice('CLOUDOS-'.length).length, 43);
    values.add(code);
  }
  assert.equal(values.size, 64);
});

test('readable recovery input normalizes separators and preserves legacy compatibility', () => {
  const generated = generateRecoveryCode();
  const compact = generated.replaceAll('-', '').toLowerCase();
  assert.equal(normalizeRecoveryCodeInput(compact), generated);
  assert.equal(validRecoveryCodeInput(compact), true);

  const legacy = `CLOUDOS-${'A'.repeat(43)}`;
  assert.equal(normalizeRecoveryCodeInput(legacy), legacy);
  assert.equal(validRecoveryCodeInput(legacy), true);
});

test('recovery code is stored/verifiable only through its bcrypt hash', async () => {
  const code = generateRecoveryCode();
  const hash = await hashRecoveryCode(code);
  assert.notEqual(hash, code);
  assert.equal(hash.includes(code), false);
  assert.equal(await verifyRecoveryCode(code, hash), true);
  assert.equal(await verifyRecoveryCode(generateRecoveryCode(), hash), false);
});
