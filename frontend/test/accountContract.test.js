import test from 'node:test';
import assert from 'node:assert/strict';
import {
  ACCOUNT_LEGACY_RECOVERY_ENDPOINT,
  ACCOUNT_RECOVERY_ENDPOINT,
  canRestoreAuthenticatedSession,
  extractRecoveryCode,
  extractRecoveryCodeFromText,
  legacyRecoveryRequestBody,
  normalizePublicUser,
  normalizeReadableRecoveryCode,
  recoveryRequestBody,
  sanitizePersistedProfile,
  validateDisplayName,
  validateNewPassword,
  validateUsername
} from '../src/services/accountContract.js';

test('never restores a persisted session while a one-time recovery code still needs confirmation', () => {
  assert.equal(canRestoreAuthenticatedSession(true, false), true);
  assert.equal(canRestoreAuthenticatedSession(true, true), false);
  assert.equal(canRestoreAuthenticatedSession(false, false), false);
});

test('validates the real account form with an eight-character minimum', () => {
  assert.equal(validateUsername('douglas.dev'), null);
  assert.equal(validateUsername('', { required: false }), null);
  assert.match(validateUsername('do'), /3 e 64/);
  assert.match(validateUsername('bad user'), /use apenas letras/);
  assert.match(validateUsername('.hidden'), /Comece com uma letra ou número/);
  assert.equal(validateDisplayName('Douglas'), null);
  assert.equal(validateDisplayName('', { required: false }), null);
  assert.match(validateDisplayName(''), /exibição/);
  assert.equal(validateNewPassword('12345678', '12345678'), null);
  assert.equal(validateNewPassword('a b c d ', 'a b c d '), null);
  assert.equal(validateNewPassword('correct horse battery staple', 'correct horse battery staple'), null);
  assert.equal(validateNewPassword('CaféComPão#2026', 'CaféComPão#2026'), null);
  assert.match(validateNewPassword('1234567', '1234567'), /8 caracteres/);
  assert.match(validateNewPassword('123', '123'), /8 caracteres/);
  assert.match(validateNewPassword('12345678\x00', '12345678\x00'), /caracteres de controle/);
  assert.match(validateNewPassword('safe-password-1', 'different'), /não confere/);
});

test('normalizes readable grouped recovery codes from text files', () => {
  const code = 'CLOUDOS-ABC-DEFG-HJKL-MNPQ-RSTU-VWXY-Z234-5678-9ABC';
  const compact = 'cloudos abcdefghjklmnpqrstuvwxyz23456789abc';
  assert.equal(normalizeReadableRecoveryCode(compact), code);
  assert.equal(extractRecoveryCodeFromText(`CloudOS recovery\n${code}\nkeep safe`), code);
  assert.equal(extractRecoveryCodeFromText('sem código'), '');
});

test('sanitizes legacy plaintext password and recovery material from persisted profiles', () => {
  const profile = sanitizePersistedProfile({
    username: 'legacy', displayName: 'Legacy User', password: 'plaintext', recoveryCode: 'secret', role: 'admin'
  });
  assert.deepEqual(profile, {
    username: 'legacy', displayName: 'Legacy User', avatar: '', isAdmin: true, lastLogin: profile.lastLogin
  });
  assert.equal('password' in profile, false);
  assert.equal('recoveryCode' in profile, false);
});

test('normalizes backend display-name aliases and extracts one-time recovery codes', () => {
  const user = normalizePublicUser({ username: 'owner', display_name: 'Owner Name', role: 'admin' });
  assert.equal(user.displayName, 'Owner Name');
  assert.equal(user.isAdmin, true);
  assert.equal(extractRecoveryCode({ new_recovery_code: 'ABCD-EFGH' }), 'ABCD-EFGH');
  assert.equal(extractRecoveryCode({ recovery: { code: 'IJKL-MNOP' } }), 'IJKL-MNOP');
});

test('recovery request carries compatibility aliases but never current session data', () => {
  const body = recoveryRequestBody({
    recoveryCode: ' CODE-123 ', username: 'new-owner', displayName: 'New Owner', password: 'new-password-1', confirmPassword: 'new-password-1'
  });
  assert.equal(body.recoveryCode, 'CODE-123');
  assert.equal(body.newUsername, 'new-owner');
  assert.equal(body.displayName, 'New Owner');
  assert.equal(body.password, 'new-password-1');
  assert.equal('token' in body, false);
});

test('recovery request omits newUsername and displayName when empty to preserve existing account credentials', () => {
  const body = recoveryRequestBody({
    recoveryCode: ' CODE-123 ', username: '', displayName: '', password: 'new-password-1', confirmPassword: 'new-password-1'
  });
  assert.equal(body.recoveryCode, 'CODE-123');
  assert.equal('newUsername' in body, false);
  assert.equal('displayName' in body, false);
  assert.equal(body.password, 'new-password-1');
  assert.equal(body.confirmPassword, 'new-password-1');
});

test('legacy recovery request formats payload with legacy token and omits empty optional fields', () => {
  assert.equal(ACCOUNT_LEGACY_RECOVERY_ENDPOINT, '/api/auth/legacy-recovery/reset');
  assert.equal(ACCOUNT_RECOVERY_ENDPOINT, '/api/auth/recovery/reset');
  const body = legacyRecoveryRequestBody({
    legacyToken: ' LEGACY-ABC123XYZ ',
    username: '',
    displayName: '',
    password: 'new-password-1',
    confirmPassword: 'new-password-1'
  });
  assert.equal(body.legacyToken, 'LEGACY-ABC123XYZ');
  assert.equal('newUsername' in body, false);
  assert.equal('displayName' in body, false);
  assert.equal(body.password, 'new-password-1');
  assert.equal(body.confirmPassword, 'new-password-1');

  const withAliases = legacyRecoveryRequestBody({
    legacyToken: 'LEGACY-999',
    username: 'novo-admin',
    displayName: 'Novo Admin',
    password: 'pass',
    confirmPassword: 'pass'
  });
  assert.equal(withAliases.newUsername, 'novo-admin');
  assert.equal(withAliases.displayName, 'Novo Admin');
});
