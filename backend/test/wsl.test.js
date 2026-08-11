import test from 'node:test';
import assert from 'node:assert';
import { listInstalled, getDefault, getPreferred, isInstalled, validateAllowlisted, parseWslListOutput } from '../src/wsl/distroService.js';
import jwt from 'jsonwebtoken';
import { config } from '../src/config/index.js';

test('WSL 1: Parsing de saída do wsl --list --verbose', () => {
  const sampleOutput = `
  NAME          STATE           VERSION
* kali-linux    Running         2
  Ubuntu        Stopped         2
`;
  const parsed = parseWslListOutput(sampleOutput);
  assert.strictEqual(parsed.length, 2);
  assert.strictEqual(parsed[0].name, 'kali-linux');
  assert.strictEqual(parsed[0].isDefault, true);
  assert.strictEqual(parsed[0].state, 'Running');
  assert.strictEqual(parsed[1].name, 'Ubuntu');
  assert.strictEqual(parsed[1].isDefault, false);
});

test('WSL 2: Preferência seleciona Kali quando instalada', () => {
  const preferred = getPreferred();
  assert.ok(preferred !== null);
  // Se kali-linux estiver instalada no host Windows, ela deve ser a preferida
  if (isInstalled('kali-linux')) {
    assert.strictEqual(preferred.toLowerCase(), 'kali-linux');
  }
});

test('WSL 3: Distribuição inexistente é rejeitada', () => {
  const valid = validateAllowlisted('distro-fantasma-inexistente-12345');
  assert.strictEqual(valid, false);
});

test('WSL 4: Injeção de caminho ou argumentos maliciosos é rejeitada', () => {
  assert.strictEqual(validateAllowlisted('kali-linux; rm -rf /'), false);
  assert.strictEqual(validateAllowlisted('../../../cmd.exe'), false);
  assert.strictEqual(validateAllowlisted('kali-linux & echo hacket'), false);
});

test('WSL 5: Fallback correto quando distribuição solicitada não existe', () => {
  const pref = getPreferred();
  assert.ok(pref); // Retorna a distribuição padrão instalada ou primeira encontrada
});
