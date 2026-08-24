import { execFile as execFileCallback } from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import { promisify } from 'node:util';
import {
  scanLinuxDesktopApps,
  toPublicLinuxDesktopApp,
} from '../backend/src/apps/linuxDesktopScanner.js';
import { WSL_EXE, safeChildEnvironment } from '../backend/src/wsl/distroService.js';

const execFileAsync = promisify(execFileCallback);

function option(name, fallback = '') {
  const index = process.argv.indexOf(name);
  return index >= 0 && process.argv[index + 1] ? process.argv[index + 1] : fallback;
}

function desktopFields(content) {
  const wanted = new Set(['Name', 'Exec', 'Icon', 'Categories', 'MimeType']);
  const fields = {};
  let inDesktopEntry = false;
  for (const rawLine of String(content || '').replace(/^\uFEFF/u, '').split(/\r?\n/u)) {
    const line = rawLine.trim();
    if (line.startsWith('[') && line.endsWith(']')) {
      inDesktopEntry = line === '[Desktop Entry]';
      continue;
    }
    if (!inDesktopEntry || !line || line.startsWith('#')) continue;
    const separator = rawLine.indexOf('=');
    if (separator <= 0) continue;
    const key = rawLine.slice(0, separator).trim();
    if (wanted.has(key)) fields[key] = rawLine.slice(separator + 1).trim();
  }
  return fields;
}

const distribution = option('--distribution', 'Ubuntu').trim();
const requestedName = option('--app', 'L3afpad').trim();
const packageName = option('--package', requestedName.toLocaleLowerCase('en-US')).trim();
const outputPath = path.resolve(option(
  '--output',
  'poc1-physical-evidence/automatic-app-integration/app-discovery-l3afpad.json',
));

if (!/^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$/u.test(packageName)) {
  throw new Error('PACKAGE_NAME_INVALID');
}

const apps = await scanLinuxDesktopApps(distribution, { force: true });
const app = apps.find((candidate) => candidate.name.toLocaleLowerCase('en-US') === requestedName.toLocaleLowerCase('en-US'));
if (!app) throw new Error(`APP_NOT_DISCOVERED:${requestedName}`);

const [{ stdout: desktopContent }, { stdout: packageVersion }] = await Promise.all([
  execFileAsync(WSL_EXE, ['--distribution', distribution, '--exec', 'cat', '--', app.desktopFile], {
    encoding: 'utf8',
    env: safeChildEnvironment(),
    timeout: 10_000,
    windowsHide: true,
    maxBuffer: 1024 * 1024,
  }),
  execFileAsync(WSL_EXE, [
    '--distribution', distribution, '--exec',
    'dpkg-query', '--show', '--showformat=${Status} ${Version}', '--', packageName,
  ], {
    encoding: 'utf8',
    env: safeChildEnvironment(),
    timeout: 10_000,
    windowsHide: true,
    maxBuffer: 64 * 1024,
  }),
]);

const publicApp = toPublicLinuxDesktopApp(app);
const evidence = {
  schemaVersion: 1,
  verdict: 'PASS',
  collectedAt: new Date().toISOString(),
  distribution,
  scanner: {
    roots: [
      '$XDG_DATA_HOME/applications',
      '~/.local/share/applications',
      '/usr/local/share/applications',
      '/usr/share/applications',
      '$XDG_DATA_DIRS/*/applications',
    ],
    discoveredCount: apps.length,
    curatedCatalog: false,
    refresh: 'forced',
  },
  package: {
    name: packageName,
    statusAndVersion: packageVersion.trim(),
  },
  desktopEntry: {
    desktopId: app.desktopId,
    fields: desktopFields(desktopContent),
  },
  registry: {
    id: app.id,
    source: app.source,
    name: app.name,
    execArgv: [...app.execTemplate],
    icon: app.iconName,
    categories: [...app.categories],
    normalizedCategory: app.category,
    mimeTypes: [...app.mimeTypes],
    launchMode: app.launchMode,
  },
  publicContract: {
    app: publicApp,
    execExposed: Object.hasOwn(publicApp, 'execTemplate') || Object.hasOwn(publicApp, 'launchArgv'),
    desktopPathExposed: Object.hasOwn(publicApp, 'desktopFile'),
  },
};

if (
  !/^linux-[a-f0-9]{32}$/u.test(app.id)
  || app.source !== 'linux'
  || app.launchMode !== 'xpra-contained'
  || evidence.publicContract.execExposed
  || evidence.publicContract.desktopPathExposed
  || !evidence.desktopEntry.fields.Name
  || !evidence.desktopEntry.fields.Exec
) {
  evidence.verdict = 'FAIL';
}

await fs.mkdir(path.dirname(outputPath), { recursive: true });
await fs.writeFile(outputPath, `${JSON.stringify(evidence, null, 2)}\n`, 'utf8');
process.stdout.write(`CLOUDOS APP DISCOVERY EVIDENCE: ${evidence.verdict}\n`);
process.stdout.write(`app=${app.name} id=${app.id} count=${apps.length} mode=${app.launchMode}\n`);
process.stdout.write(`JSON=${outputPath}\n`);
process.exitCode = evidence.verdict === 'PASS' ? 0 : 1;
