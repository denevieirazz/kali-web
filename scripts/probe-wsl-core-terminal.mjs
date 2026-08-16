import fs from 'node:fs/promises';
import path from 'node:path';
import { createWslCoreTerminalSession } from '../backend/src/terminal/wslCoreAdapter.js';

const args = new Map();
for (let index = 2; index + 1 < process.argv.length; index += 2) {
  if (process.argv[index].startsWith('--')) args.set(process.argv[index].slice(2), process.argv[index + 1]);
}
const distribution = args.get('distro');
const core = args.get('core');
const output = path.resolve(args.get('output') || 'test-results/wsl-core-secure-terminal/node-terminal-validation.json');
if (!distribution || !core) {
  console.error('Usage: node probe-wsl-core-terminal.mjs --distro <name> --core <linux-path> [--output <json-path>]');
  process.exit(2);
}

process.env.CLOUDOS_WSL_CORE_FOUNDATION = '1';
process.env.CLOUDOS_WSL_CORE_TERMINAL = '1';
process.env.CLOUDOS_WSL_CORE_TERMINAL_FALLBACK = '0';
process.env.CLOUDOS_WSL_CORE_LINUX_PATH = core;

let session = null;
let outputText = '';
let exitDetail = null;
const checks = [];
try {
  session = await createWslCoreTerminalSession({
    distribution,
    linuxCorePath: core,
    rows: 24,
    cols: 80,
    onOutput: (data) => { outputText += data; },
    onExit: (detail) => { exitDetail = detail; }
  });
  if (session.protocol !== 2 || session.protection !== 'aes-256-gcm-seq') throw new Error('CHANNEL_PROTECTION_MISMATCH');
  checks.push('backend-adapter-protected-channel-v2');

  await session.resize(100, 30);
  checks.push('terminal-resize');
  await session.input("printf 'cloudos-terminal-adapter-v2-ok\\n'\n");
  const deadline = Date.now() + 5000;
  while (!outputText.includes('cloudos-terminal-adapter-v2-ok') && Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  if (!outputText.includes('cloudos-terminal-adapter-v2-ok')) throw new Error('TERMINAL_OUTPUT_NOT_OBSERVED');
  checks.push('terminal-input-output');

  await session.input('exit\n');
  exitDetail = await session.waitForExit(5000);
  checks.push('terminal-exit');
  await session.close();
  checks.push('terminal-shutdown-cleanup');

  await fs.mkdir(path.dirname(output), { recursive: true });
  await fs.writeFile(output, JSON.stringify({
    passed: true,
    physicalValidation: true,
    protocol: session.protocol,
    protection: session.protection,
    distribution,
    corePid: session.corePid,
    terminalPid: session.terminalPid,
    exitCode: exitDetail?.exitCode ?? null,
    signal: exitDetail?.signal || '',
    checks,
    databaseTouched: false,
    wslMutated: false,
    elevationRequested: false
  }, null, 2) + '\n');
  console.log(output);
} catch (error) {
  if (session) {
    try { await session.close(); } catch {}
  }
  await fs.mkdir(path.dirname(output), { recursive: true });
  await fs.writeFile(output, JSON.stringify({
    passed: false,
    physicalValidation: true,
    protocol: 2,
    protection: 'aes-256-gcm-seq',
    distribution,
    corePid: session?.corePid || 0,
    terminalPid: session?.terminalPid || 0,
    checks,
    errorCode: error?.code || error?.message || error?.name || 'TERMINAL_PROBE_FAILED',
    databaseTouched: false,
    wslMutated: false,
    elevationRequested: false
  }, null, 2) + '\n');
  console.error(error?.code || error?.message || 'TERMINAL_PROBE_FAILED');
  process.exit(1);
}
