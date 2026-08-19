import http from 'node:http';
import net from 'node:net';
import { recordXpraPocProxyEvent, resolveXpraPocProxySession } from './xpraPoc.js';
import { recordXpraPreflightProxyEvent, resolveXpraPreflightProxySession } from './preflight.js';

const PREFIX = '/__cloudos/linux-runtime/poc1/';
function parseProxyRequest(requestUrl) { let url; try { url = new URL(requestUrl, 'http://127.0.0.1'); } catch { return null; } if (!url.pathname.startsWith(PREFIX)) return null; const parts = url.pathname.slice(PREFIX.length).split('/'); const id = parts.shift() || ''; const token = parts.shift() || ''; const targetPath = `/${parts.join('/')}` || '/'; return { id, token, targetPath: `${targetPath}${url.search}` }; }
function rewriteCsp(value) { const directives = String(value || '').split(';').map(v => v.trim()).filter(Boolean).filter(v => !/^(frame-ancestors|sandbox)\b/i.test(v)); directives.push("sandbox allow-scripts allow-forms allow-pointer-lock"); directives.push("frame-ancestors 'self'"); return directives.join('; '); }
function proxyBase(session) { return `${PREFIX}${session.id}/${session.proxyToken}`; }
function rewriteLocation(value, session) { if (!value) return value; const base = proxyBase(session); try { const parsed = new URL(value, `http://127.0.0.1:${session.port}`); if (['127.0.0.1', 'localhost'].includes(parsed.hostname)) return `${base}${parsed.pathname}${parsed.search}${parsed.hash}`; } catch {} if (String(value).startsWith('/')) return `${base}${value}`; return value; }
function buildResponseHeaders(headers, session) { const result = {}; for (const [name, value] of Object.entries(headers)) { const lower = name.toLowerCase(); if (['x-frame-options', 'content-length', 'set-cookie'].includes(lower)) continue; if (lower === 'content-security-policy') result[name] = rewriteCsp(value); else if (lower === 'location') result[name] = rewriteLocation(value, session); else result[name] = value; } if (!Object.keys(result).some(name => name.toLowerCase() === 'content-security-policy')) result['Content-Security-Policy'] = rewriteCsp(null); result['Cache-Control'] = 'no-store'; result['Referrer-Policy'] = 'no-referrer'; result['Cross-Origin-Resource-Policy'] = 'same-origin'; return result; }
function writeProxyError(res, status, message) {
  if (res.headersSent) return res.end();
  if (typeof res.status === 'function') {
    res.status(status).type('text/plain').send(message);
  } else {
    res.statusCode = status;
    res.setHeader('Content-Type', 'text/plain');
    res.end(message);
  }
}
function resolveProxySession(id, token) { return resolveXpraPocProxySession(id, token) || resolveXpraPreflightProxySession(id, token); }
function recordProxyEvent(session, event) { if (session.preflight === true) recordXpraPreflightProxyEvent(session.id, event); else recordXpraPocProxyEvent(session.id, event); }
export function xpraHttpProxyMiddleware(req, res, next) {
  const parsed = parseProxyRequest(req.originalUrl || req.url);
  if (!parsed) return next();
  if (!['GET', 'HEAD'].includes(req.method)) return writeProxyError(res, 405, 'Método não permitido.');
  const session = resolveProxySession(parsed.id, parsed.token);
  if (!session) return writeProxyError(res, 404, 'Surface Xpra indisponível ou capability expirada.');
  recordProxyEvent(session, 'http');
  const headers = { ...req.headers, host: `127.0.0.1:${session.port}` };
  for (const name of ['authorization', 'cookie', 'referer', 'origin']) delete headers[name];
  if (session.xpraPassword) {
    headers.authorization = `Basic ${Buffer.from(`xpra:${session.xpraPassword}`).toString('base64')}`;
  }
  const upstream = http.request({
    hostname: '127.0.0.1',
    port: session.port,
    method: req.method,
    path: parsed.targetPath,
    headers,
    timeout: 5000,
  }, upstreamResponse => {
    if (typeof res.status === 'function') {
      res.status(upstreamResponse.statusCode || 502);
    } else {
      res.statusCode = upstreamResponse.statusCode || 502;
    }
    for (const [name, value] of Object.entries(buildResponseHeaders(upstreamResponse.headers, session))) {
      if (value !== undefined) res.setHeader(name, value);
    }
    upstreamResponse.pipe(res);
  });
  upstream.once('timeout', () => upstream.destroy(new Error('Timeout no proxy HTTP Xpra.')));
  upstream.once('error', error => writeProxyError(res, 502, `Xpra HTTP indisponível: ${error.message}`));
  req.once('aborted', () => upstream.destroy());
  upstream.end();
}
function sendUpgradeFailure(socket, status, reason) { if (!socket.destroyed) { socket.write(`HTTP/1.1 ${status} ${reason}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`); socket.destroy(); } }
function serializeUpgradeRequest(req, targetPath, session) {
  const lines = [`GET ${targetPath} HTTP/1.1`];
  for (const [name, value] of Object.entries(req.headers)) {
    const lower = name.toLowerCase();
    if (['host', 'origin', 'authorization', 'cookie', 'referer'].includes(lower)) continue;
    if (Array.isArray(value)) for (const item of value) lines.push(`${name}: ${item}`);
    else if (value !== undefined) lines.push(`${name}: ${value}`);
  }
  lines.push(`Host: 127.0.0.1:${session.port}`);
  lines.push(`Origin: http://127.0.0.1:${session.port}`);
  if (session.xpraPassword) {
    lines.push(`Authorization: Basic ${Buffer.from(`xpra:${session.xpraPassword}`).toString('base64')}`);
  }
  lines.push('', '');
  return lines.join('\r\n');
}
export function handleXpraProxyUpgrade(req, socket, head) { const parsed = parseProxyRequest(req.url || ''); if (!parsed) return false; const session = resolveProxySession(parsed.id, parsed.token); if (!session) { sendUpgradeFailure(socket, '404', 'Not Found'); return true; } recordProxyEvent(session, 'websocket'); const upstream = net.createConnection({ host: '127.0.0.1', port: session.port }); upstream.setTimeout(5000, () => upstream.destroy(new Error('Timeout no proxy WebSocket Xpra.'))); upstream.once('connect', () => { upstream.setTimeout(0); upstream.write(serializeUpgradeRequest(req, parsed.targetPath, session)); if (head?.length) upstream.write(head); socket.pipe(upstream).pipe(socket); }); upstream.once('error', () => { if (!socket.destroyed) sendUpgradeFailure(socket, '502', 'Bad Gateway'); }); socket.once('error', () => upstream.destroy()); socket.once('close', () => upstream.destroy()); return true; }
export const __test = { parseProxyRequest, rewriteCsp, rewriteLocation, buildResponseHeaders, serializeUpgradeRequest };
