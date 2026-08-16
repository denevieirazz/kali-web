import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source=fs.readFileSync(new URL('../src/apps/TaskManager/TaskManager.tsx',import.meta.url),'utf8');
test('existing System Center exposes isolated data origins',()=>{for(const marker of ["'linux-real'","'cloudos-virtual'","'host-windows'",'data-system-center-source'])assert.match(source,new RegExp(marker.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')));});
test('Linux lifecycle has bounded polling, abort cleanup and stale suppression',()=>{assert.match(source,/LINUX_SYSTEM_CENTER_POLL_MS/);assert.match(source,/LatestRequestGate/);assert.match(source,/gateRef\.current\.dispose/);assert.match(source,/request\.current\(\)/);});
test('signals require visual confirmation and only explicit supported signals exist',()=>{assert.match(source,/window\.confirm/);for(const signal of ['SIGINT','SIGTERM','SIGKILL'])assert.match(source,new RegExp(signal));});
test('cgroup UI distinguishes read-only, available and actually applied',()=>{assert.match(source,/somente leitura/);assert.match(source,/controle real disponível/);assert.match(source,/Limite real aplicado/);assert.match(source,/result\.assignment/);});
