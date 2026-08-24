import http from 'node:http';
import {
  getDiscoveredLinuxPocApps,
  healthXpraPocSession,
  startXpraPoc,
  stopXpraPoc,
} from '../backend/src/linuxRuntime/xpraPoc.js';
import {
  handleXpraProxyUpgrade,
  xpraHttpProxyMiddleware,
} from '../backend/src/linuxRuntime/xpraProxy.js';

const distribution = process.argv[2] || 'Ubuntu';
const requestedName = (process.argv[3] || 'L3afpad').trim().toLocaleLowerCase('en');
const ownerId = `physical-evidence-${process.pid}`;
const apps = await getDiscoveredLinuxPocApps(distribution);
const app = apps.find((candidate) => candidate.name.toLocaleLowerCase('en') === requestedName);
if (!app) throw new Error(`APP_NOT_DISCOVERED:${requestedName}`);

const session = await startXpraPoc({
  app: app.id,
  distribution,
  ownerId,
});
const previewServer = http.createServer((request, response) => {
  xpraHttpProxyMiddleware(request, response, () => {
    response.statusCode = 404;
    response.end('Not Found');
  });
});
previewServer.on('upgrade', (request, socket, head) => {
  if (!handleXpraProxyUpgrade(request, socket, head)) socket.destroy();
});
await new Promise((resolve, reject) => {
  previewServer.once('error', reject);
  previewServer.listen(0, '127.0.0.1', resolve);
});
const previewAddress = previewServer.address();
if (!previewAddress || typeof previewAddress === 'string') {
  throw new Error('PREVIEW_PROXY_ADDRESS_UNAVAILABLE');
}
const previewUrl = `http://127.0.0.1:${previewAddress.port}${session.clientUrl}`;
process.stdout.write(`CLOUDOS_SESSION ${JSON.stringify({ app, session, previewUrl })}\n`);

let stopping = false;
async function stop(exitCode = 0) {
  if (stopping) return;
  stopping = true;
  await new Promise((resolve) => previewServer.close(resolve));
  await stopXpraPoc(session.id, ownerId).catch(() => undefined);
  process.stdout.write(`CLOUDOS_STOPPED ${session.id}\n`);
  process.exit(exitCode);
}

process.on('SIGINT', stop);
process.on('SIGTERM', stop);

for (;;) {
  await new Promise((resolve) => setTimeout(resolve, 15_000));
  const result = await healthXpraPocSession(session.id);
  process.stdout.write(`CLOUDOS_HEALTH ${JSON.stringify(result)}\n`);
  if (!result?.health?.healthy) {
    await stop(1);
    break;
  }
}
