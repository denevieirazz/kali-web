import http from 'node:http';
import net from 'node:net';
import zlib from 'node:zlib';
import { recordXpraPocProxyEvent, resolveXpraPocProxySession } from './xpraPoc.js';
import { recordXpraPreflightProxyEvent, resolveXpraPreflightProxySession } from './preflight.js';

const PREFIX = '/__cloudos/linux-runtime/poc1/';
function parseProxyRequest(requestUrl) { let url; try { url = new URL(requestUrl, 'http://127.0.0.1'); } catch { return null; } if (!url.pathname.startsWith(PREFIX)) return null; const parts = url.pathname.slice(PREFIX.length).split('/'); const id = parts.shift() || ''; const token = parts.shift() || ''; const targetPath = `/${parts.join('/')}` || '/'; return { id, token, targetPath: `${targetPath}${url.search}` }; }
function rewriteCsp(value) { const directives = String(value || '').split(';').map(v => v.trim()).filter(Boolean).filter(v => !/^(frame-ancestors|sandbox)\b/i.test(v)); directives.push("frame-ancestors *"); return directives.join('; '); }
function proxyBase(session) { return `${PREFIX}${session.id}/${session.proxyToken}/`; }
function rewriteLocation(value, session) { if (!value) return value; const base = proxyBase(session); try { const parsed = new URL(value, `http://127.0.0.1:${session.port}`); if (['127.0.0.1', 'localhost'].includes(parsed.hostname)) return `${base}${parsed.pathname.replace(/^\//, '')}${parsed.search}${parsed.hash}`; } catch {} if (String(value).startsWith('/')) return `${base}${value.replace(/^\//, '')}`; return value; }
function buildResponseHeaders(headers, session, isTransformedHtml = false, targetPath = '') {
  const result = {};
  for (const [name, value] of Object.entries(headers)) {
    const lower = name.toLowerCase();
    if (['x-frame-options', 'content-length', 'transfer-encoding', 'connection', 'set-cookie'].includes(lower)) continue;
    if (isTransformedHtml && lower === 'content-encoding') continue;
    if (lower === 'content-security-policy') result[name] = rewriteCsp(value);
    else if (lower === 'location') result[name] = rewriteLocation(value, session);
    else result[name] = value;
  }
  if (!Object.keys(result).some(name => name.toLowerCase() === 'content-security-policy')) result['Content-Security-Policy'] = rewriteCsp(null);
  if (!isTransformedHtml && (/\.(js|css|png|jpg|wasm|svg|woff2|ico)$/i.test(targetPath) || /javascript|css|image|font/i.test(String(headers['content-type'] || '')))) {
    result['Cache-Control'] = 'public, max-age=86400';
  } else {
    result['Cache-Control'] = 'no-store, no-cache, must-revalidate, private';
    result['Pragma'] = 'no-cache';
    result['Expires'] = '0';
  }
  result['Referrer-Policy'] = 'no-referrer';
  result['Cross-Origin-Resource-Policy'] = 'cross-origin';
  result['Access-Control-Allow-Origin'] = '*';
  result['Access-Control-Allow-Methods'] = 'GET, HEAD, OPTIONS';
  result['Access-Control-Allow-Headers'] = '*';
  return result;
}
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
function decompressBuffer(buffer, encoding) {
  if (!encoding || !buffer?.length) return buffer;
  const enc = String(encoding).toLowerCase().trim();
  try {
    if (enc === 'gzip') return zlib.gunzipSync(buffer);
    if (enc === 'deflate') return zlib.inflateSync(buffer);
    if (enc === 'br') return zlib.brotliDecompressSync(buffer);
  } catch {}
  return buffer;
}
function createOpaqueShim(sessionId, xpraPassword = null) {
  const safeSessionId = JSON.stringify(String(sessionId || ''));
  const safePassword = xpraPassword ? JSON.stringify(String(xpraPassword)) : 'null';
  return `<script>
try {
  var mem = {};
  var mock = {
    getItem: function(k) { return mem[k] || null; },
    setItem: function(k, v) { mem[k] = String(v); },
    removeItem: function(k) { delete mem[k]; },
    clear: function() { mem = {}; }
  };
  Object.defineProperty(window, 'sessionStorage', { get: function() { return mock; } });
  Object.defineProperty(window, 'localStorage', { get: function() { return mock; } });
} catch(e) { console.error("Shim storage error:", e); }
try {
  window.addEventListener('pointerdown', function() {
    try { window.focus(); } catch(e) {}
    try {
      window.parent.postMessage({
        type: 'xpra-focus-request',
        sessionId: ${safeSessionId}
      }, '*');
    } catch(e) {}
  }, true);
  if (${safePassword}) {
    var epSecret = ${safePassword};
    var attachSecret = function() {
      if (window.client) {
        window.client.passwords = [epSecret];
        var origPrompt = window.client.password_prompt_fn;
        window.client.password_prompt_fn = function(heading, cb) {
          if (epSecret) {
            var pwd = epSecret;
            epSecret = null;
            return cb(pwd);
          }
          if (origPrompt) return origPrompt.apply(this, arguments);
        };
      }
    };
    attachSecret();
    var secretInterval = setInterval(function() {
      if (window.client) {
        attachSecret();
        clearInterval(secretInterval);
      }
    }, 20);
    setTimeout(function() { clearInterval(secretInterval); }, 5000);
  }
  var autoConnect = function() {
    try {
      if (typeof window.do_connect === 'function') {
        window.do_connect();
      } else {
        var btns = Array.from(document.querySelectorAll('button, input[type="button"], a, div'));
        var btn = btns.find(b => (b.textContent || b.value || '').trim() === 'Connect');
        if (btn) btn.click();
      }
    } catch(e) {}
  };
  window.addEventListener('load', function() {
    setTimeout(autoConnect, 100);
    setTimeout(autoConnect, 400);
    setTimeout(autoConnect, 1000);
  });
  (function() {
    var _client = undefined;
    var paintNotified = false;
    var notifyRender = function(name, extra) {
      try { window.parent.postMessage(Object.assign({ type: 'xpra-render-event', sessionId: ${safeSessionId}, name: name }, extra || {}), '*'); } catch(e){}
    };
    var notifyPaintedCanvas = function() {
      if (paintNotified) return;
      var canvas = Array.from(document.querySelectorAll('canvas')).find(function(candidate) {
        var rect = candidate.getBoundingClientRect();
        return candidate.width >= 64 && candidate.height >= 64 && rect.width >= 64 && rect.height >= 64;
      });
      if (!canvas) return;
      paintNotified = true;
      requestAnimationFrame(function() {
        requestAnimationFrame(function() {
          notifyRender('frame-painted', {
            source: 'xpra-canvas',
            canvasWidth: canvas.width,
            canvasHeight: canvas.height
          });
        });
      });
    };
    var observer = new MutationObserver(notifyPaintedCanvas);
    observer.observe(document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['width', 'height', 'style', 'class']
    });
    window.addEventListener('load', function() {
      notifyPaintedCanvas();
      var paintProbe = setInterval(notifyPaintedCanvas, 100);
      setTimeout(function() { clearInterval(paintProbe); observer.disconnect(); }, 30000);
    });
    var hookClient = function(c) {
      if (!c || c._hooked) return;
      c._hooked = true;
      var origOnConnect = c.on_connect;
      c.on_connect = function() {
        notifyRender('connected');
        if (origOnConnect) origOnConnect.apply(this, arguments);
      };
      var origProcessNewWindow = c._process_new_window;
      if (origProcessNewWindow) {
        c._process_new_window = function(packet) {
          var result = origProcessNewWindow.apply(this, arguments);
          notifyPaintedCanvas();
          return result;
        };
      }
      var origProcessDraw = c._process_draw;
      if (origProcessDraw) {
        c._process_draw = function(packet) {
          var result = origProcessDraw.apply(this, arguments);
          notifyPaintedCanvas();
          return result;
        };
      }
      var origProcessOR = c._process_new_override_redirect;
      if (origProcessOR) {
        c._process_new_override_redirect = function(packet) {
          var result = origProcessOR.apply(this, arguments);
          notifyPaintedCanvas();
          return result;
        };
      }
    };
    try {
      Object.defineProperty(window, 'client', {
        configurable: true,
        enumerable: true,
        get: function() { return _client; },
        set: function(v) {
          _client = v;
          hookClient(v);
        }
      });
    } catch(e) {}
  })();
} catch(e) {}
</script>`;
}

export function xpraHttpProxyMiddleware(req, res, next) {
  const reqUrl = req.originalUrl || req.url || '';
  const parsed = parseProxyRequest(reqUrl);
  if (!parsed) return next();
  if (!['GET', 'HEAD'].includes(req.method)) return writeProxyError(res, 405, 'Método não permitido.');
  const session = resolveProxySession(parsed.id, parsed.token);
  if (!session) return writeProxyError(res, 404, 'Surface Xpra indisponível ou capability expirada.');
  const pathname = reqUrl.split('?')[0];
  if (pathname === `${PREFIX}${parsed.id}/${parsed.token}`) {
    const search = reqUrl.includes('?') ? `?${reqUrl.split('?')[1]}` : '';
    res.statusCode = 307;
    res.setHeader('Location', `${PREFIX}${parsed.id}/${parsed.token}/${search}`);
    return res.end();
  }
  recordProxyEvent(session, 'http');
  const headers = { ...req.headers, host: `127.0.0.1:${session.port}` };
  for (const name of ['authorization', 'cookie', 'referer', 'origin']) delete headers[name];
  headers['accept-encoding'] = 'identity';
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
    const statusCode = upstreamResponse.statusCode || 502;
    const isHtml = statusCode === 200 && String(upstreamResponse.headers['content-type'] || '').toLowerCase().includes('text/html');
    if (isHtml) {
      const chunks = [];
      upstreamResponse.on('data', chunk => chunks.push(chunk));
      upstreamResponse.on('end', () => {
        const rawBuffer = Buffer.concat(chunks);
        const decompressed = decompressBuffer(rawBuffer, upstreamResponse.headers['content-encoding']);
        let body = decompressed.toString('utf8');
        const shim = createOpaqueShim(session.id, session.xpraPassword);
        if (body.includes('<head>')) {
          body = body.replace('<head>', `<head>${shim}`);
        } else if (body.includes('</head>')) {
          body = body.replace('</head>', `${shim}</head>`);
        } else {
          body = `${shim}${body}`;
        }
        const responseHeaders = buildResponseHeaders(upstreamResponse.headers, session, true, parsed.targetPath);
        responseHeaders['Content-Length'] = Buffer.byteLength(body, 'utf8');
        if (typeof res.status === 'function') res.status(statusCode);
        else res.statusCode = statusCode;
        for (const [name, value] of Object.entries(responseHeaders)) {
          if (value !== undefined) res.setHeader(name, value);
        }
        res.end(body);
      });
      return;
    }
    const responseHeaders = buildResponseHeaders(upstreamResponse.headers, session, false, parsed.targetPath);
    if (typeof res.status === 'function') res.status(statusCode);
    else res.statusCode = statusCode;
    for (const [name, value] of Object.entries(responseHeaders)) {
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
export const __test = { parseProxyRequest, rewriteCsp, rewriteLocation, buildResponseHeaders, serializeUpgradeRequest, createOpaqueShim };
