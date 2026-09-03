import { useMemo, useState } from 'react';
import { apiClient } from '../../services/apiClient';
import { getUserStorageKey } from '../../services/userScope.js';
import './WebInspector.css';

type Severity = 'info' | 'low' | 'medium' | 'high' | 'critical';

type WebFinding = {
  id: string;
  severity: Severity;
  title: string;
  evidence: string;
  recommendation: string;
  certainty: string;
};

type WebCookie = {
  name: string;
  secure: boolean;
  httpOnly: boolean;
  sameSite: string | null;
  domain: string | null;
  path: string | null;
  valueExposed: false;
};

type WebRedirect = { from: string; to: string; status: number };
type TechnologyHint = { source: string; value: string; heuristic: boolean };

type WebInspection = {
  schemaVersion: number;
  kind: string;
  requestedUrl: string;
  finalUrl: string;
  resolvedAddress: string;
  resolvedFamily: number;
  status: number;
  statusMessage: string;
  title: string | null;
  contentType: string | null;
  bodySampledBytes: number;
  bodyTruncated: boolean;
  redirects: WebRedirect[];
  redirectLimitReached: boolean;
  headers: Record<string, string>;
  cookies: WebCookie[];
  tls: null | {
    protocol: string | null;
    cipher: string | null;
    subjectCommonName: string | null;
    issuerCommonName: string | null;
    issuerOrganization: string | null;
    validFrom: string | null;
    validTo: string | null;
    fingerprint256: string | null;
    subjectAltNameCount: number;
  };
  technologies: TechnologyHint[];
  completedAt: string;
  durationMs: number;
  findings: WebFinding[];
  summary: {
    findingCount: number;
    mediumOrHigher: number;
    cookieCount: number;
    redirectCount: number;
    technologyHintCount: number;
    note: string;
  };
  nextSteps: string[];
  policy: Record<string, unknown>;
};

type HistoryEntry = {
  url: string;
  finalUrl: string;
  status: number;
  title: string | null;
  completedAt: string;
  findings: number;
  mediumOrHigher: number;
};

type Tab = 'overview' | 'headers' | 'cookies' | 'redirects' | 'evidence';

const HISTORY_KEY = 'cloudos-web-inspector-history-v1';
const SEVERITY_LABEL: Record<Severity, string> = {
  info: 'info', low: 'baixo', medium: 'médio', high: 'alto', critical: 'crítico',
};

function historyKey() {
  return getUserStorageKey(HISTORY_KEY);
}

function loadHistory(): HistoryEntry[] {
  try {
    const parsed = JSON.parse(localStorage.getItem(historyKey()) || '[]');
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(item => item && typeof item.url === 'string').slice(0, 12);
  } catch {
    localStorage.removeItem(historyKey());
    return [];
  }
}

function saveHistory(entries: HistoryEntry[]) {
  localStorage.setItem(historyKey(), JSON.stringify(entries.slice(0, 12)));
}

function formatBytes(value: number) {
  if (value < 1024) return `${value} B`;
  return `${(value / 1024).toFixed(1)} KiB`;
}

function downloadJson(filename: string, payload: unknown) {
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
  const href = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = href;
  anchor.download = filename;
  anchor.click();
  window.setTimeout(() => URL.revokeObjectURL(href), 0);
}

function statusClass(status: number) {
  if (status >= 200 && status < 300) return 'ok';
  if (status >= 300 && status < 400) return 'redirect';
  if (status >= 400 && status < 500) return 'client';
  return 'server';
}

export default function WebInspector() {
  const [url, setUrl] = useState('https://');
  const [result, setResult] = useState<WebInspection | null>(null);
  const [history, setHistory] = useState<HistoryEntry[]>(loadHistory);
  const [tab, setTab] = useState<Tab>('overview');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  const highestSeverity = useMemo<Severity>(() => {
    if (!result?.findings.length) return 'info';
    const order: Severity[] = ['info', 'low', 'medium', 'high', 'critical'];
    return result.findings.reduce((highest, finding) =>
      order.indexOf(finding.severity) > order.indexOf(highest) ? finding.severity : highest, 'info' as Severity);
  }, [result]);

  const runInspection = async (candidate = url) => {
    const target = candidate.trim();
    if (!/^https?:\/\//i.test(target)) {
      setError('Informe uma URL completa começando com http:// ou https://.');
      return;
    }
    setLoading(true);
    setError('');
    setNotice('');
    try {
      const data = await apiClient<WebInspection>('/api/security/tools/web/inspect', {
        method: 'POST',
        timeoutMs: 55_000,
        body: JSON.stringify({ url: target }),
      });
      setResult(data);
      setUrl(data.requestedUrl);
      setTab('overview');
      const next: HistoryEntry[] = [{
        url: data.requestedUrl,
        finalUrl: data.finalUrl,
        status: data.status,
        title: data.title,
        completedAt: data.completedAt,
        findings: data.summary.findingCount,
        mediumOrHigher: data.summary.mediumOrHigher,
      }, ...history.filter(item => item.url !== data.requestedUrl)].slice(0, 12);
      setHistory(next);
      saveHistory(next);
      setNotice(`Inspeção concluída: HTTP ${data.status}, ${data.summary.findingCount} observação(ões).`);
    } catch (cause) {
      setResult(null);
      setError(cause instanceof Error ? cause.message : 'Não foi possível analisar a URL.');
    } finally {
      setLoading(false);
    }
  };

  const aiPayload = useMemo(() => result ? {
    schemaVersion: 1,
    kind: 'cloudos-web-assessment-context',
    purpose: 'authorized-defensive-web-assessment',
    target: {
      requestedUrl: result.requestedUrl,
      finalUrl: result.finalUrl,
      status: result.status,
      title: result.title,
      contentType: result.contentType,
      resolvedAddress: result.resolvedAddress,
    },
    redirects: result.redirects,
    tls: result.tls,
    headers: result.headers,
    cookies: result.cookies,
    technologyHints: result.technologies,
    findings: result.findings,
    recommendedNextSteps: result.nextSteps,
    constraints: {
      evidenceIsObservedHygieneNotConfirmedExploitability: true,
      noCrawling: true,
      noFuzzing: true,
      noCredentialAttacks: true,
      noExploitAutomation: true,
      doNotInventMissingEvidence: true,
    },
  } : null, [result]);

  const copyForAi = async () => {
    if (!aiPayload) return;
    try {
      await navigator.clipboard.writeText(JSON.stringify(aiPayload, null, 2));
      setNotice('Contexto web estruturado copiado para a IA do CloudOS.');
    } catch {
      setError('Não foi possível acessar a área de transferência.');
    }
  };

  const exportEvidence = () => {
    if (!aiPayload || !result) return;
    const host = new URL(result.finalUrl).hostname.replace(/[^a-z0-9.-]/gi, '_');
    downloadJson(`cloudos-web-${host}-${Date.now()}.json`, aiPayload);
    setNotice('Evidência JSON exportada.');
  };

  const clearHistory = () => {
    setHistory([]);
    saveHistory([]);
  };

  return <div className="wi-root">
    <header className="wi-hero">
      <div>
        <small>CloudOS · Web Inspector</small>
        <h1>Assessment web guiado</h1>
        <p>Cole uma URL pública e transforme HTTP, TLS, headers e cookies em evidência legível.</p>
      </div>
      <div className="wi-policy">
        <span>1 URL</span><span>HTTP/HTTPS</span><span>SSRF bloqueado</span><span>sem exploit automático</span>
      </div>
    </header>

    {(error || notice) && <div className={`wi-banner ${error ? 'is-error' : ''}`} role={error ? 'alert' : 'status'}>
      <span>{error || notice}</span>
      <button type="button" onClick={() => { setError(''); setNotice(''); }}>×</button>
    </div>}

    <section className="wi-runner">
      <label>
        <span>URL pública autorizada</span>
        <input value={url} onChange={event => setUrl(event.target.value)} placeholder="https://example.com" onKeyDown={event => { if (event.key === 'Enter') void runInspection(); }} />
      </label>
      <button type="button" className="wi-primary" onClick={() => void runInspection()} disabled={loading}>{loading ? 'Analisando…' : '▶ Analisar URL'}</button>
      <p>Sem crawler, wordlist, fuzzing, login automático ou execução de payloads.</p>
    </section>

    <div className="wi-layout">
      <aside className="wi-history">
        <header><div><small>Recentes</small><strong>Últimas URLs</strong></div><button type="button" onClick={clearHistory} disabled={!history.length}>Limpar</button></header>
        <div className="wi-history-list">
          {history.length ? history.map(item => <button type="button" key={`${item.url}-${item.completedAt}`} onClick={() => { setUrl(item.url); void runInspection(item.url); }}>
            <div><strong>{new URL(item.finalUrl).hostname}</strong><span>HTTP {item.status}</span></div>
            <small>{item.title || item.url}</small>
            <em>{item.findings} observação(ões) · {item.mediumOrHigher} média+</em>
          </button>) : <p>Nenhuma inspeção ainda.</p>}
        </div>
      </aside>

      <main className="wi-content">
        {!result ? <div className="wi-empty"><span>🌐</span><strong>Cole a primeira URL.</strong><p>O CloudOS vai explicar a resposta sem despejar terminal bruto.</p></div> : <>
          <section className="wi-summary">
            <div className="wi-summary-title">
              <div><small>{result.title || 'Página sem título'}</small><h2>{new URL(result.finalUrl).hostname}</h2><span>{result.finalUrl}</span></div>
              <span className={`wi-status wi-status--${statusClass(result.status)}`}>HTTP {result.status}</span>
            </div>
            <div className="wi-metrics">
              <article><small>Tempo</small><strong>{result.durationMs} ms</strong><span>coleta limitada</span></article>
              <article><small>Redirects</small><strong>{result.redirects.length}</strong><span>{result.redirectLimitReached ? 'limite atingido' : 'cadeia concluída'}</span></article>
              <article><small>Cookies</small><strong>{result.cookies.length}</strong><span>valores nunca expostos</span></article>
              <article><small>Atenção</small><strong>{SEVERITY_LABEL[highestSeverity]}</strong><span>{result.summary.mediumOrHigher} finding(s) médio+</span></article>
              <article><small>Corpo amostrado</small><strong>{formatBytes(result.bodySampledBytes)}</strong><span>{result.bodyTruncated ? 'limitado' : 'completo no limite'}</span></article>
            </div>
          </section>

          <nav className="wi-tabs" aria-label="Áreas do Web Inspector">
            {(['overview', 'headers', 'cookies', 'redirects', 'evidence'] as Tab[]).map(value => <button type="button" key={value} className={tab === value ? 'is-active' : ''} onClick={() => setTab(value)}>{value === 'overview' ? 'Resumo' : value === 'headers' ? 'Headers' : value === 'cookies' ? `Cookies ${result.cookies.length}` : value === 'redirects' ? `Redirects ${result.redirects.length}` : 'Evidências'}</button>)}
          </nav>

          {tab === 'overview' && <div className="wi-grid">
            <section className="wi-card">
              <header><strong>Transporte / TLS</strong><span>{result.tls ? result.tls.protocol || 'HTTPS' : 'HTTP'}</span></header>
              <dl>
                <div><dt>IP resolvido</dt><dd>{result.resolvedAddress}</dd></div>
                <div><dt>Content-Type</dt><dd>{result.contentType || 'não informado'}</dd></div>
                {result.tls && <>
                  <div><dt>Certificado</dt><dd>{result.tls.subjectCommonName || 'CN não informado'}</dd></div>
                  <div><dt>Emissor</dt><dd>{result.tls.issuerOrganization || result.tls.issuerCommonName || 'não informado'}</dd></div>
                  <div><dt>Validade</dt><dd>{result.tls.validTo || 'não informada'}</dd></div>
                  <div><dt>Cifra</dt><dd>{result.tls.cipher || 'não informada'}</dd></div>
                </>}
              </dl>
            </section>

            <section className="wi-card">
              <header><strong>Tecnologias observadas</strong><span>heurísticas</span></header>
              {result.technologies.length ? <div className="wi-tech">{result.technologies.map((item, index) => <div key={`${item.source}-${index}`}><small>{item.source}</small><strong>{item.value}</strong><span>indício, não confirmação</span></div>)}</div> : <p>Nenhuma tecnologia foi anunciada nos sinais passivos coletados.</p>}
            </section>

            <section className="wi-card wi-card--wide">
              <header><strong>O que merece revisão</strong><span>{result.findings.length} observação(ões)</span></header>
              {result.findings.length ? <div className="wi-findings">{result.findings.map(finding => <article key={finding.id}>
                <span className={`wi-risk wi-risk--${finding.severity}`}>{SEVERITY_LABEL[finding.severity]}</span>
                <div><strong>{finding.title}</strong><p>{finding.evidence}</p><small>{finding.recommendation}</small></div>
              </article>)}</div> : <p>Nenhuma observação adicional foi gerada. Isso não equivale a certificação de segurança.</p>}
            </section>

            <section className="wi-card wi-card--wide">
              <header><strong>Próximos passos</strong><span>defensivos</span></header>
              <ol className="wi-next">{result.nextSteps.map((step, index) => <li key={`${index}-${step}`}>{step}</li>)}</ol>
            </section>
          </div>}

          {tab === 'headers' && <section className="wi-table-card">
            <header><div><small>Headers selecionados</small><strong>Resposta HTTP</strong></div><span>{Object.keys(result.headers).length}</span></header>
            <div className="wi-kv">{Object.entries(result.headers).map(([name, value]) => <div key={name}><code>{name}</code><span>{value}</span></div>)}</div>
            {!Object.keys(result.headers).length && <p>Nenhum header selecionado foi retornado.</p>}
          </section>}

          {tab === 'cookies' && <section className="wi-table-card">
            <header><div><small>Metadata somente</small><strong>Cookies observados</strong></div><span>valores ocultos</span></header>
            {result.cookies.length ? <div className="wi-cookie-list">{result.cookies.map((cookie, index) => <article key={`${cookie.name}-${index}`}>
              <strong>{cookie.name}</strong>
              <div><span className={cookie.secure ? 'is-good' : 'is-review'}>Secure {cookie.secure ? '✓' : '—'}</span><span className={cookie.httpOnly ? 'is-good' : 'is-review'}>HttpOnly {cookie.httpOnly ? '✓' : '—'}</span><span>SameSite {cookie.sameSite || '—'}</span></div>
              <small>{cookie.domain || 'host atual'} · {cookie.path || '/'}</small>
            </article>)}</div> : <p>Nenhum Set-Cookie foi observado nesta resposta.</p>}
          </section>}

          {tab === 'redirects' && <section className="wi-table-card">
            <header><div><small>Cadeia limitada</small><strong>Redirects</strong></div><span>máx. 4</span></header>
            {result.redirects.length ? <div className="wi-redirect-list">{result.redirects.map((redirect, index) => <article key={`${redirect.from}-${index}`}><b>{index + 1}</b><div><strong>HTTP {redirect.status}</strong><span>{redirect.from}</span><small>→ {redirect.to}</small></div></article>)}</div> : <p>A URL não exigiu redirect.</p>}
          </section>}

          {tab === 'evidence' && <section className="wi-evidence">
            <div><small>Para IA / relatório</small><strong>Evidência estruturada</strong><p>Inclui somente metadata coletada e findings; não inclui corpo HTML nem valor de cookie.</p></div>
            <div><button type="button" className="wi-primary" onClick={() => void copyForAi()}>Copiar contexto para IA</button><button type="button" onClick={exportEvidence}>Exportar JSON</button></div>
            <pre>{JSON.stringify(aiPayload, null, 2)}</pre>
          </section>}
        </>}
      </main>
    </div>
  </div>;
}
