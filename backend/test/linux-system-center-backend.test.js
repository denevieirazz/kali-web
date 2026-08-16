import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const routes=fs.readFileSync(new URL('../src/system/routes.js',import.meta.url),'utf8');
const rpc=fs.readFileSync(new URL('../src/system/wslCoreRpcSession.js',import.meta.url),'utf8');
const service=fs.readFileSync(new URL('../src/system/linuxSystemCenterService.js',import.meta.url),'utf8');
test('backend requires existing auth and admin confirmation for destructive operations',()=>{assert.match(routes,/authenticateToken, requireAdmin/);assert.match(routes,/confirmed !== true/);assert.match(routes,/SIGINT.*SIGTERM.*SIGKILL/s);});
test('RPC session reuses approved secure codec and key derivation',()=>{assert.match(rpc,/SecureFrameCodec/);assert.match(rpc,/deriveChannelMaterial/);assert.match(rpc,/connectLoopbackWithReadiness/);assert.match(rpc,/parseBootstrapRecord/);assert.doesNotMatch(rpc,/createCipheriv|createDecipheriv/);});
test('RPC bootstrap never uses shell and cgroup control is explicit',()=>{assert.match(rpc,/shell:false/);assert.match(rpc,/--cgroup-control/);assert.match(service,/CLOUDOS_WSL_CORE_CGROUP_CONTROL === '1'/);});
test('fallback is explicit and audit is bounded without diagnostics',()=>{assert.match(service,/CLOUDOS_WSL_CORE_SYSTEM_CENTER_FALLBACK === '1'/);assert.match(service,/AUDIT_LIMIT = 100/);assert.doesNotMatch(service,/bootstrapDiagnostic/);});
