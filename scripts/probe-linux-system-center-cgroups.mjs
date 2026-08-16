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
const wslExe = `${process.env.WINDIR || 'C:\\Windows'}\\System32\\wsl.exe`;
if (!url || !distribution || !corePath || !username || !password) { console.error('LINUX_SYSTEM_CENTER_PROBE_ARGS_INVALID'); process.exit(2); }

let browser = null;
const checks = [];
let trackedGuestPids = [];
let linuxPidInt = 0;
let linuxPidTerm = 0;
let cgroupReadOnlyValidated = false;
let cgroupV2Mounted = false;

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
async function writeReport(value){await fs.mkdir(path.dirname(output),{recursive:true});await fs.writeFile(output,`${JSON.stringify(value,null,2)}\n`);}
async function waitForTerminalOutput(pane, token, timeout=8000){await pane.locator('.xterm-rows').filter({hasText:token}).first().waitFor({state:'visible',timeout});}
async function typeCommand(page,pane,command,expect){const input=pane.locator('.xterm-helper-textarea');await input.focus();await page.keyboard.type(command);await page.keyboard.press('Enter');if(expect)await waitForTerminalOutput(pane,expect);}
async function openStartApp(page,name){await page.getByTitle('Iniciar').click();const search=page.locator('.start-search-input');await search.fill(name);await page.locator('.start-app-btn').filter({hasText:name}).first().click();}
async function signalRow(page,center,query,signal){
  const search=center.locator('input[placeholder^="Pesquisar nome"]').first(); await search.fill(query);
  const row=center.locator('tr[data-linux-pid]').filter({hasText:query}).first(); await row.waitFor({state:'visible',timeout:12000});
  const pid=Number(await row.getAttribute('data-linux-pid')); if(!Number.isInteger(pid)||pid<=1)throw new Error('LINUX_PROCESS_PID_INVALID'); await row.click();
  page.once('dialog', dialog=>dialog.accept()); await center.getByRole('button',{name:signal,exact:true}).click(); await row.waitFor({state:'detached',timeout:12000}); return pid;
}

try {
  browser=await chromium.launch({headless:false,channel:process.env.CLOUDOS_SYSTEM_CENTER_BROWSER_CHANNEL||'msedge'});
  const page=await browser.newPage({viewport:{width:1500,height:930}}); await page.goto(url,{waitUntil:'domcontentloaded',timeout:30000});
  const lock=page.locator('.cloudos-lock-screen'); await lock.waitFor({state:'visible',timeout:30000}); await page.keyboard.press('Space');
  await page.locator('#login-username').fill(username); await page.locator('#login-password').fill(password); await page.getByRole('button',{name:'Entrar',exact:true}).click(); await page.locator('.taskbar').waitFor({state:'visible',timeout:30000}); checks.push('authenticated-desktop');

  await openStartApp(page,'CloudOS Terminal');
  const terminal=page.locator(`.terminal-pane[data-backend-mode="wsl-core-v2"][data-terminal-state="connected"][data-distribution="${distribution}"]`).first(); await terminal.waitFor({state:'visible',timeout:30000}); checks.push('terminal-wsl-core-v2');
  await typeCommand(page,terminal,'sleep 73'); await page.waitForTimeout(500);

  await openStartApp(page,'Gerenciador de Tarefas');
  const center=page.locator('.system-center[data-system-center-source="linux-real"]').last(); await center.waitFor({state:'visible',timeout:30000});
  await center.getByText('WSL Core v2',{exact:true}).waitFor({state:'visible',timeout:30000}); checks.push('system-center-linux-real');
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

  await writeReport({passed:true,physicalValidation:true,visibleSystemCenter:true,distribution,mode:'wsl-core-v2',protocol:2,protection:'aes-256-gcm-seq',checks,linuxPidInt,linuxPidTerm,cgroupReadOnlyValidated,cgroupV2Mounted,trackedGuestPids});
} catch(error) {
  await writeReport({passed:false,physicalValidation:true,visibleSystemCenter:true,distribution,checks,linuxPidInt,linuxPidTerm,cgroupReadOnlyValidated,cgroupV2Mounted,trackedGuestPids,errorCode:String(error?.message||error?.name||'LINUX_SYSTEM_CENTER_PROBE_FAILED').slice(0,180)});
  console.error(error?.message||'LINUX_SYSTEM_CENTER_PROBE_FAILED'); process.exitCode=1;
} finally { await browser?.close().catch(()=>{}); }
