import { useMemo, useState } from 'react';
import { apiClient } from '../../services/apiClient';
import { launchWorkflowApp } from '../../services/workflowLaunch';
import './QuickWebChecks.css';

type WebFinding = { id: string; severity: string; title: string; evidence: string; recommendation: string };
type WebCookie = { name: string; secure: boolean; httpOnly: boolean; sameSite: string | null; domain: string | null; path: string | null; valueExposed: false };
type WebInspection = {
  requestedUrl: string;
  finalUrl: string;
  resolvedAddress: string;
  status: number;
  statusMessage: string;
  title: string | null;
  redirects: Array<{ from: string; to: string; status: number }>;
  headers: Record<string, string>;
  cookies: WebCookie[];
  tls: null | { protocol: string | null; cipher: string | null; subjectCommonName: string | null; issuerCommonName: string | null; issuerOrganization: string | null; validFrom: string | null; validTo: string | null; fingerprint256: string | null; subjectAltNameCount: number };
  technologies: Array<{ source: string; value: string; heuristic: boolean }>;
  findings: WebFinding[];
  summary: { findingCount: number; mediumOrHigher: number; cookieCount: number; redirectCount: number; technologyHintCount: number };
  nextSteps: string[];
  completedAt: string;
  durationMs: number;
};

type Mode = 'summary' | 'tls' | 'headers' | 'cookies' | 'redirects' | 'technology';
type Block = { id: Mode; icon: string; title: string; description: string };

const BLOCKS: Block[] = [
  { id: 'summary', icon: '🎯', title: 'Análise web completa', description: 'Status, TLS, headers, cookies, redirects, tecnologias e prioridades em uma coleta.' },
  { id: 'tls', icon: '🔒', title: 'Checar HTTPS / TLS', description: 'Mostra protocolo, cifra, certificado, emissor, validade e fingerprint.' },
  { id: 'headers', icon: '🧱', title: 'Checar headers', description: 'Mostra os headers de segurança e infraestrutura observados.' },
  { id: 'cookies', icon: '🍪', title: 'Checar cookies', description: 'Mostra somente nome e flags; o valor do cookie nunca é exposto.' },
  { id: 'redirects', icon: '↪️', title: 'Checar redirects', description: 'Mostra a cadeia limitada e revalidada de redirecionamentos.' },
  { id: 'technology', icon: '🧩', title: 'Ver tecnologias', description: 'Mostra sinais passivos como Server, X-Powered-By, generator e edge.' },
];

function normalizeInput(value: string) {
  const trimmed = value.trim();
  if (!/^https?:\/\//i.test(trimmed)) return '';
  return trimmed;
}

export default function QuickWebChecks() {
  const [url, setUrl] = useState('https://');
  const [mode, setMode] = useState<Mode>('summary');
  const [result, setResult] = useState<WebInspection | null>(null);
  const [loading, setLoading] = useState<Mode | ''>('');
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');

  const run = async (selectedMode: Mode) => {
    const target = normalizeInput(url);
    if (!target) { setError('Cole uma URL completa começando com http:// ou https://.'); return; }
    setMode(selectedMode); setError(''); setNotice('');
    if (result?.requestedUrl === target) { setNotice('Usando a coleta atual. O bloco selecionado foi aberto abaixo.'); return; }
    setLoading(selectedMode);
    try {
      const data = await apiClient<WebInspection>('/api/security/tools/web/inspect', {
        method: 'POST', timeoutMs: 55_000, body: JSON.stringify({ url: target }),
      });
      setResult(data); setUrl(data.requestedUrl);
      setNotice(`${BLOCKS.find(block => block.id === selectedMode)?.title || 'Análise'} concluída em ${data.durationMs} ms.`);
    } catch (cause) {
      setResult(null);
      setError(cause instanceof Error ? cause.message : 'A análise web não foi concluída.');
    } finally { setLoading(''); }
  };

  const orderedFindings = useMemo(() => {
    const rank: Record<string, number> = { critical: 5, high: 4, medium: 3, low: 2, info: 1 };
    return [...(result?.findings || [])].sort((a, b) => (rank[b.severity] || 0) - (rank[a.severity] || 0)).slice(0, 8);
  }, [result]);

  const copyForAi = async () => {
    if (!result) return;
    const payload = {
      schemaVersion: 1,
      kind: 'cloudos-quick-web-check',
      purpose: 'authorized-defensive-web-assessment',
      target: { requestedUrl: result.requestedUrl, finalUrl: result.finalUrl, address: result.resolvedAddress, status: result.status },
      tls: result.tls,
      headers: result.headers,
      cookies: result.cookies,
      redirects: result.redirects,
      technologies: result.technologies,
      findings: result.findings,
      nextSteps: result.nextSteps,
      constraints: { publicHttpHttpsOnly: true, noCrawler: true, noFuzzing: true, noCredentialAttacks: true, noExploitAutomation: true },
    };
    try { await navigator.clipboard.writeText(JSON.stringify(payload, null, 2)); setNotice('Contexto web copiado para a IA.'); }
    catch { setError('Não foi possível copiar para a área de transferência.'); }
  };

  return <section className="qwc-root" aria-label="Checks web de um clique">
    <header className="qwc-head"><div><small>Web · um botão por função</small><h2>Cole uma URL e escolha o que quer entender</h2><p>Todos os blocos usam a mesma coleta segura do Web Inspector e reaproveitam o resultado enquanto a URL não mudar.</p></div><button type="button" onClick={() => launchWorkflowApp('web-inspector')}>Abrir Web Inspector completo</button></header>

    {(error || notice) && <div className={`qwc-banner ${error ? 'is-error' : ''}`}><span>{error || notice}</span><button type="button" onClick={() => { setError(''); setNotice(''); }}>×</button></div>}

    <label className="qwc-url"><span>URL pública autorizada</span><input value={url} onChange={event => { setUrl(event.target.value); if (result && event.target.value !== result.requestedUrl) setResult(null); }} placeholder="https://site-da-empresa.com" /></label>

    <div className="qwc-grid">{BLOCKS.map(block => <article key={block.id} className={mode === block.id && result ? 'is-active' : ''}><div className="qwc-icon">{block.icon}</div><strong>{block.title}</strong><p>{block.description}</p><button type="button" disabled={Boolean(loading)} onClick={() => void run(block.id)}>{loading === block.id ? 'Coletando…' : 'Verificar →'}</button></article>)}</div>

    {result && <section className="qwc-result">
      <header><div><small>{new URL(result.finalUrl).hostname}</small><strong>HTTP {result.status} · {result.title || 'sem título'}</strong><span>{result.finalUrl}</span></div><button type="button" onClick={() => void copyForAi()}>Copiar para IA</button></header>

      {mode === 'summary' && <div className="qwc-summary"><article><small>IP</small><strong>{result.resolvedAddress}</strong></article><article><small>TLS</small><strong>{result.tls?.protocol || 'não observado'}</strong></article><article><small>Cookies</small><strong>{result.cookies.length}</strong></article><article><small>Redirects</small><strong>{result.redirects.length}</strong></article><article><small>Pontos</small><strong>{result.summary.findingCount}</strong></article></div>}
      {mode === 'summary' && <div className="qwc-findings">{orderedFindings.length ? orderedFindings.map(item => <article key={item.id}><em>{item.severity}</em><div><strong>{item.title}</strong><p>{item.evidence}</p><small>{item.recommendation}</small></div></article>) : <p>Nenhum ponto adicional foi gerado nesta coleta.</p>}</div>}

      {mode === 'tls' && <div className="qwc-kv">{result.tls ? <><div><b>Protocolo</b><span>{result.tls.protocol || '—'}</span></div><div><b>Cifra</b><span>{result.tls.cipher || '—'}</span></div><div><b>Certificado</b><span>{result.tls.subjectCommonName || '—'}</span></div><div><b>Emissor</b><span>{result.tls.issuerOrganization || result.tls.issuerCommonName || '—'}</span></div><div><b>Validade</b><span>{result.tls.validTo || '—'}</span></div><div><b>Fingerprint SHA-256</b><span>{result.tls.fingerprint256 || '—'}</span></div></> : <p>A URL final não apresentou TLS nesta coleta.</p>}</div>}

      {mode === 'headers' && <div className="qwc-kv">{Object.entries(result.headers).length ? Object.entries(result.headers).map(([name, value]) => <div key={name}><b>{name}</b><span>{value}</span></div>) : <p>Nenhum header selecionado foi observado.</p>}</div>}

      {mode === 'cookies' && <div className="qwc-cookie">{result.cookies.length ? result.cookies.map((cookie, index) => <article key={`${cookie.name}-${index}`}><strong>{cookie.name}</strong><span>Secure {cookie.secure ? '✓' : '—'}</span><span>HttpOnly {cookie.httpOnly ? '✓' : '—'}</span><span>SameSite {cookie.sameSite || '—'}</span><small>{cookie.domain || 'host atual'} · {cookie.path || '/'}</small></article>) : <p>Nenhum Set-Cookie foi observado.</p>}</div>}

      {mode === 'redirects' && <div className="qwc-redirects">{result.redirects.length ? result.redirects.map((redirect, index) => <article key={`${redirect.from}-${index}`}><b>{index + 1}</b><div><strong>HTTP {redirect.status}</strong><span>{redirect.from}</span><small>→ {redirect.to}</small></div></article>) : <p>Não houve redirect.</p>}</div>}

      {mode === 'technology' && <div className="qwc-tech">{result.technologies.length ? result.technologies.map((item, index) => <article key={`${item.source}-${index}`}><small>{item.source}</small><strong>{item.value}</strong><span>indício passivo, não confirmação</span></article>) : <p>Nenhum sinal de tecnologia foi anunciado nesta coleta.</p>}</div>}
    </section>}
  </section>;
}
