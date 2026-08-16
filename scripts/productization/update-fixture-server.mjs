import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(process.argv[2] || '');
const port = Number.parseInt(process.argv[3] || '0', 10);
if (!root || !fs.existsSync(root) || !fs.statSync(root).isDirectory()) {
  console.error('UPDATE_FIXTURE_ROOT_INVALID');
  process.exit(2);
}

const server = http.createServer((req, res) => {
  const requestPath = decodeURIComponent(new URL(req.url, 'http://127.0.0.1').pathname).replace(/^\/+/, '');
  if (!requestPath || requestPath.includes('\0') || requestPath.split(/[\\/]/).includes('..')) {
    res.writeHead(400, {'content-type':'text/plain'}); res.end('invalid path'); return;
  }
  const target = path.resolve(root, requestPath);
  if (!target.startsWith(root + path.sep) || !fs.existsSync(target) || !fs.statSync(target).isFile()) {
    res.writeHead(404, {'content-type':'text/plain'}); res.end('not found'); return;
  }
  res.setHeader('cache-control','no-store');
  res.setHeader('x-content-type-options','nosniff');
  fs.createReadStream(target).pipe(res);
});
server.listen(Number.isInteger(port) && port >= 0 ? port : 0, '127.0.0.1', () => {
  const address = server.address();
  process.stdout.write(JSON.stringify({protocol:1,host:'127.0.0.1',port:address.port,root}) + '\n');
});
for (const signal of ['SIGINT','SIGTERM']) process.on(signal, () => server.close(() => process.exit(0)));
