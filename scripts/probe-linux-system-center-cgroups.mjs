import fs from 'node:fs/promises';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { chromium } from '@playwright/test';

const args = new Map();
for (let i = 2; i + 1 < process.argv.length; i += 2) if (process.argv[i].startsWith('--')) args.set(process.argv[i].slice(2), process.argv[i + 1]);
const url = args.get('url');
const distribution = args.get('distro');
const corePath = args.get('core');
const username = args.get('username');
const password = args.get('password');
const output = path.resolve(args.get('output') || 'test-results/linux-system-center-cgroups-physical/visible-validation.json');
const outputDir = path.dirname(output);
const diagnosticOutput = path.join(outputDir, 'system-center-diagnostic.json');
const openedScreenshot = path.join(outputDir, 'system-center-opened.png');
const failureScreenshot = path.join(outputDir, 'system-center-failure.png');
const wslExe = `${process.env.WINDIR || 'C:\\Windows'}\\System32\\wsl.exe`;
if (!url || !distribution || !corePath || !username || !password) { console.error('LINUX_SYSTEM_CENTER_PROBE_ARGS_INVALID'); process.exit(2); }

let browser = null;
let page = null;
const checks = [];
const browserDiagnostics = { console: [], pageErrors: [] };
let trackedGuestPids = [];
let linuxPidInt = 0;
let linuxPidTerm = 0;
let cgroupReadOnlyValidated = false;
let cgroupV2Mounted = false;
let latestDiagnostic = null;

function safeText(value, limit = 320) {
  return String(value ?? '')
    .replace(/(?:authorization|password|passwd|secret|token|credential|jwt|nonce)\s*[:=]\s*\S+/gi, '$1=[redacted]')
    .replace(/[A-Za-z0-9+/]{48,}={0,2}/g, '[redacted]')
    .replace(/[\u0000-\u001f\u007f]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, limit);
}
function pushBounded(target, value, limit = 30) { target.push(value); if (target.length > limit) target.splice(0, target.length - limit); }
function wsl(argv) { return execFileSync(wslExe, ['--distribution', distribution, '--exec', ...argv], { encoding: 'utf8', windowsHide: true }); }
function rows() {
  return wsl(['/bin/ps', '-eo', 'pid=,ppid=,args=']).split(/\r?\n/).map(line => {
    const match = line.trim().match(/^(\d+)\s+(\d+)\s+(.*)$/); return match ? { pid:Number(match[1]), ppid:Number(match[2]), args:match[3] } : null;
  }).filter(Boolean);
}
function collectCoreTree() {
  const all = rows(); const roots = all.filter(row => row.args.includes(corePath) && /\sserve(?:\s|$)/.test(row.args)).map(row=>row.pid); const selected=new Set(roots);
  let changed=true; while(changed){changed=false;for(const row of all)if(selected.has(row.ppid)&&!selected.has(row.pid)){selected.add(row.pid);changed=true;}}
  return [...selected].sort((a,b)=>a-b);
}
async function writeReport(value){await fs.mkdir(outputDir,{recursive:true});await fs.writeFile(output,`${JSON.stringify(value,null,2)}\n`);}
async function writeDiagnostic(value){await fs.mkdir(outputDir,{recursive:true});latestDiagnostic=value;await fs.writeFile(diagnosticOutput,`${JSON.stringify(value,null,2)}\n`);}
async function waitForTerminalOutput(pane, token, timeout=8000){await pane.locator('.xterm-rows').filter({hasText:token}).first().waitFor({state:'visible',timeout});}
async function typeCommand(currentPage,pane,command,expect){const input=pane.locator('.xterm-helper-textarea');await input.focus();await currentPage.keyboard.type(command);await currentPage.keyboard.press('Enter');if(expect)await waitForTerminalOutput(pane,expect);}
async function openStartApp(currentPage,name){await currentPage.getByTitle('Iniciar').click();const search=currentPage.locator('.start-search-input');await search.fill(name);const match=currentPage.locator('.start-app-btn').filter({hasText:name}).first();await match.waitFor({state:'visible',timeout:10000});await match.click();}

async function safeApiSnapshot(currentPage, endpoint) {
  try {
    const result = await currentPage.evaluate(async endpointValue => {
      const token = localStorage.getItem('cloudos_jwt_token');
      const runtime = window.__CLOUDOS_RUNTIME__ || {};
      const base = typeof runtime.apiBase === 'string' && runtime.apiBase ? runtime.apiBase : window.location.origin;
      const controller = new AbortController();
      const timer = window.setTimeout(() => controller.abort(), 6000);
      try {
        const response = await fetch(new URL(endpointValue, base).href, {
          headers: token ? { Authorization: `Bearer ${token}`, Accept: 'application/json' } : { Accept: 'application/json' },
          signal: controller.signal,
        });
        let body = null;
        try { body = await response.json(); } catch {}
        return { status: response.status, ok: response.ok, body };
      } catch (error) {
        return { status: 0, ok: false, fetchError: error instanceof Error ? error.name : 'FETCH_FAILED' };
      } finally { window.clearTimeout(timer); }
    }, endpoint);
    const body = result?.body && typeof result.body === 'object' ? result.body : {};
    if (endpoint.includes('/status')) {
      return {
        status: Number(result?.status || 0), ok: result?.ok === true,
        enabled: body.enabled === true, available: body.available === true, fallbackAllowed: body.fallbackAllowed === true,
        distribution: typeof body.distribution === 'string' ? safeText(body.distribution, 80) : null,
        wsl2: body.wsl2 === true, corePathConfigured: body.corePathConfigured === true,
        protocol: Number.isInteger(body.protocol) ? body.protocol : null,
        protection: typeof body.protection === 'string' ? safeText(body.protection, 64) : null,
        source: typeof body.source === 'string' ? safeText(body.source, 32) : null,
        mode: typeof body.mode === 'string' ? safeText(body.mode, 32) : null,
        reason: typeof body.reason === 'string' ? safeText(body.reason, 96) : null,
        fetchError: typeof result?.fetchError === 'string' ? safeText(result.fetchError, 64) : null,
      };
    }
    return {
      status: Number(result?.status || 0), ok: result?.ok === true,
      source: typeof body.source === 'string' ? safeText(body.source, 32) : null,
      mode: typeof body.mode === 'string' ? safeText(body.mode, 32) : null,
      total: Number.isInteger(body.total) ? body.total : null,
      page: Number.isInteger(body.page) ? body.page : null,
      pageSize: Number.isInteger(body.pageSize) ? body.pageSize : null,
      truncated: body.truncated === true,
      errorCode: typeof body.error?.code === 'string' ? safeText(body.error.code, 96) : null,
      fetchError: typeof result?.fetchError === 'string' ? safeText(result.fetchError, 64) : null,
    };
  } catch (error) {
    return { status: 0, ok: false, fetchError: safeText(error?.name || 'SNAPSHOT_FAILED', 64) };
  }
}

async function collectUiSnapshot(currentPage) {
  const openWindows = await currentPage.evaluate(() => {
    try {
      const windows = window.kernel?.getWindows?.() || [];
      return windows.filter(item => !item?.isSystem).map(item => ({
        id: String(item?.id || '').slice(0, 80), appId: String(item?.appId || '').slice(0, 80), title: String(item?.title || '').slice(0, 120),
        isMinimized: item?.isMinimized === true, isActive: item?.isActive === true,
      }));
    } catch { return []; }
  });
  const roots = currentPage.locator('.system-center');
  const rootCount = await roots.count();
  const centers = [];
  for (let index = 0; index < Math.min(rootCount, 4); index += 1) {
    const root = roots.nth(index);
    const source = await root.getAttribute('data-system-center-source').catch(() => null);
    const sourceSelect = root.locator('select[aria-label="Origem dos dados"]');
    const selectedSource = await sourceSelect.count() ? await sourceSelect.inputValue().catch(() => null) : null;
    const alert = root.locator('[role="alert"]').first();
    const alertText = await alert.count() ? safeText(await alert.innerText().catch(() => ''), 500) : '';
    centers.push({ source, selectedSource, alertText, text: safeText(await root.innerText().catch(() => ''), 2400) });
  }
  return { openWindows, systemCenterRootCount: rootCount, centers };
}

async function captureDiagnostics(currentPage, stage, screenshotPath, error = null) {
  const [ui, apiStatus, apiProcesses] = await Promise.all([
    collectUiSnapshot(currentPage),
    safeApiSnapshot(currentPage, '/api/system/linux/status'),
    safeApiSnapshot(currentPage, '/api/system/linux/processes?page=1&pageSize=1'),
  ]);
  let screenshotSaved = false;
  try { await currentPage.screenshot({ path: screenshotPath, fullPage: true }); screenshotSaved = true; } catch {}
  const diagnostic = {
    capturedAt: new Date().toISOString(), stage, distribution,
    errorCode: error ? safeText(error?.message || error?.name || error, 180) : null,
    screenshot: screenshotSaved ? path.basename(screenshotPath) : null,
    openWindows: ui.openWindows,
    systemCenterRootCount: ui.systemCenterRootCount,
    systemCenters: ui.centers,
    safeApi: { status: apiStatus, processes: apiProcesses },
    browser: { console: [...browserDiagnostics.console], pageErrors: [...browserDiagnostics.pageErrors] },
  };
  await writeDiagnostic(diagnostic);
  return diagnostic;
}

async function waitForLinuxReadiness(currentPage, center, timeoutMs = 30000) {
  const started = Date.now();
  let preTimeoutCaptured = false;
  let lastStatus = null;
  while (Date.now() - started < timeoutMs) {
    lastStatus = await safeApiSnapshot(currentPage, '/api/system/linux/status');
    const source = await center.getAttribute('data-system-center-source').catch(() => null);
    const selected = await center.locator('select[aria-label="Origem dos dados"]').inputValue().catch(() => null);
    if (source !== 'linux-real' || selected !== 'linux-real') throw new Error(`LINUX_SOURCE_NOT_SELECTED:${source || 'none'}:${selected || 'none'}`);
    if (lastStatus.available === true) {
      const processApi = await safeApiSnapshot(currentPage, '/api/system/linux/processes?page=1&pageSize=1');
      if (!processApi.ok) throw new Error(`LINUX_PROCESS_API_UNAVAILABLE:${processApi.errorCode || processApi.status || processApi.fetchError || 'unknown'}`);
      const successText = center.getByText('WSL Core v2', { exact: true });
      if (await successText.count() && await successText.first().isVisible().catch(() => false)) return { status: lastStatus, processes: processApi };
    }
    if (!preTimeoutCaptured && Date.now() - started >= Math.max(5000, timeoutMs - 10000)) {
      await captureDiagnostics(currentPage, 'linux-readiness-pending-before-timeout', failureScreenshot);
      preTimeoutCaptured = true;
    }
    await currentPage.waitForTimeout(750);
  }
  throw new Error(`LINUX_SYSTEM_CENTER_READINESS_TIMEOUT:${lastStatus?.reason || lastStatus?.fetchError || lastStatus?.status || 'unknown'}`);
}

async function signalRow(currentPage,center,query,signal){
  const search=center.locator('input[placeholder^="Pesquisar nome"]').first(); await search.fill(query);
  const row=center.locator('tr[data-linux-pid]').filter({hasText:query}).first(); await row.waitFor({state:'visible',timeout:12000});
  const pid=Number(await row.getAttribute('data-linux-pid')); if(!Number.isInteger(pid)||pid<=1)throw new Error('LINUX_PROCESS_PID_INVALID'); await row.click();
  currentPage.once('dialog', dialog=>dialog.accept()); await center.getByRole('button',{name:signal,exact:true}).click(); await row.waitFor({state:'detached',timeout:12000}); return pid;
}

try {
  await fs.mkdir(outputDir,{recursive:true});
  browser=await chromium.launch({headless:false,channel:process.env.CLOUDOS_SYSTEM_CENTER_BROWSER_CHANNEL||'msedge'});
  page=await browser.newPage({viewport:{width:1500,height:930}});
  page.on('console', message => { if (['error','warning'].includes(message.type())) pushBounded(browserDiagnostics.console, { type: message.type(), text: safeText(message.text(), 320) }); });
  page.on('pageerror', error => pushBounded(browserDiagnostics.pageErrors, safeText(error?.message || error, 320)));
  await page.goto(url,{waitUntil:'domcontentloaded',timeout:30000});
  const lock=page.locator('.cloudos-lock-screen'); await lock.waitFor({state:'visible',timeout:30000}); await page.keyboard.press('Space');
  await page.locator('#login-username').fill(username); await page.locator('#login-password').fill(password); await page.getByRole('button',{name:'Entrar',exact:true}).click(); await page.locator('.taskbar').waitFor({state:'visible',timeout:30000}); checks.push('authenticated-desktop');

  await openStartApp(page,'CloudOS Terminal');
  const terminal=page.locator(`.terminal-pane[data-backend-mode="wsl-core-v2"][data-terminal-state="connected"][data-distribution="${distribution}"]`).first(); await terminal.waitFor({state:'visible',timeout:30000}); checks.push('terminal-wsl-core-v2');
  await typeCommand(page,terminal,'sleep 73'); await page.waitForTimeout(500);

  await openStartApp(page,'Gerenciador de Tarefas');
  const taskWindow=page.locator('.window',{has:page.locator('.window-title',{hasText:'Gerenciador de Tarefas'})}).last();
  try { await taskWindow.waitFor({state:'visible',timeout:10000}); } catch (error) { await captureDiagnostics(page,'task-manager-window-missing',failureScreenshot,error); throw error; }
  const windowIdentity=await page.evaluate(() => {
    const windows=window.kernel?.getWindows?.()||[]; const matches=windows.filter(item=>item?.title==='Gerenciador de Tarefas'&&!item?.isSystem); const selected=matches.at(-1);
    return selected ? { appId:selected.appId,title:selected.title } : null;
  });
  if(windowIdentity?.appId!=='task-manager'){await captureDiagnostics(page,'wrong-task-manager-window',failureScreenshot,new Error(`WRONG_APP_ID:${windowIdentity?.appId||'none'}`));throw new Error(`WRONG_APP_ID:${windowIdentity?.appId||'none'}`);}
  checks.push('task-manager-app-id');

  const center=taskWindow.locator('.system-center').first();
  try { await center.waitFor({state:'visible',timeout:10000}); } catch (error) { await captureDiagnostics(page,'system-center-root-missing',failureScreenshot,error); throw error; }
  const sourceSelect=center.locator('select[aria-label="Origem dos dados"]');
  await sourceSelect.waitFor({state:'visible',timeout:5000});
  if((await sourceSelect.inputValue())!=='linux-real')await sourceSelect.selectOption('linux-real');
  if((await center.getAttribute('data-system-center-source'))!=='linux-real')throw new Error('LINUX_SOURCE_ATTRIBUTE_NOT_APPLIED');
  checks.push('system-center-linux-source-selected');
  await captureDiagnostics(page,'system-center-opened',openedScreenshot);

  let readiness;
  try { readiness=await waitForLinuxReadiness(page,center,30000); } catch(error) { await captureDiagnostics(page,'linux-readiness-failed',failureScreenshot,error); throw error; }
  if(readiness.status.protocol!==2||readiness.status.protection!=='aes-256-gcm-seq'||readiness.status.mode!=='wsl-core-v2')throw new Error('LINUX_STATUS_PROTOCOL_MISMATCH');
  checks.push('system-center-linux-real');

  const search=center.locator('input[placeholder^="Pesquisar nome"]').first(); await search.fill('sleep 73');
  const row73=center.locator('tr[data-linux-pid]').filter({hasText:'sleep 73'}).first(); await row73.waitFor({state:'visible',timeout:12000});
  linuxPidInt=Number(await row73.getAttribute('data-linux-pid')); if(!Number.isInteger(linuxPidInt)||linuxPidInt<=1)throw new Error('REAL_PROCESS_NOT_OBSERVED');
  if(!await row73.getByText(/UID \d+/).count())throw new Error('REAL_PROCESS_UID_MISSING'); checks.push('real-process-pid-metrics');

  const stateSelect=center.locator('.sc-toolbar select').first(); await stateSelect.selectOption('S'); await row73.waitFor({state:'visible',timeout:8000}); checks.push('state-filter'); await stateSelect.selectOption('');
  await center.getByRole('button',{name:'Atualizar',exact:true}).click(); await row73.waitFor({state:'visible',timeout:8000}); checks.push('manual-refresh');

  await center.getByRole('button',{name:'Desempenho',exact:true}).click(); const performance=center.locator('[data-cgroup-readonly]').first(); await performance.waitFor({state:'visible',timeout:10000});
  cgroupReadOnlyValidated=(await performance.getAttribute('data-cgroup-readonly'))==='true'; if(!cgroupReadOnlyValidated)throw new Error('CGROUP_READ_ONLY_NOT_ENFORCED');
  const control=performance.locator('[data-cgroup-control-available]').first(); if((await control.getAttribute('data-cgroup-control-available'))!=='false')throw new Error('CGROUP_CONTROL_UNEXPECTED_IN_READ_ONLY_MODE');
  cgroupV2Mounted=(await performance.getByText('Detectado',{exact:true}).count())>0; checks.push('cgroup-read-only');

  await center.getByRole('button',{name:'Processos',exact:true}).click();
  linuxPidInt=await signalRow(page,center,'sleep 73','SIGINT'); checks.push('sigint');
  await typeCommand(page,terminal,"printf 'system-center-after-int-ok\\n'",'system-center-after-int-ok');
  await typeCommand(page,terminal,'sleep 74'); await page.waitForTimeout(500); linuxPidTerm=await signalRow(page,center,'sleep 74','SIGTERM'); checks.push('sigterm');
  await typeCommand(page,terminal,"printf 'system-center-after-term-ok\\n'",'system-center-after-term-ok');
  await typeCommand(page,terminal,'sleep 75'); await page.waitForTimeout(500);

  trackedGuestPids=collectCoreTree(); if(trackedGuestPids.length<3)throw new Error('GUEST_CORE_TREE_NOT_OBSERVED'); checks.push('core-tree-tracked');
  const centerWindow=center.locator('xpath=ancestor::div[contains(concat(" ", normalize-space(@class), " "), " window ")][1]'); await centerWindow.locator('.window-btn.close').click(); await center.waitFor({state:'detached',timeout:10000}); checks.push('system-center-unmount');
  const terminalWindow=terminal.locator('xpath=ancestor::div[contains(concat(" ", normalize-space(@class), " "), " window ")][1]'); await terminalWindow.locator('.window-btn.close').click(); await terminal.waitFor({state:'detached',timeout:10000}); checks.push('terminal-cleanup-requested');

  await writeReport({passed:true,physicalValidation:true,visibleSystemCenter:true,distribution,mode:'wsl-core-v2',protocol:2,protection:'aes-256-gcm-seq',checks,linuxPidInt,linuxPidTerm,cgroupReadOnlyValidated,cgroupV2Mounted,trackedGuestPids,diagnosticFile:path.basename(diagnosticOutput),openedScreenshot:path.basename(openedScreenshot)});
} catch(error) {
  if(page)await captureDiagnostics(page,'probe-failed',failureScreenshot,error).catch(()=>{});
  await writeReport({passed:false,physicalValidation:true,visibleSystemCenter:Boolean(latestDiagnostic?.systemCenterRootCount),distribution,checks,linuxPidInt,linuxPidTerm,cgroupReadOnlyValidated,cgroupV2Mounted,trackedGuestPids,errorCode:safeText(error?.message||error?.name||'LINUX_SYSTEM_CENTER_PROBE_FAILED',180),diagnosticFile:path.basename(diagnosticOutput),failureScreenshot:path.basename(failureScreenshot)});
  console.error(error?.message||'LINUX_SYSTEM_CENTER_PROBE_FAILED'); process.exitCode=1;
} finally { await browser?.close().catch(()=>{}); }
