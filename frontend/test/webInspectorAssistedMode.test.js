import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = relativePath => readFileSync(new URL(relativePath, import.meta.url), 'utf8');

test('Web Inspector opens in beginner-first assisted mode', () => {
  const inspector = read('../src/apps/WebInspector/WebInspector.tsx');
  const coach = read('../src/apps/WebInspector/WebOperatorCoach.tsx');

  assert.match(inspector, /Modo Assistido/);
  assert.match(inspector, /Fazer análise guiada/);
  assert.match(inspector, /<WebOperatorCoach/);
  assert.match(coach, /O que você deve olhar primeiro/);
  assert.match(coach, /Por que importa:/);
  assert.match(coach, /Evidência:/);
  assert.match(coach, /Faça agora:/);
  assert.match(coach, /Explicar com IA/);
});

test('assisted score is triage-only and cannot masquerade as exploitability', () => {
  const coach = read('../src/apps/WebInspector/WebOperatorCoach.tsx');
  const guidance = read('../src/apps/WebInspector/webGuidance.ts');

  assert.match(coach, /não é probabilidade de exploração/i);
  assert.match(coach, /não é CVSS/i);
  assert.match(coach, /não confirma vulnerabilidade/i);
  assert.match(guidance, /Math\.min\(100, raw\)/);
  assert.match(guidance, /observada/i);
});

test('assisted Web Inspector adds guidance without arbitrary execution', () => {
  const inspector = read('../src/apps/WebInspector/WebInspector.tsx');
  const coach = read('../src/apps/WebInspector/WebOperatorCoach.tsx');
  const guidance = read('../src/apps/WebInspector/webGuidance.ts');
  const combined = `${inspector}\n${coach}\n${guidance}`;

  assert.doesNotMatch(combined, /\/api\/security\/(?:execute|run|command|shell)/i);
  assert.doesNotMatch(combined, /\b(?:child_process|spawn|execFile|execSync|Invoke-Expression)\b/);
  assert.match(inspector, /noExploitAutomation: true/);
  assert.match(inspector, /noCredentialAttacks: true/);
  assert.match(inspector, /noFuzzing: true/);
});
