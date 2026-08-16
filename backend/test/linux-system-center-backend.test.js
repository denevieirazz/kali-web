import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const routes=fs.readFileSync(new URL('../src/system/routes.js',import.meta.url),'utf8');
const rpc=fs.readFileSync(new URL('../src/system/wslCoreRpcSession.js',import.meta.url),'utf8');
const service=fs.readFileSync(new URL('../src/system/linuxSystemCenterService.js',import.meta.url),'utf8');
const physicalProbe=fs.readFileSync(new URL('../../scripts/probe-linux-system-center-cgroups.mjs',import.meta.url),'utf8');
const goSystemCenter=fs.readFileSync(new URL('../../core/wsl/cloudos-core/internal/server/systemcenter.go',import.meta.url),'utf8');
const goLinuxProcesses=fs.readFileSync(new URL('../../core/wsl/cloudos-core/internal/linuxproc/linuxproc.go',import.meta.url),'utf8');
const frontendClient=fs.readFileSync(new URL('../../frontend/src/apps/TaskManager/linuxSystemCenterClient.ts',import.meta.url),'utf8');

test('backend requires existing auth and admin confirmation for destructive operations',()=>{assert.match(routes,/authenticateToken, requireAdmin/);assert.match(routes,/confirmed !== true/);assert.match(routes,/SIGINT.*SIGTERM.*SIGKILL/s);});
test('RPC session reuses approved secure codec and key derivation',()=>{assert.match(rpc,/SecureFrameCodec/);assert.match(rpc,/deriveChannelMaterial/);assert.match(rpc,/connectLoopbackWithReadiness/);assert.match(rpc,/parseBootstrapRecord/);assert.doesNotMatch(rpc,/createCipheriv|createDecipheriv/);});
test('RPC bootstrap never uses shell and cgroup control is explicit',()=>{assert.match(rpc,/shell:false/);assert.match(rpc,/--cgroup-control/);assert.match(service,/CLOUDOS_WSL_CORE_CGROUP_CONTROL === '1'/);});
test('fallback is explicit and audit is bounded without diagnostics',()=>{assert.match(service,/CLOUDOS_WSL_CORE_SYSTEM_CENTER_FALLBACK === '1'/);assert.match(service,/AUDIT_LIMIT = 100/);assert.doesNotMatch(service,/bootstrapDiagnostic/);});

test('wire contract keeps real Linux process identity and metrics field names stable',()=>{
  for(const field of ['pid','ppid','state','uid','user','name','cpuPercent','rssBytes','virtualBytes','threads','startTimeTicks','cgroup','protected']) assert.match(goLinuxProcesses,new RegExp(`json:\\"${field}`));
  for(const field of ['uptimeSeconds','load1','load5','load15','memoryTotalBytes','memoryAvailableBytes','processCount','cgroupCapabilities','resourceMetrics']) assert.match(goSystemCenter,new RegExp(`json:\\"${field}`));
  assert.match(routes,/source: 'linux-real', mode: 'wsl-core-v2', \.\.\.result/);
  assert.match(routes,/source: 'linux-real', mode: 'wsl-core-v2', \.\.\.\(await linuxSystemCenterService\.request\('system\.metrics'\)\)/);
});

test('frontend treats wire payloads as unknown until boundary normalization',()=>{
  assert.match(frontendClient,/apiClient<unknown>/);
  assert.match(frontendClient,/normalizeLinuxProcessPage/);
  assert.match(frontendClient,/normalizeLinuxMetrics/);
  assert.match(frontendClient,/normalizeLinuxStatus/);
});

test('physical System Center probe verifies exact app identity and Linux source instead of trusting success text',()=>{
  assert.match(physicalProbe,/appId!=='task-manager'/);
  assert.match(physicalProbe,/select\[aria-label="Origem dos dados"\]/);
  assert.match(physicalProbe,/selectOption\('linux-real'\)/);
  assert.match(physicalProbe,/data-system-center-source/);
  assert.match(physicalProbe,/LINUX_SOURCE_ATTRIBUTE_NOT_APPLIED/);
});

test('physical probe persists opened, pre-timeout and final failure evidence independently',()=>{
  for(const artifact of ['system-center-diagnostic.json','system-center-pretimeout-diagnostic.json','system-center-opened.png','system-center-pretimeout.png','system-center-failure.png']) assert.match(physicalProbe,new RegExp(artifact.replaceAll('.','\\.')));
  assert.match(physicalProbe,/linux-readiness-pending-before-timeout/);
  assert.match(physicalProbe,/preTimeoutScreenshot, null, preTimeoutDiagnosticOutput/);
  assert.match(physicalProbe,/openWindows/);
  assert.match(physicalProbe,/systemCenters/);
  assert.match(physicalProbe,/safeApi:\s*\{\s*status:\s*apiStatus,\s*processes:\s*apiProcesses\s*\}/s);
});

test('physical probe never persists the JWT value or raw process payload',()=>{
  assert.match(physicalProbe,/localStorage\.getItem\('cloudos_jwt_token'\)/);
  assert.match(physicalProbe,/Authorization: `Bearer \$\{token\}`/);
  assert.doesNotMatch(physicalProbe,/token\s*:\s*token/);
  assert.doesNotMatch(physicalProbe,/processes:\s*body\.processes/);
});
