import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const srcDirectory = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../src');
const files = [];

function collect(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) collect(fullPath);
    else if (entry.name.endsWith('.js')) files.push(fullPath);
  }
}

collect(srcDirectory);
const failures = [];
for (const file of files) {
  const result = spawnSync(process.execPath, ['--check', file], { encoding: 'utf8', shell: false });
  if (result.status !== 0) failures.push(`${file}\n${result.stderr || result.stdout}`);
}

console.log(`Verificados: ${files.length} arquivos JavaScript`);
if (failures.length) {
  console.error(failures.join('\n'));
  process.exit(1);
}
console.log('Nenhum erro de sintaxe encontrado.');
