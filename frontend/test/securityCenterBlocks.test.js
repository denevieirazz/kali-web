import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = relativePath => readFileSync(new URL(relativePath, import.meta.url), 'utf8');

test('Kali Tool Center opens through the beginner-first Security Center', () => {
  const registry = read('../src/core/appRegistry.ts');
  const center = read('../src/apps/SecurityCenter/SecurityCenter.tsx');

  assert.match(registry, /'kali-tool-center': lazy\(\(\) => import\('\.\.\/apps\/SecurityCenter\/SecurityCenter'\)\)/);
  assert.match(center, /Um botão\. Uma função\./);
  assert.match(center, /Começar assessment/);
  assert.match(center, /<KaliToolCenter \/>/);
  assert.match(center, /Voltar para os blocos/);
});

test('Security Center exposes many small task blocks', () => {
  const center = read('../src/apps/SecurityCenter/SecurityCenter.tsx');
  for (const label of [
    'Assessment de rede',
    'Diagnosticar um IP',
    'Saúde do Wi‑Fi',
    'Proteção deste PC',
    'Consultar DNS',
    'Analisar um site',
    'Verificar ambiente',
    'Preparar Linux / Kali',
    'Terminal CloudOS',
    'Monitorar o PC',
    'Instalar dependência',
    'Abrir evidências',
    'Workspace do projeto',
  ]) {
    assert.match(center, new RegExp(label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  }
  const blockCount = (center.match(/id: '/g) || []).length;
  assert.ok(blockCount >= 14, `expected at least 14 task blocks, got ${blockCount}`);
});

test('block launcher cannot become arbitrary command execution', () => {
  const center = read('../src/apps/SecurityCenter/SecurityCenter.tsx');
  const combined = `${center}\n${read('../src/apps/WebInspector/WebInspector.tsx')}`;

  assert.doesNotMatch(combined, /\/api\/security\/(?:execute|run|command|shell)/i);
  assert.doesNotMatch(center, /\b(?:child_process|spawn|execFile|execSync|shellCommand|argv)\b/);
  assert.match(center, /launchWorkflowApp\(block\.appId\)/);
  assert.match(center, /não executam exploit, brute force ou bypass automático/i);
});
