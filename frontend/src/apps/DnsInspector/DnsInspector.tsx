import { useMemo, useState } from 'react';
import { apiClient } from '../../services/apiClient';
import './DnsInspector.css';

type RecordResult<T = string> = { status: 'ok' | 'empty' | 'error'; records: T[]; errorCode?: string };
type MxRecord = { exchange: string; priority: number | null };
type DnsInspection = {
  schemaVersion: number;
  kind: string;
  name: string;
  startedAt: string;
  completedAt: string;
  durationMs: number;
  records: {
    A: RecordResult<string>;
    AAAA: RecordResult<string>;
    CNAME: RecordResult<string>;
    MX: RecordResult<MxRecord>;
    NS: RecordResult<string>;
    TXT: RecordResult<string>;
  };
  summary: { presentTypes: string[]; recommendations: string[] };
  resolvers: string[];
  policy: { exactNameOnly: boolean; recordTypes: string[]; bruteForce: boolean; wordlists: boolean; customResolverFromFrontend: boolean; arbitraryArguments: boolean };
};

type HistoryItem = { name: string; completedAt: string; types: string[] };

function downloadJson(filename: string, payload: unknown) {
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 0);
}

function renderRecords(type: string, result: RecordResult<string> | RecordResult<MxRecord>) {
  if (!result.records.length) return <p className="di-empty-record">Nenhum registro retornado.</p>;
  if (type === 'MX') {
    return <div className="di-record-list">{(result.records as MxRecord[]).map((record, index) => <code key={`${record.exchange}-${index}`}>{record.priority ?? '—'} · {record.exchange}</code>)}</div>;
  }
  return <div className="di-record-list">{(result.records as string[]).map((record, index) => <code key={`${record}-${index}`}>{record}</code>)}</div>;
}

export default function DnsInspector() {
  const [name, setName] = useState('');
  const [result, setResult] = useState<DnsInspection | null>(null);
  const [history, setHistory] = useState<HistoryItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  const lookup = async (candidate = name) => {
    const normalized = candidate.trim();
    if (!normalized) {
      setError('Informe um hostname ou domínio, por exemplo example.com.');
      return;
    }
    setLoading(true);
    setError('');
    setNotice('');
    try {
      const data = await apiClient<DnsInspection>('/api/security/tools/network/dns/lookup', {
        method: 'POST', timeoutMs: 12000,
        body: JSON.stringify({ name: normalized }),
      });
      setName(data.name);
      setResult(data);
      setHistory(current => [{ name: data.name, completedAt: data.completedAt, types: data.summary.presentTypes }, ...current.filter(item => item.name !== data.name)].slice(0, 8));
      setNotice(`DNS de ${data.name} consultado em ${data.durationMs} ms.`);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Falha na consulta DNS.');
    } finally {
      setLoading(false);
    }
  };

  const aiPayload = useMemo(() => result ? {
    schemaVersion: 1,
    kind: 'cloudos-dns-context',
    purpose: 'authorized-defensive-dns-review',
    name: result.name,
    records: result.records,
    resolvers: result.resolvers,
    recommendations: result.summary.recommendations,
    constraints: {
      exactNameOnly: true,
      doNotBruteForceSubdomains: true,
      doNotUseWordlists: true,
      doNotTreatPublicDnsDataAsProofOfVulnerability: true,
    },
  } : null, [result]);

  const copyForAi = async () => {
    if (!aiPayload) return;
    try {
      await navigator.clipboard.writeText(JSON.stringify(aiPayload, null, 2));
      setNotice('Contexto DNS copiado para a IA do CloudOS.');
    } catch {
      setError('Não foi possível acessar a área de transferência.');
    }
  };

  const exportEvidence = () => {
    if (!aiPayload || !result) return;
    downloadJson(`cloudos-dns-${result.name.replace(/[^a-z0-9.-]+/gi, '_')}-${Date.now()}.json`, aiPayload);
    setNotice('Relatório DNS exportado.');
  };

  const recordEntries = result ? Object.entries(result.records) as Array<[keyof DnsInspection['records'], DnsInspection['records'][keyof DnsInspection['records']]]> : [];

  return <div className="di-root">
    <header className="di-hero"><div><small>CloudOS · DNS Inspector</small><h1>Entenda o DNS de um nome</h1><p>Consulta exata de A, AAAA, CNAME, MX, NS e TXT sem wordlists ou descoberta automática.</p></div><div className="di-actions"><button type="button" onClick={() => void copyForAi()} disabled={!aiPayload}>Copiar para IA</button><button type="button" onClick={exportEvidence} disabled={!aiPayload}>Exportar JSON</button></div></header>

    {(error || notice) && <div className={`di-banner ${error ? 'is-error' : ''}`}><span>{error || notice}</span><button type="button" onClick={() => { setError(''); setNotice(''); }}>×</button></div>}

    <section className="di-runner"><label><span>Hostname ou domínio</span><input value={name} onChange={event => setName(event.target.value)} onKeyDown={event => { if (event.key === 'Enter') void lookup(); }} placeholder="example.com" /></label><button className="di-primary" type="button" onClick={() => void lookup()} disabled={loading}>{loading ? 'Consultando…' : '⌕ Consultar DNS'}</button><p>Digite somente o nome: sem https://, caminho ou porta.</p></section>

    <div className="di-layout"><main>
      {!result ? <section className="di-empty"><span>DNS</span><strong>Faça a primeira consulta.</strong><p>O resultado será separado por tipo de registro e explicado para quem não trabalha com DNS.</p></section> : <>
        <section className="di-summary"><div><small>Nome consultado</small><h2>{result.name}</h2><span>{result.summary.presentTypes.length ? `${result.summary.presentTypes.length} tipo(s) com resposta` : 'nenhum tipo retornou resposta'}</span></div><div className="di-type-chips">{result.policy.recordTypes.map(type => <span className={result.summary.presentTypes.includes(type) ? 'is-present' : ''} key={type}>{type}</span>)}</div></section>
        <section className="di-record-grid">{recordEntries.map(([type, records]) => <article key={type}><header><strong>{type}</strong><span className={`di-status di-status--${records.status}`}>{records.status === 'ok' ? `${records.records.length} registro(s)` : records.status === 'empty' ? 'sem resposta' : 'erro'}</span></header>{renderRecords(type, records as RecordResult<string> | RecordResult<MxRecord>)}</article>)}</section>
        <section className="di-recommendations"><header><small>Leitura defensiva</small><strong>Como interpretar</strong></header><ol>{result.summary.recommendations.map((item, index) => <li key={`${index}-${item}`}>{item}</li>)}</ol></section>
      </>}
    </main><aside>
      <section className="di-panel"><header><small>Resolver</small><strong>DNS usado pelo host</strong></header>{result?.resolvers.length ? result.resolvers.map(resolver => <code key={resolver}>{resolver}</code>) : <p>Será exibido após a consulta.</p>}</section>
      <section className="di-panel"><header><small>Consultas recentes</small><strong>Histórico da janela</strong></header>{history.length ? history.map(item => <button type="button" key={`${item.name}-${item.completedAt}`} onClick={() => void lookup(item.name)}><strong>{item.name}</strong><span>{item.types.join(', ') || 'sem registros'}</span></button>) : <p>Nenhuma consulta ainda.</p>}</section>
      <section className="di-panel di-boundary"><header><small>Boundary</small><strong>Consulta exata</strong></header><p>Não há enumeração automática de subdomínios, wordlist, brute force de nomes, AXFR automático nem seleção de servidor DNS arbitrário pelo frontend.</p></section>
    </aside></div>
  </div>;
}
