import http from 'node:http';
import net from 'node:net';

export async function getFreePort(): Promise<number> {
  return await new Promise((resolve, reject) => {
    const server = net.createServer();
    server.on('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      if (!address || typeof address === 'string') return reject(new Error('Porta temporária indisponível.'));
      const port = address.port;
      server.close((error) => error ? reject(error) : resolve(port));
    });
  });
}

export async function startNativeBrowserServer() {
  const server = http.createServer((req, res) => {
    const path = new URL(req.url || '/', 'http://127.0.0.1').pathname;
    const html = (body: string, headers: Record<string, string> = {}) => {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', ...headers });
      res.end(`<!doctype html><meta charset="utf-8"><title>CloudOS Browser Test</title>${body}`);
    };
    if (path === '/xfo-deny') return html('<h1 id="xfo">XFO top-level carregado</h1>', { 'X-Frame-Options': 'DENY' });
    if (path === '/csp-deny') return html('<h1 id="csp">CSP top-level carregado</h1>', { 'Content-Security-Policy': "frame-ancestors 'none'" });
    if (path === '/popup') return html('<button id="popup" onclick="window.open(\'/child\', \'_blank\')">popup</button>');
    if (path === '/child') return html('<h1 id="child">Popup em aba</h1>');
    if (path === '/cookie') return html('<script>document.cookie="cloudos_browser_test=shared; path=/"</script><h1>cookie</h1>');
    if (path === '/probe') return html('<h1>probe</h1>');
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('not found');
  });
  await new Promise<void>((resolve, reject) => {
    server.on('error', reject);
    server.listen(0, '127.0.0.1', () => resolve());
  });
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('Servidor de teste sem porta.');
  return {
    port: address.port,
    origin: `http://127.0.0.1:${address.port}`,
    close: () => new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve())),
  };
}
