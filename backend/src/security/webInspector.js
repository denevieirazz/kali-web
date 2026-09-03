import dns from 'node:dns/promises';
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';

const MAX_BODY_BYTES = 128 * 1024;
const REQUEST_TIMEOUT_MS = 10_000;
const MAX_REDIRECTS = 4;
const ALLOWED_PORTS = new Set([80, 443, 8080, 8443]);
const REDIRECT_CODES = new Set([301, 302, 303, 307, 308]);

function makeError(message, code) {
  const error = new Error(message);
  error.code = code;
  return error;
}

function ipv4Number(address) {
  const parts = String(address || '').split('.');
  if (parts.length !== 4 || parts.some(part => !/^\d{1,3}$/.test(part))) return null;
  const octets = parts.map(Number);
  if (octets.some(value => value < 0 || value > 255)) return null;
  return (((octets[0] << 24) >>> 0) + (octets[1] << 16) + (octets[2] << 8) + octets[3]) >>> 0;
}

function inIpv4Range(value, base, prefix) {
  const candidate = ipv4Number(value);
  const network = ipv4Number(base);
  if (candidate === null || network === null) return false;
  const mask = prefix === 0 ? 0 : (0xffffffff << (32 - prefix)) >>> 0;
  return (candidate & mask) === (network & mask);
}

function unbracketHostname(hostname) {
  const value = String(hostname || '');
  return value.startsWith('[') && value.endsWith(']') ? value.slice(1, -1) : value;
}

export function isPublicWebAddress(address) {
  const family = net.isIP(address);
  if (family === 4) {
    const blocked = [
      ['0.0.0.0', 8], ['10.0.0.0', 8], ['100.64.0.0', 10], ['127.0.0.0', 8],
      ['169.254.0.0', 16], ['172.16.0.0', 12], ['192.0.0.0', 24], ['192.0.2.0', 24],
      ['192.88.99.0', 24], ['192.168.0.0', 16], ['198.18.0.0', 15], ['198.51.100.0', 24],
      ['203.0.113.0', 24], ['224.0.0.0', 4], ['240.0.0.0', 4],
    ];
    return !blocked.some(([base, prefix]) => inIpv4Range(address, base, prefix));
  }
  if (family === 6) {
    const value = address.toLowerCase();
    if (value === '::' || value === '::1') return false;
    if (value.startsWith('fc') || value.startsWith('fd')) return false;
    if (/^fe[89ab]/.test(value)) return false;
    if (value.startsWith('ff')) return false;
    if (value.startsWith('2001:db8:') || value === '2001:db8::') return false;
    const mapped = value.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/)?.[1];
    if (mapped) return isPublicWebAddress(mapped);
    return true;
  }
  return false;
}

export function normalizePublicWebUrl(value) {
  const raw = String(value || '').trim();
  if (!raw || raw.length > 2048 || /[\u0000-\u001f\u007f]/.test(raw)) {
    throw makeError('Informe uma URL HTTP/HTTPS pública válida.', 'INVALID_WEB_URL');
  }

  let url;
  try {
    url = new URL(raw);
  } catch {
    throw makeError('Informe uma URL completa, por exemplo https://example.com.', 'INVALID_WEB_URL');
  }

  if (!['http:', 'https:'].includes(url.protocol)) {
    throw makeError('O Web Inspector aceita somente HTTP ou HTTPS.', 'WEB_SCHEME_NOT_ALLOWED');
  }
  if (url.username || url.password) {
    throw makeError('Credenciais embutidas na URL não são aceitas.', 'WEB_CREDENTIALS_NOT_ALLOWED');
  }
  const hostname = url.hostname.toLowerCase().replace(/\.$/, '');
  const addressLiteral = unbracketHostname(hostname);
  if (!hostname || hostname === 'localhost' || hostname.endsWith('.localhost') || hostname.endsWith('.local')) {
    throw makeError('O Web Inspector não acessa localhost nem nomes de rede local.', 'WEB_TARGET_NOT_PUBLIC');
  }
  const explicitPort = url.port ? Number(url.port) : (url.protocol === 'https:' ? 443 : 80);
  if (!ALLOWED_PORTS.has(explicitPort)) {
    throw makeError('Use uma porta web suportada: 80, 443, 8080 ou 8443.', 'WEB_PORT_NOT_ALLOWED');
  }
  if (net.isIP(addressLiteral) && !isPublicWebAddress(addressLiteral)) {
    throw makeError('Endereços privados, locais, reservados ou de metadata não são acessados pelo Web Inspector.', 'WEB_TARGET_NOT_PUBLIC');
  }

  url.hostname = hostname;
  url.hash = '';
  return url.toString();
}

async function resolvePublicTarget(urlString) {
  const url = new URL(normalizePublicWebUrl(urlString));
  const addressLiteral = unbracketHostname(url.hostname);
  const literalFamily = net.isIP(addressLiteral);
  if (literalFamily) {
    if (!isPublicWebAddress(addressLiteral)) {
      throw makeError('Endereços privados, locais, reservados ou de metadata não são acessados pelo Web Inspector.', 'WEB_TARGET_NOT_PUBLIC');
    }
    return { url, address: addressLiteral, family: literalFamily };
  }

  let addresses;
  try {
    addresses = await dns.lookup(url.hostname, { all: true, verbatim: true });
  } catch {
    throw makeError('O nome não pôde ser resolvido pelo DNS do host.', 'WEB_DNS_FAILED');
  }
  if (!addresses.length) throw makeError('O DNS não retornou endereços para esse nome.', 'WEB_DNS_EMPTY');
  if (addresses.some(item => !isPublicWebAddress(item.address))) {
    throw makeError('O nome resolve para endereço privado/local/reservado e foi bloqueado.', 'WEB_TARGET_NOT_PUBLIC');
  }
  return { url, address: addresses[0].address, family: addresses[0].family };
}

function headerValue(headers, name) {
  const value = headers[name.toLowerCase()];
  if (Array.isArray(value)) return value.join(', ');
  return typeof value === 'string' ? value : '';
}

function clip(value, max = 512) {
  return String(value || '').replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, max);
}

export function parseSetCookieMetadata(values) {
  const list = Array.isArray(values) ? values : values ? [values] : [];
  return list.slice(0, 50).map(raw => {
    const parts = String(raw).split(';').map(part => part.trim()).filter(Boolean);
    const first = parts.shift() || '';
    const separator = first.indexOf('=');
    const name = separator > 0 ? first.slice(0, separator).trim().slice(0, 128) : '(sem nome)';
    const attributes = parts.map(part => part.toLowerCase());
    const sameSitePart = attributes.find(part => part.startsWith('samesite='));
    const domainPart = parts.find(part => /^domain=/i.test(part));
    const pathPart = parts.find(part => /^path=/i.test(part));
    return {
      name,
      secure: attributes.includes('secure'),
      httpOnly: attributes.includes('httponly'),
      sameSite: sameSitePart ? sameSitePart.split('=')[1] || null : null,
      domain: domainPart ? clip(domainPart.slice(domainPart.indexOf('=') + 1), 255) : null,
      path: pathPart ? clip(pathPart.slice(pathPart.indexOf('=') + 1), 255) : null,
      valueExposed: false,
    };
  });
}

function extractTitle(body) {
  const match = String(body || '').match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  return match ? clip(match[1].replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' '), 300) : '';
}

function extractGenerator(body) {
  const html = String(body || '');
  const patterns = [
    /<meta[^>]+name=["']generator["'][^>]+content=["']([^"']+)["'][^>]*>/i,
    /<meta[^>]+content=["']([^"']+)["'][^>]+name=["']generator["'][^>]*>/i,
  ];
  for (const pattern of patterns) {
    const match = html.match(pattern);
    if (match) return clip(match[1], 200);
  }
  return '';
}

function selectedHeaders(headers) {
  const names = [
    'content-type', 'content-length', 'server', 'x-powered-by', 'strict-transport-security',
    'content-security-policy', 'x-content-type-options', 'x-frame-options', 'referrer-policy',
    'permissions-policy', 'access-control-allow-origin', 'access-control-allow-credentials',
    'cross-origin-opener-policy', 'cross-origin-resource-policy', 'cross-origin-embedder-policy',
    'cache-control', 'etag', 'last-modified', 'cf-ray', 'x-vercel-id',
  ];
  const result = {};
  for (const name of names) {
    const value = headerValue(headers, name);
    if (value) result[name] = clip(value, 1024);
  }
  return result;
}

function tlsSummary(socket) {
  if (!socket || typeof socket.getPeerCertificate !== 'function') return null;
  const certificate = socket.getPeerCertificate(false);
  if (!certificate || Object.keys(certificate).length === 0) return null;
  const cipher = typeof socket.getCipher === 'function' ? socket.getCipher() : null;
  return {
    protocol: typeof socket.getProtocol === 'function' ? socket.getProtocol() : null,
    cipher: cipher?.name || null,
    subjectCommonName: clip(certificate.subject?.CN, 255) || null,
    issuerCommonName: clip(certificate.issuer?.CN, 255) || null,
    issuerOrganization: clip(certificate.issuer?.O, 255) || null,
    validFrom: certificate.valid_from || null,
    validTo: certificate.valid_to || null,
    fingerprint256: certificate.fingerprint256 || null,
    subjectAltNameCount: certificate.subjectaltname
      ? certificate.subjectaltname.split(',').filter(Boolean).length
      : 0,
  };
}

function requestOnce(target) {
  return resolvePublicTarget(target).then(({ url, address, family }) => new Promise((resolve, reject) => {
    const transport = url.protocol === 'https:' ? https : http;
    const literalHostname = unbracketHostname(url.hostname);
    const isLiteral = net.isIP(literalHostname) !== 0;
    const headers = {
      'user-agent': 'CloudOS-Web-Inspector/1.0',
      accept: 'text/html,application/xhtml+xml,application/json;q=0.8,*/*;q=0.2',
      'accept-encoding': 'identity',
      range: `bytes=0-${MAX_BODY_BYTES - 1}`,
      connection: 'close',
    };
    const options = {
      protocol: url.protocol,
      hostname: isLiteral ? literalHostname : url.hostname,
      port: url.port || undefined,
      path: `${url.pathname}${url.search}`,
      method: 'GET',
      headers,
      timeout: REQUEST_TIMEOUT_MS,
      lookup: (_hostname, _options, callback) => callback(null, address, family),
      ...(url.protocol === 'https:' ? {
        ...(isLiteral ? {} : { servername: url.hostname }),
        rejectUnauthorized: true,
      } : {}),
    };

    let settled = false;
    const request = transport.request(options, response => {
      const chunks = [];
      let received = 0;
      let truncated = false;
      const finish = () => {
        if (settled) return;
        settled = true;
        const body = Buffer.concat(chunks).toString('utf8');
        resolve({
          url: url.toString(),
          address,
          family,
          status: response.statusCode || 0,
          statusMessage: clip(response.statusMessage, 100),
          headers: response.headers,
          selectedHeaders: selectedHeaders(response.headers),
          cookies: parseSetCookieMetadata(response.headers['set-cookie']),
          body,
          bodyTruncated: truncated,
          title: extractTitle(body),
          generator: extractGenerator(body),
          tls: url.protocol === 'https:' ? tlsSummary(response.socket) : null,
        });
      };
      response.on('data', chunk => {
        if (settled) return;
        const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
        const remaining = MAX_BODY_BYTES - received;
        if (remaining > 0) {
          const accepted = buffer.subarray(0, Math.min(remaining, buffer.length));
          chunks.push(accepted);
          received += accepted.length;
        }
        if (buffer.length > remaining || received >= MAX_BODY_BYTES) {
          truncated = true;
          finish();
          response.destroy();
        }
      });
      response.on('end', finish);
      response.on('error', error => {
        if (!settled) {
          settled = true;
          reject(error);
        }
      });
    });

    request.on('timeout', () => request.destroy(makeError('A URL não respondeu dentro do limite de tempo.', 'WEB_REQUEST_TIMEOUT')));
    request.on('error', error => {
      if (settled) return;
      settled = true;
      if (error?.code === 'CERT_HAS_EXPIRED' || error?.code === 'DEPTH_ZERO_SELF_SIGNED_CERT' || error?.code === 'UNABLE_TO_VERIFY_LEAF_SIGNATURE') {
        reject(makeError('A conexão HTTPS não passou na validação do certificado TLS.', 'WEB_TLS_VALIDATION_FAILED'));
        return;
      }
      reject(error?.code === 'WEB_REQUEST_TIMEOUT'
        ? error
        : makeError('Não foi possível concluir a requisição HTTP/HTTPS.', 'WEB_REQUEST_FAILED'));
    });
    request.end();
  }));
}

function finding(id, severity, title, evidence, recommendation) {
  return { id, severity, title, evidence, recommendation, certainty: 'observed-hygiene' };
}

export function buildWebFindings(result) {
  const findings = [];
  const headers = result?.headers || {};
  const finalUrl = new URL(result.finalUrl);
  const httpsEnabled = finalUrl.protocol === 'https:';

  if (!httpsEnabled) {
    findings.push(finding('transport-http', 'medium', 'Página final sem HTTPS', 'A URL final usa HTTP.', 'Prefira HTTPS e redirecione HTTP para HTTPS quando isso fizer sentido para o serviço.'));
  }
  if (httpsEnabled && !headers['strict-transport-security']) {
    findings.push(finding('hsts-missing', 'low', 'HSTS não observado', 'Strict-Transport-Security não apareceu na resposta HTTPS.', 'Revise a política HSTS depois de confirmar que todo o domínio opera corretamente em HTTPS.'));
  }
  if (!headers['content-security-policy']) {
    findings.push(finding('csp-missing', 'low', 'CSP não observada', 'Content-Security-Policy não apareceu na resposta.', 'Avalie uma CSP compatível com a aplicação para reduzir exposição a conteúdo não esperado.'));
  }
  if (!headers['x-content-type-options']) {
    findings.push(finding('nosniff-missing', 'low', 'nosniff não observado', 'X-Content-Type-Options não apareceu na resposta.', 'Considere X-Content-Type-Options: nosniff para respostas web aplicáveis.'));
  }
  const hasFramePolicy = Boolean(headers['x-frame-options']) || /frame-ancestors/i.test(headers['content-security-policy'] || '');
  if (!hasFramePolicy) {
    findings.push(finding('frame-policy-missing', 'low', 'Política de framing não observada', 'Não foi visto X-Frame-Options nem frame-ancestors na CSP.', 'Revise se a página precisa ser incorporada por outros sites e defina uma política explícita.'));
  }
  if (!headers['referrer-policy']) {
    findings.push(finding('referrer-policy-missing', 'info', 'Referrer-Policy não observada', 'Referrer-Policy não apareceu na resposta.', 'Defina uma política de referer apropriada ao fluxo da aplicação se ainda não houver uma herdada.'));
  }
  if (headers['access-control-allow-origin'] === '*') {
    findings.push(finding('cors-wildcard', 'info', 'CORS permite origem ampla', 'Access-Control-Allow-Origin foi observado como *.', 'Confirme se os recursos expostos foram projetados para acesso por qualquer origem.'));
  }
  for (const cookie of result?.cookies || []) {
    if (httpsEnabled && !cookie.secure) {
      findings.push(finding(`cookie-secure-${cookie.name}`, 'medium', `Cookie ${cookie.name} sem Secure`, 'O atributo Secure não foi observado.', 'Revise se este cookie deve trafegar somente por HTTPS.'));
    }
    if (!cookie.httpOnly) {
      findings.push(finding(`cookie-httponly-${cookie.name}`, 'low', `Cookie ${cookie.name} sem HttpOnly`, 'O atributo HttpOnly não foi observado.', 'Se JavaScript não precisa ler o cookie, considere HttpOnly.'));
    }
    if (!cookie.sameSite) {
      findings.push(finding(`cookie-samesite-${cookie.name}`, 'info', `Cookie ${cookie.name} sem SameSite explícito`, 'SameSite não foi observado.', 'Revise a política SameSite adequada ao fluxo de navegação e autenticação.'));
    }
  }
  if (result?.status >= 500) {
    findings.push(finding('server-error', 'medium', 'Servidor respondeu com erro 5xx', `Status HTTP ${result.status}.`, 'Revise disponibilidade, logs da aplicação e dependências do serviço.'));
  }
  if (headers['x-powered-by']) {
    findings.push(finding('powered-by', 'info', 'Tecnologia anunciada em header', `X-Powered-By: ${clip(headers['x-powered-by'], 160)}`, 'Confirme se divulgar essa identificação é necessário.'));
  }
  return findings.slice(0, 100);
}

function technologyHints(response) {
  const hints = [];
  const add = (source, value) => {
    const clean = clip(value, 200);
    if (clean && !hints.some(item => item.source === source && item.value === clean)) hints.push({ source, value: clean, heuristic: true });
  };
  add('server', response.selectedHeaders.server);
  add('x-powered-by', response.selectedHeaders['x-powered-by']);
  add('meta-generator', response.generator);
  if (response.selectedHeaders['cf-ray']) add('edge', 'Cloudflare signal observed');
  if (response.selectedHeaders['x-vercel-id']) add('edge', 'Vercel signal observed');
  return hints;
}

export async function inspectPublicWebUrl(input) {
  const started = Date.now();
  const requestedUrl = normalizePublicWebUrl(input);
  const redirects = [];
  let current = requestedUrl;
  let response;
  let redirectLimitReached = false;

  for (let index = 0; index <= MAX_REDIRECTS; index += 1) {
    response = await requestOnce(current);
    const location = headerValue(response.headers, 'location');
    if (!REDIRECT_CODES.has(response.status) || !location) break;
    if (index === MAX_REDIRECTS) {
      redirectLimitReached = true;
      break;
    }
    let next;
    try {
      next = new URL(location, response.url).toString();
    } catch {
      throw makeError('O servidor retornou um redirect inválido.', 'WEB_REDIRECT_INVALID');
    }
    next = normalizePublicWebUrl(next);
    redirects.push({ from: response.url, to: next, status: response.status });
    current = next;
  }

  const result = {
    schemaVersion: 1,
    kind: 'cloudos-web-inspection',
    requestedUrl,
    finalUrl: response.url,
    resolvedAddress: response.address,
    resolvedFamily: response.family,
    status: response.status,
    statusMessage: response.statusMessage,
    title: response.title || null,
    contentType: response.selectedHeaders['content-type'] || null,
    bodySampledBytes: Buffer.byteLength(response.body),
    bodyTruncated: response.bodyTruncated,
    redirects,
    redirectLimitReached,
    headers: response.selectedHeaders,
    cookies: response.cookies,
    tls: response.tls,
    technologies: technologyHints(response),
    completedAt: new Date().toISOString(),
    durationMs: Date.now() - started,
    policy: {
      publicHttpHttpsOnly: true,
      allowedPorts: [...ALLOWED_PORTS],
      privateAndLocalTargetsBlocked: true,
      redirectRevalidation: true,
      maxRedirects: MAX_REDIRECTS,
      maxBodyBytes: MAX_BODY_BYTES,
      requestTimeoutMs: REQUEST_TIMEOUT_MS,
      arbitraryHeaders: false,
      arbitraryMethods: false,
      crawling: false,
      fuzzing: false,
      credentialAttacks: false,
      exploitAutomation: false,
    },
  };
  result.findings = buildWebFindings(result);
  result.summary = {
    findingCount: result.findings.length,
    mediumOrHigher: result.findings.filter(item => ['medium', 'high', 'critical'].includes(item.severity)).length,
    cookieCount: result.cookies.length,
    redirectCount: result.redirects.length,
    technologyHintCount: result.technologies.length,
    note: 'Ausência/presença de headers é evidência de higiene observada, não prova automática de vulnerabilidade.',
  };
  result.nextSteps = [
    'Confirmar se a URL e o ambiente estão dentro do escopo autorizado.',
    'Revisar findings de transporte, headers e cookies no contexto real da aplicação.',
    'Validar configurações no servidor/CDN antes de alterar políticas de segurança.',
    'Comparar uma nova coleta depois das correções para confirmar a mudança.',
  ];
  return result;
}