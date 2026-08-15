import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = relativePath => readFileSync(new URL(relativePath, import.meta.url), 'utf8');

test('App remains a composition root instead of reaching into kernel internals', () => {
  const app = read('../src/App.tsx');
  assert.doesNotMatch(app, /kernel\s+as\s+any/);
  assert.doesNotMatch(app, /\._resources|\._user|\._emitSystemSnapshot/);
  assert.match(app, /useShellWindows/);
  assert.match(app, /useViewportSize/);
  assert.ok(app.split('\n').length < 180, 'App.tsx should stay focused on composition');
});

test('kernel facade installs one centralized hardening boundary', () => {
  const facade = read('../src/core/kernel.ts');
  const hardening = read('../src/core/kernelHardening.ts');
  assert.match(facade, /kernelLegacy/);
  assert.match(facade, /installKernelHardening\(kernel\)/);
  assert.match(hardening, /reconcileActiveWindow/);
  assert.match(hardening, /clearRunQueues/);
  assert.match(hardening, /stopResourceLoop/);
  assert.match(hardening, /SHELL_MEMORY_TARGETS/);
});

test('global design system has no network font dependency and supports reduced motion', () => {
  const css = read('../src/index.css');
  assert.doesNotMatch(css, /fonts\.googleapis\.com/);
  assert.match(css, /prefers-reduced-motion/);
  assert.match(css, /data-theme='light'/);
  assert.match(css, /cloudos-window-loading/);
});

test('window renderer isolates lazy application rerenders', () => {
  const renderer = read('../src/components/Window/WindowRenderer.tsx');
  assert.match(renderer, /memo\(function RenderedWindow/);
  assert.match(renderer, /Carregando aplicativo/);
});

test('api client forwards and cleans caller cancellation signals', () => {
  const client = read('../src/services/apiClient.ts');
  assert.match(client, /signal: externalSignal/);
  assert.match(client, /addEventListener\('abort', forwardExternalAbort/);
  assert.match(client, /removeEventListener\('abort', forwardExternalAbort/);
  assert.match(client, /finally/);
});

test('Environment Doctor uses the shared design system instead of inline styles', () => {
  const doctor = read('../src/apps/EnvDoctor/EnvDoctor.tsx');
  assert.doesNotMatch(doctor, /style=\{\{/);
  assert.match(doctor, /Saúde do Sistema/);
  assert.match(doctor, /nativeHostBridge\.available/);
});
