import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const requestedDirectories = process.argv.slice(2);
if (!requestedDirectories.length) {
  console.error('Informe ao menos um diretório de testes.');
  process.exit(2);
}

const files = requestedDirectories.flatMap((directory) => {
  const absolute = path.resolve(root, directory);
  return fs.readdirSync(absolute, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith('.test.js'))
    .map((entry) => path.join(absolute, entry.name));
});

const testRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'cloudos-test-run-'));
const testEnvironment = { ...process.env, NODE_ENV: 'test', CLOUDOS_TEST_ROOT: testRoot };
delete testEnvironment.CLOUDOS_DATA_DIR;
delete testEnvironment.DATABASE_PATH;
let result;
try {
  result = spawnSync(process.execPath, ['--test', ...files], {
    cwd: root,
    env: testEnvironment,
    stdio: 'inherit',
    shell: false
  });
} finally {
  fs.rmSync(testRoot, { recursive: true, force: true });
}

process.exit(result.status ?? 1);
