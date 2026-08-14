import http from 'node:http';
import net, { type Socket } from 'node:net';

export async function getFreePort(): Promise<number> {
  return await new Promise((resolve, reject) => {
    const server = net.createServer();
    server.on('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      if (!address || typeof address === 'string') {
        server.close();
        reject(new Error('Porta temporária indisponível.'));
        return;
      }
      const port = address.port;
      server.close((error) => error ? reject(error) : resolve(port));
    });
  });
}

function listen(server: http.Server): Promise<number> {
  return new Promise((resolve, reject) => {
    server.on('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      if (!address || typeof address === 'string') {
        reject(new Error('Servidor de teste sem porta.'));
        return;
      }
      resolve(address.port);
    });
  });
}

function closeServer(server: http.Server, sockets: Set<Socket>): Promise<void> {
  for (const socket of sockets) socket.destroy();
  return new Promise((resolve, reject) => {
    server.close((error) => error ? reject(error) : resolve());
  });
}

export async function startNativeBrowserServer() {
  let backendHttpHits = 0;
  let backendUpgradeHits = 0;
  let startedDownloads = 0;
  let abortedDownloads = 0;
  const backendSockets = new Set<Socket>();
  const backend = http.createServer((req, res) => {
    backendHttpHits++;
    res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify({ ok: true, path: req.url || '/' }));
  });
  backend.on('connection', (socket) => {
    backendSockets.add(socket);
    socket.once('close', () => backendSockets.delete(socket));
  });
  backend.on('upgrade', (_req, socket) => {
    backendUpgradeHits++;
    socket.write('HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');
    socket.destroy();
  });
  const backendPort = await listen(backend);
  const backendOrigin = `http://127.0.0.1:${backendPort}`;
  const backendWsOrigin = `ws://127.0.0.1:${backendPort}`;

  const contentSockets = new Set<Socket>();
  const content = http.createServer((req, res) => {
    const requestUrl = new URL(req.url || '/', 'http://127.0.0.1');
    const pathname = requestUrl.pathname;
    const html = (body: string, headers: Record<string, string> = {}) => {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', ...headers });
      res.end(`<!doctype html><meta charset="utf-8"><title>CloudOS Browser Test</title>${body}`);
    };

    if (pathname === '/xfo-deny') return html('<h1 id="xfo">XFO top-level carregado</h1>', { 'X-Frame-Options': 'DENY' });
    if (pathname === '/csp-deny') return html('<h1 id="csp">CSP top-level carregado</h1>', { 'Content-Security-Policy': "frame-ancestors 'none'" });
    if (pathname === '/popup') return html('<button id="popup" onclick="window.open(\'/child\', \'_blank\')">popup</button>');
    if (pathname === '/child') return html('<h1 id="child">Popup em aba</h1>');
    if (pathname === '/cookie') return html('<script>document.cookie="cloudos_browser_test=shared; path=/"</script><h1>cookie</h1>');
    if (pathname === '/probe') return html('<h1 id="probe">probe</h1>');
    if (pathname === '/redirect-shell') {
      res.writeHead(302, { Location: 'https://cloudos.local/', 'Cache-Control': 'no-store' });
      return res.end();
    }
    if (pathname === '/redirect-backend') {
      res.writeHead(302, { Location: `${backendOrigin}/internal`, 'Cache-Control': 'no-store' });
      return res.end();
    }
    if (pathname === '/network-probe') {
      return html(`<script>
        window.backendOrigin = ${JSON.stringify(backendOrigin)};
        window.backendWsOrigin = ${JSON.stringify(backendWsOrigin)};
      </script><h1 id="network">network probe</h1>`);
    }
    if (pathname === '/downloads') {
      return html(`
        <a id="download-one" href="/download-slow?name=one.bin">download one</a>
        <a id="download-two" href="/download-slow?name=two.bin">download two</a>
      `);
    }
    if (pathname === '/download-slow') {
      startedDownloads++;
      const requestedName = requestUrl.searchParams.get('name') || 'download.bin';
      const safeName = requestedName.replace(/[^a-zA-Z0-9._-]/g, '_').slice(0, 80) || 'download.bin';
      const total = 32 * 1024 * 1024;
      const chunk = Buffer.alloc(64 * 1024, 0x41);
      let sent = 0;
      let completed = false;
      res.writeHead(200, {
        'Content-Type': 'application/octet-stream',
        'Content-Length': String(total),
        'Content-Disposition': `attachment; filename="${safeName}"`,
        'Cache-Control': 'no-store',
      });
      const timer = setInterval(() => {
        if (res.destroyed || sent >= total) {
          clearInterval(timer);
          if (!res.destroyed && sent >= total) {
            completed = true;
            res.end();
          }
          return;
        }
        res.write(chunk);
        sent += chunk.length;
      }, 25);
      res.once('close', () => {
        clearInterval(timer);
        if (!completed && sent < total) abortedDownloads++;
      });
      return;
    }
    res.writeHead(404, { 'Content-Type': 'text/plain', 'Cache-Control': 'no-store' });
    res.end('not found');
  });
  content.on('connection', (socket) => {
    contentSockets.add(socket);
    socket.once('close', () => contentSockets.delete(socket));
  });
  const port = await listen(content);
  const origin = `http://127.0.0.1:${port}`;

  return {
    port,
    origin,
    backendOrigin,
    backendWsOrigin,
    getBackendHttpHits: () => backendHttpHits,
    getBackendUpgradeHits: () => backendUpgradeHits,
    getStartedDownloads: () => startedDownloads,
    getAbortedDownloads: () => abortedDownloads,
    close: async () => {
      await closeServer(content, contentSockets);
      await closeServer(backend, backendSockets);
    },
  };
}
