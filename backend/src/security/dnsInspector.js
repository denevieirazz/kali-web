import dns from 'node:dns/promises';
import { domainToASCII } from 'node:url';

const DNS_TIMEOUT_MS = 5000;
const MAX_RECORDS_PER_TYPE = 32;

export function normalizeDnsName(value) {
  const raw = String(value || '').trim().replace(/\.$/, '');
  if (!raw || raw.length > 253 || /[\s/:\\]/.test(raw)) {
    const error = new Error('Informe um nome DNS válido, sem protocolo, caminho ou porta.');
    error.code = 'INVALID_DNS_NAME';
    throw error;
  }
  const ascii = domainToASCII(raw).toLowerCase();
  const labels = ascii.split('.');
  if (!ascii || labels.length < 2 || labels.some(label => !label || label.length > 63 || !/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(label))) {
    const error = new Error('Informe um hostname ou domínio DNS válido.');
    error.code = 'INVALID_DNS_NAME';
    throw error;
  }
  return ascii;
}

async function withTimeout(promise) {
  let timeoutId;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timeoutId = setTimeout(() => {
          const error = new Error('DNS lookup timeout');
          error.code = 'DNS_TIMEOUT';
          reject(error);
        }, DNS_TIMEOUT_MS);
      }),
    ]);
  } finally {
    if (timeoutId) clearTimeout(timeoutId);
  }
}

function cleanStrings(values) {
  return [...new Set((Array.isArray(values) ? values : []).filter(value => typeof value === 'string').map(value => value.trim()).filter(Boolean))].slice(0, MAX_RECORDS_PER_TYPE);
}

function cleanTxt(values) {
  if (!Array.isArray(values)) return [];
  return values.slice(0, MAX_RECORDS_PER_TYPE).map(chunks => Array.isArray(chunks) ? chunks.join('') : String(chunks || '')).map(value => value.slice(0, 2048));
}

function cleanMx(values) {
  if (!Array.isArray(values)) return [];
  return values.slice(0, MAX_RECORDS_PER_TYPE).map(item => ({
    exchange: String(item?.exchange || '').slice(0, 253),
    priority: Number.isFinite(item?.priority) ? Number(item.priority) : null,
  })).filter(item => item.exchange);
}

async function settle(resolver, clean) {
  try {
    return { status: 'ok', records: clean(await withTimeout(resolver())) };
  } catch (error) {
    const code = String(error?.code || 'DNS_LOOKUP_FAILED');
    const emptyCodes = new Set(['ENODATA', 'ENOTFOUND', 'ESERVFAIL', 'EREFUSED', 'ETIMEOUT', 'DNS_TIMEOUT']);
    return { status: emptyCodes.has(code) ? 'empty' : 'error', records: [], errorCode: code };
  }
}

export function summarizeDnsRecords(records) {
  const presentTypes = Object.entries(records || {}).filter(([, value]) => Array.isArray(value?.records) && value.records.length > 0).map(([type]) => type);
  const recommendations = [];
  if (presentTypes.includes('A') || presentTypes.includes('AAAA')) recommendations.push('Confirme se os endereços publicados correspondem à infraestrutura esperada antes de associá-los a um ativo do projeto.');
  if (presentTypes.includes('MX')) recommendations.push('Os registros MX indicam provedores de e-mail publicados; use-os como inventário e revise a configuração de e-mail por fontes administrativas.');
  if (presentTypes.includes('TXT')) recommendations.push('Registros TXT podem conter políticas e verificações públicas. A presença de texto não deve ser tratada automaticamente como segredo ou vulnerabilidade.');
  if (presentTypes.includes('NS')) recommendations.push('Registre os nameservers como dependências externas/administrativas quando isso for relevante para o escopo.');
  if (!presentTypes.length) recommendations.push('Nenhum dos tipos consultados retornou registros nesta coleta; confirme o nome e a resolução DNS usada pelo host.');
  return { presentTypes, recommendations: recommendations.slice(0, 6) };
}

export async function inspectDnsName(rawName) {
  const name = normalizeDnsName(rawName);
  const startedAt = new Date().toISOString();
  const started = Date.now();

  const [a, aaaa, cname, mx, ns, txt] = await Promise.all([
    settle(() => dns.resolve4(name), cleanStrings),
    settle(() => dns.resolve6(name), cleanStrings),
    settle(() => dns.resolveCname(name), cleanStrings),
    settle(() => dns.resolveMx(name), cleanMx),
    settle(() => dns.resolveNs(name), cleanStrings),
    settle(() => dns.resolveTxt(name), cleanTxt),
  ]);
  const records = { A: a, AAAA: aaaa, CNAME: cname, MX: mx, NS: ns, TXT: txt };

  return {
    schemaVersion: 1,
    kind: 'cloudos-dns-inspection',
    name,
    startedAt,
    completedAt: new Date().toISOString(),
    durationMs: Date.now() - started,
    records,
    summary: summarizeDnsRecords(records),
    resolvers: dns.getServers().slice(0, 16),
    policy: {
      exactNameOnly: true,
      recordTypes: ['A', 'AAAA', 'CNAME', 'MX', 'NS', 'TXT'],
      bruteForce: false,
      wordlists: false,
      customResolverFromFrontend: false,
      arbitraryArguments: false,
    },
  };
}
