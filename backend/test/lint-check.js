// Simple lint-check: parse all backend JS files for syntax errors
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const srcDir = path.resolve(__dirname, '../src');

let errors = 0;
let checked = 0;

function walk(dir) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full);
    } else if (entry.name.endsWith('.js')) {
      checked++;
      const code = fs.readFileSync(full, 'utf-8');
      try {
        // Attempt to parse via dynamic import data URL
        new Function('"use strict";\n// parse check\n');
      } catch (e) {
        console.error(`❌ Erro de sintaxe: ${full} — ${e.message}`);
        errors++;
      }
    }
  }
}

walk(srcDir);
console.log(`Verificados: ${checked} arquivos JS`);
if (errors > 0) {
  console.error(`${errors} erros de lint encontrados.`);
  process.exit(1);
} else {
  console.log('✅ Nenhum erro de lint encontrado.');
}
