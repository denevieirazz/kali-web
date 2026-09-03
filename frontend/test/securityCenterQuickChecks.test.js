import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = relativePath => readFileSync(new URL(relativePath, import.meta.url), 'utf8');

const center = read('../src/apps/SecurityCenter/SecurityCenter.tsx');
const quick = read('../src/apps/SecurityCenter/QuickLocalChecks.tsx');
const knowledge = read('../src/apps/SecurityCenter/portKnowledge.ts');
const registry = read('../src/core/appRegistry.ts');

test('Kali Tool Center opens the beginner-first Security Center without adding a new Start app', () => {
  assert.match(registry, /'kali-tool-center': lazy\(\(\) => import\('\.\.\/apps\/SecurityCenter\/SecurityCenter'\)\)/);
  assert.match(center, /Um botão\. Uma função\./);
  assert.match(center, /<QuickLocalChecks \/>/);
  assert.match(center, /Voltar para os blocos/);
  assert.match(center, /<KaliToolCenter \/>/);
});

test('Security Center exposes a large set of small dedicated blocks', () => {
  for (const title of [
    'Assessment de rede', 'Diagnosticar um IP', 'Saúde do Wi‑Fi', 'Proteção deste PC',
    'Consultar DNS', 'Analisar um site', 'Abrir navegador', 'Verificar ambiente',
    'Preparar Linux / Kali', 'Terminal CloudOS', 'Monitorar o PC', 'Instalar dependência',
    'Abrir evidências', 'Workspace do projeto',
  ]) assert.match(center, new RegExp(title.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
});

test('quick local checks expose reviewed one-click profiles and full profile', () => {
  for (const preset of [
    'fullProfile', 'commonPorts', 'webSurface', 'remoteAccess', 'windowsServices',
    'fileSharing', 'databases', 'infrastructure', 'printersIot', 'development', 'mailServices',
  ]) assert.match(quick, new RegExp(`['"]${preset}['"]`));
  assert.match(quick, /Perfil completo local/);
  assert.match(quick, /Descobrir dispositivos da minha rede/);
  assert.match(quick, /Usar gateway/);
  assert.match(quick, /Usar este IP nos checks/);
  assert.match(quick, /Copiar explicado para IA/);
});

test('single-host checks combine surface scan with identity and connectivity diagnostics', () => {
  assert.match(quick, /\/api\/security\/tools\/network\/host\/diagnostics/);
  assert.match(quick, /Promise\.all\(\[scanPromise, diagnosticsPromise\]\)/);
  assert.match(quick, /Latência média/);
  assert.match(quick, /MAC/);
  assert.match(quick, /Nome PTR/);
  assert.match(quick, /Rota/);
  assert.match(quick, /Próximos passos deste host/);
  assert.match(quick, /hostDiagnostics/);
});

test('quick checks remain fixed-endpoint and do not expose arbitrary command execution', () => {
  assert.match(quick, /\/api\/security\/tools\/network\/scan/);
  assert.doesNotMatch(quick, /\/api\/security\/(?:execute|run|command|shell)/i);
  assert.doesNotMatch(quick, /\b(?:argv|spawn|execFile|execSync|shellCommand)\b/);
  assert.match(quick, /privateLocalOnly: true/);
  assert.match(quick, /arbitraryArguments: false/);
  assert.match(quick, /credentialAttacks: false/);
  assert.match(quick, /exploitAutomation: false/);
});

test('port explanation layer covers common web, Windows, remote, database and IoT services', () => {
  for (const needle of ['445:', '3389:', '22:', '443:', '6379:', '3306:', '5432:', '1883:', '9100:', '27017:']) {
    assert.match(knowledge, new RegExp(needle));
  }
  assert.match(knowledge, /explainPort/);
  assert.match(knowledge, /Confirme/);
});
